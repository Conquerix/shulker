"""Initial data only; native Hermes owns configuration and subsequent learned state."""
import json
import os
from pathlib import Path

import subprocess
import sys
import tempfile


def absent(path):
    return not path.exists() and not path.is_symlink()


def create_once(path, content):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        return
    with os.fdopen(fd, "wb") as stream:
        stream.write(content)


def bootstrap_files(settings, state):
    for relative, source in settings["files"].items():
        parts = Path(relative).parts
        if (not parts or parts[0] not in ("data", "workspace")
                or ".." in parts or Path(relative).is_absolute()
                or str(Path(relative)) != relative
                or str(Path(relative)) == "data/config.yaml"):
            raise ValueError("invalid initial file target")
        target = state / relative
        if absent(target):
            create_once(target, Path(source).read_bytes())


def bootstrap_native(settings, home):
    target = home / "config.yaml"
    if not absent(target):
        return
    # A failed command cannot leave a partial real config that suppresses retries.
    with tempfile.TemporaryDirectory(prefix=".bootstrap-", dir=home) as staging:
        environment = dict(os.environ, HERMES_HOME=staging)
        for key, value in settings["settings"].items():
            if "." not in key or not key[0].islower():
                raise ValueError("initial settings must be non-secret dotted keys")
            subprocess.run(["hermes", "config", "set", key, value],
                           env=environment, check=True, capture_output=True)
        for plugin in settings["plugins"]:
            subprocess.run(["hermes", "plugins", "enable", plugin],
                           env=environment, check=True, capture_output=True)
        source = Path(staging) / "config.yaml"
        if not source.is_file():
            raise ValueError("native commands did not create config")
        create_once(target, source.read_bytes())


if __name__ == "__main__":
    os.umask(0o077)
    try:
        settings = json.loads(Path(sys.argv[2]).read_text())
        if sys.argv[1] == "files":
            bootstrap_files(settings, Path(sys.argv[3]))
        elif sys.argv[1] == "native":
            bootstrap_native(settings, Path(sys.argv[3]))
        else:
            raise ValueError("unknown bootstrap mode")
    except Exception:
        print("Hermes initial bootstrap failed; existing state was not replaced.", file=sys.stderr)
        sys.exit(1)
