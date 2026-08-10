#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 7 ]; then
	echo "usage: $0 LOGICAL VALIDATE PREPARE CLEANUP RESTORE_PREPARE RESTORE_VERIFY RESTORE_TEARDOWN" >&2
	exit 64
fi

logical="$1"
validate="$2"
prepare="$3"
cleanup="$4"
restore_prepare="$5"
restore_verify="$6"
restore_teardown="$7"
: "$validate"

root="$(mktemp -d "$TMPDIR/seafile-backup-fixture.XXXXXX")"
trap 'rm -rf -- "$root"' EXIT HUP INT TERM
bin="$root/bin"
state="$root/state"
runtime="$root/runtime"
validator_state="$root/validator"
events="$root/events"
snapshot_state="$root/snapshot-state"
mkdir -p "$bin" "$state/backups" "$state/control" "$state/shared/logs" \
	"$state/shared/seafile/logs" "$runtime" "$validator_state"
: >"$events"
: >"$snapshot_state"
real_install="$(command -v install)"

cat >"$bin/install" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
arguments=()
while [ "$#" -gt 0 ]; do
	case "$1" in
		-o|-g) shift 2 ;;
		*) arguments+=("$1"); shift ;;
	esac
done
exec "$STUB_REAL_INSTALL" "${arguments[@]}"
EOF

cat >"$bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'systemctl:%s\n' "$*" >>"$STUB_EVENTS"
case "$1" in
	is-active) [ "${STUB_STACK_ACTIVE:-1}" = 1 ] ;;
	start) ;;
	*) echo "unexpected systemctl invocation: $*" >&2; exit 64 ;;
esac
EOF

cat >"$bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'docker:%s\n' "$*" >>"$STUB_EVENTS"
case "$1" in
	inspect)
		if [[ "$*" == *'{{.State.Running}}'* ]]; then
			[ "${STUB_CONTAINER_RUNNING:-1}" = 1 ] && printf 'true\n' || printf 'false\n'
		elif [[ "$*" == *'{{.Id}}'* ]]; then
			printf '%s\n' "${STUB_CONTAINER_ID:-owned-container-id}"
		elif [[ "$*" == *'{{index .Config.Labels '* ]]; then
			printf '%s\n' "${STUB_CONTAINER_LABEL:-}"
		else
			printf '%s\n' "${STUB_CONTAINER_ID:-owned-container-id}"
		fi
		;;
	exec)
		if [[ "$*" == *documentserver-prepare4shutdown.sh* ]] && [ "${STUB_ONLYOFFICE_PREPARE_FAIL:-0}" = 1 ]; then
			exit 75
		fi
		if [[ "$*" == *mariadb-dump* ]]; then
			printf '%s\n' 'CREATE TABLE fixture (id int);'
		fi
		if [[ "$*" == *'SELECT COUNT(*)'* ]]; then
			printf '1\n'
		fi
		;;
	kill)
		[ "${STUB_STOP_FAIL:-0}" = 0 ] || exit 75
		export STUB_CONTAINER_RUNNING=0
		;;
	start) ;;
	run)
		cidfile=
		previous=
		for argument in "$@"; do
			if [ "$previous" = --cidfile ]; then cidfile="$argument"; fi
			previous="$argument"
		done
		[ -z "$cidfile" ] || printf '%s\n' "${STUB_CONTAINER_ID:-owned-validator-id}" >"$cidfile"
		printf '%s\n' "${STUB_CONTAINER_ID:-owned-validator-id}"
		;;
	rm|network|compose) ;;
	*) echo "unexpected docker invocation: $*" >&2; exit 64 ;;
esac
EOF

cat >"$bin/zfs" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'zfs:%s\n' "$*" >>"$STUB_EVENTS"
case "$1" in
	list)
		if [ -s "$STUB_SNAPSHOT_STATE" ]; then
			cat "$STUB_SNAPSHOT_STATE"
		else
			exit 1
		fi
		;;
	get)
		case " $* " in
			*' guid '*) printf '%s\n' "${STUB_SNAPSHOT_GUID:-424242}" ;;
			*' available '*) printf '%s\n' "${STUB_ZFS_AVAILABLE:-1099511627776}" ;;
			*) printf '%s\n' "${STUB_ZFS_VALUE:-zstd}" ;;
		esac
		;;
	snapshot) printf '%s\n' "$2" >"$STUB_SNAPSHOT_STATE" ;;
	destroy)
		[ "${STUB_DESTROY_FAIL:-0}" = 0 ] || exit 75
		: >"$STUB_SNAPSHOT_STATE"
		;;
	*) echo "unexpected zfs invocation: $*" >&2; exit 64 ;;
esac
EOF

cat >"$bin/seafile-health-check" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'health\n' >>"$STUB_EVENTS"
[ "${STUB_HEALTHY:-1}" = 1 ]
EOF

