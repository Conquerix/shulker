"""Real Hermes registry/context contracts; no environment impersonation."""
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import sys
import pytest
from conftest import ROOT

source=os.environ.get('HERMES_TEST_SOURCE')
pytestmark=pytest.mark.skipif(not source,reason='requires pinned Hermes source')
if source: sys.path.insert(0,source)
PLUGIN=ROOT/'system/modules/nixos/services/hermes-trial/coding'

@pytest.fixture
def tools(tmp_path,monkeypatch):
    monkeypatch.setenv('HERMES_HOME',str(tmp_path))
    monkeypatch.setenv('ZULIP_ALLOWED_USER_IDS','123')
    monkeypatch.setenv('ZULIP_ALLOWED_CHANNEL_IDS','42')
    with sqlite3.connect(tmp_path/'overseer-intake.sqlite') as db:
        db.execute('CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT)')
        db.execute("INSERT INTO metadata VALUES('blocked_chats','[]')")
    spec=importlib.util.spec_from_file_location('coding_tools',PLUGIN/'tools.py')
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
    return mod

@pytest.fixture
def context():
    from gateway.session_context import set_session_vars,clear_session_vars
    from tools.approval_context import set_current_observability_context,reset_current_observability_context
    tokens=set_session_vars(platform='zulip',user_id='123',chat_id='stream:42:topic:Example',message_id='17',session_key='fixture')
    obs=set_current_observability_context(tool_call_id='call-1')
    yield
    reset_current_observability_context(obs);clear_session_vars(tokens)

def test_missing_or_forged_gateway_context_denied(tools,monkeypatch):
    from gateway.session_context import reset_session_vars
    reset_session_vars()
    monkeypatch.setenv('HERMES_SESSION_PLATFORM','zulip')
    monkeypatch.setenv('HERMES_SESSION_USER_ID','123')
    assert json.loads(tools.invoke('submit',{'project':'shulker','task':'task'}))['error']=='unauthorized'

def test_repeated_tool_delivery_reuses_request_id(tools,context,monkeypatch):
    sent=[]
    monkeypatch.setattr(tools,'rpc',lambda value:sent.append(value) or {'state':'running'})
    tools.invoke('submit',{'project':'shulker','task':'task'})
    tools.invoke('submit',{'project':'shulker','task':'task'})
    assert len(sent)==2 and sent[0]['request_id']==sent[1]['request_id']
    assert sent[0]['origin']==sent[1]['origin']

def test_topic_move_blocks_old_result(tools,context,monkeypatch):
    path=Path(os.environ['HERMES_HOME'])/'overseer-intake.sqlite'
    with sqlite3.connect(path) as db: db.execute("UPDATE metadata SET value=? WHERE key='blocked_chats'",(json.dumps(['stream:42:topic:Example']),))
    monkeypatch.setattr(tools,'rpc',lambda value:pytest.fail('blocked topic contacted broker'))
    assert json.loads(tools.invoke('result',{'task_id':'task'}))['error']=='unauthorized'

def test_real_hermes_registers_coding_tools(tmp_path,monkeypatch):
    from hermes_cli.plugins import PluginManager
    from hermes_cli.plugins_manifest import parse_manifest_file
    from tools.registry import registry
    monkeypatch.setenv('HERMES_HOME',str(tmp_path))
    manifest=parse_manifest_file(PLUGIN/'plugin.yaml',PLUGIN,'user','')
    manager=PluginManager();manager._load_plugin(manifest)
    assert manager._plugins[manifest.name].error is None
    for name in ('coding_submit','coding_status','coding_result','coding_pause'):
        entry=registry.get_entry(name,scope=manager.scope_key)
        assert entry is not None
        assert 'origin' not in entry.schema['parameters']['properties']
