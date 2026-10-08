import importlib.util
from pathlib import Path
import pytest

JOURNAL = Path(__file__).resolve().parents[2]/'system/modules/nixos/services/hermes-trial/plugin/journal.py'

def journal(path):
    assert JOURNAL.exists(), 'Durable intake journal is missing'
    spec = importlib.util.spec_from_file_location('overseer_journal_test', JOURNAL)
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    return mod.Journal(path)


def test_duplicate_survives_restart(tmp_path):
    path=tmp_path/'journal.db'
    first=journal(path)
    assert first.accept(17,'dm:123')
    first.close()
    second=journal(path)
    assert not second.accept(17,'dm:123')
    assert second.recover()[0]['state']=='uncertain'
    second.close()


def test_completed_not_replayed(tmp_path):
    store=journal(tmp_path/'journal.db')
    store.accept(17,'dm:123'); store.mark(17,'dispatched'); store.mark(17,'completed')
    assert not store.recover()
    assert not store.accept(17,'dm:123')
    store.close()


def test_notice_failure_remains_pending(tmp_path):
    store=journal(tmp_path/'journal.db')
    store.accept(17,'dm:123'); store.mark(17,'needs_resend')
    assert [x['message_id'] for x in store.recover()]==[17]
    assert [x['message_id'] for x in store.recover()]==[17]
    store.notified(17)
    assert not store.recover()
    store.close()


def test_bound_to_bot_identity(tmp_path):
    store=journal(tmp_path/'journal.db')
    store.bind('site|bot1')
    with pytest.raises(ValueError): store.bind('site|bot2')
    store.close()
