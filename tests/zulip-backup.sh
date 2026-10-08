#!/usr/bin/env bash
set -euo pipefail
backup=$1
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/state/data"
echo fixture >"$sandbox/state/data/upload.txt"
cat >"$sandbox/compose" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  pause|unpause) echo "$1" >> "$TRACE" ;;
  exec) if [ "${FAIL_DUMP:-0}" = 1 ]; then exit 9; fi; echo 'synthetic SQL dump' ;;
  *) exit 20 ;;
esac
EOF
chmod +x "$sandbox/compose"
export TRACE="$sandbox/trace"
bash "$backup" "$sandbox/state" "$sandbox/compose"
tar -tzf "$sandbox/state/backups/zulip.tar.gz" | grep -q 'data/upload.txt'
tar -tzf "$sandbox/state/backups/zulip.tar.gz" | grep -q 'database.sql'
cp "$sandbox/state/backups/zulip.tar.gz" "$sandbox/before"
export FAIL_DUMP=1
if bash "$backup" "$sandbox/state" "$sandbox/compose"; then exit 1; fi
cmp "$sandbox/before" "$sandbox/state/backups/zulip.tar.gz"
[ "$(tail -1 "$TRACE")" = unpause ]
echo 'Zulip backup failure handling passed'
