import pytest
from gateway.platforms.base import SendResult
from test_policy import message

@pytest.mark.asyncio
async def test_duplicate_message_dispatches_once(adapter):
    seen=[]
    async def handle(event): seen.append(event)
    adapter.handle_message=handle
    event={'type':'message','message':message()}
    await adapter._handle_zulip_message_event(event)
    await adapter._handle_zulip_message_event(event)
    assert len(seen)==1
    assert seen[0].allow_gateway_control is False

@pytest.mark.asyncio
async def test_topic_change_blocks_old_output(adapter):
    await adapter._handle_topic_change({'type':'update_message','stream_id':42,
        'orig_subject':'old','subject':'new','message_ids':[1]})
    result=await adapter.send('stream:42:topic:old','late result')
    assert not result.success
    assert 'changed' in result.error.lower()

@pytest.mark.asyncio
async def test_recovery_notices_never_dispatch(adapter):
    adapter.journal.accept(17,'dm:123')
    adapter.journal.recover()  # Simulate reopening after an interrupted process.
    seen=[]
    async def send(chat_id, text, **kwargs):
        seen.append((chat_id,text)); return SendResult(success=True,message_id='1')
    adapter.send=send
    await adapter._send_recovery_notices()
    assert len(seen)==1 and 'resend' in seen[0][1].lower()
    await adapter._send_recovery_notices()
    assert len(seen)==1

@pytest.mark.asyncio
async def test_move_blocks_actual_destination(adapter):
    adapter.allowed_channel_ids.add('43')
    await adapter._handle_topic_change({'stream_id':42, 'new_stream_id':43,
        'orig_subject':'old', 'subject':'new'})
    assert 'stream:43:topic:new' in adapter._blocked_chats

@pytest.mark.asyncio
async def test_content_edit_preserves_approvals(adapter):
    adapter._approval_reactions['7']={'chat_id':'stream:42:topic:other'}
    await adapter._handle_topic_change({'stream_id':42,'content':'edited'})
    assert '7' in adapter._approval_reactions

@pytest.mark.asyncio
async def test_move_preserves_unrelated_approvals(adapter):
    adapter._approval_reactions['7']={'chat_id':'stream:42:topic:other'}
    await adapter._handle_topic_change({'stream_id':42,'orig_subject':'old','subject':'new'})
    assert '7' in adapter._approval_reactions

@pytest.mark.asyncio
async def test_queue_gap_invalidates_known_stream_conversations(adapter):
    adapter._conversation_sessions['stream:42:topic:old']='session'
    adapter._approval_reactions['7']={'chat_id':'stream:42:topic:old'}
    adapter._invalidate_queue_gap()
    assert 'stream:42:topic:old' in adapter._blocked_chats
    assert '7' not in adapter._approval_reactions
