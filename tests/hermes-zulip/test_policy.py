import pytest


def message(**changes):
    return dict({'id': 17, 'sender_id': 123, 'sender_email': 'owner@example.test',
                 'type': 'private', 'content': 'hello',
                 'display_recipient': [{'id': 123}, {'id': 99}]}, **changes)

@pytest.mark.asyncio
@pytest.mark.parametrize('changes', [
    {'sender_id': 777},
    {'display_recipient': [{'id':123}, {'id':456}, {'id':99}]},
    {'type':'stream', 'stream_id':43, 'content':'@**Overseer** hello'},
    {'content':'/approve all'}, {'content':'/approve'}, {'content':'/yolo'},
])
async def test_rejects_unauthorized_or_unsafe_dispatch(adapter, changes):
    received = []
    async def handle(event): received.append(event)
    async def send(*a, **kw): pass
    adapter.handle_message = handle
    adapter.send = send
    await adapter._handle_zulip_message_event({'type':'message', 'message':message(**changes)})
    assert not received
