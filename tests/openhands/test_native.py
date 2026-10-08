"""Native profile selection stays fixed while its model provider remains replaceable."""
import importlib.util
import json
from pathlib import Path
from uuid import UUID
import pytest
from broker.client import create_payload

ROOT = Path(__file__).resolve().parents[2]
SERVICE = ROOT/'system/modules/nixos/services/openhands'
PROFILE_ID = '8dcb2360-3c3f-4e30-bb75-626b5f7d27d6'

def test_broker_selects_fixed_native_profile_without_provider_settings():
    payload = create_payload('00000000-0000-0000-0000-000000000001', 'inspect README', PROFILE_ID)
    assert payload['agent_profile_id'] == PROFILE_ID
    assert 'agent_settings' not in payload
    assert payload['autotitle'] is False
    assert payload['worktree'] is True
    assert payload['workspace']['working_dir'] == '/projects/shulker/repository'
    assert 'initial_message' not in payload


def seed_module():
    spec = importlib.util.spec_from_file_location('seed_native', SERVICE/'seed-native.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def test_native_seed_preserves_changed_provider_and_profiles(tmp_path):
    module = seed_module()
    module.seed(tmp_path, SERVICE/'native-profile.json')
    profile = json.loads((tmp_path/'agent-profiles/overseer-coding.json').read_text())
    assert profile['agent_kind'] == 'openhands'
    assert str(UUID(profile['id'])) == PROFILE_ID
    assert {tool['name'] for tool in profile['tools']} == {'terminal', 'file_editor', 'task_tracker'}
    assert profile['mcp_server_refs'] == [] and profile['secret_refs'] == []
    llm = tmp_path/'profiles/overseer-coding.json'
    assert json.loads(llm.read_text())['auth_type'] == 'subscription'
    llm.write_text(json.dumps({'model':'anthropic/fixture', 'api_key':'synthetic'}))
    profile_path = tmp_path/'agent-profiles/overseer-coding.json'
    original = profile_path.read_bytes()
    module.seed(tmp_path, SERVICE/'native-profile.json')
    assert json.loads(llm.read_text())['model'] == 'anthropic/fixture'
    assert profile_path.read_bytes() == original
    assert llm.stat().st_mode & 0o777 == 0o600


def test_seed_refuses_symlink_destination(tmp_path):
    outside = tmp_path/'outside'; outside.mkdir()
    state = tmp_path/'state'; state.mkdir()
    (state/'profiles').symlink_to(outside, target_is_directory=True)
    with pytest.raises(ValueError): seed_module().seed(state, SERVICE/'native-profile.json')
    assert not list(outside.iterdir())


def test_reseeding_preserves_renamed_profile_uuid_and_llm(tmp_path):
    module = seed_module(); module.seed(tmp_path, SERVICE/'native-profile.json')
    profile = tmp_path/'agent-profiles/overseer-coding.json'
    data = json.loads(profile.read_text()); data['name'] = 'renamed-agent'
    data['llm_profile_ref'] = 'renamed-model'
    profile.write_text(json.dumps(data)); profile.rename(profile.with_name('renamed-agent.json'))
    llm = tmp_path/'profiles/overseer-coding.json'; llm.rename(llm.with_name('renamed-model.json'))
    module.seed(tmp_path, SERVICE/'native-profile.json')
    assert not profile.exists()
    assert not llm.exists()
    saved = [json.loads(p.read_text()) for p in profile.parent.glob('*.json')]
    assert len(saved) == 1 and saved[0] == data


def test_conflicting_profile_identity_is_not_overwritten(tmp_path):
    module = seed_module(); module.seed(tmp_path, SERVICE/'native-profile.json')
    profile = tmp_path/'agent-profiles/overseer-coding.json'
    data = json.loads(profile.read_text()); data['id'] = '00000000-0000-0000-0000-000000000002'
    profile.write_text(json.dumps(data)); original = profile.read_bytes()
    with pytest.raises(ValueError): module.seed(tmp_path, SERVICE/'native-profile.json')
    assert profile.read_bytes() == original


@pytest.mark.parametrize('kind', ['duplicate', 'acp'])
def test_rejects_ambiguous_or_non_native_identity(tmp_path, kind):
    module = seed_module(); module.seed(tmp_path, SERVICE/'native-profile.json')
    profile = tmp_path/'agent-profiles/overseer-coding.json'
    data = json.loads(profile.read_text())
    if kind == 'duplicate':
        data['name'] = 'duplicate'
        (profile.parent/'duplicate.json').write_text(json.dumps(data))
    else:
        data['agent_kind'] = 'acp'; profile.write_text(json.dumps(data))
    with pytest.raises(ValueError): module.seed(tmp_path, SERVICE/'native-profile.json')
