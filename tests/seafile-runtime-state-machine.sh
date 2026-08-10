#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
	echo "usage: $0 VALIDATOR" >&2
	exit 64
fi

validator="$1"
database_managed_owner="999:999"

fixture_root="$TMPDIR/seafile-state-fixture"
state_dir="$fixture_root/state"
stub_dir="$fixture_root/bin"
dataset="synthetic_pool/state/seafile"
quota="1649267441664"

mkdir -p "$state_dir" "$stub_dir"
real_mv="$(command -v mv)"
real_rmdir="$(command -v rmdir)"
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
