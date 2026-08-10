#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
	echo "usage: $0 VALIDATOR RENDERER RECONCILER COMPOSE_STARTER" >&2
	exit 64
fi

validator="$1"
renderer="$2"
reconciler="$3"
compose_starter="$4"
database_managed_owner="999:999"

fixture_root="$TMPDIR/seafile-state-fixture"
state_dir="$fixture_root/state"
stub_dir="$fixture_root/bin"
dataset="synthetic_pool/state/seafile"
quota="1649267441664"

mkdir -p "$state_dir" "$stub_dir"
real_mv="$(command -v mv)"
real_rmdir="$(command -v rmdir)"
real_stat="$(command -v stat)"
real_unlink="$(command -v unlink)"

cat >"$stub_dir/findmnt" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case " $* " in
  *" SOURCE "*) printf '%s\n' "${STUB_FINDMNT_SOURCE:?}" ;;
  *" FSTYPE "*) printf '%s\n' "${STUB_FINDMNT_FSTYPE:?}" ;;
  *" TARGET "*) printf '%s\n' "${STUB_FINDMNT_TARGET:?}" ;;
  *) echo "unexpected findmnt invocation" >&2; exit 64 ;;
esac
EOF

cat >"$stub_dir/zfs" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
property=""
for argument in "$@"; do
  case "$argument" in
    quota|compression|atime|acltype|xattr|dnodesize) property="$argument" ;;
  esac
done
case "$property" in
  quota) printf '%s\n' "${STUB_ZFS_QUOTA:?}" ;;
  compression) printf '%s\n' "${STUB_ZFS_COMPRESSION:?}" ;;
  atime) printf '%s\n' "${STUB_ZFS_ATIME:?}" ;;
  acltype) printf '%s\n' "${STUB_ZFS_ACLTYPE:?}" ;;
  xattr) printf '%s\n' "${STUB_ZFS_XATTR:?}" ;;
  dnodesize) printf '%s\n' "${STUB_ZFS_DNODESIZE:?}" ;;
  *) echo "unexpected zfs invocation" >&2; exit 64 ;;
esac
EOF

cat >"$stub_dir/stat" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
format=""
path=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --format|-c) format="$2"; shift 2 ;;
    --) shift; path="$1"; shift ;;
    *) path="$1"; shift ;;
  esac
done

if [ -n "${STUB_STAT_OVERRIDE_PATH:-}" ] && [ "$path" = "$STUB_STAT_OVERRIDE_PATH" ]; then
  file_type="${STUB_STAT_OVERRIDE_TYPE:-directory}"
  owner="${STUB_STAT_OVERRIDE_OWNER:-0:0}"
  mode="${STUB_STAT_OVERRIDE_MODE:-750}"
elif [ -L "$path" ]; then
  file_type="symbolic link"
  owner="0:0"
  mode="777"
elif [ -d "$path" ]; then
  file_type="directory"
  owner="0:0"
  case "$path" in
    */.seafile-state-staging|*/database|*/backups|*/control) mode="700" ;;
    *) mode="750" ;;
  esac
elif [ -f "$path" ]; then
  file_type="regular file"
  owner="0:0"
  case "$path" in
    */.seafile-state-transaction|*/.seafile-state-transaction.next) mode="600" ;;
    *) mode="644" ;;
  esac
else
  echo "missing synthetic path: $path" >&2
  exit 1
fi

case "$format" in
  %F) printf '%s\n' "$file_type" ;;
  %u:%g) printf '%s\n' "$owner" ;;
  %a) printf '%s\n' "$mode" ;;
  *) echo "unexpected stat format: $format" >&2; exit 64 ;;
esac
EOF

cat >"$stub_dir/install" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
paths=()
directory=0
mode=""
owner=""
group=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -d) directory=1; shift ;;
    -m) mode="$2"; shift 2 ;;
    -o) owner="$2"; shift 2 ;;
    -g) group="$2"; shift 2 ;;
    --) shift; paths+=("$@"); break ;;
    -*) echo "unexpected install option: $1" >&2; exit 64 ;;
    *) paths+=("$1"); shift ;;
  esac
done
[ -n "$mode" ] && [ -n "$owner" ] && [ -n "$group" ]
if [ "$directory" -eq 1 ]; then
  for path in "${paths[@]}"; do
    printf '%s\t%s\t%s\t%s\n' "$mode" "$owner" "$group" "$path" >> "${STUB_INSTALL_LOG:?}"
    mkdir -p "$path"
    if [[ "$path" == "${STUB_STAGING_ROOT:?}/"* ]] && [ "$path" != "$STUB_STAGING_ROOT" ]; then
      count_file="${STUB_INSTALL_COUNT_PREFIX:?}-$mode"
      count=0
      if [ -f "$count_file" ]; then
        count="$(cat "$count_file")"
      fi
      count="$((count + 1))"
      printf '%s\n' "$count" >"$count_file"
      if [ "${STUB_INSTALL_CRASH_MODE:-}" = "$mode" ] \
        && [ "$count" -eq "${STUB_INSTALL_CRASH_AFTER:-0}" ]; then
        kill -KILL "$PPID"
        exit 137
      fi
    fi
  done
else
  [ "${#paths[@]}" -eq 2 ] && [ "${paths[0]}" = /dev/null ]
  printf '%s\t%s\t%s\t%s\n' "$mode" "$owner" "$group" "${paths[1]}" >> "${STUB_INSTALL_LOG:?}"
  : > "${paths[1]}"
fi
EOF

cat >"$stub_dir/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source_path="$2"
destination_path="$3"
source_phase=""
if [ "$source_path" = "${STUB_MARKER_NEXT:?}" ] && [ -f "$source_path" ]; then
  source_phase="$(tr -d '\n' <"$source_path")"
fi
printf 'mv:%s:%s\n' "$source_path" "$destination_path" >>"${STUB_EVENT_LOG:?}"
"${STUB_REAL_MV:?}" "$@"

if [ -n "${STUB_MV_CRASH_MARKER_PHASE:-}" ] \
  && [ "$source_phase" = "v1 $STUB_MV_CRASH_MARKER_PHASE" ]; then
  kill -KILL "$PPID"
  exit 137
fi

if [[ "$source_path" == "${STUB_STAGING_ROOT:?}/"* ]] \
  && [ "${source_path%/*}" = "$STUB_STAGING_ROOT" ]; then
  count=0
  if [ -f "${STUB_MV_COUNT:?}" ]; then
    count="$(cat "$STUB_MV_COUNT")"
  fi
  count="$((count + 1))"
  printf '%s\n' "$count" >"$STUB_MV_COUNT"
  if [ -n "${STUB_MV_CRASH_AFTER:-}" ] && [ "$count" -eq "$STUB_MV_CRASH_AFTER" ]; then
    kill -KILL "$PPID"
    exit 137
  fi
fi
EOF

cat >"$stub_dir/sync" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "$#" -eq 2 ] && [ "$1" = -f ]
printf 'sync:%s\n' "$2" >> "${STUB_EVENT_LOG:?}"
if [ "$2" = "${STUB_MARKER_NEXT:?}" ] && [ -f "$2" ] \
  && [ -n "${STUB_SYNC_CRASH_NEXT_PHASE:-}" ] \
  && [ "$(tr -d '\n' <"$2")" = "v1 $STUB_SYNC_CRASH_NEXT_PHASE" ]; then
  kill -KILL "$PPID"
  exit 137
fi
EOF

