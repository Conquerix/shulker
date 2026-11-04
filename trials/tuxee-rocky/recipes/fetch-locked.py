#!/usr/bin/env python3
"""Download the retained GUI source lock; never regenerate pins from a moving index."""
import hashlib
import json
import pathlib
import urllib.request

root = pathlib.Path(__file__).resolve().parent
out = root / 'gui-inputs'
out.mkdir(exist_ok=True)
pins = json.loads((root / 'gui-source-lock.json').read_text())
assert pins and all(p.get('sha256') and p.get('file') for p in pins)
for pin in pins:
    assert pathlib.Path(pin['file']).name == pin['file']
    target = out / pin['file']
    data = target.read_bytes() if target.exists() else urllib.request.urlopen(pin['url'], timeout=120).read()
    assert hashlib.sha256(data).hexdigest() == pin['sha256'], pin['file']
    if not target.exists():
        target.write_bytes(data)
    print(pin['package'], pin['sha256'])
