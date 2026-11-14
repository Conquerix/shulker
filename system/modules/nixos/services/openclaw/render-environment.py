"""Validate secret files and atomically render a private systemd environment."""
import os
from pathlib import Path
import sys


def render(sources, destination):
    names = ('OPENCLAW_GATEWAY_TOKEN', 'AEGIS_OMNIROUTE_API_KEY', 'OP_SERVICE_ACCOUNT_TOKEN')
    values = []
    for name, source in zip(names, sources, strict=True):
        value = Path(source).read_text().strip()
        if not value or any(c in value for c in '\r\n\x00'):
            raise ValueError(f'Invalid secret for {name}')
        escaped = value.replace('\\', '\\\\').replace('"', '\\"')
        values.append(f'{name}="{escaped}"\n')
    target = Path(destination)
    temporary = target.with_suffix('.new')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as output:
        output.write(''.join(values))
    os.replace(temporary, target)


if __name__ == '__main__':
    render(sys.argv[1:4], sys.argv[4])
