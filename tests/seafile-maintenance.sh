#!/usr/bin/env bash
set -euo pipefail

write_bash_stub() {
	local destination="$1"
	printf '#!%s\n' "$BASH" >"$destination"
	cat >>"$destination"
}

if [ "$#" -ne 8 ]; then
	echo "usage: seafile-maintenance.sh HEALTH EXTENDED METADATA ENABLE-PUBLIC SEARCH CONTRACT ONLYOFFICE-DRIVER ONLYOFFICE" >&2
	exit 64
fi

health="$1"
extended="$2"
metadata="$3"
enable_public="$4"
search="$5"
contract_source="$6"
onlyoffice_driver="$7"
onlyoffice="$8"
root="$(mktemp -d "$TMPDIR/seafile-maintenance-fixture.XXXXXX")"
holder_pid=
cleanup_fixture() {
	if [ -n "$holder_pid" ]; then
		kill "$holder_pid" 2>/dev/null || true
		wait "$holder_pid" 2>/dev/null || true
	fi
	rm -rf -- "$root"
}
trap cleanup_fixture EXIT HUP INT TERM
bin="$root/bin"
state="$root/state"
runtime_host="$root/run-host"
runtime_app="$root/run-app"
runtime_metadata="$root/run-metadata"
runtime_container=/run/seafile
lock="$root/maintenance.lock"
calls="$root/calls"
mkdir -p "$bin" "$state/shared/logs" "$state/shared/seafile/logs" \
	"$state/shared/seafile/conf" "$state/shared/seafile/md-data" \
	"$state/backups/seafile-29990101T000000-11111111-1111-4111-8111-111111111111" "$state/control" \
	"$runtime_host" "$runtime_app" "$runtime_metadata"
: >"$calls"
: >"$lock"

cat >"$runtime_host/environment" <<'EOF'
SEAFILE_MYSQL_DB_PASSWORD=fixture-database-password
REDIS_PASSWORD=fixture-redis-password
JWT_PRIVATE_KEY=fixture-jwt-private-key
SEAHUB_SECRET_KEY=fixture-seahub-secret-key
INIT_SEAFILE_ADMIN_EMAIL=fixture-admin@example.invalid
INIT_SEAFILE_ADMIN_PASSWORD=fixture-admin-password
SEAFILE_OAUTH_CLIENT_ID=fixture-client-id
SEAFILE_OAUTH_CLIENT_SECRET=fixture-client-secret
ONLYOFFICE_JWT_SECRET=fixture-office-secret
EOF
chmod 0400 "$runtime_host/environment"

cat >"$runtime_host/bootstrap.environment" <<'EOF'
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
chmod 0400 "$runtime_host/bootstrap.environment"
[ "$(wc -l <"$runtime_host/environment" | tr -d ' ')" -eq 9 ]
[ "$(wc -l <"$runtime_host/bootstrap.environment" | tr -d ' ')" -eq 12 ]

for name in .env seahub_settings.py seafevents.conf seafile.conf seafdav.conf; do
	target="$name"
	[ "$name" != .env ] || target=seafile.env
	: >"$runtime_app/$target"
	chmod 0444 "$runtime_app/$target"
	ln -s "$runtime_container/$target" "$state/shared/seafile/conf/$name"
done
chmod 0600 "$runtime_app/seafevents.conf"
cat >"$runtime_app/seafevents.conf" <<'EOF'
[SEASEARCH]
enabled = true
seasearch_token = Zml4dHVyZS1zZWFyY2gtdXNlcjpmaXh0dXJlLXNlYXJjaC1wYXNzd29yZA==
EOF
chmod 0400 "$runtime_app/seafevents.conf"
: >"$runtime_metadata/seafile.conf"
chmod 0444 "$runtime_metadata/seafile.conf"

cat >"$state/backups/seafile-29990101T000000-11111111-1111-4111-8111-111111111111/manifest.json" <<'EOF'
{"transaction_kind":"writers_quiesced=true","databases":[{},{},{}]}
EOF
chmod 0600 "$state/backups/seafile-29990101T000000-11111111-1111-4111-8111-111111111111/manifest.json"
chmod 0700 "$state/backups/seafile-29990101T000000-11111111-1111-4111-8111-111111111111"

