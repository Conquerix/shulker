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

root="$(realpath "$(mktemp -d "$TMPDIR/seafile-backup-fixture.XXXXXX")")"
trap 'rm -rf -- "$root"' EXIT HUP INT TERM
bin="$root/bin"
state="$root/state"
runtime="$root/runtime"
validator_state="$root/validator"
events="$root/events"
snapshot_state="$root/snapshot-state"
restore_container_state="$root/restore-container-state"
restore_network_state="$root/restore-network-state"
mkdir -p "$bin" "$state/backups" "$state/control" "$state/shared/logs" \
	"$state/shared/seafile/logs" "$runtime" "$validator_state"
: >"$events"
: >"$snapshot_state"
: >"$restore_container_state"
: >"$restore_network_state"
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
		target="${!#}"
		if [[ "$target" == seafile-restore-* || "$target" == restore-*-id ]]; then
			line="$(awk -v target="$target" '$1 == target || $2 == target { print; exit }' "$STUB_RESTORE_CONTAINER_STATE")"
			[ -n "$line" ] || exit 1
			id="$(awk '{print $2}' <<<"$line")"
			if [[ "$*" == *'{{.State.Running}}'* ]]; then
				awk '{print $5}' <<<"$line"
			elif [[ "$*" == *'com.docker.compose.project'* ]]; then
				printf 'seafile-restore\n'
			elif [[ "$*" == *'shulker.seafile.restore-invocation'* ]]; then
				awk '{print $4}' <<<"$line"
			else
				printf '%s\n' "$id"
			fi
			exit 0
		fi
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
		if [[ "$*" == *'SEAFILE_RESTORE_NATIVE_MODE=identify'* ]]; then
			printf 'native-admin@restore.invalid\n'
		fi
		;;
	kill)
		[ "${STUB_STOP_FAIL:-0}" = 0 ] || exit 75
		export STUB_CONTAINER_RUNNING=0
		;;
	start|restart)
		target="${!#}"
		awk -v target="$target" '{ if ($1 == target || $2 == target) $5 = "true"; print }' \
			"$STUB_RESTORE_CONTAINER_STATE" >"$STUB_RESTORE_CONTAINER_STATE.next"
		mv "$STUB_RESTORE_CONTAINER_STATE.next" "$STUB_RESTORE_CONTAINER_STATE"
		;;
	info) printf '%s\n' "${STUB_DOCKER_ROOT:-/tmp}" ;;
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
	rm)
		target="${!#}"
		awk -v target="$target" '$1 != target && $2 != target' "$STUB_RESTORE_CONTAINER_STATE" \
			>"$STUB_RESTORE_CONTAINER_STATE.next"
		mv "$STUB_RESTORE_CONTAINER_STATE.next" "$STUB_RESTORE_CONTAINER_STATE"
		;;
	network)
		case "${2:-}" in
			inspect)
				[ -s "$STUB_RESTORE_NETWORK_STATE" ] || exit 1
				read -r id invocation <"$STUB_RESTORE_NETWORK_STATE"
				if [[ "$*" == *'{{.Id}}'* ]]; then
					printf '%s\n' "$id"
				elif [[ "$*" == *'shulker.seafile.restore-invocation'* ]]; then
					printf '%s\n' "$invocation"
				else
					printf '%s\n' "$id"
				fi
				;;
			create)
				invocation="$(sed -n 's/.*shulker\.seafile\.restore-invocation=\([^ ]*\).*/\1/p' <<<"$*")"
				printf 'restore-network-id %s\n' "$invocation" >"$STUB_RESTORE_NETWORK_STATE"
				printf 'restore-network-id\n'
				;;
			rm) : >"$STUB_RESTORE_NETWORK_STATE" ;;
			*) echo "unexpected docker network invocation: $*" >&2; exit 64 ;;
		esac
		;;
	compose)
		if [[ "$*" == *' create'* ]] && [ "${STUB_COMPOSE_CREATE_FAIL:-0}" = 1 ]; then
			printf 'seafile-restore-mariadb restore-database-id database %s false\n' \
				"$SEAFILE_RESTORE_INVOCATION" >"$STUB_RESTORE_CONTAINER_STATE"
			exit 75
		fi
		if [[ "$*" == *' create'* ]]; then
			cat >"$STUB_RESTORE_CONTAINER_STATE" <<STATE