cat >"$stub_dir/rmdir" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
target="${*: -1}"
printf 'rmdir:%s\n' "$target" >>"${STUB_EVENT_LOG:?}"
"${STUB_REAL_RMDIR:?}" "$@"
if [ "$target" = "${STUB_STAGING_ROOT:?}" ] && [ "${STUB_RMDIR_CRASH:-0}" = 1 ]; then
  kill -KILL "$PPID"
  exit 137
fi
EOF

cat >"$stub_dir/unlink" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "$#" -eq 1 ]
printf 'unlink:%s\n' "$1" >> "${STUB_EVENT_LOG:?}"
exec "${STUB_REAL_UNLINK:?}" "$1"
EOF

chmod +x \
	"$stub_dir/findmnt" \
	"$stub_dir/zfs" \
	"$stub_dir/stat" \
	"$stub_dir/install" \
	"$stub_dir/mv" \
	"$stub_dir/rmdir" \
	"$stub_dir/sync" \
	"$stub_dir/unlink"

export PATH="$stub_dir:$PATH"
export STUB_REAL_MV="$real_mv"
export STUB_REAL_RMDIR="$real_rmdir"
export STUB_REAL_UNLINK="$real_unlink"
export STUB_INSTALL_LOG="$fixture_root/install.log"
export STUB_INSTALL_COUNT_PREFIX="$fixture_root/install-count"
export STUB_MV_COUNT="$fixture_root/mv-count"
export STUB_EVENT_LOG="$fixture_root/events.log"
export STUB_MARKER_NEXT="$state_dir/.seafile-state-transaction.next"
export STUB_STAGING_ROOT="$state_dir/.seafile-state-staging"
export STUB_FINDMNT_SOURCE="$dataset"
export STUB_FINDMNT_FSTYPE="zfs"
export STUB_FINDMNT_TARGET="$state_dir"
export STUB_ZFS_QUOTA="$quota"
export STUB_ZFS_COMPRESSION="zstd"
export STUB_ZFS_ATIME="off"
export STUB_ZFS_ACLTYPE="posix"
export STUB_ZFS_XATTR="sa"
export STUB_ZFS_DNODESIZE="auto"

run_validator() {
	bash "$validator" \
		--state-dir "$state_dir" \
		--dataset "$dataset" \
		--quota "$quota" \
		"$@"
}

expect_failure() {
	if "$@" >/dev/null 2>&1; then
		echo "command unexpectedly succeeded: $*" >&2
		exit 1
	fi
}

reset_state() {
	rm -rf "$state_dir"
	mkdir -p "$state_dir"
	: >"$STUB_INSTALL_LOG"
	: >"$STUB_EVENT_LOG"
	rm -f "$STUB_MV_COUNT" "$STUB_INSTALL_COUNT_PREFIX-0750" "$STUB_INSTALL_COUNT_PREFIX-0700"
	unset STUB_INSTALL_CRASH_MODE STUB_INSTALL_CRASH_AFTER
	unset STUB_MV_CRASH_AFTER STUB_MV_CRASH_MARKER_PHASE
	unset STUB_SYNC_CRASH_NEXT_PHASE STUB_RMDIR_CRASH
	unset STUB_STAT_OVERRIDE_PATH STUB_STAT_OVERRIDE_TYPE STUB_STAT_OVERRIDE_OWNER STUB_STAT_OVERRIDE_MODE
	export STUB_FINDMNT_SOURCE="$dataset"
	export STUB_FINDMNT_FSTYPE="zfs"
	export STUB_FINDMNT_TARGET="$state_dir"
	export STUB_ZFS_QUOTA="$quota"
	export STUB_ZFS_COMPRESSION="zstd"
	export STUB_ZFS_ATIME="off"
	export STUB_ZFS_ACLTYPE="posix"
	export STUB_ZFS_XATTR="sa"
	export STUB_ZFS_DNODESIZE="auto"
}

assert_install_contract() {
	actual="$TMPDIR/actual-seafile-installs"
	expected="$TMPDIR/expected-seafile-installs"
	sed \
		-e "s#$state_dir/\\.seafile-state-transaction\\.next#MARKER_NEXT#" \
		-e "s#$state_dir/\\.seafile-state-transaction#MARKER#" \
		-e "s#$state_dir/\\.seafile-state-staging#STAGING#" \
		"$STUB_INSTALL_LOG" >"$actual"
	printf '%s\n' \
		$'0600\t0\t0\tMARKER_NEXT' \
		$'0700\t0\t0\tSTAGING' \
		$'0750\t0\t0\tSTAGING/shared' \
		$'0750\t0\t0\tSTAGING/search' \
		$'0750\t0\t0\tSTAGING/onlyoffice' \
		$'0750\t0\t0\tSTAGING/onlyoffice/logs' \
		$'0750\t0\t0\tSTAGING/onlyoffice/data' \
		$'0750\t0\t0\tSTAGING/onlyoffice/lib' \
		$'0700\t0\t0\tSTAGING/database' \
		$'0700\t0\t0\tSTAGING/backups' \
		$'0700\t0\t0\tSTAGING/control' \
		$'0600\t0\t0\tMARKER_NEXT' \
		>"$expected"
	cmp "$expected" "$actual"
}

assert_commit_fsync_order() {
	unlink_line="$(grep -n -F "unlink:$state_dir/.seafile-state-transaction" "$STUB_EVENT_LOG" | cut -d: -f1)"
	[ -n "$unlink_line" ]
	awk -v unlink_line="$unlink_line" -v state_dir="$state_dir" '
    NR == unlink_line - 1 && $0 == "sync:" state_dir { immediately_before = 1 }
    NR == unlink_line + 1 && $0 == "sync:" state_dir { immediately_after = 1 }
    END { exit !(immediately_before && immediately_after) }
  ' "$STUB_EVENT_LOG"
}

assert_exact_paths() {
	actual="$TMPDIR/actual-seafile-paths"
	expected="$TMPDIR/expected-seafile-paths"
	find "$state_dir" -mindepth 1 -type d -print |
		sed "s#^$state_dir/##" |
		LC_ALL=C sort >"$actual"
	printf '%s\n' \
		backups \
		control \
		database \
		onlyoffice \
		onlyoffice/data \
		onlyoffice/lib \
		onlyoffice/logs \
		search \
		shared \
		>"$expected"
	cmp "$expected" "$actual"
}

assert_final_state() {
	assert_exact_paths
	test ! -e "$state_dir/.seafile-state-transaction"
	test ! -e "$state_dir/.seafile-state-transaction.next"
	test ! -e "$state_dir/.seafile-state-staging"
}

resume_initialization() {
	unset STUB_INSTALL_CRASH_MODE STUB_INSTALL_CRASH_AFTER
	unset STUB_MV_CRASH_AFTER STUB_MV_CRASH_MARKER_PHASE
	unset STUB_SYNC_CRASH_NEXT_PHASE STUB_RMDIR_CRASH
	run_validator --initialize
	assert_final_state
}

# A pristine dataset is valid only through the first-initialization path.
reset_state
expect_failure run_validator
run_validator --initialize
assert_final_state
assert_install_contract
assert_commit_fsync_order
run_validator

# Every construction boundary is durable and resumes through its explicit phase.
reset_state
export STUB_SYNC_CRASH_NEXT_PHASE=preparing
expect_failure run_validator --initialize
test -f "$state_dir/.seafile-state-transaction.next"
test ! -e "$state_dir/.seafile-state-transaction"
resume_initialization

