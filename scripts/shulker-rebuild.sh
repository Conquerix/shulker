#!/usr/bin/env bash

set -euo pipefail

usage() {
	cat <<'EOF'
Usage: shulker-rebuild [--skip-secret-check] <nixos-rebuild arguments>

Evaluates the requested flake host, verifies that every configured OpNix
secret can be resolved with its configured service-account token, and then
runs nixos-rebuild with the remaining arguments unchanged.

Examples:
  shulker-rebuild dry-activate --flake .#shulker
  shulker-rebuild switch --flake .#shulker
  shulker-rebuild --skip-secret-check switch --flake .#shulker

Rollback and help commands do not need a secret preflight.
EOF
}

nix_command="${SHULKER_NIX_COMMAND:-nix}"
opnix_command="${SHULKER_OPNIX_COMMAND:-opnix}"
rebuild_command="${SHULKER_NIXOS_REBUILD_COMMAND:-nixos-rebuild}"

skip_secret_check=false
flake_ref=""
rollback=false
show_help=false
rebuild_args=()

while (($# > 0)); do
	case "$1" in
	--skip-secret-check)
		skip_secret_check=true
		shift
		;;
	--flake)
		if (($# < 2)); then
			echo "shulker-rebuild: --flake requires a value" >&2
			exit 2
		fi
		flake_ref="$2"
		rebuild_args+=("$1" "$2")
		shift 2
		;;
	--flake=*)
		flake_ref="${1#--flake=}"
		rebuild_args+=("$1")
		shift
		;;
	--rollback)
		rollback=true
		rebuild_args+=("$1")
		shift
		;;
	-h | --help)
		show_help=true
		rebuild_args+=("$1")
		shift
		;;
	*)
		rebuild_args+=("$1")
		shift
		;;
	esac
done

if $show_help; then
	usage
	echo
	exec "$rebuild_command" "${rebuild_args[@]}"
fi

if $rollback; then
	exec "$rebuild_command" "${rebuild_args[@]}"
fi

if $skip_secret_check; then
	echo "WARNING: skipping the 1Password secret preflight" >&2
	exec "$rebuild_command" "${rebuild_args[@]}"
fi

if [[ -z $flake_ref ]]; then
	echo "shulker-rebuild: pass an explicit NixOS flake target with --flake .#<host>" >&2
	exit 2
fi

if [[ $flake_ref != *#* ]]; then
	echo "shulker-rebuild: the --flake value must include a host fragment, for example .#shulker" >&2
	exit 2
fi

flake_source="${flake_ref%%#*}"
host_name="${flake_ref#*#}"

if [[ -z $flake_source ]]; then
	flake_source="."
fi

if [[ ! $host_name =~ ^[a-zA-Z0-9_-]+$ ]]; then
	echo "shulker-rebuild: invalid NixOS host name in --flake: $host_name" >&2
	exit 2
fi

umask 077
temporary_root="${XDG_RUNTIME_DIR:-/tmp}"
temporary_dir="$(mktemp -d "$temporary_root/shulker-secret-preflight.XXXXXX")"

cleanup() {
	case "$temporary_dir" in
	"$temporary_root"/shulker-secret-preflight.*)
		rm -rf -- "$temporary_dir"
		;;
	esac
}
trap cleanup EXIT

metadata_file="$temporary_dir/metadata.json"
config_file="$temporary_dir/secrets.json"
output_dir="$temporary_dir/resolved"
opnix_log="$temporary_dir/opnix.log"

echo "Evaluating prospective 1Password secrets for $host_name..."
# shellcheck disable=SC2016 # This is a Nix expression, not shell interpolation.
"$nix_command" eval --json \
	"${flake_source}#nixosConfigurations.${host_name}.config.services.onepassword-secrets" \
	--apply '
    cfg: {
      enabled = cfg.enable;
      tokenFile = toString cfg.tokenFile;
      configFiles = builtins.map toString cfg.configFiles;
      secrets = builtins.map (name: {
        path = name;
        reference = cfg.secrets.${name}.reference;
        owner = "";
        group = "";
        mode = "0600";
        services = [];
      }) (builtins.attrNames cfg.secrets);
    }
  ' >"$metadata_file"

if [[ "$(jq -r '.enabled' "$metadata_file")" != "true" ]]; then
	echo "OpNix is disabled for $host_name; no secret preflight is needed."
	cleanup
	trap - EXIT
	exec "$rebuild_command" "${rebuild_args[@]}"
fi

jq '{secrets, systemdIntegration: {enable: false}}' "$metadata_file" >"$config_file"

mapfile -t additional_config_files < <(jq -r '.configFiles[]' "$metadata_file")
if ((${#additional_config_files[@]} > 0)); then
	jq -s '
    .[0] as $metadata
    | {
        secrets: (
          $metadata.secrets
          + (
              [.[1:][] | .secrets[] | .reference]
              | to_entries
              | map({
                  path: "externalConfigSecret" + ((.key + 1) | tostring),
                  reference: .value,
                  owner: "",
                  group: "",
                  mode: "0600",
                  services: []
                })
            )
        ),
        systemdIntegration: {enable: false}
      }
  ' "$metadata_file" "${additional_config_files[@]}" >"$config_file"
fi

secret_count="$(jq -r '.secrets | length' "$config_file")"
if [[ $secret_count -eq 0 ]]; then
	echo "No OpNix secrets are configured for $host_name."
	cleanup
	trap - EXIT
	exec "$rebuild_command" "${rebuild_args[@]}"
fi

token_file="$(jq -r '.tokenFile' "$metadata_file")"
if [[ ! -r $token_file ]]; then
	echo "shulker-rebuild: the OpNix token file is not readable: $token_file" >&2
	echo "Run this command with sufficient privileges or provision the token first." >&2
	exit 1
fi
if [[ ! -s $token_file ]]; then
	echo "shulker-rebuild: the OpNix token file is empty: $token_file" >&2
	exit 1
fi

echo "Checking $secret_count configured secret references with 1Password..."
set +e
"$opnix_command" secret \
	-token-file "$token_file" \
	-config "$config_file" \
	-output "$output_dir" >"$opnix_log" 2>&1
opnix_status=$?
set -e

case "$opnix_status" in
0)
	echo "1Password preflight passed for all $secret_count configured secrets."
	;;
65)
	echo "shulker-rebuild: one or more configured secrets could not be resolved:" >&2
	jq -r --rawfile log "$opnix_log" \
		'.secrets[] as $secret | select($log | contains($secret.reference)) | "  - " + $secret.path' \
		"$config_file" >&2
	echo "Create the missing item or field, correct its reference, or grant the service account access." >&2
	exit 1
	;;
75)
	echo "shulker-rebuild: 1Password rate-limited the secret preflight; wait and retry." >&2
	exit 1
	;;
*)
	echo "shulker-rebuild: the 1Password preflight failed before references could be verified." >&2
	echo "Check the token, network connectivity, and 1Password service status, then retry." >&2
	exit 1
	;;
esac

cleanup
trap - EXIT
exec "$rebuild_command" "${rebuild_args[@]}"
