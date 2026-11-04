#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
module="$root/trials/tuxee-rocky/harness.nix"
test -f "$module"
python3 - "$module" <<'PY'
import pathlib, sys
s = pathlib.Path(sys.argv[1]).read_text()
for required in ['127.0.0.1:22229-:22', 'MemoryMax', 'Restart = "no"', '92c206cc6f790c61583247eefe87890f8828420662c17cacf247cec78ab4eec8']:
    assert required in s, required
assert 'hostfwd=tcp::' not in s
assert 'wantedBy' not in s, 'Trial must never autostart at boot'
PY