reset_state
export STUB_MV_CRASH_MARKER_PHASE=preparing
expect_failure run_validator --initialize
test -f "$state_dir/.seafile-state-transaction"
test "$(tr -d '\n' <"$state_dir/.seafile-state-transaction")" = "v1 preparing"
resume_initialization

for preparing_crash in 0750:3 0700:2; do
	reset_state
	export STUB_INSTALL_CRASH_MODE="${preparing_crash%%:*}"
	export STUB_INSTALL_CRASH_AFTER="${preparing_crash##*:}"
	expect_failure run_validator --initialize
	test -f "$state_dir/.seafile-state-transaction"
	test "$(tr -d '\n' <"$state_dir/.seafile-state-transaction")" = "v1 preparing"
	resume_initialization
done

reset_state
export STUB_SYNC_CRASH_NEXT_PHASE=publishing
expect_failure run_validator --initialize
test -f "$state_dir/.seafile-state-transaction"
test -f "$state_dir/.seafile-state-transaction.next"
test "$(tr -d '\n' <"$state_dir/.seafile-state-transaction")" = "v1 preparing"
test "$(tr -d '\n' <"$state_dir/.seafile-state-transaction.next")" = "v1 publishing"
resume_initialization

reset_state
export STUB_MV_CRASH_MARKER_PHASE=publishing
expect_failure run_validator --initialize
test -f "$state_dir/.seafile-state-transaction"
test ! -e "$state_dir/.seafile-state-transaction.next"
test "$(tr -d '\n' <"$state_dir/.seafile-state-transaction")" = "v1 publishing"
resume_initialization

reset_state
export STUB_MV_CRASH_AFTER=3
expect_failure run_validator --initialize
test -f "$state_dir/.seafile-state-transaction"
test "$(tr -d '\n' <"$state_dir/.seafile-state-transaction")" = "v1 publishing"
resume_initialization

reset_state
export STUB_RMDIR_CRASH=1
expect_failure run_validator --initialize
test -f "$state_dir/.seafile-state-transaction"
test ! -e "$state_dir/.seafile-state-staging"
resume_initialization

# Marked recovery refuses content, symlink, ownership, or mode tampering.
reset_state
export STUB_INSTALL_CRASH_MODE=0750
export STUB_INSTALL_CRASH_AFTER=3
expect_failure run_validator --initialize
unset STUB_INSTALL_CRASH_MODE STUB_INSTALL_CRASH_AFTER
touch "$state_dir/.seafile-state-staging/shared/foreign"
expect_failure run_validator --initialize
test -f "$state_dir/.seafile-state-staging/shared/foreign"

reset_state
export STUB_INSTALL_CRASH_MODE=0750
export STUB_INSTALL_CRASH_AFTER=3
expect_failure run_validator --initialize
unset STUB_INSTALL_CRASH_MODE STUB_INSTALL_CRASH_AFTER
mkdir "$state_dir/.seafile-state-staging/foreign"
expect_failure run_validator --initialize
test -d "$state_dir/.seafile-state-staging/foreign"

reset_state
export STUB_MV_CRASH_AFTER=3
expect_failure run_validator --initialize
unset STUB_MV_CRASH_AFTER
touch "$state_dir/shared/foreign"
expect_failure run_validator --initialize
test -f "$state_dir/shared/foreign"

reset_state
export STUB_MV_CRASH_AFTER=3
expect_failure run_validator --initialize
unset STUB_MV_CRASH_AFTER
rm -rf "$state_dir/.seafile-state-staging/onlyoffice/data"
ln -s "$state_dir/shared" "$state_dir/.seafile-state-staging/onlyoffice/data"
expect_failure run_validator --initialize

reset_state
export STUB_MV_CRASH_AFTER=3
expect_failure run_validator --initialize
unset STUB_MV_CRASH_AFTER
export STUB_STAT_OVERRIDE_PATH="$state_dir/.seafile-state-transaction"
export STUB_STAT_OVERRIDE_TYPE="regular file"
export STUB_STAT_OVERRIDE_OWNER="4242:4242"
export STUB_STAT_OVERRIDE_MODE="600"
expect_failure run_validator --initialize

reset_state
export STUB_MV_CRASH_AFTER=3
expect_failure run_validator --initialize
unset STUB_MV_CRASH_AFTER
printf '%s\n' foreign-transaction >"$state_dir/.seafile-state-transaction"
expect_failure run_validator --initialize

reset_state
export STUB_MV_CRASH_AFTER=3
expect_failure run_validator --initialize
unset STUB_MV_CRASH_AFTER
export STUB_STAT_OVERRIDE_PATH="$state_dir/shared"
export STUB_STAT_OVERRIDE_OWNER="0:0"
export STUB_STAT_OVERRIDE_MODE="770"
expect_failure run_validator --initialize

# An unmarked foreign partial tree is never adopted or repaired.
reset_state
mkdir "$state_dir/shared"
expect_failure run_validator --initialize
test -d "$state_dir/shared"

reset_state
install -m 0600 -o 0 -g 0 /dev/null "$state_dir/.seafile-state-transaction.next"
printf '%s\n' "v1 preparing" >"$state_dir/.seafile-state-transaction.next"
mkdir "$state_dir/shared"
expect_failure run_validator --initialize
test -d "$state_dir/shared"

reset_state
install -m 0600 -o 0 -g 0 /dev/null "$state_dir/.seafile-state-transaction.next"
printf '%s\n' "v1 foreign" >"$state_dir/.seafile-state-transaction.next"
expect_failure run_validator --initialize

# Initialization is fail-closed: every possible partially initialized tree fails.
for missing_path in \
	shared \
	database \
	search \
	onlyoffice \
	onlyoffice/logs \
	onlyoffice/data \
	onlyoffice/lib \
	backups \
	control; do
	reset_state
	run_validator --initialize
	rm -rf "${state_dir:?}/$missing_path"
	expect_failure run_validator --initialize
	expect_failure run_validator
done

# MariaDB's exact pinned-image managed identity is accepted after initialization.
reset_state
run_validator --initialize
export STUB_STAT_OVERRIDE_PATH="$state_dir/database"
export STUB_STAT_OVERRIDE_OWNER="$database_managed_owner"
export STUB_STAT_OVERRIDE_MODE="700"
run_validator

# No post-start OnlyOffice chown is proven, so every bind source remains root-owned.
for managed_path in \
	onlyoffice/logs \
	onlyoffice/data \
	onlyoffice/lib; do
	reset_state
	run_validator --initialize
	export STUB_STAT_OVERRIDE_PATH="$state_dir/$managed_path"
	export STUB_STAT_OVERRIDE_OWNER="0:0"
	run_validator
	export STUB_STAT_OVERRIDE_OWNER="4242:4242"
	expect_failure run_validator
done

# The mount and every required ZFS invariant are checked independently.
reset_state
run_validator --initialize
export STUB_FINDMNT_SOURCE="synthetic_pool/state/wrong"
expect_failure run_validator
export STUB_FINDMNT_SOURCE="$dataset"
export STUB_FINDMNT_FSTYPE="ext4"
expect_failure run_validator
export STUB_FINDMNT_FSTYPE="zfs"
export STUB_FINDMNT_TARGET="$fixture_root"
expect_failure run_validator
export STUB_FINDMNT_TARGET="$state_dir"
export STUB_ZFS_QUOTA="1649267441663"
expect_failure run_validator
export STUB_ZFS_QUOTA="$quota"

for property in COMPRESSION ATIME ACLTYPE XATTR DNODESIZE; do
	variable="STUB_ZFS_$property"
	original="${!variable}"
	export "$variable=unsafe"
	expect_failure run_validator
	export "$variable=$original"
