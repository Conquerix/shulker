import pytest
from gateway.platforms.base import SendResult
from tools import approval
from tools.approval_gateway_wait import _ApprovalEntry

@pytest.fixture
def pending():
    a = _ApprovalEntry({'command':'echo harmless', 'request_id':'req1'})
    approval._gateway_queues['session'] = [a]
    yield a
    approval.clear_session('session')

@pytest.fixture
def sent(adapter):
    messages = []
    async def send(chat_id, content, **kw):
        messages.append(content)
        return SendResult(success=True, message_id='100')
    adapter.send = send
    return messages

@pytest.mark.asyncio
async def test_full_command_and_once_only(adapter, pending, sent):
    command = 'echo ' + 'x'*220 + '\n```\nwhoami'
    result = await adapter.send_exec_approval('dm:123', command, 'session',
        metadata={'zulip_sender_id':123}, request_id='req1', allow_session=False)
    assert result.success
    assert command in sent[0]
    assert 'session' not in sent[0] and 'approve all' not in sent[0]

@pytest.mark.asyncio
async def test_unknown_or_oversize_request_not_published(adapter, sent):
    result = await adapter.send_exec_approval('dm:123', 'x'*9000, 'session', request_id='missing')
    assert not result.success and not sent

@pytest.mark.asyncio
async def test_old_prompt_cannot_approve_next_request(adapter, pending, sent):
    await adapter.send_exec_approval('dm:123','echo harmless','session',
        metadata={'zulip_sender_id':123}, request_id='req1')
    newer = _ApprovalEntry({'command':'two', 'request_id':'req2'})
    approval._gateway_queues['session'] = [newer]
    await adapter._handle_zulip_reaction_event({'op':'add','message_id':100,'user_id':123,'emoji_name':'thumbs_up'})
    assert newer.result is None

@pytest.mark.asyncio
@pytest.mark.parametrize('user,emoji,expected', [(123,'thumbs_up','once'),(777,'thumbs_up',None),(123,'white_check_mark',None),(123,'infinity',None),(123,'thumbs_down','deny')])
async def test_reaction_scope(adapter, pending, sent, user, emoji, expected):
    await adapter.send_exec_approval('dm:123','echo harmless','session',
        metadata={'zulip_sender_id':123}, request_id='req1')
    await adapter._handle_zulip_reaction_event({'op':'add','message_id':100,'user_id':user,'emoji_name':emoji})
    assert pending.result == expected
