#!/usr/bin/env bash
set -euo pipefail
script="$1"
[ -f "$script" ] || {
	echo 'TaskView backup helper is not implemented'
	exit 1
}
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir "$fixture/bin" "$fixture/backups"
printf '{}\n' >"$fixture/manifest.json"
cat >"$fixture/bin/docker" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *'{{.State.Running}}'*) echo true ;;
  *'{{.Config.Image}}'*) echo 'previous-image@sha256:fixture' ;;
  *pg_dump*) [ "$MODE" != dump ] || exit 1; echo fixture-dump ;;
  *pg_restore*) [ "$MODE" != catalogue ] || exit 1; cat ;;
esac
STUB
cat >"$fixture/bin/validate" <<'STUB'
#!/usr/bin/env bash
[ "$MODE" != state ]
STUB
chmod +x "$fixture/bin/"*
export PATH="$fixture/bin:$PATH"
for mode in state dump catalogue success; do
	export MODE="$mode"
	if bash "$script" "$fixture/backups" "$fixture/lock" validate "$fixture/manifest.json"; then
		[ "$mode" = success ] || exit 1
		find "$fixture/backups" -name taskview.dump | grep -q .
		manifest_path="$(find "$fixture/backups" -name manifest.json)"
		jq -e '.images.api == "previous-image@sha256:fixture"' "$manifest_path" >/dev/null
	else
		[ "$mode" != success ] || exit 1
		[ -z "$(find "$fixture/backups" -mindepth 1 -print -quit)" ]
	fi
done
echo 'TaskView backup: failures publish no dump; successful dump includes verified catalogue and checksum'