done

# Symlinks, unexpected identities, and group/world-writable paths are rejected.
reset_state
run_validator --initialize
rm -rf "$state_dir/search"
ln -s "$state_dir/shared" "$state_dir/search"
expect_failure run_validator

reset_state
run_validator --initialize
export STUB_STAT_OVERRIDE_PATH="$state_dir/shared"
export STUB_STAT_OVERRIDE_OWNER="4242:0"
expect_failure run_validator
export STUB_STAT_OVERRIDE_OWNER="0:4242"
expect_failure run_validator

export STUB_STAT_OVERRIDE_OWNER="0:0"
export STUB_STAT_OVERRIDE_MODE="770"
expect_failure run_validator
export STUB_STAT_OVERRIDE_MODE="751"
expect_failure run_validator

echo "Seafile runtime state-machine contract passed"

# Runtime configuration uses a separate fixture so the durable Task 1 crash and
# mount cases above remain intact.
runtime_root="$TMPDIR/seafile-runtime-config-fixture"
runtime_state="$runtime_root/state"
runtime_host="$runtime_root/run-host"
runtime_app="$runtime_root/run-app"
runtime_metadata="$runtime_root/run-metadata"
runtime_lock="$runtime_root/maintenance.lock"
runtime_source="$runtime_root/source.env"
runtime_stub_dir="$runtime_root/bin"

rm -rf "$runtime_root"
mkdir -p "$runtime_state" "$runtime_stub_dir"
runtime_owner="$($real_stat -c %u:%g "$runtime_state")"

cat >"$runtime_stub_dir/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${STUB_LIVE_CONTAINERS:-0}" = 1 ]; then
	printf '%s\n' synthetic-seafile-container
fi
EOF
chmod +x "$runtime_stub_dir/docker"

write_runtime_environment() {
	local suffix="$1"
	if [ -e "$runtime_source" ]; then
		chmod 0600 "$runtime_source"
	fi
	cat >"$runtime_source" <<EOF
INIT_SEAFILE_MYSQL_ROOT_PASSWORD=RootPassword0123456789abcdef0123${suffix}
SEAFILE_MYSQL_DB_PASSWORD=DatabasePassword0123456789abcdef0${suffix}
REDIS_PASSWORD=Allowed._~!@%+,/:=-Allowed._~!@%+,/:=-${suffix}
JWT_PRIVATE_KEY=JwtPrivateKey0123456789abcdef0123456${suffix}
SEAHUB_SECRET_KEY=SeahubSecretKey0123456789abcdef0123456789abcdef0123456${suffix}
INIT_SEAFILE_ADMIN_EMAIL=admin${suffix}@example.invalid
INIT_SEAFILE_ADMIN_PASSWORD=AdminPassword0123456789abcdef01234${suffix}
INIT_SS_ADMIN_USER=seasearch-admin${suffix}
INIT_SS_ADMIN_PASSWORD=SeaSearchPassword0123456789abcdef0${suffix}
SEAFILE_OAUTH_CLIENT_ID=seafile-client${suffix}
SEAFILE_OAUTH_CLIENT_SECRET=OAuthSecret0123456789abcdef0123456${suffix}
ONLYOFFICE_JWT_SECRET=OnlyOfficeSecret0123456789abcdef012${suffix}
EOF
	chmod 0400 "$runtime_source"
}

run_renderer() {
	env \
		SEAFILE_DOCKER_COMMAND="$runtime_stub_dir/docker" \
		SEAFILE_EXPECTED_OWNER="$runtime_owner" \
		"$renderer" \
		--source "$runtime_source" \
		--host-dir "$runtime_host" \
		--app-dir "$runtime_app" \
		--metadata-dir "$runtime_metadata" \
		--state-dir "$runtime_state" \
		--lock-file "$runtime_lock" \
		--lock-timeout 0
}

run_reconciler() {
	env \
		SEAFILE_DOCKER_COMMAND="$runtime_stub_dir/docker" \
		SEAFILE_EXPECTED_OWNER="$runtime_owner" \
		"$reconciler" \
		--source "$runtime_source" \
		--app-dir "$runtime_app" \
		--state-dir "$runtime_state" \
		--container-config-dir "$runtime_app" \
		--lock-file "$runtime_lock" \
		--lock-timeout 0 \
		--wait-timeout 0
}

assert_runtime_modes() {
	test "$($real_stat -c %a "$runtime_host")" = 700
	test "$($real_stat -c %a "$runtime_app")" = 700
	test "$($real_stat -c %a "$runtime_metadata")" = 555
	test "$($real_stat -c %a "$runtime_host/bootstrap.environment")" = 400
	test "$($real_stat -c %a "$runtime_host/environment")" = 400
	test "$($real_stat -c %a "$runtime_app/seafile.env")" = 400
	test "$($real_stat -c %a "$runtime_app/seahub_settings.py")" = 400
	test "$($real_stat -c %a "$runtime_app/seafevents.conf")" = 400
	test "$($real_stat -c %a "$runtime_metadata/seafile.conf")" = 444
}

assert_runtime_path_sets() {
	actual="$runtime_root/actual-host-paths"
	expected="$runtime_root/expected-host-paths"
	find "$runtime_host" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort >"$actual"
	printf '%s\n' bootstrap.environment environment >"$expected"
	cmp "$expected" "$actual"

	actual="$runtime_root/actual-app-paths"
	expected="$runtime_root/expected-app-paths"
	find "$runtime_app" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort >"$actual"
	printf '%s\n' seafdav.conf seafevents.conf seafile.conf seafile.env seahub_settings.py >"$expected"
	cmp "$expected" "$actual"

	actual="$runtime_root/actual-metadata-paths"
	expected="$runtime_root/expected-metadata-paths"
	find "$runtime_metadata" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort >"$actual"
	printf '%s\n' seafile.conf >"$expected"
	cmp "$expected" "$actual"
}

assert_environment_separation() {
	local bootstrap="$runtime_host/bootstrap.environment"
	local established="$runtime_host/environment"
	test "$(wc -l <"$bootstrap")" -eq 12
	test "$(cut -d= -f1 "$bootstrap" | LC_ALL=C sort -u | wc -l)" -eq 12
	test "$(wc -l <"$established")" -eq 9
	for bootstrap_only in \
		INIT_SEAFILE_MYSQL_ROOT_PASSWORD \
		INIT_SS_ADMIN_USER \
		INIT_SS_ADMIN_PASSWORD; do
		grep -F -- "$bootstrap_only=" "$bootstrap" >/dev/null
		if grep -F -- "$bootstrap_only=" "$established" "$runtime_app/seafile.env" >/dev/null; then
			echo "bootstrap-only key entered established runtime configuration" >&2
			exit 1
		fi
	done
	grep -F -- 'REDIS_PASSWORD=Allowed._~!@%+,/:=-Allowed._~!@%+,/:=-A' "$established" >/dev/null
	grep -F -- 'os.environ["SEAFILE_OAUTH_CLIENT_SECRET"]' "$runtime_app/seahub_settings.py" >/dev/null
	grep -F -- '[SEASEARCH]' "$runtime_app/seafevents.conf" >/dev/null
	grep -F -- 'enabled = true' "$runtime_app/seafevents.conf" >/dev/null
	grep -F -- 'url = http://seafile-seasearch:4080' "$runtime_app/seafevents.conf" >/dev/null
	grep -F -- 'interval = 600' "$runtime_app/seafevents.conf" >/dev/null
	grep -F -- 'index_office_pdf = true' "$runtime_app/seafevents.conf" >/dev/null
	grep -F -- '[INDEX FILES]' "$runtime_app/seafevents.conf" >/dev/null
	grep -F -- 'enabled = false' "$runtime_app/seafevents.conf" >/dev/null
	grep -F -x -- 'SEAFILE_MYSQL_DB_HOST=database' "$runtime_app/seafile.env" >/dev/null
	grep -F -x -- 'host = database' "$runtime_app/seafile.conf" >/dev/null
	if grep -R -F -- 'seafile-database' "$runtime_app" "$runtime_metadata" >/dev/null; then
		echo 'renderer emitted a database hostname absent from the Compose network' >&2
		exit 1
	fi
}

