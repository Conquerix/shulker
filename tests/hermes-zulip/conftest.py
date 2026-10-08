"""Load our maintained adapter against the real pinned Hermes source."""
import importlib.util
import os
from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[2]
PLUGIN = ROOT / 'system/modules/nixos/services/hermes-trial/plugin'
source = os.environ.get('HERMES_TEST_SOURCE')
if not source:
    raise RuntimeError('Set HERMES_TEST_SOURCE to the pinned Hermes source; mocks are not a substitute')
sys.path.insert(0, source)
spec = importlib.util.spec_from_file_location('overseer_zulip', PLUGIN / 'adapter.py', submodule_search_locations=[str(PLUGIN)])
adapter_module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = adapter_module
spec.loader.exec_module(adapter_module)

@pytest.fixture
def adapter(tmp_path, monkeypatch):
    monkeypatch.setenv('HERMES_HOME', str(tmp_path / 'home'))
    from gateway.config import PlatformConfig
    result = adapter_module.ZulipAdapter(PlatformConfig(extra={
        'site_url': 'https://zulip.example.test', 'bot_email': 'overseer@example.test',
        'api_key': 'synthetic-test-value', 'allowed_user_ids': ['123'],
        'allowed_channel_ids': ['42'],
    }))
    result.bot_user_id = '99'
    return result
