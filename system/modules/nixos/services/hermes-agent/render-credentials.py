"""Fetch one complete Hermes credential generation without exposing vault values."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def parse_environment(text):
    values = {}
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        # Docker's literal env-file and Hermes' dotenv parser must agree.
        if (not separator or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key)
                or key in values or key == "OP_SERVICE_ACCOUNT_TOKEN"
                or "\x00" in value or value != value.strip()
                or value.startswith(("'", '"')) or re.search(r"\s#", value)):
            raise ValueError("invalid environment field")
        values[key] = value
    return values


def render_credentials(op_path, token_file, references_file, target_dir):
    manifest = json.loads(references_file.read_text())
    token = token_file.read_text().strip()
    if not token:
        raise ValueError("missing bootstrap token")
    environment = dict(os.environ, OP_SERVICE_ACCOUNT_TOKEN=token)

    def read(reference):
        if not reference.startswith("op://"):
            raise ValueError("invalid secret reference")
        return subprocess.run(
            [op_path, "read", reference], env=environment, check=True,
            capture_output=True, text=True, timeout=30,
        ).stdout

    values = {}
    for entry in manifest["environment"]:
        fetched = parse_environment(read(entry["reference"]))
        if any(not fetched.get(key) for key in entry["requiredKeys"]):
            raise ValueError("missing required environment field")
        if values.keys() & fetched.keys():
            raise ValueError("duplicate environment field")
        values.update(fetched)
    values.update(manifest["policy"])
    env_text = "".join(f"{key}={value}\n" for key, value in values.items())
    parse_environment(env_text)
    payloads = {".env": env_text}
    if manifest.get("sshKey"):
        payloads["host-key"] = read(manifest["sshKey"])

    target_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(target_dir, 0o700)
    current = target_dir / "current"
    previous = os.readlink(current) if current.is_symlink() else None
    generation = Path(tempfile.mkdtemp(prefix="generation-", dir=target_dir))
    pending_link = target_dir / (".current-" + generation.name)
    published = False
    try:
        for name, content in payloads.items():
            path = generation / name
            path.write_text(content)
            os.chmod(path, 0o600)
        if "host-key" in payloads:
            subprocess.run(
                ["ssh-keygen", "-y", "-P", "", "-f", str(generation / "host-key")],
                capture_output=True, check=True, timeout=10,
            )
        for path in generation.iterdir():
            if "owner" in manifest:
                os.chown(path, *manifest["owner"])
            os.chmod(path, 0o400)
        if "owner" in manifest:
            os.chown(generation, *manifest["owner"])
        pending_link.symlink_to(generation.name)
        # One pointer publishes the environment and SSH key together.
        os.replace(pending_link, current)
        published = True
    finally:
        pending_link.unlink(missing_ok=True)
        if not published:
            shutil.rmtree(generation)
    # Keep the prior complete generation for recovery; older generations are stale.
    for stale in target_dir.glob("generation-*"):
        if stale.name not in (generation.name, previous) and stale.is_dir() and not stale.is_symlink():
            shutil.rmtree(stale)


if __name__ == "__main__":
    os.umask(0o077)
    try:
        render_credentials(sys.argv[1], *(Path(arg) for arg in sys.argv[2:]))
    except Exception:
        # CLI stderr and exception payloads can contain secrets: never forward them.
        print("Hermes credential refresh failed; check 1Password fields and access.", file=sys.stderr)
        sys.exit(1)
