"""Broker mutations are bounded and never replayed after uncertain outcomes."""
import pytest
from broker.journal import Journal
from broker.policy import Policy
from broker.server import Broker
from broker.client import BackendError

class Backend:
    def __init__(self): self.creates=0;self.runs=0;self.status='running';self.lost=False;self.workspace='/projects/shulker/worktrees/x/repository'
    def create(self, task):
        self.creates+=1
        if self.lost: raise BackendError('unavailable')
        return {'id':task['id'],'workspace':{'working_dir':self.workspace},'execution_status':'idle'}
    def start(self, task): self.runs+=1
    def inspect(self, task_id): return {'id':task_id,'execution_status':self.status,'workspace':{'working_dir':self.workspace}}
    def final_response(self, task_id): return 'result text'
    def pause(self, task_id): self.status='paused'

@pytest.fixture
def broker(tmp_path):
    return Broker(Policy('https://coding-api.shulker.link','8dcb2360-3c3f-4e30-bb75-626b5f7d27d6',10010,'https://code.shulker.link'),Journal(tmp_path/'journal.db'),Backend())

def submit(broker, **extra):
    return broker.dispatch(10010, {'operation':'submit','origin':'user:9/topic:4:example','project':'shulker','task':'Inspect README','request_id':'call-1',**extra})

@pytest.mark.parametrize('extra',[{'project':'../shulker'},{'model':'other'},{'path':'/etc'},{'url':'https://other'},{'task':'bad\x00task'}])
def test_unknown_fields_and_paths_denied(broker,extra):
    assert submit(broker,**extra)['error']=='invalid_request'
    assert broker.client.creates==0

def test_wrong_peer_denied(broker):
    assert broker.dispatch(1, {'operation':'submit'})['error']=='unauthorized'

def test_duplicate_submit_runs_once(broker):
    a=submit(broker);b=submit(broker)
    assert a['task_id']==b['task_id']
    assert broker.client.creates==broker.client.runs==1

def test_lost_create_response_is_uncertain(broker):
    broker.client.lost=True
    a=submit(broker);b=submit(broker)
    assert a['state']==b['state']=='uncertain'
    assert broker.client.creates==1 and broker.client.runs==0

def test_idle_is_not_completed(broker):
    a=submit(broker);broker.client.status='idle'
    result=broker.dispatch(10010,{'operation':'result','origin':'user:9/topic:4:example','task_id':a['task_id']})
    assert 'result' not in result and result['state']=='running'

def test_terminal_result_releases_lease(broker):
    a=submit(broker);broker.client.status='finished'
    result=broker.dispatch(10010,{'operation':'result','origin':'user:9/topic:4:example','task_id':a['task_id']})
    assert result['state']=='completed' and result['result']=='result text'
    assert submit(broker,request_id='call-2')['task_id']!=a['task_id']

def test_paused_task_retains_lease(broker):
    a=submit(broker)
    paused=broker.dispatch(10010,{'operation':'pause','origin':'user:9/topic:4:example','task_id':a['task_id']})
    assert paused['state']=='paused'
    assert submit(broker,request_id='call-2')['error']=='task_conflict'

def test_server_assigned_workspace_cannot_escape_project(broker):
    broker.client.workspace='/etc'
    assert submit(broker)['state']=='uncertain'
    assert broker.client.runs==0

def test_other_origin_cannot_pause(broker):
    a=submit(broker)
    assert broker.dispatch(10010,{'operation':'pause','origin':'other','task_id':a['task_id']})['error']=='task_conflict'


def test_lost_run_response_is_uncertain_and_not_replayed(broker,monkeypatch):
    def lost(task):
        broker.client.runs+=1
        raise BackendError('unavailable')
    monkeypatch.setattr(broker.client,'start',lost)
    first=submit(broker);second=submit(broker)
    assert first['state']==second['state']=='uncertain'
    assert broker.client.creates==broker.client.runs==1

def test_offline_status_keeps_project_lease(broker,monkeypatch):
    first=submit(broker)
    def offline(task_id):raise BackendError('unavailable')
    monkeypatch.setattr(broker.client,'inspect',offline)
    status=broker.dispatch(10010,{'operation':'status','origin':'user:9/topic:4:example','task_id':first['task_id']})
    assert status['error']=='backend_unavailable' and status['state']=='running'
    assert submit(broker,request_id='call-2')['error']=='task_conflict'