# A complete render is published with exact path sets, protected modes, literal
# values, and a strict bootstrap/established split.
echo "runtime fixture: initial render"
write_runtime_environment A
valid_runtime_source="$runtime_root/valid-source.env"
cp "$runtime_source" "$valid_runtime_source"

nul_key_source="$runtime_root/nul-key-source.env"
grep -v '^REDIS_PASSWORD=' "$valid_runtime_source" >"$nul_key_source"
printf 'REDIS\000_PASSWORD=Allowed._~!@%%+,/:=-Allowed._~!@%%+,/:=-A\n' >>"$nul_key_source"
chmod 0400 "$nul_key_source"
runtime_source="$nul_key_source"
expect_failure run_renderer

nul_value_source="$runtime_root/nul-value-source.env"
grep -v '^JWT_PRIVATE_KEY=' "$valid_runtime_source" >"$nul_value_source"
printf 'JWT_PRIVATE_KEY=JwtPrivateKey012345\0006789abcdef0123456A\n' >>"$nul_value_source"
chmod 0400 "$nul_value_source"
runtime_source="$nul_value_source"
expect_failure run_renderer

runtime_source="$valid_runtime_source"
run_renderer
assert_runtime_modes
assert_runtime_path_sets
assert_environment_separation
first_environment="$runtime_root/first-environment"
cp "$runtime_host/environment" "$first_environment"

# A replacement render changes the complete protected view and does not retain
# a prior inode or expand punctuation through the shell.
echo "runtime fixture: replacement render"
write_runtime_environment B
run_renderer
if cmp "$first_environment" "$runtime_host/environment" >/dev/null; then
	echo "runtime renderer did not replace the established environment" >&2
	exit 1
fi
grep -F -- 'REDIS_PASSWORD=Allowed._~!@%+,/:=-Allowed._~!@%+,/:=-B' \
	"$runtime_host/environment" >/dev/null
assert_runtime_path_sets

# Unknown output is fail-closed and remains untouched for diagnosis.
echo "runtime fixture: unexpected output"
touch "$runtime_app/foreign-output"
expect_failure run_renderer
test -e "$runtime_app/foreign-output"
rm "$runtime_app/foreign-output"

# Expected basenames are valid only when an existing destination is the exact
# protected regular-file state from an earlier render.
rm "$runtime_app/seafile.conf"
mkdir "$runtime_app/seafile.conf"
expect_failure run_renderer
test -d "$runtime_app/seafile.conf"
rmdir "$runtime_app/seafile.conf"
run_renderer

rm "$runtime_host/environment"
ln -s "$first_environment" "$runtime_host/environment"
expect_failure run_renderer
test -L "$runtime_host/environment"
test "$(readlink "$runtime_host/environment")" = "$first_environment"
rm "$runtime_host/environment"
run_renderer

# A live owned container prevents any rewrite of the already published tree.
echo "runtime fixture: live container"
before_live="$runtime_root/before-live"
cp "$runtime_host/environment" "$before_live"
write_runtime_environment C
export STUB_LIVE_CONTAINERS=1
expect_failure run_renderer
unset STUB_LIVE_CONTAINERS
cmp "$before_live" "$runtime_host/environment"

# Lock ambiguity times out before either runtime or persistent state changes.
echo "runtime fixture: lock contention"
lock_held="$runtime_root/lock-held"
# shellcheck disable=SC2016 # $1 expands in the nested Bash process.
flock "$runtime_lock" bash -c 'touch "$1"; sleep 2' _ "$lock_held" &
lock_holder=$!
for _ in $(seq 20); do
	test -e "$lock_held" && break
	sleep 0.05
done
test -e "$lock_held"
state_before_lock="$runtime_root/state-before-lock"
find "$runtime_state" -mindepth 1 -print | LC_ALL=C sort >"$state_before_lock"
expect_failure run_renderer
state_after_lock="$runtime_root/state-after-lock"
find "$runtime_state" -mindepth 1 -print | LC_ALL=C sort >"$state_after_lock"
cmp "$state_before_lock" "$state_after_lock"
wait "$lock_holder"

# Fresh upstream bootstrap output is replaced only at the exact five managed
# paths, and an initialized tree validates idempotently.
echo "runtime fixture: reconciliation"
write_runtime_environment B
run_renderer
config_dir="$runtime_state/shared/seafile/conf"
mkdir -p "$runtime_state/shared/seafile/seafile-data" "$config_dir"
printf '%s\n' '13.0.25' >"$runtime_state/shared/seafile/seafile-data/current_version"
for managed in .env seahub_settings.py seafevents.conf seafile.conf seafdav.conf; do
	printf '%s\n' upstream >"$config_dir/$managed"
	chmod 0600 "$config_dir/$managed"
done
run_reconciler
for managed in .env seahub_settings.py seafevents.conf seafile.conf seafdav.conf; do
	test -L "$config_dir/$managed"
done
test "$(readlink "$config_dir/.env")" = "$runtime_app/seafile.env"
run_reconciler

# A foreign symlink, unsafe mode, or unexpected owner is never adopted.
echo "runtime fixture: unsafe reconciliation inputs"
rm "$config_dir/seafile.conf"
ln -s "$runtime_root/foreign" "$config_dir/seafile.conf"
expect_failure run_reconciler
test "$(readlink "$config_dir/seafile.conf")" = "$runtime_root/foreign"

rm "$config_dir/seafile.conf"
printf '%s\n' upstream >"$config_dir/seafile.conf"
chmod 0666 "$config_dir/seafile.conf"
expect_failure run_reconciler
test ! -L "$config_dir/seafile.conf"

chmod 0600 "$config_dir/seafile.conf"
SEAFILE_EXPECTED_OWNER=99999:99999 expect_failure "$reconciler" \
	--source "$runtime_source" \
	--app-dir "$runtime_app" \
	--state-dir "$runtime_state" \
	--container-config-dir "$runtime_app" \
	--lock-file "$runtime_lock" \
	--lock-timeout 0 \
	--wait-timeout 0
test ! -L "$config_dir/seafile.conf"

# Persistent secret residue is detected without printing the matching value.
echo "runtime fixture: persistent secret scan"
run_reconciler
mkdir -p "$runtime_state/shared/logs"
oversized_pattern="$runtime_root/oversized-pattern"
grep '^JWT_PRIVATE_KEY=' "$runtime_source" | cut -d= -f2- >"$oversized_pattern"
oversized_log="$runtime_state/shared/logs/oversized.log"
cp "$oversized_pattern" "$oversized_log"
truncate -s 16777216 "$oversized_log"
oversized_output="$runtime_root/oversized-output"
if run_reconciler >"$oversized_output" 2>&1; then
	echo "reconciler silently skipped an oversized persistent log" >&2
	exit 1
