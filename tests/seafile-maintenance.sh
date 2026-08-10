#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
	echo "usage: seafile-maintenance.sh HEALTH EXTENDED METADATA ENABLE-PUBLIC" >&2
	exit 64
fi

health="$1"
extended="$2"
metadata="$3"
enable_public="$4"
root="$(mktemp -d "$TMPDIR/seafile-maintenance-fixture.XXXXXX")"
trap 'rm -rf -- "$root"' EXIT HUP INT TERM
bin="$root/bin"
state="$root/state"
runtime_host="$root/run-host"
runtime_app="$root/run-app"
runtime_metadata="$root/run-metadata"
lock="$root/maintenance.lock"
calls="$root/calls"
mkdir -p "$bin" "$state/shared/logs" "$state/shared/seafile/logs" \
	"$state/shared/seafile/conf" "$state/shared/seafile/md-data" \
	"$state/backups/seafile-29990101T000000.000000000Z" "$state/control" \
	"$runtime_host" "$runtime_app" "$runtime_metadata"
: >"$calls"
: >"$lock"

cat >"$runtime_host/environment" <<'EOF'
INIT_SEAFILE_MYSQL_ROOT_PASSWORD=fixture-root-password
SEAFILE_MYSQL_DB_PASSWORD=fixture-database-password
REDIS_PASSWORD=fixture-redis-password
JWT_PRIVATE_KEY=fixture-jwt-private-key
SEAHUB_SECRET_KEY=fixture-seahub-secret-key
INIT_SEAFILE_ADMIN_EMAIL=fixture-admin@example.invalid
INIT_SEAFILE_ADMIN_PASSWORD=fixture-admin-password
INIT_SS_ADMIN_USER=fixture-search-user
INIT_SS_ADMIN_PASSWORD=fixture-search-password
SEAFILE_OAUTH_CLIENT_ID=fixture-client-id
SEAFILE_OAUTH_CLIENT_SECRET=fixture-client-secret
ONLYOFFICE_JWT_SECRET=fixture-office-secret
EOF
chmod 0400 "$runtime_host/environment"

for name in .env seahub_settings.py seafevents.conf seafile.conf seafdav.conf; do
	target="$name"
	[ "$name" != .env ] || target=seafile.env
	: >"$runtime_app/$target"
	chmod 0444 "$runtime_app/$target"
	ln -s "$runtime_app/$target" "$state/shared/seafile/conf/$name"
done
: >"$runtime_metadata/seafile.conf"
chmod 0444 "$runtime_metadata/seafile.conf"

cat >"$state/backups/seafile-29990101T000000.000000000Z/manifest.json" <<'EOF'
{"writers_quiesced":true}
EOF
chmod 0600 "$state/backups/seafile-29990101T000000.000000000Z/manifest.json"

cat >"$state/control/last-validated-backup" <<EOF
{"set":"seafile-29990101T000000.000000000Z","validated_at_epoch":$(date +%s),"writers_quiesced":true}
EOF
chmod 0600 "$state/control/last-validated-backup"

cat >"$bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'systemctl %s\n' "$*" >>"${STUB_CALLS:?}"
case "$*" in
	'is-active --quiet seafile-compose.service')
		[ "${STUB_FAIL:-}" != inactive ]
		;;
	'show --property Result --value borgmatic.service')
		[ "${STUB_FAIL:-}" != backup ] || printf '%s\n' failed
		[ "${STUB_FAIL:-}" = backup ] || printf '%s\n' success
		;;
	'show --property ExecMainExitTimestampMonotonic --value borgmatic.service')
		printf '%s\n' 1
		;;
	*) exit 0 ;;
esac
EOF

cat >"$bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'docker %s\n' "$*" >>"${STUB_CALLS:?}"
if [ "${1:-}" = ps ]; then
	if [ "${STUB_FAIL:-}" = compose ]; then
		printf '%s\n' database metadata notification onlyoffice redis seafile
	else
		printf '%s\n' database metadata notification onlyoffice redis seafile seasearch
	fi
	exit 0
fi
if [ "${1:-}" = inspect ]; then
	container="${*: -1}"
	case "${STUB_FAIL:-}:$container" in
		health-seafile:seafile|health-database:seafile-mariadb|health-redis:seafile-redis|health-seasearch:seafile-seasearch|health-notification:seafile-notification|health-metadata:seafile-metadata|health-onlyoffice:seafile-onlyoffice)
			printf '%s\n' unhealthy
			;;
		*) printf '%s\n' healthy ;;
	esac
	exit 0