validated_at="$(date +%s)"
cat >"$state/control/seafile-29990101T000000-11111111-1111-4111-8111-111111111111.validated" <<EOF
invocation=11111111-1111-4111-8111-111111111111
candidate=$state/backups/seafile-29990101T000000-11111111-1111-4111-8111-111111111111
validated_at=$(date --utc --iso-8601=seconds)
transaction_kind=writers_quiesced=true
EOF
chmod 0600 "$state/control/seafile-29990101T000000-11111111-1111-4111-8111-111111111111.validated"

write_bash_stub "$bin/systemctl" <<'EOF'
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

write_bash_stub "$bin/docker" <<'EOF'
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
		*' seafile '*curl*)
			[ "${STUB_FAIL:-}" != seasearch ] || exit 1
			printf '%s\n' '{}'
			;;
		*' seafile '*pgrep*'[s]eafevents.main'*)
			[ "${STUB_FAIL:-}" != seafevents ] || exit 1
			;;
		*' seafile-notification '*curl*)
			[ "${STUB_FAIL:-}" != notification-internal ] || exit 1
			;;
		*' seafile-metadata '*test*)
			[ "${STUB_FAIL:-}" != metadata ] || exit 1
			;;
		*' seafile '*python*)
			python_source="$(cat)"
			grep -F -- 'from seaserv import ccnet_api' <<<"$python_source" >/dev/null
			grep -F -- 'ccnet_api.get_emailusers("DB", -1, -1)' <<<"$python_source" >/dev/null
			grep -F -- 'if user.is_active' <<<"$python_source" >/dev/null
			grep -F -- 'SHULKER_SEAFILE_ACTIVE_USER_COUNT=' <<<"$python_source" >/dev/null
			if grep -F -- 'User.objects.filter' <<<"$python_source" >/dev/null; then
				exit 65
			fi
			case "${STUB_FAIL:-}" in
				account)
					# The pinned seahub.sh wrapper masks its child status and still
					# prints a blank and this completion line after a failed child.
					printf '%s\n' '' 'Done.'
					;;
				account-output)
					printf '%s\n' \
						'' \
						'unexpected output' \
						'SHULKER_SEAFILE_ACTIVE_USER_COUNT=3' \
						'Done.'
					;;
				account-reversed)
					printf '%s\n' \
						'' \
						'Done.' \
						'SHULKER_SEAFILE_ACTIVE_USER_COUNT=3'
					;;
				*)
					printf '%s\n' \
						'' \
						'SHULKER_SEAFILE_ACTIVE_USER_COUNT=3' \
						'Done.'
					;;
			esac
			;;
		*) exit 0 ;;
	esac
	exit 0
fi
exit 0
EOF

write_bash_stub "$bin/curl" <<'EOF'
set -euo pipefail
printf 'curl %s\n' "$*" >>"${STUB_CALLS:?}"
case " $* " in
	*':23239/'*) [ "${STUB_FAIL:-}" != seafile ] || exit 1 ;;
	*':23241/ping'*)
		[ "${STUB_FAIL:-}" != notification ] || exit 1
		if [ "${STUB_FAIL:-}" = notification-body ]; then
			printf '%s\n' '{"ret": "wrong"}'
		else
			printf '%s\n' '{"ret": "pong"}'
		fi
		;;
	*':23240/healthcheck'*)
		[ "${STUB_FAIL:-}" != onlyoffice ] || exit 1
		printf '%s\n' true
		;;
	*) exit 0 ;;
esac
EOF

write_bash_stub "$bin/flock" <<'EOF'
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

write_bash_stub "$bin/seafile-validate-state" <<'EOF'
set -euo pipefail
printf 'validate-state\n' >>"${STUB_CALLS:?}"
[ "${STUB_FAIL:-}" != dataset ]
EOF

