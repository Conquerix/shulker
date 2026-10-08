"""Transactional request identity and leases; uncertain mutations are never replayed."""
import os
from contextlib import contextmanager
from pathlib import Path
import sqlite3
from uuid import uuid4


class TaskConflict(Exception):
    pass


class Journal:
    def __init__(self, path: Path):
        self.path = path
        if path.is_symlink(): raise ValueError('Unsafe journal')
        path.parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as db:
            db.execute("CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, origin TEXT NOT NULL, project TEXT NOT NULL, request_id TEXT NOT NULL, digest TEXT NOT NULL, task TEXT NOT NULL, state TEXT NOT NULL, workspace TEXT, result TEXT, UNIQUE(origin,request_id))")
            db.execute("CREATE UNIQUE INDEX IF NOT EXISTS project_lease ON tasks(project) WHERE state NOT IN ('completed','failed')")
            # Restart cannot prove where any live mutation stopped. Never resume automatically.
            db.execute("UPDATE tasks SET state='uncertain' WHERE state NOT IN ('completed','failed','paused','uncertain')")
        os.chmod(path, 0o600)

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=5)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def reserve(self, origin, project, request_id, digest, task):
        try:
            with self.connect() as db:
                db.execute('BEGIN IMMEDIATE')
                row = db.execute('SELECT * FROM tasks WHERE origin=? AND request_id=?', (origin,request_id)).fetchone()
                if row:
                    if row['digest'] != digest or row['project'] != project: raise TaskConflict()
                    return dict(row), False
                task_id = str(uuid4())
                db.execute("INSERT INTO tasks(id,origin,project,request_id,digest,task,state) VALUES(?,?,?,?,?,?,'reserved')", (task_id,origin,project,request_id,digest,task))
                row = db.execute('SELECT * FROM tasks WHERE id=?',(task_id,)).fetchone()
                return dict(row), True
        except sqlite3.IntegrityError:
            raise TaskConflict() from None

    def get(self, task_id, origin):
        with self.connect() as db:
            row = db.execute('SELECT * FROM tasks WHERE id=? AND origin=?',(task_id,origin)).fetchone()
            if not row: raise TaskConflict()
            return dict(row)

    def mark(self, task_id, state, *, workspace=None, result=None):
        if state not in {'reserved','creating','ready','running','paused','completed','failed','uncertain'}:
            raise ValueError('Invalid state')
        with self.connect() as db:
            db.execute('UPDATE tasks SET state=?, workspace=COALESCE(?,workspace), result=COALESCE(?,result) WHERE id=?',(state,workspace,result,task_id))