seafile-restore-mariadb restore-database-id database $SEAFILE_RESTORE_INVOCATION false
seafile-restore-redis restore-redis-id redis $SEAFILE_RESTORE_INVOCATION false
seafile-restore-seafile restore-seafile-id seafile $SEAFILE_RESTORE_INVOCATION false
seafile-restore-seasearch restore-seasearch-id seasearch $SEAFILE_RESTORE_INVOCATION false
seafile-restore-notification restore-notification-id notification $SEAFILE_RESTORE_INVOCATION false
seafile-restore-metadata restore-metadata-id metadata $SEAFILE_RESTORE_INVOCATION false
seafile-restore-onlyoffice restore-onlyoffice-id onlyoffice $SEAFILE_RESTORE_INVOCATION false
seafile-restore-proxy restore-proxy-id proxy $SEAFILE_RESTORE_INVOCATION false
STATE
		fi
		if [ -n "${STUB_COMPOSE_FAIL_SERVICE:-}" ] \
			&& [[ "$*" == *' up '* ]] \
			&& [ "${!#}" = "$STUB_COMPOSE_FAIL_SERVICE" ]; then
			exit 75
		fi
		if [[ "$*" == *' ps -q '* ]]; then
			service="${!#}"
			awk -v service="$service" '$3 == service { print $2; exit }' "$STUB_RESTORE_CONTAINER_STATE"
		fi
		if [[ "$*" == *' up '* && "$*" == *'--project-name seafile-restore'* ]]; then
			selected=0
			for service in database redis seafile seasearch notification metadata onlyoffice proxy; do
				if [[ " $* " == *" $service "* ]]; then
					awk -v service="$service" '{ if ($3 == service) $5 = "true"; print }' \
						"$STUB_RESTORE_CONTAINER_STATE" >"$STUB_RESTORE_CONTAINER_STATE.next"
					mv "$STUB_RESTORE_CONTAINER_STATE.next" "$STUB_RESTORE_CONTAINER_STATE"
					selected=1
				fi
			done
			if [ "$selected" -eq 0 ]; then
				awk '{ $5 = "true"; print }' "$STUB_RESTORE_CONTAINER_STATE" \
					>"$STUB_RESTORE_CONTAINER_STATE.next"
				mv "$STUB_RESTORE_CONTAINER_STATE.next" "$STUB_RESTORE_CONTAINER_STATE"
			fi
		fi
		;;
	*) echo "unexpected docker invocation: $*" >&2; exit 64 ;;
esac
EOF

cat >"$bin/seafile-render-runtime-config" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'render:%s\n' "$*" >>"$STUB_EVENTS"
source_file=
host_dir=
app_dir=
metadata_dir=
while [ "$#" -gt 0 ]; do
	case "$1" in
		--source) source_file="$2"; shift 2 ;;
		--host-dir) host_dir="$2"; shift 2 ;;
		--app-dir) app_dir="$2"; shift 2 ;;
		--metadata-dir) metadata_dir="$2"; shift 2 ;;
		*) shift 2 ;;
	esac
done
test "$(wc -l <"$source_file")" -eq 12
mkdir -p "$host_dir" "$app_dir" "$metadata_dir"
cp "$source_file" "$host_dir/bootstrap.environment"
grep -Ev '^(INIT_SEAFILE_MYSQL_ROOT_PASSWORD|INIT_SS_ADMIN_USER|INIT_SS_ADMIN_PASSWORD)=' \
	"$source_file" >"$host_dir/environment"
cp "$host_dir/environment" "$app_dir/seafile.env"
for file in seahub_settings.py seafevents.conf seafile.conf seafdav.conf; do
	printf 'restore fixture\n' >"$app_dir/$file"
done
cp "$app_dir/seafile.conf" "$metadata_dir/seafile.conf"
chmod 0400 "$host_dir/bootstrap.environment" "$host_dir/environment" \
	"$app_dir/seafile.env" "$app_dir/seahub_settings.py" "$app_dir/seafevents.conf"