write_bash_stub "$bin/journalctl" <<'EOF'
set -euo pipefail
printf 'journalctl %s\n' "$*" >>"${STUB_CALLS:?}"
case "${STUB_BORG_RECORD:-current}" in
	current) record_epoch="${STUB_VALIDATED_AT:?}" ;;
	stale) record_epoch="$((STUB_VALIDATED_AT - 1))" ;;
	no-row) exit 0 ;;
	*) exit 64 ;;
esac
printf '{"MESSAGE_ID":"39f53479d3a045ac8e11786248231fbf","UNIT":"borgmatic.service","__REALTIME_TIMESTAMP":"%s000000"}\n' \
	"$record_epoch"
EOF

write_bash_stub "$bin/metadata-probe" <<'EOF'
set -euo pipefail
exit 0
EOF

write_bash_stub "$bin/id" <<'EOF'
set -euo pipefail
[ "${1:-}" = -u ] || exit 64
printf '%s\n' 0
EOF

site_packages="$root/site-packages"
mkdir -p "$site_packages"
cat >"$site_packages/sitecustomize.py" <<'PY'
import http.server
import json
import sys
import types
import urllib.error
import urllib.request


class Response:
    def __init__(self, payload=b""):
        self.payload = payload

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self, amount=-1):
        return self.payload if amount is None or amount < 0 else self.payload[:amount]


detail_calls = 0


def urlopen(request, *_args, **_kwargs):
    global detail_calls
    url = request.full_url if hasattr(request, "full_url") else str(request)
    method = request.get_method() if hasattr(request, "get_method") else "GET"
    if method == "DELETE":
        raise urllib.error.URLError("cleanup rejected")
    if url.endswith("/api2/auth-token/"):
        return Response(json.dumps({"token": "fixture-token"}).encode())
    if "/api2/repos/?" in url:
        return Response(json.dumps([{
            "name": ".seafile-health",
            "id": "fixture-repo",
            "owner": "fixture-admin@example.invalid",
        }]).encode())
    if url.endswith("/api2/repos/fixture-repo/upload-link/"):
        return Response(json.dumps("http://fixture/upload").encode())
    if url == "http://fixture/upload":
        return Response()
    if "/api2/repos/fixture-repo/file/detail/?" in url:
        detail_calls += 1
        object_id = "before" if detail_calls == 1 else "after"
        return Response(json.dumps({"id": object_id}).encode())
    if url == "http://fixture/converted":
        return Response(b"PK fixture document")
    if url.endswith("/onlyoffice/editor-callback/"):
        return Response(b'{"error": 0}')
    if "/api2/repos/fixture-repo/file/?" in url:
        return Response(b"PK reopened document")
    raise urllib.error.URLError("unexpected fixture request")


urllib.request.urlopen = urlopen


class FakeServer:
    server_port = 32123

    def __init__(self, *_args, **_kwargs):
        pass

    def serve_forever(self):
        pass

    def shutdown(self):
        pass

    def server_close(self):
        pass


http.server.ThreadingHTTPServer = FakeServer


def module(name):
    value = types.ModuleType(name)
    value.__path__ = []
    sys.modules[name] = value
    return value


django = module("django")
django.setup = lambda: None
django_test = module("django.test")


class RequestFactory:
    def get(self, *_args, **_kwargs):
        return types.SimpleNamespace()


django_test.RequestFactory = RequestFactory
seahub = module("seahub")
seahub_base = module("seahub.base")
accounts = module("seahub.base.accounts")


class UserManager:
    def get(self, **_kwargs):
        return types.SimpleNamespace()


accounts.User = types.SimpleNamespace(objects=UserManager())
onlyoffice_package = module("seahub.onlyoffice")
converter = module("seahub.onlyoffice.converter")
converter.get_converter_uri = lambda *_args, **_kwargs: "http://fixture/converted"
onlyoffice_utils = module("seahub.onlyoffice.utils")
onlyoffice_utils.get_onlyoffice_dict = lambda *_args, **_kwargs: {
    "doc_key": "fixture-doc-key",
    "doc_url": "http://fixture/document",
}
seahub.base = seahub_base
seahub.onlyoffice = onlyoffice_package
seahub_base.accounts = accounts
onlyoffice_package.converter = converter
onlyoffice_package.utils = onlyoffice_utils
PY