fi
if [ "${1:-}" = logs ]; then
	[ "${STUB_FAIL:-}" != metadata-log ] || exit 1
	printf '%s\n' 'Starting Metadata server'
	exit 0
fi
if [ "${1:-}" = exec ]; then
	case " $* " in
		*' seafile-mariadb '*mariadb*)
			[ "${STUB_FAIL:-}" != sql ] || exit 1
			printf '%s\n' 1
			;;
		*' seafile-redis '*redis-cli*)
			[ "${STUB_FAIL:-}" != redis ] || exit 1
			printf '%s\n' PONG
			;;
		*' seafile-seasearch '*curl*)
			[ "${STUB_FAIL:-}" != seasearch ] || exit 1
			printf '%s\n' '{}'
			;;
		*' seafile-notification '*curl*)
			[ "${STUB_FAIL:-}" != notification-internal ] || exit 1
			;;
		*' seafile-metadata '*test*)
			[ "${STUB_FAIL:-}" != metadata ] || exit 1
			;;
		*' seafile '*python*)
			[ "${STUB_FAIL:-}" != account ] || exit 1
			printf '%s\n' 3
			;;
		*) exit 0 ;;
	esac
	exit 0
fi
exit 0
EOF

cat >"$bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'curl %s\n' "$*" >>"${STUB_CALLS:?}"
case " $* " in
	*':23239/'*) [ "${STUB_FAIL:-}" != seafile ] || exit 1 ;;
	*':23241/ping'*) [ "${STUB_FAIL:-}" != notification ] || exit 1 ;;
	*':23240/healthcheck'*)
		[ "${STUB_FAIL:-}" != onlyoffice ] || exit 1
		printf '%s\n' true
		;;
	*) exit 0 ;;
esac
EOF

cat >"$bin/flock" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'flock %s\n' "$*" >>"${STUB_CALLS:?}"
if [ "${1:-}" = -n ] && [ "${STUB_LOCK_BUSY:-0}" = 1 ]; then
	exit 1
fi
if [ "${1:-}" = -n ] && [ "${2:-}" = 8 ] && [ "${STUB_INHERITED_LOCK_HELD:-0}" = 1 ]; then
	exit 1
fi
if [ "${1:-}" = -w ] && [ "${STUB_LOCK_TIMEOUT:-0}" = 1 ]; then
	exit 1
fi
exit 0
EOF

cat >"$bin/seafile-validate-state" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'validate-state\n' >>"${STUB_CALLS:?}"
[ "${STUB_FAIL:-}" != dataset ]
EOF

cat >"$bin/journalctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'journalctl %s\n' "$*" >>"${STUB_CALLS:?}"
[ "${STUB_FAIL:-}" != borg-journal ] || exit 1
printf '%s\n' 'Backup completed'
EOF

cat >"$bin/id" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = -u ] || exit 64
printf '%s\n' 0
EOF

