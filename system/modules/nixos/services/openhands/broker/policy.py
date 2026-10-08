"""Root-owned placement policy; agent input cannot select URLs or workspaces."""
from dataclasses import dataclass
import json
from pathlib import Path
from uuid import UUID
from urllib.parse import urlsplit


@dataclass(frozen=True)
class Policy:
    backend: str
    profile_id: str
    uid: int
    canvas: str

    def __post_init__(self):
        for origin in (self.backend, self.canvas):
            p = urlsplit(origin)
            if p.scheme != 'https' or not p.hostname or p.username or p.password or p.path or p.query or p.fragment:
                raise ValueError('Invalid service origin')
        UUID(self.profile_id)
        if self.uid <= 0:
            raise ValueError('Invalid coding policy')

    @classmethod
    def load(cls, path: Path):
        return cls(**json.loads(path.read_text()))
