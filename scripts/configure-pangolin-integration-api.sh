#!/usr/bin/env bash

set -Eeuo pipefail

api_host="${1:-api.shulker.link}"
config_dir="/var/lib/pangolin/config"
config_file="$config_dir/config.yml"
dynamic_file="$config_dir/traefik/dynamic_config.yml"

if [[ $EUID -ne 0 ]]; then
	echo "Run this helper as root on the Pangolin host." >&2
	exit 1
fi

if [[ ! $api_host =~ ^[a-zA-Z0-9.-]+$ || $api_host != *.* ]]; then
	echo "Invalid API hostname: $api_host" >&2
	exit 1
fi

for command in yq systemctl docker curl; do
	if ! command -v "$command" >/dev/null 2>&1; then
		echo "Required command is unavailable: $command" >&2
		exit 1
	fi
done

for file in "$config_file" "$dynamic_file"; do
	if [[ ! -f $file ]]; then
		echo "Required Pangolin configuration is missing: $file" >&2
		exit 1
	fi
	yq eval '.' "$file" >/dev/null
done

umask 077
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="$config_dir/codex-backups/integration-api-$timestamp"
mkdir -p "$backup_dir"
chmod 0700 "$config_dir/codex-backups" "$backup_dir"
cp --preserve=all "$config_file" "$backup_dir/config.yml"
cp --preserve=all "$dynamic_file" "$backup_dir/dynamic_config.yml"

config_tmp="$(mktemp "$config_dir/.config.yml.codex.XXXXXX")"
dynamic_tmp="$(mktemp "$config_dir/traefik/.dynamic_config.yml.codex.XXXXXX")"
rollback_needed=0

cleanup() {
	rm -f "$config_tmp" "$dynamic_tmp"
}

rollback() {
	local exit_code="$?"
	trap - ERR

	if [[ $rollback_needed -eq 1 ]]; then
		echo "Configuration failed; restoring the backups." >&2
		cp --preserve=all "$backup_dir/config.yml" "$config_file"
		cp --preserve=all "$backup_dir/dynamic_config.yml" "$dynamic_file"
		systemctl restart docker-pangolin.service docker-traefik.service || true
	fi

	cleanup
	exit "$exit_code"
}

trap cleanup EXIT
trap rollback ERR

cp --preserve=all "$config_file" "$config_tmp"
cp --preserve=all "$dynamic_file" "$dynamic_tmp"

yq eval --inplace \
	'.flags.enable_integration_api = true | .server.integration_port = 3003' \
	"$config_tmp"

# The yq expression reads API_HOST with strenv; shell expansion is unwanted.
# shellcheck disable=SC2016
API_HOST="$api_host" yq eval --inplace '
  .http.routers."int-api-router-redirect" = {
    "rule": ("Host(`" + strenv(API_HOST) + "`)"),
    "service": "int-api-service",
    "entryPoints": ["web"],
    "middlewares": ["redirect-to-https"]
  } |
  .http.routers."int-api-router" = {
    "rule": ("Host(`" + strenv(API_HOST) + "`)"),
    "service": "int-api-service",
    "entryPoints": ["websecure"],
    "tls": {"certResolver": "letsencrypt"}
  } |
  .http.services."int-api-service" = {
    "loadBalancer": {
      "servers": [{"url": "http://pangolin:3003"}]
    }
  }
' "$dynamic_tmp"

if yq eval --exit-status '.http.middlewares.badger != null' "$dynamic_file" >/dev/null; then
	yq eval --inplace \
		'.http.routers."int-api-router-redirect".middlewares += ["badger"]' \
		"$dynamic_tmp"
fi

yq eval --exit-status \
	'.flags.enable_integration_api == true and .server.integration_port == 3003' \
	"$config_tmp" >/dev/null
# shellcheck disable=SC2016
API_HOST="$api_host" yq eval --exit-status '
  .http.routers."int-api-router".rule == ("Host(`" + strenv(API_HOST) + "`)") and
  .http.routers."int-api-router".service == "int-api-service" and
  .http.services."int-api-service".loadBalancer.servers[0].url == "http://pangolin:3003"
' "$dynamic_tmp" >/dev/null

chown --reference="$config_file" "$config_tmp"
chmod --reference="$config_file" "$config_tmp"
chown --reference="$dynamic_file" "$dynamic_tmp"
chmod --reference="$dynamic_file" "$dynamic_tmp"

rollback_needed=1
mv -f "$config_tmp" "$config_file"
mv -f "$dynamic_tmp" "$dynamic_file"

systemctl restart docker-pangolin.service
systemctl restart docker-traefik.service
systemctl is-active --quiet docker-pangolin.service docker-traefik.service

api_ready=0
for _ in $(seq 1 30); do
	if docker exec pangolin /usr/bin/curl -fsS \
		"http://127.0.0.1:3003/v1/docs" >/dev/null 2>&1; then
		api_ready=1
		break
	fi
	sleep 2
done

if [[ $api_ready -ne 1 ]]; then
	echo "Pangolin's internal Integration API did not become ready." >&2
	exit 1
fi

rollback_needed=0
trap - ERR

echo "Pangolin Integration API enabled for https://$api_host/v1/."
echo "Root-only backups: $backup_dir"

external_ready=0
for _ in $(seq 1 30); do
	if curl -fsS "https://$api_host/v1/docs" >/dev/null 2>&1; then
		external_ready=1
		break
	fi
	sleep 2
done

if [[ $external_ready -ne 1 ]]; then
	echo "The internal API is healthy, but external TLS/routing is not ready yet." >&2
	exit 2
fi

echo "External TLS and routing verified."
