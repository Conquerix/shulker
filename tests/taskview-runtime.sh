#!/usr/bin/env bash
set -euo pipefail
script="$1"
[ -f "$script" ] || {
	echo 'TaskView runtime lifecycle is not implemented'
	exit 1
}
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/state/postgres"
export EVENTS="$fixture/events"
cat >"$fixture/bin/compose" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$EVENTS"
case "$*" in
  *'up '*database*) [ "$MODE" != database ] ;;
  *'run '*migration*) [ "$MODE" != migration ] ;;
  *'up '*centrifugo*) if [ "$MODE" = signal ]; then kill -TERM "$PPID"; fi ;;
esac
STUB
cat >"$fixture/bin/validate" <<'STUB'
#!/usr/bin/env bash
echo validate >> "$EVENTS"
[ "$MODE" != state ]
STUB
cat >"$fixture/bin/backup" <<'STUB'
#!/usr/bin/env bash
echo backup >> "$EVENTS"
[ "$MODE" != backup ]
STUB
cat >"$fixture/bin/health" <<'STUB'
#!/usr/bin/env bash
echo health >> "$EVENTS"
STUB
for stub in "$fixture/bin/"*; do
	sed "1s|.*|#!$(command -v bash)|" "$stub" >"$stub.fixed"
	mv "$stub.fixed" "$stub"
done
chmod +x "$fixture/bin/"*
export PATH="$fixture/bin:$PATH"
for mode in state database migration backup signal success; do
	export MODE="$mode"
	: >"$EVENTS"
	touch "$fixture/state/postgres/PG_VERSION"
	if bash "$script" start "$fixture/state" "$fixture/lock" compose validate backup health; then
		[ "$mode" = success ] || {
			echo "unexpected success: $mode"
			exit 1
		}
		python3 - "$EVENTS" <<'PY'
import sys
s=open(sys.argv[1]).read()
assert s.index('stop api mcp') < s.index('backup') < s.index('run --rm --no-deps migration') < s.index('up --detach --force-recreate --no-deps --wait --wait-timeout 180 centrifugo api web mcp') < s.index('health')
PY
	else
		[ "$mode" != success ] || exit 1
		if [ "$mode" = signal ]; then
			[ "$(tail -1 "$EVENTS")" = 'stop api mcp' ] || {
				echo 'Signal left writers running'
				exit 1
			}
		else
			if grep -q 'up .*centrifugo api web mcp' "$EVENTS"; then exit 1; fi
		fi
		if [ "$mode" = database ] && grep -q 'run .*migration' "$EVENTS"; then exit 1; fi
	fi
done
echo 'TaskView lifecycle: failed state/database/backup/migration prevent application startup'
