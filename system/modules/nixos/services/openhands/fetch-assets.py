"""Fetch only the digest-verified public Canvas assets layer, never an account token."""
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import tarfile
import urllib.request
import sys

LAYER = 'fa294766f6225f85333af89553edc621949089a9be27d715117d65c19f53640c'
PREFIX = PurePosixPath('opt/agent-canvas/frontend')

class PublicRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new is not None: new.remove_header('Authorization')
        return new


def extract(data: bytes, destination: Path) -> None:
    if hashlib.sha256(data).hexdigest() != LAYER:
        raise ValueError('Canvas layer digest mismatch')
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
        total = 0
        for member in archive:
            path = PurePosixPath(member.name)
            if '..' in path.parts or path.is_absolute():
                raise ValueError('Unsafe asset path')
            if not path.is_relative_to(PREFIX) or path == PREFIX: continue
            target = destination / path.relative_to(PREFIX)
            if member.isdir(): target.mkdir(parents=True, exist_ok=True); continue
            if not member.isfile(): raise ValueError('Unsafe asset type')
            total += member.size
            if total > 64 * 1024 * 1024: raise ValueError('Oversized assets')
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.extractfile(member) as source: target.write_bytes(source.read())
    if not (destination / 'index.html').is_file(): raise ValueError('Missing Canvas index')

if __name__ == '__main__':
    opener = urllib.request.build_opener(PublicRedirect())
    with opener.open('https://ghcr.io/token?scope=repository:openhands/agent-canvas:pull', timeout=30) as response:
        token = json.load(response)['token']
    request = urllib.request.Request('https://ghcr.io/v2/openhands/agent-canvas/blobs/sha256:' + LAYER,
                                    headers={'Authorization': 'Bearer ' + token})
    with opener.open(request, timeout=60) as response:
        data = response.read(4 * 1024 * 1024 + 1)
    if len(data) > 4 * 1024 * 1024: raise ValueError('Oversized asset layer')
    extract(data, Path(sys.argv[1]))