chmod 0444 "$app_dir/seafile.conf" "$app_dir/seafdav.conf" "$metadata_dir/seafile.conf"
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
	*' --output=avail '*) printf 'Avail\n%s\n' "${STUB_FREE_BLOCKS:-1099511627776}" ;;
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

cat >"$bin/findmnt" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
target="${!#}"
if [[ "$target" == "$STUB_PRODUCTION_STATE" || "$target" == "$STUB_PRODUCTION_STATE"/* ]]; then
	printf 'production-source\n'
else
	printf 'restore-source\n'
fi
EOF

cat >"$bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'curl:%s\n' "$*" >>"$STUB_EVENTS"
if [ -n "${STUB_CURL_FAIL_MATCH:-}" ] && [[ "$*" == *"$STUB_CURL_FAIL_MATCH"* ]]; then
	exit 22
fi
if [[ "$*" == *'/healthcheck'* ]]; then
	printf 'true\n'
fi
EOF

chmod +x "$bin"/*

export PATH="$bin:$PATH"
export STUB_EVENTS="$events"
export STUB_SNAPSHOT_STATE="$snapshot_state"
export STUB_RESTORE_CONTAINER_STATE="$restore_container_state"
export STUB_RESTORE_NETWORK_STATE="$restore_network_state"
export STUB_REAL_INSTALL="$real_install"
export STUB_PRODUCTION_STATE="$state"
export SEAFILE_SYSTEMCTL_COMMAND="$bin/systemctl"
export SEAFILE_DOCKER_COMMAND="$bin/docker"
export SEAFILE_ZFS_COMMAND="$bin/zfs"
export SEAFILE_TIMEOUT_COMMAND="$bin/timeout"
export SEAFILE_FINDMNT_COMMAND="$bin/findmnt"
export SEAFILE_CURL_COMMAND="$bin/curl"
export SEAFILE_FREE_COMMAND="$bin/free"
export SEAFILE_DF_COMMAND="$bin/df"
export SEAFILE_INSTALL_COMMAND="$bin/install"
export SEAFILE_HEALTH_COMMAND="$bin/seafile-health-check"
export SEAFILE_LOGICAL_BACKUP_COMMAND="$bin/seafile-logical-backup"
export SEAFILE_VALIDATE_LOGICAL_BACKUP_COMMAND="$bin/seafile-validate-logical-backup"
export SEAFILE_VALIDATE_STATE_COMMAND="$bin/seafile-validate-state"
export SEAFILE_RENDER_RUNTIME_CONFIG_COMMAND="$bin/seafile-render-runtime-config"
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
	: >"$restore_container_state"
	: >"$restore_network_state"
	rm -f -- "$state/control/backup-snapshot-owner" "$state/control"/*.validated
	unset STUB_STACK_ACTIVE STUB_HEALTHY STUB_STATE_VALID STUB_ONLYOFFICE_PREPARE_FAIL
	unset STUB_STOP_FAIL STUB_LOGICAL_FAIL STUB_VALIDATE_FAIL STUB_DESTROY_FAIL
	unset STUB_COMPOSE_CREATE_FAIL STUB_COMPOSE_FAIL_SERVICE
	unset STUB_CURL_FAIL_MATCH
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

# Any attempted OnlyOffice preparation truly cycles the originally running
# container through the guarded Compose path, even when preparation fails
# before its normal stop.
reset_fixture
export STUB_ONLYOFFICE_PREPARE_FAIL=1
expect_failure "$prepare"
grep -F -- 'docker:kill --signal TERM seafile-onlyoffice' "$events" >/dev/null
grep -E -- 'docker:compose .* up --detach --no-deps --no-recreate --wait .*onlyoffice' "$events" >/dev/null
if grep -F -- 'docker:start seafile-onlyoffice' "$events"; then exit 1; fi
test ! -s "$snapshot_state"

# Dump and validation failures clean only current owned state and restore the
# original stack. Validation happens after production has returned healthy.
reset_fixture
export STUB_LOGICAL_FAIL=1
expect_failure "$prepare"
grep -E -- 'docker:compose .* up --detach --no-deps --no-recreate --wait .*redis' "$events" >/dev/null
if grep -E -- 'docker:compose .* up --detach --no-deps --no-recreate --wait .*database' "$events"; then exit 1; fi
grep -E -- 'docker:compose .* up --detach --no-deps --no-recreate --wait .*onlyoffice' "$events" >/dev/null
if grep -F -- 'docker:start' "$events"; then exit 1; fi
test ! -s "$snapshot_state"

# A failed dependency-ordered Compose restart is propagated rather than hidden.
reset_fixture
export STUB_COMPOSE_FAIL_SERVICE=seafile
expect_failure "$prepare"
grep -E -- 'docker:compose .* up --detach --no-deps --no-recreate --wait .*seafile' "$events" >/dev/null
if grep -E -- 'docker:compose .* up --detach --no-deps .*seasearch' "$events"; then exit 1; fi

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

# Restore helpers reject production/nonempty targets and unsafe runtime paths
# before changing their ownership or mode.
restore_target="$root/restore-target"
restore_runtime="$root/restore-runtime"
mkdir -p "$restore_target" "$restore_runtime"
chmod 0700 "$restore_target" "$restore_runtime"
expect_failure "$restore_prepare" --target "$state" --runtime-dir "$restore_runtime"
printf 'foreign\n' >"$restore_target/foreign"
expect_failure "$restore_prepare" --target "$restore_target" --runtime-dir "$restore_runtime"
rm -f "$restore_target/foreign"

chmod 0755 "$restore_runtime"
expect_failure "$restore_prepare" --target "$restore_target" --runtime-dir "$restore_runtime"
test "$(stat -c %a "$restore_runtime")" = 755
chmod 0700 "$restore_runtime"

expect_failure "$restore_prepare" --target "$restore_target/../restore-target" --runtime-dir "$restore_runtime"
ln -s "$root" "$root/restore-alias"
expect_failure "$restore_prepare" --target "$root/restore-alias/restore-target" --runtime-dir "$restore_runtime"
rm -f "$root/restore-alias"

protected_runtime="$state/control/restore-runtime"
mkdir -p "$protected_runtime"
chmod 0700 "$protected_runtime"
expect_failure "$restore_prepare" --target "$restore_target" --runtime-dir "$protected_runtime"
test -z "$(find "$protected_runtime" -mindepth 1 -print -quit)"

# Every pre-session failure removes only invocation-created namespace/runtime
# artifacts and returns an originally empty restore target/runtime to empty.
export STUB_COMPOSE_CREATE_FAIL=1
expect_failure "$restore_prepare" \
	--target "$restore_target" --runtime-dir "$restore_runtime"
test -z "$(find "$restore_target" -mindepth 1 -print -quit)"
test -z "$(find "$restore_runtime" -mindepth 1 -print -quit)"
if ! grep -F -- 'docker:network rm' "$events" >/dev/null; then
	cat "$root/failure.stderr" >&2
	cat "$events" >&2
	exit 1
fi
unset STUB_COMPOSE_CREATE_FAIL

# Successful preparation renders from a protected exact twelve-key source,
# keeps Compose interpolation separate, and hands off one owned session.
"$restore_prepare" \
	--target "$restore_target" --runtime-dir "$restore_runtime"
test -f "$restore_runtime/rehearsal-session"
grep -F -- 'render:' "$events" >/dev/null
grep -F -- '--container-project seafile-restore' "$events" >/dev/null
test "$(wc -l <"$restore_runtime/source.environment")" -eq 12
test "$(stat -c %a "$restore_runtime/source.environment")" = 600
test "$(wc -l <"$restore_runtime/compose.environment")" -eq 11
session_invocation="$(sed -n 's/^invocation=//p' "$restore_runtime/rehearsal-session")"
test "$(awk -v invocation="$session_invocation" '$4 == invocation && $5 == "false" {count++} END {print count+0}' "$restore_container_state")" -eq 8

backup_set="$restore_target/backups/seafile-selected"
mkdir -p "$backup_set"
manifest_databases='[]'
for database in ccnet_db seafile_db seahub_db; do
	printf '%s\n' 'CREATE TABLE fixture (id int);' >"$backup_set/$database.sql"
	size="$(stat -c %s "$backup_set/$database.sql")"
	checksum="$(sha256sum "$backup_set/$database.sql" | cut -d' ' -f1)"
	manifest_databases="$(jq -c --arg name "$database" --arg file "$database.sql" \
		--argjson size "$size" --arg checksum "$checksum" \
		'. + [{name:$name,file:$file,size_bytes:$size,sha256:$checksum}]' \
		<<<"$manifest_databases")"
done
jq -nS \
	--argjson release_versions '{"seafile":"13.0.25","mariadb":"10.11.18","redis":"7.4.10-alpine","seasearch":"1.0.4","notification":"13.0.21","metadata":"13.0.22","onlyoffice":"9.4.0.1"}' \
	--arg schema_format mariadb-sql-v1 \
	--arg transaction_kind writers_quiesced=true \
	--argjson databases "$manifest_databases" \
	'{release_versions:$release_versions,schema_format:$schema_format,transaction_kind:$transaction_kind,databases:$databases}' \
	>"$backup_set/manifest.json"

# Tampering is rejected before any restore container is started.
cp "$backup_set/ccnet_db.sql" "$root/ccnet.original"
printf 'tampered\n' >>"$backup_set/ccnet_db.sql"
: >"$events"
expect_failure "$restore_verify" \
	--runtime-dir "$restore_runtime" --backup-set seafile-selected
if grep -E -- 'docker:compose .* up ' "$events"; then exit 1; fi
mv "$root/ccnet.original" "$backup_set/ccnet_db.sql"

# Every HTTPS probe is mandatory and its failure propagates.
: >"$events"
export STUB_CURL_FAIL_MATCH=notification/ping
expect_failure "$restore_verify" \
	--runtime-dir "$restore_runtime" --backup-set seafile-selected
if ! grep -F -- 'notification/ping' "$events" >/dev/null; then
	cat "$root/failure.stderr" >&2
	cat "$events" >&2
	cat "$restore_container_state" >&2
	exit 1
fi
unset STUB_CURL_FAIL_MATCH
awk '{ $5 = "false"; print }' "$restore_container_state" >"$restore_container_state.next"
mv "$restore_container_state.next" "$restore_container_state"

# Verify starts/imports in order, resets only the existing native account,
# then checks the isolated HTTPS stack without recreating containers.
: >"$events"
"$restore_verify" \
	--runtime-dir "$restore_runtime" --backup-set seafile-selected \
	>"$root/restore-verify.stdout"
grep -E -- 'docker:compose .* up --detach --no-deps --wait .*database redis' "$events" >/dev/null
test "$(grep -E -c -- '^docker:exec .*mariadb --user root$' "$events")" -eq 3
grep -E -- 'docker:compose .* up --detach --no-recreate --wait' "$events" >/dev/null
grep -F -- 'SEAFILE_RESTORE_NATIVE_MODE=reset' "$events" >/dev/null
grep -F -- 'SEAFILE_RESTORE_NATIVE_MODE=verify' "$events" >/dev/null
if grep -F -- 'reset-admin.sh' "$events"; then exit 1; fi
grep -F -- 'files.restore.invalid:24239/' "$events" >/dev/null
grep -F -- 'notification/ping' "$events" >/dev/null
grep -F -- 'office.restore.invalid:24240/healthcheck' "$events" >/dev/null
grep -F -- 'read-only fsck' "$root/restore-verify.stdout" >/dev/null
for unproved in login share upload ACL ownership; do
	if grep -F -i -- "$unproved" "$root/restore-verify.stdout"; then exit 1; fi
done

# A completed/partially running rehearsal cannot be re-imported in place.
: >"$events"
expect_failure "$restore_verify" --runtime-dir "$restore_runtime" --backup-set seafile-selected
if grep -E -- 'docker:compose .* up ' "$events"; then exit 1; fi

# Teardown remains idempotent when an earlier attempt removed only part of the
# invocation-owned namespace.
rm -f "$restore_runtime/ca/office.restore.invalid.key"
"$restore_teardown" --runtime-dir "$restore_runtime"
test -d "$restore_target"
test ! -e "$restore_runtime/rehearsal-session"
"$restore_teardown" --runtime-dir "$restore_runtime"

# Secret fixture values never reach helper output or command logs.
if grep -R -F -- 'fixture-secret-value' "$root"/*.stdout "$root"/*.stderr "$events" 2>/dev/null; then
	echo 'backup helper exposed a secret fixture value' >&2
	exit 1
fi

echo "Seafile backup state-machine contract passed"
