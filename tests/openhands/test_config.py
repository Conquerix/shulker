"""Runtime secret rendering must fail closed and leave no public files."""
import importlib.util
import json
from pathlib import Path
import pytest
from conftest import ROOT

def renderer():
    path = ROOT/'system/modules/nixos/services/openhands/render-config.py'
    spec = importlib.util.spec_from_file_location('oh_render', path)
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    return mod.render_config

@pytest.mark.parametrize('key', ['', ' ', '\n', 'bad\nkey'])
def test_render_rejects_empty_auth(tmp_path, key):
    with pytest.raises(ValueError):
        renderer()({'OH_SESSION_API_KEYS_0':key, 'OH_SECRET_KEY':'fixture'}, {}, tmp_path/'config')
    assert not (tmp_path/'config').exists()

def test_render_secrets_stay_private(tmp_path):
    dest=tmp_path/'config'
    renderer()({'OH_SESSION_API_KEYS_0':'synthetic', 'OH_SECRET_KEY':'synthetic-encryption'}, {'canvasOrigin':'https://code.shulker.link'}, dest)
    data=json.loads(dest.read_text())
    assert data['enable_vscode'] is False
    assert data['conversation_worktree_root'] == '/projects/shulker/worktrees'
    assert data['conversations_path'] == '/state/conversations'
    assert dest.stat().st_mode & 0o777 == 0o600

def test_render_does_not_replace_symlink(tmp_path):
    victim=tmp_path/'victim';victim.write_text('keep');dest=tmp_path/'config';dest.symlink_to(victim)
    with pytest.raises(ValueError):
        renderer()({'OH_SESSION_API_KEYS_0':'fixture','OH_SECRET_KEY':'fixture'}, {}, dest)
    assert victim.read_text() == 'keep'