cat >"$bin/seafile-logical-backup" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'logical-backup\n' >>"$STUB_EVENTS"
[ "${STUB_LOGICAL_FAIL:-0}" = 0 ] || exit 75
candidate="$SEAFILE_STATE_DIR/backups/seafile-fixture"
mkdir -p "$candidate"
for dump in ccnet_db.sql seafile_db.sql seahub_db.sql; do
	printf '%s\n' 'CREATE TABLE fixture (id int);' >"$candidate/$dump"
done
printf '%s\n' '{"transaction_kind":"writers_quiesced=true"}' >"$candidate/manifest.json"
printf '%s\n' "$candidate" >"$SEAFILE_BACKUP_CANDIDATE_FILE"
EOF

cat >"$bin/seafile-validate-logical-backup" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'validate-logical-backup\n' >>"$STUB_EVENTS"
[ "${STUB_VALIDATE_FAIL:-0}" = 0 ]
EOF

cat >"$bin/seafile-validate-state" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'validate-state\n' >>"$STUB_EVENTS"
[ "${STUB_STATE_VALID:-1}" = 1 ]
EOF

cat >"$bin/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'timeout:%s\n' "$*" >>"$STUB_EVENTS"
shift
exec "$@"
EOF

cat >"$bin/df" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case " $* " in
	*' --output=avail '*) printf 'Avail\n%s\n' "${STUB_FREE_BLOCKS:-1073741824}" ;;
	*' --output=iavail '*) printf 'IAvail\n%s\n' "${STUB_FREE_INODES:-1000000}" ;;
	*) exec /bin/df "$@" ;;
esac
EOF

cat >"$bin/free" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '              total        used        free      shared  buff/cache   available\n'
printf 'Mem:       33554432           0           0           0           0    %s\n' "${STUB_AVAILABLE_RAM_KIB:-16777216}"
printf 'Swap:       %s           0     %s\n' "${STUB_SWAP_KIB:-8388608}" "${STUB_SWAP_KIB:-8388608}"
EOF