chmod +x "$bin"/*

if stat --version >/dev/null 2>&1; then
	expected_owner="$(stat -c '%u:%g' "$state/shared/seafile/conf/.env")"
else
	expected_owner="$(stat -f '%u:%g' "$state/shared/seafile/conf/.env")"
fi

run_health() {
	env \
		STUB_CALLS="$calls" \
		STUB_FAIL="${STUB_FAIL:-}" \
		STUB_LOCK_BUSY="${STUB_LOCK_BUSY:-0}" \
		STUB_INHERITED_LOCK_HELD="${STUB_INHERITED_LOCK_HELD:-0}" \
		SEAFILE_SYSTEMCTL_COMMAND="$bin/systemctl" \
		SEAFILE_DOCKER_COMMAND="$bin/docker" \
		SEAFILE_CURL_COMMAND="$bin/curl" \
		SEAFILE_FLOCK_COMMAND="$bin/flock" \
		SEAFILE_VALIDATE_STATE_COMMAND="$bin/seafile-validate-state" \
		SEAFILE_STATE_DIR="$state" \
		SEAFILE_HOST_DIR="$runtime_host" \
		SEAFILE_APP_DIR="$runtime_app" \
		SEAFILE_METADATA_DIR="$runtime_metadata" \
		SEAFILE_EXPECTED_OWNER="$expected_owner" \
		SEAFILE_MAINTENANCE_LOCK="$lock" \
		"$health"
}

expect_failure() {
	local failure="$1" expected="$2" output
	: >"$calls"
	if output="$(STUB_FAIL="$failure" run_health 2>&1)"; then
		echo "health unexpectedly accepted $failure failure" >&2
		exit 1
	fi
	if ! grep -F -- "$expected" <<<"$output" >/dev/null; then
		printf 'unexpected output for %s failure:\n%s\n' "$failure" "$output" >&2
		exit 1
	fi
}

expect_failure inactive 'Seafile Compose service is not active'
expect_failure compose 'Seafile does not have exactly seven running Compose services'
expect_failure sql 'Seafile SQL probe failed'
expect_failure redis 'Seafile Redis probe failed'
expect_failure seafile 'Seafile HTTP probe failed'
expect_failure notification 'Seafile Notification probe failed'
expect_failure seasearch 'Seafile SeaSearch probe failed'
expect_failure metadata 'Seafile Metadata probe failed'
expect_failure onlyoffice 'Seafile OnlyOffice probe failed'
expect_failure dataset 'Seafile dataset probe failed'

: >"$calls"
busy_output="$(STUB_LOCK_BUSY=1 run_health)"
[ "$busy_output" = 'Seafile maintenance in progress' ]
if grep -E 'systemctl|docker|curl|validate-state' "$calls" >/dev/null; then
	echo 'busy health performed probes' >&2
	exit 1
fi

if SEAFILE_MAINTENANCE_LOCK_HELD=1 run_health >/dev/null 2>&1; then
	echo 'health accepted a lock-held flag without an inherited descriptor' >&2
	exit 1
fi

exec 9>"$lock"
if SEAFILE_MAINTENANCE_LOCK_HELD=1 run_health >/dev/null 2>&1; then
	echo 'health accepted an inherited but unlocked descriptor' >&2
	exit 1
fi
STUB_INHERITED_LOCK_HELD=1 SEAFILE_MAINTENANCE_LOCK_HELD=1 run_health >/dev/null
exec 9>&-

: >"$calls"
if env \
	STUB_CALLS="$calls" \
	STUB_FAIL=backup \
	STUB_INHERITED_LOCK_HELD=1 \
	SEAFILE_SYSTEMCTL_COMMAND="$bin/systemctl" \
	SEAFILE_DOCKER_COMMAND="$bin/docker" \
	SEAFILE_CURL_COMMAND="$bin/curl" \
	SEAFILE_FLOCK_COMMAND="$bin/flock" \
	SEAFILE_ID_COMMAND="$bin/id" \
	SEAFILE_JOURNALCTL_COMMAND="$bin/journalctl" \
	SEAFILE_VALIDATE_STATE_COMMAND="$bin/seafile-validate-state" \
	SEAFILE_HEALTH_COMMAND="$health" \
	SEAFILE_STATE_DIR="$state" \
	SEAFILE_HOST_DIR="$runtime_host" \
	SEAFILE_APP_DIR="$runtime_app" \
	SEAFILE_METADATA_DIR="$runtime_metadata" \
	SEAFILE_EXPECTED_OWNER="$expected_owner" \
	SEAFILE_MAINTENANCE_LOCK="$lock" \
	"$extended" >"$root/extended-output" 2>&1; then
	echo 'extended health accepted a failed backup freshness probe' >&2
	exit 1
fi
grep -F -- 'Seafile backup freshness probe failed' "$root/extended-output" >/dev/null

: >"$calls"
if env \
	STUB_CALLS="$calls" \
	STUB_LOCK_TIMEOUT=1 \
	SEAFILE_FLOCK_COMMAND="$bin/flock" \
	SEAFILE_ID_COMMAND="$bin/id" \
	SEAFILE_DOCKER_COMMAND="$bin/docker" \
	SEAFILE_STATE_DIR="$state" \
	SEAFILE_HOST_DIR="$runtime_host" \
	SEAFILE_MAINTENANCE_LOCK="$lock" \
	"$metadata" >"$root/metadata-output" 2>&1; then
	echo 'metadata probe accepted lock timeout' >&2
	exit 1
fi
grep -F -- 'Seafile maintenance lock timed out' "$root/metadata-output" >/dev/null
if grep -F 'docker ' "$calls" >/dev/null; then
	echo 'metadata probe started work before acquiring the lock' >&2
	exit 1
fi

if env SEAFILE_STATE_DIR="$state" "$enable_public" >/dev/null 2>&1; then
	echo 'public-health marker command accepted an unprivileged caller' >&2
	exit 1
fi
[ ! -e "$state/control/public-ingress-accepted" ]

echo 'Seafile maintenance state-machine fixtures passed'
