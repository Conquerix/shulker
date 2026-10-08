"""Materialize only known Zulip secrets; never evaluate shell or Python input."""
import json
import os
from pathlib import Path
import sys

NAMES = {'postgres_password', 'memcached_password', 'rabbitmq_password',
         'redis_password', 'secret_key', 'email_password', 'social_auth_oidc_secret'}

def render(source, output):
    values = json.loads(source.read_text())
    if not isinstance(values, dict) or set(values) != NAMES:
        raise ValueError('Unexpected or missing secret names')
    if any(not isinstance(v,str) or not v or any(c in v for c in '\r\n\0') for v in values.values()):
        raise ValueError('Secrets must be nonempty single-line strings')
    output.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(output, 0o700)
    for name, value in values.items():
        target=output/('zulip__'+name)
        temporary=target.with_suffix('.new')
        temporary.write_text(value)
        # Host directory is private; individual mounts must be readable by each
        # container's non-root service user. Docker exposes only named files.
        os.chmod(temporary, 0o444)
        os.replace(temporary,target)

if __name__ == '__main__':
    try:
        render(Path(sys.argv[1]),Path(sys.argv[2]))
    except Exception:
        sys.exit('Zulip secret rendering failed; check secret names and format')