chmod +x "$bin"/*

export PATH="$bin:$PATH"
export STUB_EVENTS="$events"
export STUB_SNAPSHOT_STATE="$snapshot_state"
export STUB_REAL_INSTALL="$real_install"
export SEAFILE_SYSTEMCTL_COMMAND="$bin/systemctl"
export SEAFILE_DOCKER_COMMAND="$bin/docker"
export SEAFILE_ZFS_COMMAND="$bin/zfs"
export SEAFILE_TIMEOUT_COMMAND="$bin/timeout"
export SEAFILE_INSTALL_COMMAND="$bin/install"
export SEAFILE_HEALTH_COMMAND="$bin/seafile-health-check"
export SEAFILE_LOGICAL_BACKUP_COMMAND="$bin/seafile-logical-backup"
export SEAFILE_VALIDATE_LOGICAL_BACKUP_COMMAND="$bin/seafile-validate-logical-backup"
export SEAFILE_VALIDATE_STATE_COMMAND="$bin/seafile-validate-state"
export SEAFILE_STATE_DIR="$state"
export SEAFILE_BACKUP_RUNTIME_DIR="$runtime"
export SEAFILE_VALIDATOR_STATE_DIR="$validator_state"
export SEAFILE_MAINTENANCE_LOCK="$root/maintenance.lock"
export SEAFILE_DATASET="flash_pool/flash/storage/seafile"
export SEAFILE_SNAPSHOT_NAME="borgmatic"
export SEAFILE_TEST_SKIP_LOCK_PROOF=1
export SEAFILE_TEST_SKIP_OWNERSHIP=1
export SEAFILE_TEST_NO_SLEEP=1

reset_fixture() {
	rm -rf -- "$runtime" "$validator_state"
	mkdir -p "$runtime" "$validator_state"
	: >"$events"
	: >"$snapshot_state"
	rm -f -- "$state/control/backup-snapshot-owner" "$state/control"/*.validated
	unset STUB_STACK_ACTIVE STUB_HEALTHY STUB_STATE_VALID STUB_ONLYOFFICE_PREPARE_FAIL
	unset STUB_STOP_FAIL STUB_LOGICAL_FAIL STUB_VALIDATE_FAIL STUB_DESTROY_FAIL
}

expect_failure() {
	if "$@" >"$root/failure.stdout" 2>"$root/failure.stderr"; then
		echo "command unexpectedly succeeded: $*" >&2
		exit 1
	fi
}

# Inactive and unhealthy stacks fail before OnlyOffice or writer shutdown.
reset_fixture
export STUB_STACK_ACTIVE=0
expect_failure "$prepare"
if grep -F -- 'documentserver-prepare4shutdown.sh' "$events"; then exit 1; fi
if grep -F -- 'docker:kill' "$events"; then exit 1; fi

reset_fixture
export STUB_HEALTHY=0
expect_failure "$prepare"
if grep -F -- 'docker:kill' "$events"; then exit 1; fi

# A pre-existing reserved snapshot is preserved and blocks preparation.
reset_fixture
printf '%s\n' 'flash_pool/flash/storage/seafile@borgmatic' >"$snapshot_state"
expect_failure "$prepare"
test -s "$snapshot_state"
if grep -F -- 'zfs:destroy' "$events"; then exit 1; fi

# OnlyOffice preparation precedes every writer stop, and MariaDB stops only
# after the bounded logical dump stage.
reset_fixture
"$prepare"
prepare_line="$(grep -n -F 'documentserver-prepare4shutdown.sh' "$events" | head -1 | cut -d: -f1)"
first_stop_line="$(grep -n -F 'docker:kill --signal TERM' "$events" | head -1 | cut -d: -f1)"
logical_line="$(grep -n -F 'logical-backup' "$events" | head -1 | cut -d: -f1)"
database_stop_line="$(grep -n -F 'docker:kill --signal TERM seafile-mariadb' "$events" | cut -d: -f1)"
snapshot_line="$(grep -n -F 'zfs:snapshot' "$events" | cut -d: -f1)"
test "$prepare_line" -lt "$first_stop_line"
test "$logical_line" -lt "$database_stop_line"
test "$database_stop_line" -lt "$snapshot_line"
health_before_validation="$(grep -n -E '^(health|validate-logical-backup)$' "$events" | tail -2 | head -1 | cut -d: -f1)"
validation_line="$(grep -n -F 'validate-logical-backup' "$events" | tail -1 | cut -d: -f1)"
test "$health_before_validation" -lt "$validation_line"
test -f "$runtime/cleanup-armed"
test -f "$state/control/backup-snapshot-owner"

# Matching owner marker/token/GUID cleanup is destructive only after proof.
"$cleanup"
test ! -s "$snapshot_state"
test ! -e "$runtime/cleanup-armed"
test ! -e "$state/control/backup-snapshot-owner"

# Empty cleanup is idempotent. Partial or mismatched ownership preserves data.
"$cleanup"
reset_fixture
printf '%s\n' 'flash_pool/flash/storage/seafile@borgmatic' >"$snapshot_state"
expect_failure "$cleanup"
test -s "$snapshot_state"

reset_fixture
"$prepare"
printf '%s\n' 'invocation=foreign' >"$runtime/cleanup-armed"
expect_failure "$cleanup"
test -s "$snapshot_state"
test -f "$state/control/backup-snapshot-owner"

# Any attempted OnlyOffice preparation restarts the originally running
# container, even when preparation fails before its stop.
reset_fixture
export STUB_ONLYOFFICE_PREPARE_FAIL=1
expect_failure "$prepare"
grep -F -- 'docker:start seafile-onlyoffice' "$events" >/dev/null
test ! -s "$snapshot_state"

# Dump and validation failures clean only current owned state and restore the
# original stack. Validation happens after production has returned healthy.
reset_fixture
export STUB_LOGICAL_FAIL=1
expect_failure "$prepare"
grep -F -- 'docker:start' "$events" >/dev/null
test ! -s "$snapshot_state"

reset_fixture
export STUB_VALIDATE_FAIL=1
expect_failure "$prepare"
grep -F -- 'health' "$events" >/dev/null
test ! -s "$snapshot_state"
test ! -e "$runtime/cleanup-armed"

# Logical backup requires a real inherited-lock claim. A flag alone fails.
reset_fixture
unset SEAFILE_TEST_SKIP_LOCK_PROOF
SEAFILE_MAINTENANCE_LOCK_HELD=1 expect_failure "$logical"
export SEAFILE_TEST_SKIP_LOCK_PROOF=1

# Restore helpers reject production and nonempty targets before creating a
# namespace. Successful preparation hands off one session; teardown removes
# owned runtime/container/network state while preserving restored data.
restore_target="$root/restore-target"
restore_runtime="$root/restore-runtime"
mkdir -p "$restore_target" "$restore_runtime"
expect_failure "$restore_prepare" --target "$state" --runtime-dir "$restore_runtime"
printf 'foreign\n' >"$restore_target/foreign"
expect_failure "$restore_prepare" --target "$restore_target" --runtime-dir "$restore_runtime"
rm -f "$restore_target/foreign"
SEAFILE_RESTORE_TEST_MODE=1 "$restore_prepare" \
	--target "$restore_target" --runtime-dir "$restore_runtime"
test -f "$restore_runtime/rehearsal-session"
SEAFILE_RESTORE_TEST_MODE=1 "$restore_verify" --runtime-dir "$restore_runtime"
SEAFILE_RESTORE_TEST_MODE=1 "$restore_teardown" --runtime-dir "$restore_runtime"
test -d "$restore_target"
test ! -e "$restore_runtime/rehearsal-session"
SEAFILE_RESTORE_TEST_MODE=1 "$restore_teardown" --runtime-dir "$restore_runtime"

# Secret fixture values never reach helper output or command logs.
if grep -R -F -- 'fixture-secret-value' "$root"/*.stdout "$root"/*.stderr "$events" 2>/dev/null; then
	echo 'backup helper exposed a secret fixture value' >&2
	exit 1
fi

echo "Seafile backup state-machine contract passed"