fi
if grep -F -f "$oversized_pattern" "$oversized_output" >/dev/null; then
	echo "reconciler exposed content from an oversized persistent log" >&2
	exit 1
fi
rm "$oversized_log"

secret_residue="$runtime_state/shared/foreign.conf"
grep '^JWT_PRIVATE_KEY=' "$runtime_source" | cut -d= -f2- >"$secret_residue"
chmod 0600 "$secret_residue"
scan_output="$runtime_root/scan-output"
if run_reconciler >"$scan_output" 2>&1; then
	echo "reconciler accepted persistent secret residue" >&2
	exit 1
fi
secret_value="$(cat "$secret_residue")"
if grep -F -- "$secret_value" "$scan_output" >/dev/null; then
	echo "reconciler exposed a secret match" >&2
	exit 1
fi

echo "Seafile runtime configuration contract passed"

# The stack fixture exercises the real orchestration helper with synthetic
# Docker and systemd boundaries. It never starts or removes a real container.
stack_root="$TMPDIR/seafile-stack-fixture"
stack_state="$stack_root/state"
stack_host="$stack_root/run-host"
stack_app="$stack_root/run-app"
stack_metadata="$stack_root/run-metadata"
stack_lock="$stack_root/maintenance.lock"
stack_bin="$stack_root/bin"
stack_log="$stack_root/events.log"
stack_running="$stack_root/running-containers"

reset_stack_fixture() {
	rm -rf "$stack_root"
	mkdir -p \
		"$stack_state/shared/seafile/seafile-data" \
		"$stack_state/shared/seafile/conf" \
		"$stack_host" "$stack_app" "$stack_metadata" "$stack_bin"
	cp "$runtime_host/bootstrap.environment" "$stack_host/bootstrap.environment"
	cp "$runtime_host/environment" "$stack_host/environment"
	cp -R "$runtime_app/." "$stack_app/"
	cp -R "$runtime_metadata/." "$stack_metadata/"
	: >"$stack_log"
	cat >"$stack_bin/seafile-reconcile-runtime-config" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# The production inherited-FD proof uses Linux /proc. This contract runs on
# Darwin, so adapt only that proof to an independent synthetic lock while the
# real reconciler still enforces its owned-container and state gates.
arguments=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --lock-file)
      arguments+=(--lock-file "${STUB_RECONCILE_LOCK:?}")
      shift 2
      ;;
    *)
      arguments+=("$1")
      shift
      ;;
  esac
done
exec 9>&-
exec env -u SEAFILE_MAINTENANCE_LOCK_FD -u SEAFILE_ORCHESTRATION_STOPPED \
  "${STUB_REAL_RECONCILER:?}" "${arguments[@]}"
EOF
	cat >"$stack_bin/journalctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${STUB_JOURNAL_CONTENT:-}"
if [ "${STUB_JOURNAL_PAD_BYTES:-0}" -gt 0 ]; then
  head -c "$STUB_JOURNAL_PAD_BYTES" /dev/zero | tr '\000' x
fi
EOF
	cat >"$stack_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if ! flock -n "${STUB_STACK_LOCK:?}" -c true; then
  printf 'systemctl-lock:held\n' >>"${STUB_STACK_LOG:?}"
  exit 70
fi
printf 'systemctl-lock:released\n' >>"${STUB_STACK_LOG:?}"
printf 'systemctl:%s\n' "$*" >>"${STUB_STACK_LOG:?}"
case " $* " in
  *" is-active "*) [ "${STUB_SYSTEMD_ACTIVE:-0}" = 1 ] ;;
esac
EOF
	cat >"$stack_bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

contains_line() {
  [ -f "$1" ] && grep -F -x -- "$2" "$1" >/dev/null
}

add_line() {
  touch "$1"
  contains_line "$1" "$2" || printf '%s\n' "$2" >>"$1"
}

remove_line() {
  local temporary
  temporary="$1.next"
  if [ -f "$1" ]; then
    grep -F -v -x -- "$2" "$1" >"$temporary" || true
  else
    : >"$temporary"
  fi
  mv -f "$temporary" "$1"
}

container_for_service() {
  case "$1" in
    database) printf '%s\n' seafile-mariadb ;;
    metadata) printf '%s\n' seafile-metadata ;;
    notification) printf '%s\n' seafile-notification ;;
    onlyoffice) printf '%s\n' seafile-onlyoffice ;;
    redis) printf '%s\n' seafile-redis ;;
    seafile) printf '%s\n' seafile ;;
    seasearch) printf '%s\n' seafile-seasearch ;;
    *) printf 'unexpected Compose service: %s\n' "$1" >&2; exit 64 ;;
  esac
}

printf 'docker:%s\n' "$*" >>"${STUB_STACK_LOG:?}"
if [ "$1" = compose ]; then
  seen_up=0
  skip_next=0
  services=()
  for argument in "$@"; do
    if [ "$seen_up" -eq 0 ]; then
      [ "$argument" = up ] && seen_up=1
      continue
    fi
    if [ "$skip_next" -eq 1 ]; then
      skip_next=0
      continue
    fi
    case "$argument" in
      --wait-timeout) skip_next=1 ;;
      --detach|--wait|--force-recreate) ;;
      --*) ;;
      *) services+=("$argument") ;;
    esac
  done
  [ "$seen_up" -eq 1 ] || exit 0
  if [[ " $* " == *" up "* ]] && [ "${STUB_FAIL_STAGE:-}" = "${*: -1}" ]; then
    exit 1
  fi
  if [ "${#services[@]}" -eq 0 ] \
    && [[ " $* " == *" --wait "* ]] \
    && [ "${STUB_FAIL_FINAL_ONCE:-0}" = 1 ] \
    && [ ! -e "${STUB_FAIL_ONCE_MARKER:?}" ]; then
    touch "$STUB_FAIL_ONCE_MARKER"
    exit 1
  fi
  if [ "${STUB_FAIL_RESTORE:-0}" = 1 ] \
    && [ "${services[*]:-}" = "seafile database" ]; then
    exit 1
  fi
  if [ "${STUB_FAIL_AUTO_DEPS:-0}" = 1 ] \
    && [ "${services[*]:-}" = seafile ] \
    && [[ " $* " != *" --no-deps "* ]]; then
    add_line "${STUB_CONTAINER_FILE:?}" seafile-mariadb
    add_line "${STUB_CONTAINER_FILE:?}" seafile-redis
    add_line "${STUB_RUNNING_FILE:?}" seafile-mariadb
    add_line "${STUB_RUNNING_FILE:?}" seafile-redis
    exit 1
  fi
  if [ "${#services[@]}" -eq 0 ]; then
    services=(database metadata notification onlyoffice redis seafile seasearch)
  fi
  for service in "${services[@]}"; do
    container="$(container_for_service "$service")"
    add_line "${STUB_CONTAINER_FILE:?}" "$container"
    add_line "${STUB_RUNNING_FILE:?}" "$container"
    if [ "$service" = seafile ]; then
      mkdir -p "${STUB_STACK_STATE:?}/shared/seafile/seafile-data"
      printf '13.0.25\n' >"$STUB_STACK_STATE/shared/seafile/seafile-data/current_version"
    fi
  done
  exit 0
