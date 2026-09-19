#!/usr/bin/env bash
# Publish only validated portable PostgreSQL dump sets; no application downtime.
set -euo pipefail
umask 077
backups_dir="$1" lock_file="$2" validate="$3" manifest="$4"
if [ "${TASKVIEW_MAINTENANCE_LOCK_HELD:-0}" != 1 ]; then
	exec 9>"$lock_file"
	flock -w 900 9
fi
"$validate"
[ "$(docker inspect --format '{{.State.Running}}' taskview-database)" = true ]
candidate="$(mktemp -d "$backups_dir/.candidate.XXXXXXXX")"
trap 'rm -rf -- "$candidate"' EXIT
trap 'exit 1' INT TERM
# Timeout bounds failed database operations without aborting normal larger dumps.
timeout 600 docker exec taskview-database pg_dump --username taskview --dbname taskview --format custom >"$candidate/taskview.dump"
test -s "$candidate/taskview.dump"
timeout 120 docker exec -i taskview-database pg_restore --list <"$candidate/taskview.dump" >"$candidate/catalogue.txt"
(cd "$candidate" && sha256sum taskview.dump >SHA256SUMS)
# During upgrades the running source images can differ from the prospective Nix lock.
images='{}'
for component in database api web mcp centrifugo; do
	if image="$(docker inspect --format '{{.Config.Image}}' "taskview-$component" 2>/dev/null)"; then
		images="$(jq --arg component "$component" --arg image "$image" '. + {($component): $image}' <<<"$images")"
	fi
done
jq --argjson images "$images" --arg created_at "$(date --utc --iso-8601=seconds)" '. + {created_at: $created_at, images: $images}' "$manifest" >"$candidate/manifest.json"
jq -e 'type == "object" and (.created_at | type == "string")' "$candidate/manifest.json" >/dev/null
completed="$backups_dir/taskview-$(date --utc +%Y%m%dT%H%M%S.%NZ)"
mv -- "$candidate" "$completed"
trap - EXIT INT TERM
# Only direct, completed, owned dump-set directories are eligible for retention.
mapfile -t sets < <(find "$backups_dir" -mindepth 1 -maxdepth 1 -type d -name 'taskview-*' -printf '%f\n' | sort -r)
for ((index = 14; index < ${#sets[@]}; index++)); do
	name="${sets[$index]}"
	if [[ $name =~ ^taskview-[0-9]{8}T[0-9]{6}\.[0-9]{9}Z$ ]]; then
		rm -rf -- "${backups_dir:?}/${name:?}"
	fi
done
echo 'TaskView database backup created and catalogue validated'
