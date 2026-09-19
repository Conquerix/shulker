#!/usr/bin/env bash
set -euo pipefail
validator="$1"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir "$fixture/bin"
cat >"$fixture/bin/findmnt" <<'STUB'
#!/usr/bin/env bash
[ "$MODE" != missing ] || exit 1
if [ "$MODE" = source ]; then echo wrong; else echo flash_pool/flash/storage/taskview; fi
STUB
cat >"$fixture/bin/zfs" <<'STUB'
#!/usr/bin/env bash
case "$5" in
quota) if [ "$MODE" = quota ]; then echo 1; else echo 21474836480; fi ;;
compression) echo zstd ;; atime) echo off ;; acltype) echo posix ;; xattr) echo sa ;; dnodesize) echo auto ;;
esac
STUB
for stub in "$fixture/bin/"*; do
	sed "1s|.*|#!$(command -v bash)|" "$stub" >"$stub.fixed"
	mv "$stub.fixed" "$stub"
done
chmod +x "$fixture/bin/"*
export PATH="$fixture/bin:$PATH"
for mode in missing source quota; do
	if MODE="$mode" bash -euo pipefail "$validator" >/dev/null 2>&1; then
		echo "Unexpected acceptance of $mode state" >&2
		exit 1
	fi
done
MODE=valid bash -euo pipefail "$validator"
echo 'TaskView state: missing mount, wrong dataset/quota refused; correct state accepted'
