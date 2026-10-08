"""Render private worker configuration outside the Nix store."""
import json
import os
from pathlib import Path
import sys
import tempfile
from urllib.parse import urlsplit


def render_config(environment, policy: dict, destination: Path) -> None:
    values = {}
    for name in ('OH_SESSION_API_KEYS_0', 'OH_SECRET_KEY'):
        value = environment.get(name, '')
        if not isinstance(value, str) or not value.strip() or any(ord(c) < 33 for c in value):
            raise ValueError('Invalid ' + name)
        values[name] = value
    origin = policy.get('canvasOrigin', 'https://code.shulker.link')
    parsed = urlsplit(origin)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.path or parsed.query or parsed.fragment:
        raise ValueError('Invalid canvasOrigin')
    if destination.is_symlink():
        raise ValueError('Invalid configuration destination')
    data = {
        'session_api_keys': [values['OH_SESSION_API_KEYS_0']],
        'secret_key': values['OH_SECRET_KEY'], 'enable_vscode': False,
        'allow_cors_origins': [origin], 'allow_cors_origin_regex': None,
        'conversations_path': '/state/conversations',
        'bash_events_dir': '/state/bash-events',
        'workspace_path': '/projects/shulker/repository',
        'conversation_worktree_root': '/projects/shulker/worktrees',
    }
    fd, pending = tempfile.mkstemp(prefix='.config-', dir=destination.parent)
    try:
        with os.fdopen(fd, 'w') as handle:
            json.dump(data, handle); handle.flush(); os.fsync(handle.fileno())
        os.replace(pending, destination)
    finally:
        if os.path.exists(pending): os.unlink(pending)


if __name__ == '__main__':
    try:
        render_config(os.environ, json.loads(Path(sys.argv[1]).read_text()), Path(sys.argv[2]))
    except Exception:
        sys.exit('OpenHands configuration validation failed; inspect field names without logging credentials')
