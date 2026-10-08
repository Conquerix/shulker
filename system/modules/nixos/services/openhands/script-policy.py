"""Allow only the pinned Canvas HTML's exact inline bootstrap scripts."""
import base64
import hashlib
from html.parser import HTMLParser
from pathlib import Path
import sys

class Scripts(HTMLParser):
    def __init__(self):
        super().__init__(); self.hashes=[]; self.current=None
    def handle_starttag(self,tag,attrs):
        if tag=='script': self.current=None if dict(attrs).get('src') else ''
    def handle_data(self,data):
        if self.current is not None:self.current+=data
    def handle_endtag(self,tag):
        if tag=='script' and self.current is not None:
            digest=base64.b64encode(hashlib.sha256(self.current.encode()).digest()).decode()
            self.hashes.append("'sha256-"+digest+"'");self.current=None

root=Path(sys.argv[1]);parser=Scripts();parser.feed((root/'index.html').read_text())
if not parser.hashes:raise ValueError('Missing pinned Canvas bootstrap scripts')
(root/'script-hashes.caddy').write_text('vars scriptHashes "'+ ' '.join(sorted(set(parser.hashes))) +'"\n')
