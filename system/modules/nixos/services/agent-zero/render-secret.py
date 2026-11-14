"""Merge managed inference credential without discarding user settings."""
from pathlib import Path
import os
import sys

source, target = map(Path, sys.argv[1:3])
value = source.read_text().strip()
if not value or any(c in value for c in '\n\r\x00'):
    raise ValueError('Invalid inference credential')
lines = target.read_text().splitlines() if target.exists() else []
lines = [line for line in lines if not line.startswith('API_KEY_OPENAI=')]
lines.append('API_KEY_OPENAI=' + value)
fd = os.open(str(target) + '.new', os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
with os.fdopen(fd, 'w') as output:
    output.write('\n'.join(lines) + '\n')
os.replace(str(target) + '.new', target)