fi
case "$1" in
  kill)
    remove_line "${STUB_RUNNING_FILE:?}" "${*: -1}"
    ;;
  logs)
    printf '%s\n' "${STUB_DOCKER_LOG_CONTENT:-}"
    if [ "${STUB_DOCKER_LOG_PAD_BYTES:-0}" -gt 0 ]; then
      head -c "$STUB_DOCKER_LOG_PAD_BYTES" /dev/zero | tr '\000' x
    fi
    ;;
  ps)
    if [[ " $* " == *"name=^/"* ]]; then
      for argument in "$@"; do
        case "$argument" in
          name='^/'*'$')
            name="${argument#name=^/}"
            name="${name%\$}"
            contains_line "${STUB_RUNNING_FILE:?}" "$name" && printf '%s-id\n' "$name"
            ;;
        esac
      done
    elif [[ " $* " == *"com.docker.compose.project=seafile"* ]]; then
      if [[ " $* " == *" --all "* ]]; then
        if [ -f "${STUB_CONTAINER_FILE:?}" ]; then
          cat "$STUB_CONTAINER_FILE"
        elif [ -n "${STUB_PROJECT_CONTAINERS:-}" ]; then
          printf '%s\n' $STUB_PROJECT_CONTAINERS
        fi
      else
        running_snapshot=""
        if [ -f "${STUB_RUNNING_FILE:?}" ]; then
          cat "$STUB_RUNNING_FILE"
          running_snapshot="$(tr '\n' ',' <"$STUB_RUNNING_FILE")"
        fi
        printf 'docker-project-running:%s\n' "$running_snapshot" >>"${STUB_STACK_LOG:?}"
      fi
    fi
    ;;
  inspect)
    if [[ " $* " == *"Config.Env"* ]]; then
      printf '%s\n' "${STUB_INSPECT_ENV_KEYS:-INIT_SEAFILE_ADMIN_EMAIL INIT_SEAFILE_ADMIN_PASSWORD}"
    elif [[ " $* " == *"State.Health.Status"* ]]; then
      printf '%s\n' healthy
    else
      printf '%s\n' true
    fi
    ;;
esac
EOF
	chmod +x "$stack_bin/docker" "$stack_bin/journalctl" \
		"$stack_bin/seafile-reconcile-runtime-config" "$stack_bin/systemctl"
	export STUB_STACK_LOG="$stack_log"
	export STUB_STACK_STATE="$stack_state"
	export STUB_STACK_APP="$stack_app"
	export STUB_CONTAINER_FILE="$stack_root/containers"
	export STUB_RUNNING_FILE="$stack_running"
	export STUB_FAIL_ONCE_MARKER="$stack_root/failed-once"
	export STUB_REAL_RECONCILER="$reconciler"
	export STUB_RECONCILE_LOCK="$stack_root/reconciler.lock"
	export STUB_STACK_LOCK="$stack_lock"
	export STUB_PROJECT_CONTAINERS=""
	export STUB_INSPECT_ENV_KEYS="INIT_SEAFILE_ADMIN_EMAIL INIT_SEAFILE_ADMIN_PASSWORD"
	export STUB_SYSTEMD_ACTIVE=0
	unset STUB_CAPTURE_MAX_BYTES STUB_DOCKER_LOG_CONTENT STUB_DOCKER_LOG_PAD_BYTES \
		STUB_FAIL_AUTO_DEPS STUB_FAIL_RESTORE STUB_FAIL_STAGE STUB_FAIL_FINAL_ONCE \
		STUB_JOURNAL_CONTENT STUB_JOURNAL_PAD_BYTES
}

run_stack_helper() {
	env \
		PATH="$stack_bin:$PATH" \
		SEAFILE_STATE_DIR="$stack_state" \
		SEAFILE_HOST_DIR="$stack_host" \
		SEAFILE_APP_DIR="$stack_app" \
		SEAFILE_METADATA_DIR="$stack_metadata" \
		SEAFILE_MAINTENANCE_LOCK="$stack_lock" \
		SEAFILE_LOCK_TIMEOUT=0 \
		SEAFILE_WAIT_TIMEOUT=1 \
		SEAFILE_STOP_TIMEOUT=1 \
		SEAFILE_DOCKER_COMMAND="$stack_bin/docker" \
		SEAFILE_SYSTEMCTL_COMMAND="$stack_bin/systemctl" \
		SEAFILE_JOURNALCTL_COMMAND="$stack_bin/journalctl" \
		SEAFILE_RECONCILE_COMMAND="$stack_bin/seafile-reconcile-runtime-config" \
		SEAFILE_LOG_CAPTURE_MAX_BYTES="${STUB_CAPTURE_MAX_BYTES:-16777215}" \
		SEAFILE_EXPECTED_OWNER="$runtime_owner" \
		"$compose_starter" "$@"
}

# Fresh bootstrap is staged, reconciled under the inherited lock, stripped of
# removable init variables, and followed by the exact seven-service start.
reset_stack_fixture
run_stack_helper start
grep -F -- '--env-file '"$stack_host/bootstrap.environment" "$stack_log" >/dev/null
grep -F -- 'database redis seafile' "$stack_log" >/dev/null
grep -F -- 'docker:kill --signal TERM seafile' "$stack_log" >/dev/null
grep -F -- 'docker:kill --signal TERM seafile-mariadb' "$stack_log" >/dev/null
grep -F -- 'docker:kill --signal TERM seafile-redis' "$stack_log" >/dev/null
grep -F -x -- 'docker-project-running:' "$stack_log" >/dev/null
for managed in .env seahub_settings.py seafevents.conf seafile.conf seafdav.conf; do
	test -L "$stack_state/shared/seafile/conf/$managed"
done
grep -F -- '--force-recreate database seasearch' "$stack_log" >/dev/null
grep -F -- '--env-file '"$stack_host/environment" "$stack_log" >/dev/null

# Rollback restores an exact running set without Compose dependency traversal.
# With only Seafile running on entry, MariaDB and Redis remain stopped.
reset_stack_fixture
printf '13.0.25\n' >"$stack_state/shared/seafile/seafile-data/current_version"
printf '%s\n' seafile seafile-mariadb seafile-redis >"$STUB_CONTAINER_FILE"
printf '%s\n' seafile >"$STUB_RUNNING_FILE"
export STUB_FAIL_AUTO_DEPS=1 STUB_FAIL_FINAL_ONCE=1
no_deps_output="$stack_root/no-deps-output"
if run_stack_helper start >"$no_deps_output" 2>&1; then
	echo "startup unexpectedly succeeded after the injected final failure" >&2
	exit 1
fi
if grep -F 'failure recovery could not restore the entry stack' "$no_deps_output"; then
	echo "rollback allowed Compose to traverse stopped dependencies" >&2
	exit 1
fi
grep -F -- 'up --detach --no-deps seafile' "$stack_log" >/dev/null
printf '%s\n' seafile >"$stack_root/expected-running"
cmp "$stack_root/expected-running" "$STUB_RUNNING_FILE"

# Mid-stage failure stops work started by this invocation. When the unit owned
# an established stack on entry, only those exact known containers are brought
# back through Compose; Docker start is never used.
reset_stack_fixture
printf '13.0.25\n' >"$stack_state/shared/seafile/seafile-data/current_version"
printf '%s\n' seafile seafile-mariadb seafile-metadata seafile-notification \
	seafile-onlyoffice seafile-redis seafile-seasearch >"$STUB_CONTAINER_FILE"
printf '%s\n' seafile seafile-mariadb >"$STUB_RUNNING_FILE"
export STUB_FAIL_FINAL_ONCE=1
expect_failure run_stack_helper start
grep -F -- 'up --detach --no-deps seafile database' "$stack_log" >/dev/null
if grep -F -- 'up --detach seafile seafile-mariadb' "$stack_log"; then
	echo "failure recovery passed container names to Compose" >&2
	exit 1
