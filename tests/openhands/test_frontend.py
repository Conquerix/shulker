"""Check the actual Caddy listener and the pinned HTML's executable script policy."""
import base64
import hashlib
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import subprocess
import pytest

class Scripts(HTMLParser):
    def __init__(self):
        super().__init__(); self.inline=[]; self.current=None
    def handle_starttag(self, tag, attrs):
        if tag == 'script': self.current = None if dict(attrs).get('src') else ''
    def handle_data(self, data):
        if self.current is not None: self.current += data
    def handle_endtag(self, tag):
        if tag == 'script' and self.current is not None:
            self.inline.append(self.current); self.current=None

@pytest.mark.skipif(not os.environ.get('OPENHANDS_FRONTEND'), reason='requires built pinned assets')
def test_pinned_inline_scripts_have_exact_csp_hashes():
    root=Path(os.environ['OPENHANDS_FRONTEND'])
    parser=Scripts();parser.feed((root/'index.html').read_text())
    expected={"'sha256-"+base64.b64encode(hashlib.sha256(s.encode()).digest()).decode()+"'" for s in parser.inline}
    policy=(root/'script-hashes.caddy').read_text()
    assert len(expected) >= 5
    assert all(h in policy for h in expected)
    assert "'unsafe-inline'" not in policy
    assert (root/'index.html').read_text().index('/canvas/privacy.js') < (root/'index.html').read_text().index('window.__reactRouterContext')

@pytest.mark.skipif(not os.environ.get('OPENHANDS_CADDY_CONFIG'), reason='requires evaluated Caddy config')
def test_adapted_listener_is_http_loopback_without_host_restriction():
    adapted=json.loads(subprocess.check_output([os.environ['CADDY'],'adapt','--adapter','caddyfile','--config',os.environ['OPENHANDS_CADDY_CONFIG']]))
    assert adapted['admin']['disabled'] is True
    servers=adapted['apps']['http']['servers']
    assert len(servers)==1
    server=next(iter(servers.values()))
    assert server['listen']==['127.0.0.1:23250']
    assert not server.get('tls_connection_policies')
    def inspect(value):
        if isinstance(value,dict):
            assert 'host' not in value
            for child in value.values():inspect(child)
        elif isinstance(value,list):
            for child in value:inspect(child)
    inspect(server['routes'])
