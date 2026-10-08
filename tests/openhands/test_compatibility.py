"""Optional real pinned SDK contracts; no model calls or real credentials."""
import os
from uuid import uuid4
import pytest
from broker.client import create_payload

pytestmark = pytest.mark.skipif(not os.environ.get('OPENHANDS_TEST_SDK'), reason='run in frozen SDK 1.53.0 environment')

def test_start_request_uses_native_profile_and_persistent_worktree():
    from openhands.sdk.conversation.request import StartConversationRequest
    payload = create_payload(str(uuid4()), 'inspect the README', '8dcb2360-3c3f-4e30-bb75-626b5f7d27d6')
    request = StartConversationRequest.model_validate(payload)
    assert str(request.agent_profile_id) == '8dcb2360-3c3f-4e30-bb75-626b5f7d27d6'
    assert request.agent_settings is None
    assert request.initial_message is None
    assert request.worktree is True
    assert request.workspace.working_dir == '/projects/shulker/repository'

def test_terminal_status_mapping():
    from openhands.sdk.conversation.state import ConversationExecutionStatus as Status
    assert {s.value for s in Status if s.is_terminal()} == {'finished', 'error', 'stuck'}

def test_actual_server_requires_key(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv('OH_PERSISTENCE_DIR', str(tmp_path))
    monkeypatch.setenv('OH_SESSION_API_KEYS_0', 'synthetic-key')
    from openhands.agent_server.config import Config
    from openhands.agent_server.api import create_app
    from fastapi.testclient import TestClient
    from starlette.websockets import WebSocketDisconnect
    app = create_app(Config(session_api_keys=['synthetic-key'], enable_vscode=False,
                            conversations_path=tmp_path/'conversations'))
    with TestClient(app) as client:
        for headers in ({}, {'X-Session-API-Key': 'wrong'}):
            assert client.get('/api/conversations/count', headers=headers).status_code == 401
        assert client.get('/api/conversations/count', headers={'X-Session-API-Key':'synthetic-key'}).status_code == 200
        with client.websocket_connect('/sockets/events/' + str(uuid4())) as ws:
            ws.send_json({'type':'auth', 'session_api_key':'wrong'})
            with pytest.raises(WebSocketDisconnect):
                ws.receive_json()


def test_real_server_worktree_message_result_and_pause(tmp_path, monkeypatch):
    """Real native HTTP/profile/worktree/tools with a deterministic model boundary."""
    import json, subprocess, sys, time
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv('OH_PERSISTENCE_DIR', str(tmp_path/'settings'))
    monkeypatch.setenv('DO_NOT_TRACK','1')
    from openhands.agent_server import config as config_module, conversation_service, bash_service, persistence
    from openhands.agent_server.api import create_app
    from fastapi.testclient import TestClient
    repo=tmp_path/'repository';repo.mkdir()
    subprocess.run(['git','init','-b','main',str(repo)],check=True,capture_output=True)
    (repo/'README.md').write_text('fixture repository')
    subprocess.run(['git','-C',str(repo),'add','README.md'],check=True)
    subprocess.run(['git','-C',str(repo),'-c','user.name=Fixture','-c','user.email=fixture@example.test','commit','-m','fixture'],check=True,capture_output=True)
    from openhands.sdk.llm import LLM, LLMResponse, MetricsSnapshot, Message
    from litellm.types.utils import Choices, Message as LiteLLMMessage, ModelResponse
    from conftest import ROOT
    import importlib.util
    seed_path=ROOT/'system/modules/nixos/services/openhands/seed-native.py'
    spec=importlib.util.spec_from_file_location('native_seed_fixture',seed_path)
    seed=importlib.util.module_from_spec(spec);spec.loader.exec_module(seed)
    seed.seed(tmp_path/'settings',ROOT/'system/modules/nixos/services/openhands/native-profile.json')
    # A deterministic model replaces only the network boundary. Profile loading,
    # the native agent loop, file editing, events and workspace remain real.
    (tmp_path/'settings/profiles/overseer-coding.json').write_text(json.dumps({'model':'openai/gpt-4o','api_key':'synthetic'}))
    calls=[]
    def generate(llm,messages,**kwargs):
        calls.append(messages)
        if len(calls)==1:
            worktree=next((tmp_path/'worktrees').glob('*/repository'))
            name='file_editor';arguments={'command':'create','path':str(worktree/'NATIVE_FIXTURE.md'),'file_text':'NATIVE_WORKSPACE_OK\n'}
        else:
            name='finish';arguments={'message':'fixture completed'}
        msg=LiteLLMMessage(role='assistant',content=None,tool_calls=[{'id':'fixture-'+str(len(calls)),'type':'function','function':{'name':name,'arguments':json.dumps(arguments)}}])
        choice=Choices(finish_reason='tool_calls',index=0,message=msg)
        raw=ModelResponse(id='fixture',choices=[choice],model=llm.model)
        return LLMResponse(message=Message.from_llm_chat_message(choice['message']),metrics=MetricsSnapshot(model_name=llm.model,accumulated_cost=0.0,max_budget_per_task=None,accumulated_token_usage=None),raw_response=raw)
    async def agenerate(llm,messages,**kwargs):
        return generate(llm,messages,**kwargs)
    monkeypatch.setattr(LLM,'generate',generate)
    monkeypatch.setattr(LLM,'agenerate',agenerate)
    config=config_module.Config(session_api_keys=['synthetic-key'],enable_vscode=False,enable_browser=False,
        conversations_path=tmp_path/'conversations',bash_events_dir=tmp_path/'bash',
        workspace_path=repo,conversation_worktree_root=tmp_path/'worktrees')
    monkeypatch.setattr(config_module,'_default_config',config)
    monkeypatch.setattr(conversation_service,'_conversation_service',None)
    monkeypatch.setattr(bash_service,'_bash_event_service',None)
    persistence.reset_stores()
    task_id=str(uuid4())
    payload=create_payload(task_id,'fixture','8dcb2360-3c3f-4e30-bb75-626b5f7d27d6')
    payload['workspace']['working_dir']=str(repo)
    with TestClient(create_app(config)) as client:
        client.headers['X-Session-API-Key']='synthetic-key'
        created=client.post('/api/conversations',json=payload)
        assert created.status_code==201, created.text
        data=created.json()
        assert data['execution_status']=='idle'
        assert str(tmp_path/'worktrees') in data['workspace']['working_dir']
        assert client.post('/api/conversations/'+task_id+'/pause').status_code==200
        sent=client.post('/api/conversations/'+task_id+'/events',json={'role':'user','content':[{'type':'text','text':'fixture'}],'run':True})
        assert sent.status_code==200, sent.text
        deadline=time.monotonic()+20
        while time.monotonic()<deadline:
            status=client.get('/api/conversations/'+task_id).json()['execution_status']
            if status in ('finished','error','stuck'):break
            time.sleep(0.02)
        assert status=='finished'
        final=client.get('/api/conversations/'+task_id+'/agent_final_response')
        assert final.status_code==200 and 'fixture completed' in final.json()['response']

        assert len(calls)==2
        assert (next((tmp_path/'worktrees').glob('*/repository'))/'NATIVE_FIXTURE.md').read_text()=='NATIVE_WORKSPACE_OK\n'


def test_legacy_chatgpt_metadata_cannot_start_interactive_login(tmp_path, monkeypatch):
    """The read-only container guard blocks implicit auth during validation."""
    import errno
    from litellm.llms.chatgpt.authenticator import Authenticator
    from openhands.sdk import LLM
    blocked = '/run/openhands/disabled-litellm-login'
    monkeypatch.setenv('CHATGPT_TOKEN_DIR', blocked)
    original_makedirs = os.makedirs
    denied = []
    def makedirs(path, *args, **kwargs):
        if str(path) == blocked:
            denied.append(path)
            raise OSError(errno.EROFS, 'Read-only file system', path)
        return original_makedirs(path, *args, **kwargs)
    monkeypatch.setattr(os, 'makedirs', makedirs)
    def unexpected_login(*args, **kwargs):
        pytest.fail('Metadata lookup must never start an interactive login')
    monkeypatch.setattr(Authenticator, 'get_access_token', unexpected_login)
    # Unknown legacy-provider metadata may be absent; it must return promptly.
    LLM(model='chatgpt/gpt-6-astra')
    assert denied
    # The intended native profile remains valid without triggering legacy auth.
    before = len(denied)
    llm = LLM(model='openai/gpt-6-astra', auth_type='subscription', subscription_vendor='openai')
    assert llm.auth_type == 'subscription'
    assert len(denied) == before
