"""Exercise real event and approval contracts, not fake gateway classes."""
import inspect
from gateway.platforms.base import MessageEvent
from tools import approval
from tools.approval_gateway_wait import _ApprovalEntry


def test_real_message_event(adapter):
    message = {'id': 17, 'sender_id': 123, 'sender_email': 'owner@example.test',
               'type': 'private', 'content': 'hello',
               'display_recipient': [{'id': 123}, {'id': 99}]}
    event = adapter._build_message_event(message, 'hello', is_dm=True)
    assert isinstance(event, MessageEvent)
    assert event.text == 'hello'
    assert event.source.user_id == '123'


def test_request_id_round_trip():
    a = _ApprovalEntry({'command': 'one', 'request_id': 'old'})
    b = _ApprovalEntry({'command': 'two', 'request_id': 'new'})
    approval._gateway_queues['test'] = [a, b]
    try:
        assert approval.resolve_gateway_approval('test', 'once', request_id='new') == 1
        assert b.result == 'once' and a.result is None
        assert approval.resolve_gateway_approval('test', 'once', request_id='new') == 0
    finally:
        approval.clear_session('test')


def test_adapter_accepts_exact_request_identity(adapter):
    assert 'request_id' in inspect.signature(adapter.send_exec_approval).parameters


def test_native_approval_transport_is_selected(adapter):
    assert type(adapter).supports_exec_approval_buttons()


def test_plugin_loads_through_real_registry(tmp_path, monkeypatch):
    from conftest import PLUGIN
    from hermes_cli.plugins import PluginManager
    from hermes_cli.plugins_manifest import parse_manifest_file
    from gateway.platform_registry import platform_registry
    monkeypatch.setenv('HERMES_HOME', str(tmp_path))
    manifest = parse_manifest_file(PLUGIN/'plugin.yaml', PLUGIN, 'user', '')
    manager = PluginManager()
    manager._load_plugin(manifest)
    assert manager._plugins[manifest.name].error is None
    assert platform_registry.get('zulip') is not None


def test_fresh_adapter_publishes_durable_denial_state(adapter):
    # Coding tools require an explicit durable policy, even before any topic move.
    assert adapter.journal.get('blocked_chats') == '[]'


def test_adapter_restart_preserves_blocked_topics(adapter):
    adapter.journal.put('blocked_chats', '["dm:123"]')
    adapter.journal.close()
    restarted = type(adapter)(adapter.config)
    assert restarted.journal.get('blocked_chats') == '["dm:123"]'
    assert restarted._blocked_chats == {'dm:123'}
    restarted.journal.close()
