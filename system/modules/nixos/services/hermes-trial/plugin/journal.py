"""Durable intake bookkeeping; uncertain work is never replayed automatically."""
import sqlite3


class Journal:
    def __init__(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(path)
        self.db.row_factory = sqlite3.Row
        # DELETE mode avoids depending on WAL recovery across backup snapshots.
        self.db.execute('PRAGMA synchronous=FULL')
        self.db.executescript('''
          CREATE TABLE IF NOT EXISTS intake (
            message_id INTEGER PRIMARY KEY, conversation TEXT NOT NULL,
            state TEXT NOT NULL, notified INTEGER NOT NULL DEFAULT 0);
          CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        ''')

    def bind(self, identity):
        old = self.get('identity')
        if old is not None and old != identity:
            raise ValueError('Journal belongs to another bot/site; refusing reuse')
        self.put('identity', identity)

    def get(self, key):
        row = self.db.execute('SELECT value FROM metadata WHERE key=?', (key,)).fetchone()
        return row[0] if row else None

    def put(self, key, value):
        with self.db:
            self.db.execute('INSERT OR REPLACE INTO metadata VALUES (?,?)', (key,str(value)))

    def accept(self, message_id, conversation):
        with self.db:
            return self.db.execute('INSERT OR IGNORE INTO intake VALUES (?,?,?,0)',
                                   (message_id,conversation,'accepted')).rowcount == 1

    def mark(self, message_id, state):
        if state not in {'accepted','dispatched','completed','uncertain','needs_resend'}:
            raise ValueError('Invalid intake state')
        with self.db:
            self.db.execute('UPDATE intake SET state=? WHERE message_id=?', (state,message_id))

    def recover(self, interrupted=True):
        if interrupted:
            with self.db:
                self.db.execute("UPDATE intake SET state='uncertain' WHERE state IN ('accepted','dispatched')")
        return [dict(row) for row in self.db.execute(
            "SELECT * FROM intake WHERE state IN ('uncertain','needs_resend') AND notified=0 ORDER BY message_id")]

    def notified(self, message_id):
        with self.db:
            self.db.execute('UPDATE intake SET notified=1 WHERE message_id=?', (message_id,))

    def close(self):
        self.db.close()
