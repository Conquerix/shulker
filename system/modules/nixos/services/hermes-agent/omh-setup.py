"""Run pinned upstream setup once per bundle, before the gateway, without secrets."""
import json
import os
from pathlib import Path
import subprocess
import sys


def main():
    bundle, home = map(Path, sys.argv[1:])
    revision = (bundle / "revision").read_text().strip()
    state = home / "omh"
    marker = state / ".shulker-setup-revision"
    if marker.exists() and marker.read_text() == revision:
        return
    # No --force, model activation, MCP, star, menubar or external executor.
    # Full is upstream's default; memory is explicitly off, not auto-safe.
    result = subprocess.run(
        [sys.executable, str(bundle / "launch.py"),
         "--omh-home", str(state), "--hermes-home", str(home),
         "setup", "--no-interactive", "--json", "--no-menubar",
         "--memory-mode", "off", "--source-ref", revision],
        check=True, capture_output=True, text=True,
        env={**os.environ, "OMH_TUI_UPDATE_CHECK": "0", "OMH_IMPACT_CHECK": "0",
             "OMH_SKIP_COMMAND_PACKAGE_UPDATE": "1", "PYTHONDONTWRITEBYTECODE": "1"},
    )
    if json.loads(result.stdout).get("ok") is not True:
        raise RuntimeError("OMH native setup did not report success; gateway blocked")
    state.mkdir(parents=True, exist_ok=True)
    pending = marker.with_suffix(".pending")
    pending.write_text(revision)
    pending.replace(marker)


if __name__ == "__main__":
    main()