write_bash_stub "$bin/docker-onlyoffice" <<'EOF'
set -euo pipefail
[ "${1:-}" = exec ] || exit 64
PYTHONPATH="${STUB_SITE_PACKAGES:?}" python3 -
EOF

chmod +x "$bin"/*

if stat --version >/dev/null 2>&1; then
	expected_owner="$(stat -c '%u:%g' "$state/shared/seafile/conf/.env")"
	expected_control_owner="$(stat -c '%u:%g' "$state/control/seafile-29990101T000000-11111111-1111-4111-8111-111111111111.validated")"
else
	expected_owner="$(stat -f '%u:%g' "$state/shared/seafile/conf/.env")"
	expected_control_owner="$(stat -f '%u:%g' "$state/control/seafile-29990101T000000-11111111-1111-4111-8111-111111111111.validated")"
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
		SEAFILE_FLOCK_COMMAND="${SEAFILE_FLOCK_COMMAND_OVERRIDE:-$bin/flock}" \
		SEAFILE_VALIDATE_STATE_COMMAND="$bin/seafile-validate-state" \
		SEAFILE_STATE_DIR="$state" \
		SEAFILE_HOST_DIR="$runtime_host" \
		SEAFILE_APP_DIR="$runtime_app" \
		SEAFILE_CONTAINER_CONFIG_DIR="$runtime_container" \
		SEAFILE_METADATA_DIR="$runtime_metadata" \
		SEAFILE_EXPECTED_OWNER="$expected_owner" \
		SEAFILE_MAINTENANCE_LOCK="$lock" \
		"$health"
}

run_search() {
	env \
		STUB_CALLS="$calls" \
		STUB_FAIL="${STUB_FAIL:-}" \
		SEAFILE_SYSTEMCTL_COMMAND="$bin/systemctl" \
		SEAFILE_DOCKER_COMMAND="$bin/docker" \
		SEAFILE_FLOCK_COMMAND="$bin/flock" \
		SEAFILE_ID_COMMAND="$bin/id" \
		SEAFILE_STATE_DIR="$state" \
		SEAFILE_HOST_DIR="$runtime_host" \
		SEAFILE_APP_DIR="$runtime_app" \
		SEAFILE_EXPECTED_OWNER="$expected_owner" \
		SEAFILE_MAINTENANCE_LOCK="$lock" \
		"$search"
}

expect_bootstrap_failure() {
	local scenario="$1" output
	if output="$(run_health 2>&1)"; then
		echo "health unexpectedly accepted $scenario bootstrap environment" >&2
		exit 1
	fi
	grep -F -- 'Seafile bootstrap maintenance environment probe failed' <<<"$output" >/dev/null
	for value in fixture-root-password fixture-search-user fixture-search-password; do
		if grep -F -- "$value" <<<"$output" >/dev/null; then
			echo "health exposed a bootstrap value for $scenario" >&2
			exit 1
		fi
	done
}

expect_search_auth_failure() {
	local scenario="$1" command output
	for command in run_health run_search; do
		if output="$($command 2>&1)"; then
			echo "$command unexpectedly accepted $scenario SeaSearch authorization" >&2
			exit 1
		fi
		grep -F -- 'Seafile SeaSearch credentials probe failed' <<<"$output" >/dev/null
		for value in \
			fixture-search-user \
			fixture-search-password \
			Zml4dHVyZS1zZWFyY2gtdXNlcjpmaXh0dXJlLXNlYXJjaC1wYXNzd29yZA==; do
			if grep -F -- "$value" <<<"$output" >/dev/null; then
				echo "$command exposed a SeaSearch credential for $scenario" >&2
				exit 1
			fi
		done
	done
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
expect_failure seafevents 'Seafile events worker probe failed'
expect_failure notification 'Seafile Notification probe failed'
expect_failure notification-body 'Seafile Notification probe failed'
expect_failure seasearch 'Seafile SeaSearch probe failed'
expect_failure metadata 'Seafile Metadata probe failed'
expect_failure onlyoffice 'Seafile OnlyOffice probe failed'
expect_failure dataset 'Seafile dataset probe failed'
expect_failure account 'Seafile account count probe failed'
expect_failure account-output 'Seafile account count probe failed'
expect_failure account-reversed 'Seafile account count probe failed'

: >"$calls"
run_health >/dev/null
grep -F 'curl --fail --silent --show-error --max-time 10 http://127.0.0.1:23241/ping' "$calls" >/dev/null
grep -F "docker exec seafile pgrep -f [s]eafevents.main" "$calls" >/dev/null
if grep -F 'docker exec seafile-notification curl' "$calls" >/dev/null; then
	echo 'health used an unavailable in-container Notification curl probe' >&2
	exit 1
fi

: >"$calls"
run_search >/dev/null
grep -F 'docker exec --interactive seafile curl --config -' "$calls" >/dev/null
if grep -F 'docker exec --interactive seafile-seasearch curl' "$calls" >/dev/null; then
	echo 'maintenance used curl missing from the pinned SeaSearch image' >&2
	exit 1
fi
for value in \
	fixture-root-password \
	fixture-search-user \
	fixture-search-password \
	Zml4dHVyZS1zZWFyY2gtdXNlcjpmaXh0dXJlLXNlYXJjaC1wYXNzd29yZA==; do
	if grep -F -- "$value" "$calls" >/dev/null; then
		echo "maintenance probe logged a protected value" >&2
		exit 1
	fi
done

rm "$state/shared/seafile/conf/seafile.conf"
ln -s "$runtime_app/seafile.conf" "$state/shared/seafile/conf/seafile.conf"
if output="$(run_health 2>&1)"; then
	echo 'health accepted a persistent link to the host runtime namespace' >&2
	exit 1
fi
grep -F -- 'Seafile runtime configuration probe failed' <<<"$output" >/dev/null
rm "$state/shared/seafile/conf/seafile.conf"
ln -s "$runtime_container/seafile.conf" "$state/shared/seafile/conf/seafile.conf"

cp "$runtime_app/seafevents.conf" "$runtime_app/seafevents.conf.saved"
chmod 0600 "$runtime_app/seafevents.conf"
: >"$runtime_app/seafevents.conf"
chmod 0400 "$runtime_app/seafevents.conf"
expect_search_auth_failure missing
mv -f "$runtime_app/seafevents.conf.saved" "$runtime_app/seafevents.conf"

cp "$runtime_app/seafevents.conf" "$runtime_app/seafevents.conf.saved"
chmod 0600 "$runtime_app/seafevents.conf"
printf '%s\n' 'seasearch_token = %%%' >"$runtime_app/seafevents.conf"
chmod 0400 "$runtime_app/seafevents.conf"
expect_search_auth_failure malformed
mv -f "$runtime_app/seafevents.conf.saved" "$runtime_app/seafevents.conf"

cp "$runtime_app/seafevents.conf" "$runtime_app/seafevents.conf.saved"
chmod 0600 "$runtime_app/seafevents.conf"
printf '%s\n' \
	'seasearch_token = Zml4dHVyZS1zZWFyY2gtdXNlcjpmaXh0dXJlLXNlYXJjaC1wYXNzd29yZA==' \
	>>"$runtime_app/seafevents.conf"
chmod 0400 "$runtime_app/seafevents.conf"
expect_search_auth_failure duplicate
mv -f "$runtime_app/seafevents.conf.saved" "$runtime_app/seafevents.conf"

chmod 0600 "$runtime_app/seafevents.conf"
expect_search_auth_failure unsafe-mode
chmod 0400 "$runtime_app/seafevents.conf"

mv "$runtime_app/seafevents.conf" "$runtime_app/seafevents.conf.saved"
ln -s "$runtime_app/seafevents.conf.saved" "$runtime_app/seafevents.conf"
expect_search_auth_failure symlink
rm "$runtime_app/seafevents.conf"
mv "$runtime_app/seafevents.conf.saved" "$runtime_app/seafevents.conf"

mv "$runtime_host/bootstrap.environment" "$runtime_host/bootstrap.environment.saved"
expect_bootstrap_failure missing
mv "$runtime_host/bootstrap.environment.saved" "$runtime_host/bootstrap.environment"

chmod 0600 "$runtime_host/bootstrap.environment"
expect_bootstrap_failure unsafe-mode
chmod 0400 "$runtime_host/bootstrap.environment"

ln "$runtime_host/bootstrap.environment" "$runtime_host/bootstrap.environment.link"
expect_bootstrap_failure hardlink
rm "$runtime_host/bootstrap.environment.link"

cp "$runtime_host/bootstrap.environment" "$runtime_host/bootstrap.environment.saved"
chmod 0600 "$runtime_host/bootstrap.environment"
printf '%s\n' 'INIT_SS_ADMIN_USER=fixture-search-user' >>"$runtime_host/bootstrap.environment"
chmod 0400 "$runtime_host/bootstrap.environment"
expect_bootstrap_failure duplicate-key
mv -f "$runtime_host/bootstrap.environment.saved" "$runtime_host/bootstrap.environment"

printf '%s\n' fixture-root-password >"$state/shared/logs/bootstrap-secret.log"
if output="$(run_health 2>&1)"; then
	echo 'health accepted a bootstrap-only secret in persistent logs' >&2
	exit 1
fi
grep -F -- 'Seafile persistent log probe failed' <<<"$output" >/dev/null
if grep -F -- fixture-root-password <<<"$output" >/dev/null; then
	echo 'health exposed the bootstrap-only persistent-log secret' >&2
	exit 1
fi
rm -f "$state/shared/logs/bootstrap-secret.log"

monitor_log="$state/shared/seafile/logs/seafile-monitor.log"
truncate -s 56623104 "$monitor_log"
run_health >/dev/null

printf '%s\n' fixture-root-password >>"$monitor_log"
if output="$(run_health 2>&1)"; then
	echo 'health skipped a secret beyond 16 MiB in seafile-monitor.log' >&2
	exit 1
fi
grep -F -- 'Seafile persistent log probe failed' <<<"$output" >/dev/null
if grep -F -- fixture-root-password <<<"$output" >/dev/null; then
	echo 'health exposed a secret from seafile-monitor.log' >&2
	exit 1
fi

: >"$monitor_log"
truncate -s 67108865 "$monitor_log"
if run_health >/dev/null 2>&1; then
	echo 'health accepted seafile-monitor.log above 64 MiB' >&2
	exit 1
fi
rm -f "$monitor_log"

other_log="$state/shared/seafile/logs/other.log"
truncate -s 16777216 "$other_log"
if run_health >/dev/null 2>&1; then
	echo 'health accepted a non-monitor log above 16 MiB' >&2
	exit 1
fi
rm -f "$other_log"

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

real_flock="$(command -v flock)"
holder_ready="$root/holder-ready"
holder_release="$root/holder-release"
(
	exec 7>"$lock"
	"$real_flock" -n 7
	: >"$holder_ready"
	while [ ! -e "$holder_release" ]; do
		sleep 0.01
	done
) &
holder_pid="$!"
for _ in $(seq 1 500); do
	[ ! -e "$holder_ready" ] || break
	sleep 0.01
done
[ -e "$holder_ready" ]
exec 9>"$lock"
if SEAFILE_FLOCK_COMMAND_OVERRIDE="$real_flock" SEAFILE_MAINTENANCE_LOCK_HELD=1 \
	run_health >"$root/foreign-lock-output" 2>&1; then
	echo 'health accepted an unlocked inherited descriptor while another process held the lock' >&2
	exit 1
fi
grep -F -- 'Seafile inherited maintenance lock descriptor is not held' \
	"$root/foreign-lock-output" >/dev/null
exec 9>&-
: >"$holder_release"
wait "$holder_pid"
holder_pid=

exec 9>"$lock"
"$real_flock" -n 9
SEAFILE_FLOCK_COMMAND_OVERRIDE="$real_flock" SEAFILE_MAINTENANCE_LOCK_HELD=1 run_health >/dev/null
"$real_flock" -u 9
exec 9>&-

run_extended() {
	env \
		STUB_CALLS="$calls" \
		STUB_FAIL="${STUB_FAIL:-}" \
		STUB_BORG_RECORD="${STUB_BORG_RECORD:-current}" \
		STUB_VALIDATED_AT="$validated_at" \
		STUB_INHERITED_LOCK_HELD=1 \
		SEAFILE_SYSTEMCTL_COMMAND="$bin/systemctl" \
		SEAFILE_DOCKER_COMMAND="$bin/docker" \
		SEAFILE_CURL_COMMAND="$bin/curl" \
		SEAFILE_FLOCK_COMMAND="$bin/flock" \
		SEAFILE_ID_COMMAND="$bin/id" \
		SEAFILE_JOURNALCTL_COMMAND="$bin/journalctl" \
		SEAFILE_VALIDATE_STATE_COMMAND="$bin/seafile-validate-state" \
		SEAFILE_HEALTH_COMMAND="$health" \
		SEAFILE_METADATA_PROBE_COMMAND="$bin/metadata-probe" \
		SEAFILE_STATE_DIR="$state" \
		SEAFILE_HOST_DIR="$runtime_host" \
		SEAFILE_APP_DIR="$runtime_app" \
		SEAFILE_METADATA_DIR="$runtime_metadata" \
		SEAFILE_EXPECTED_OWNER="$expected_owner" \
		SEAFILE_EXPECTED_CONTROL_OWNER="$expected_control_owner" \
		SEAFILE_MAINTENANCE_LOCK="$lock" \
		"$extended"
}

expect_backup_failure() {
	local scenario="$1" output
	: >"$calls"
	if output="$(run_extended 2>&1)"; then
		printf 'extended health accepted %s backup evidence\n' "$scenario" >&2
		exit 1
	fi
	grep -F -- 'Seafile backup freshness probe failed' <<<"$output" >/dev/null
}

STUB_FAIL=backup expect_backup_failure 'failed service result'
STUB_BORG_RECORD=stale expect_backup_failure 'stale completion record'
STUB_BORG_RECORD=no-row expect_backup_failure 'empty completion record'

: >"$calls"
[ "$(STUB_BORG_RECORD=current run_extended)" = 'public ingress acceptance pending' ]

# Use the on-disk schema emitted by backup.nix, not a separate health-only marker.
validation_marker="$state/control/seafile-29990101T000000-11111111-1111-4111-8111-111111111111.validated"
backup_candidate="$state/backups/seafile-29990101T000000-11111111-1111-4111-8111-111111111111"
cp "$validation_marker" "$root/good-validation"
cp "$backup_candidate/manifest.json" "$root/good-manifest"

printf 'invocation=duplicate\n' >>"$validation_marker"
expect_backup_failure 'duplicate validation field'
cp "$root/good-validation" "$validation_marker"
sed 's/^invocation=.*/invocation=foreign/' "$root/good-validation" >"$validation_marker"
expect_backup_failure 'mismatched invocation'
sed 's/^invocation=.*/invocation=111111111111/' "$root/good-validation" >"$validation_marker"
expect_backup_failure 'partial invocation suffix'
sed 's|^candidate=.*|candidate=/foreign/backup|' "$root/good-validation" >"$validation_marker"
expect_backup_failure 'foreign candidate'
sed '/^validated_at=/d' "$root/good-validation" >"$validation_marker"
expect_backup_failure 'missing validation timestamp'
for validation_time in '2000-01-01T00:00:00+00:00' '2999-01-01T00:00:00+00:00' 'invalid'; do
	sed "s/^validated_at=.*/validated_at=$validation_time/" "$root/good-validation" >"$validation_marker"
	expect_backup_failure 'stale, future, or malformed validation timestamp'
