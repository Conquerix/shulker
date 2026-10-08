"""Durable idempotency and project leases survive broker process restarts."""
import pytest
from broker.journal import Journal, TaskConflict


def test_duplicate_submit_single_run(tmp_path):
    journal=Journal(tmp_path/'journal.db')
    a,new=journal.reserve('origin', 'shulker', 'request', 'digest', 'task')
    b,again=journal.reserve('origin','shulker','request','digest','task')
    assert new and not again and a['id']==b['id']
    with pytest.raises(TaskConflict): journal.reserve('origin','shulker','request','changed','task')
    with pytest.raises(TaskConflict): journal.reserve('origin','shulker','other','digest','task')

@pytest.mark.parametrize('state',['reserved','creating','ready','running','paused','uncertain'])
def test_restart_at_each_transition(tmp_path,state):
    path=tmp_path/'journal.db';j=Journal(path)
    a,_=j.reserve('origin','shulker','request','digest','task');j.mark(a['id'],state)
    restarted=Journal(path)
    assert restarted.get(a['id'],'origin')['state'] in ('uncertain','paused')
    with pytest.raises(TaskConflict): restarted.reserve('origin','shulker','other','digest','task')

def test_other_origin_denied(tmp_path):
    j=Journal(tmp_path/'journal.db');a,_=j.reserve('origin','shulker','request','digest','task')
    with pytest.raises(TaskConflict): j.get(a['id'],'other')


def test_database_connections_are_closed(tmp_path,monkeypatch):
    import sqlite3
    opened=[]
    original=sqlite3.connect
    class Tracked(sqlite3.Connection):
        def close(self):
            opened.remove(self)
            super().close()
    def connect(*args,**kwargs):
        connection=original(*args,**kwargs,factory=Tracked)
        opened.append(connection)
        return connection
    monkeypatch.setattr(sqlite3,'connect',connect)
    journal=Journal(tmp_path/'journal.db')
    row,_=journal.reserve('origin','shulker','call','digest','task')
    journal.get(row['id'],'origin')
    assert not opened
