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

cat >"$stub_dir/findmnt" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case " $* " in
  *" SOURCE "*) printf '%s\n' "${STUB_FINDMNT_SOURCE:?}" ;;
  *" FSTYPE "*) printf '%s\n' "${STUB_FINDMNT_FSTYPE:?}" ;;
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
    */database|*/backups|*/control) mode="700" ;;
    *) mode="750" ;;
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
[ "$directory" -eq 1 ] && [ -n "$mode" ] && [ -n "$owner" ] && [ -n "$group" ]
for path in "${paths[@]}"; do
  printf '%s\t%s\t%s\t%s\n' "$mode" "$owner" "$group" "$path" >> "${STUB_INSTALL_LOG:?}"
done
mkdir -p "${paths[@]}"
EOF

cat >"$stub_dir/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
count=0
if [ -f "${STUB_MV_COUNT:?}" ]; then
  count="$(cat "$STUB_MV_COUNT")"
fi
count="$((count + 1))"
printf '%s\n' "$count" > "$STUB_MV_COUNT"
if [ -n "${STUB_MV_FAIL_AFTER:-}" ] && [ "$count" -eq "$STUB_MV_FAIL_AFTER" ]; then
  exit 74
fi
exec "${STUB_REAL_MV:?}" "$@"
EOF

chmod +x "$stub_dir/findmnt" "$stub_dir/zfs" "$stub_dir/stat" "$stub_dir/install" "$stub_dir/mv"

export PATH="$stub_dir:$PATH"
export STUB_REAL_MV="$real_mv"
export STUB_INSTALL_LOG="$fixture_root/install.log"
export STUB_MV_COUNT="$fixture_root/mv-count"
export STUB_FINDMNT_SOURCE="$dataset"
export STUB_FINDMNT_FSTYPE="zfs"
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
	rm -f "$STUB_MV_COUNT"
	unset STUB_MV_FAIL_AFTER
	unset STUB_STAT_OVERRIDE_PATH STUB_STAT_OVERRIDE_TYPE STUB_STAT_OVERRIDE_OWNER STUB_STAT_OVERRIDE_MODE
	export STUB_FINDMNT_SOURCE="$dataset"
	export STUB_FINDMNT_FSTYPE="zfs"
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
	sed -E "s#$state_dir/\\.seafile-state\\.[^/]+#STAGING#" "$STUB_INSTALL_LOG" >"$actual"
	printf '%s\n' \
		$'0750\t0\t0\tSTAGING/shared' \
		$'0750\t0\t0\tSTAGING/search' \
		$'0750\t0\t0\tSTAGING/onlyoffice' \
		$'0750\t0\t0\tSTAGING/onlyoffice/logs' \
		$'0750\t0\t0\tSTAGING/onlyoffice/data' \
		$'0750\t0\t0\tSTAGING/onlyoffice/lib' \
		$'0700\t0\t0\tSTAGING/database' \
		$'0700\t0\t0\tSTAGING/backups' \
		$'0700\t0\t0\tSTAGING/control' \
		>"$expected"
	cmp "$expected" "$actual"
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

# A pristine dataset is valid only through the first-initialization path.
reset_state
expect_failure run_validator
run_validator --initialize
assert_exact_paths
assert_install_contract
run_validator

# A failed multi-path commit rolls back every path created by this invocation.
reset_state
export STUB_MV_FAIL_AFTER=3
expect_failure run_validator --initialize
test -z "$(find "$state_dir" -mindepth 1 -maxdepth 1 -print -quit)"

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