done
cp "$root/good-validation" "$validation_marker"
chmod 0644 "$validation_marker"
expect_backup_failure 'unprotected validation marker'
chmod 0600 "$validation_marker"
mv "$validation_marker" "$root/saved-validation"
ln -s "$root/saved-validation" "$validation_marker"
expect_backup_failure 'symlinked validation marker'
rm "$validation_marker"
mv "$root/saved-validation" "$validation_marker"
mv "$backup_candidate" "$root/saved-candidate"
ln -s "$root/saved-candidate" "$backup_candidate"
expect_backup_failure 'symlinked candidate'
rm "$backup_candidate"
mv "$root/saved-candidate" "$backup_candidate"
for manifest_content in '{"writers_quiesced":true}' '{"transaction_kind":"writers_quiesced=false","databases":[{},{},{}]}' '{"transaction_kind":"writers_quiesced=true","databases":[]}' 'invalid'; do
	printf '%s\n' "$manifest_content" >"$backup_candidate/manifest.json"
	expect_backup_failure 'invalid manifest transaction'
done
cp "$root/good-manifest" "$backup_candidate/manifest.json"
mv "$backup_candidate/manifest.json" "$root/saved-manifest"
ln -s "$root/saved-manifest" "$backup_candidate/manifest.json"
expect_backup_failure 'symlinked manifest'
rm "$backup_candidate/manifest.json"
mv "$root/saved-manifest" "$backup_candidate/manifest.json"
[ "$(STUB_BORG_RECORD=current run_extended)" = 'public ingress acceptance pending' ]