fi
printf '%s\n' seafile seafile-mariadb | LC_ALL=C sort >"$stack_root/expected-running"
LC_ALL=C sort "$STUB_RUNNING_FILE" >"$stack_root/actual-running"
cmp "$stack_root/expected-running" "$stack_root/actual-running"
if grep -F 'docker:start' "$stack_log"; then
	echo "failure recovery started a container directly" >&2
	exit 1
fi

# A restore failure is explicit rather than being swallowed by the ERR trap.
reset_stack_fixture
printf '13.0.25\n' >"$stack_state/shared/seafile/seafile-data/current_version"
printf '%s\n' seafile seafile-mariadb >"$STUB_CONTAINER_FILE"
cp "$STUB_CONTAINER_FILE" "$STUB_RUNNING_FILE"
export STUB_FAIL_FINAL_ONCE=1 STUB_FAIL_RESTORE=1
rollback_output="$stack_root/rollback-output"
if run_stack_helper start >"$rollback_output" 2>&1; then
	echo "startup accepted a failed ownership restore" >&2
	exit 1
fi
grep -F 'failure recovery could not restore the entry stack' "$rollback_output" >/dev/null

# An unrecognized project-labelled residue is refused and never deleted.
reset_stack_fixture
export STUB_PROJECT_CONTAINERS=seafile-foreign
expect_failure run_stack_helper start
grep -F 'docker:ps --all --filter label=com.docker.compose.project=seafile' "$stack_log" >/dev/null
if grep -E 'docker:(rm|kill).*seafile-foreign' "$stack_log"; then
	echo "unknown project residue was modified" >&2
	exit 1
fi

# Established state never uses the bootstrap interpolation file.
reset_stack_fixture
printf '13.0.25\n' >"$stack_state/shared/seafile/seafile-data/current_version"
run_stack_helper start
if grep -F -- '--env-file '"$stack_host/bootstrap.environment" "$stack_log" >/dev/null; then
	echo "established startup exposed bootstrap interpolation" >&2
	exit 1
fi
grep -F -x -- 'docker-project-running:' "$stack_log" >/dev/null

# Only the exact protected JSON residue produced by pinned start.py is removed.
reset_stack_fixture
printf '13.0.25\n' >"$stack_state/shared/seafile/seafile-data/current_version"
admin_email="$(sed -n 's/^INIT_SEAFILE_ADMIN_EMAIL=//p' "$stack_host/environment")"
admin_password="$(sed -n 's/^INIT_SEAFILE_ADMIN_PASSWORD=//p' "$stack_host/environment")"
printf '{"email": "%s", "password": "%s"}' "$admin_email" "$admin_password" \
	>"$stack_state/shared/seafile/conf/admin.txt"
chmod 0600 "$stack_state/shared/seafile/conf/admin.txt"
run_stack_helper start
test ! -e "$stack_state/shared/seafile/conf/admin.txt"

reset_stack_fixture
printf '13.0.25\n' >"$stack_state/shared/seafile/seafile-data/current_version"
printf '%s\n' '{"email":"foreign","password":"foreign"}' \
	>"$stack_state/shared/seafile/conf/admin.txt"
chmod 0600 "$stack_state/shared/seafile/conf/admin.txt"
expect_failure run_stack_helper start
test -f "$stack_state/shared/seafile/conf/admin.txt"

# Docker and journal output is captured to protected bounded files before a
# quiet scan, so an early match cannot be hidden by producer SIGPIPE. Neither
# the secret match nor an over-bound payload is printed.
stack_secret="$(sed -n 's/^JWT_PRIVATE_KEY=//p' "$runtime_host/bootstrap.environment")"
reset_stack_fixture
printf '13.0.25\n' >"$stack_state/shared/seafile/seafile-data/current_version"
export STUB_DOCKER_LOG_CONTENT="$stack_secret" STUB_DOCKER_LOG_PAD_BYTES=1048576
docker_scan_output="$stack_root/docker-scan-output"
if run_stack_helper start >"$docker_scan_output" 2>&1; then
	echo "startup missed sensitive Docker log output" >&2
	exit 1
fi
if grep -F -- "$stack_secret" "$docker_scan_output" >/dev/null; then
	echo "Docker log scan exposed the sensitive match" >&2
	exit 1
fi

reset_stack_fixture
printf '13.0.25\n' >"$stack_state/shared/seafile/seafile-data/current_version"
export STUB_JOURNAL_CONTENT="$stack_secret" STUB_JOURNAL_PAD_BYTES=1048576
journal_scan_output="$stack_root/journal-scan-output"
if run_stack_helper start >"$journal_scan_output" 2>&1; then
	echo "startup missed sensitive journal output" >&2
	exit 1
fi
if grep -F -- "$stack_secret" "$journal_scan_output" >/dev/null; then
	echo "journal scan exposed the sensitive match" >&2
	exit 1
fi

reset_stack_fixture
printf '13.0.25\n' >"$stack_state/shared/seafile/seafile-data/current_version"
export STUB_CAPTURE_MAX_BYTES=64 STUB_DOCKER_LOG_CONTENT=public \
	STUB_DOCKER_LOG_PAD_BYTES=65
bounded_scan_output="$stack_root/bounded-scan-output"
if run_stack_helper start >"$bounded_scan_output" 2>&1; then
	echo "startup accepted over-bound Docker log output" >&2
	exit 1
fi
grep -F 'Docker log output exceeded its capture bound' "$bounded_scan_output" >/dev/null

# Start and stop lock contention is non-mutating.
for action in start stop; do
	reset_stack_fixture
	# shellcheck disable=SC2016
	flock "$stack_lock" bash -c 'touch "$1"; sleep 2' _ "$stack_root/held" &
	stack_lock_holder=$!
	for _ in $(seq 20); do
		test -e "$stack_root/held" && break
		sleep 0.05
	done
	expect_failure run_stack_helper "$action"
	test ! -s "$stack_log"
	wait "$stack_lock_holder"
done

# Recovery of a crashed container and a restarted daemon is delegated only to
# the guarded systemd start/reload path; Docker is never started directly.
reset_stack_fixture
export STUB_SYSTEMD_ACTIVE=1
export STUB_PROJECT_CONTAINERS="seafile seafile-mariadb seafile-redis"
run_stack_helper recover
grep -F -x 'systemctl-lock:released' "$stack_log" >/dev/null
grep -F 'systemctl:--no-block reload seafile-compose.service' "$stack_log" >/dev/null
if grep -F 'systemctl-lock:held' "$stack_log"; then
	echo "recovery called systemctl while retaining the maintenance lock" >&2
	exit 1
fi
if grep -F 'docker:start' "$stack_log"; then
	echo "container recovery bypassed systemd" >&2
	exit 1
fi

reset_stack_fixture
export STUB_SYSTEMD_ACTIVE=0
run_stack_helper recover
grep -F -x 'systemctl-lock:released' "$stack_log" >/dev/null
grep -F 'systemctl:--no-block start seafile-compose.service' "$stack_log" >/dev/null
if grep -F 'systemctl-lock:held' "$stack_log"; then
	echo "daemon recovery called systemctl while retaining the maintenance lock" >&2
	exit 1
fi
if grep -F 'docker:start' "$stack_log"; then
	echo "daemon recovery bypassed systemd" >&2
	exit 1
fi

echo "Seafile stack lifecycle contract passed"
