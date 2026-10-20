"""Publish Engineer's file-based credentials; never forward secret-bearing errors."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile


def render_environment(parser_path, discord_file, provider_file, settings_file, target):
    # Pass the parser path explicitly: Nix stores these source files separately.
    spec = importlib.util.spec_from_file_location("hermes_credentials", parser_path)
    if spec is None or spec.loader is None:
        raise ValueError("missing environment parser")
    parser = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(parser)
    settings = json.loads(settings_file.read_text())
    values = {}
    for source, key in ((discord_file, "DISCORD_BOT_TOKEN"),
                        (provider_file, "HERMES_OMNIROUTE_API_KEY")):
        fetched = parser.parse_environment(source.read_text())
        if set(fetched) != {key} or not fetched[key]:
            raise ValueError("invalid source fields")
        values.update(fetched)
    values.update(settings["policy"])
    payload = "".join(f"{key}={value}\n" for key, value in values.items())
    parser.parse_environment(payload)
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(target.parent, 0o700)
    fd, pending = tempfile.mkstemp(prefix=".env-", dir=target.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(payload)
            stream.flush()
            os.fchown(stream.fileno(), *settings["owner"])
            os.fchmod(stream.fileno(), 0o400)
            os.fsync(stream.fileno())
        os.replace(pending, target)
    finally:
        Path(pending).unlink(missing_ok=True)


if __name__ == "__main__":
    os.umask(0o077)
    try:
        render_environment(*(Path(arg) for arg in sys.argv[1:]))
    except Exception:
        print("Engineer environment refresh failed; check source fields and access.", file=sys.stderr)
        sys.exit(1)