websocket_nonce="$(sed -n "s/.*Sec-WebSocket-Key: \([^']*\)'.*/\1/p" "$contract_source")"
[ "$websocket_nonce" = 'dGhlIHNhbXBsZSBub25jZQ==' ]
decoded_nonce="$root/websocket-nonce"
printf '%s' "$websocket_nonce" | base64 --decode >"$decoded_nonce"
[ "$(wc -c <"$decoded_nonce" | tr -d ' ')" -eq 16 ]

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

driver_status=0
env \
	INIT_SEAFILE_ADMIN_EMAIL=fixture-admin@example.invalid \
	INIT_SEAFILE_ADMIN_PASSWORD=fixture-admin-password \
	PYTHONPATH="$site_packages" \
	python3 "$onlyoffice_driver" >"$root/onlyoffice-driver-output" 2>&1 || driver_status="$?"
if [ -s "$root/onlyoffice-driver-output" ]; then
	echo 'OnlyOffice driver emitted output after cleanup failure' >&2
	exit 1
fi
if [ "$driver_status" -eq 0 ]; then
	echo 'OnlyOffice driver accepted probe-object cleanup failure' >&2
	exit 1
fi

: >"$state/control/public-ingress-accepted"
chmod 0600 "$state/control/public-ingress-accepted"
onlyoffice_status=0
env \
	STUB_CALLS="$calls" \
	STUB_SITE_PACKAGES="$site_packages" \
	SEAFILE_DOCKER_COMMAND="$bin/docker-onlyoffice" \
	SEAFILE_FLOCK_COMMAND="$bin/flock" \
	SEAFILE_ID_COMMAND="$bin/id" \
	SEAFILE_ONLYOFFICE_PROBE_PROGRAM="$onlyoffice_driver" \
	SEAFILE_STATE_DIR="$state" \
	SEAFILE_HOST_DIR="$runtime_host" \
	SEAFILE_MAINTENANCE_LOCK="$lock" \
	SEAFILE_SYSTEMCTL_COMMAND="$bin/systemctl" \
	"$onlyoffice" >"$root/onlyoffice-output" 2>&1 || onlyoffice_status="$?"
if [ "$onlyoffice_status" -eq 0 ]; then
	echo 'OnlyOffice helper accepted probe-object cleanup failure' >&2
	exit 1
fi
if ! grep -F -- 'Seafile OnlyOffice functional probe failed' "$root/onlyoffice-output" >/dev/null; then
	echo 'OnlyOffice helper did not report the cleanup failure' >&2
	exit 1
fi
if grep -F -- 'Seafile OnlyOffice callback and reopen probe passed' \
	"$root/onlyoffice-output" >/dev/null; then
	echo 'OnlyOffice helper printed success after cleanup failure' >&2
	exit 1
fi

echo 'Seafile maintenance state-machine fixtures passed'
