"""Linux peer-authenticated, bounded Unix socket task API."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import socket
import sqlite3
import socketserver
import struct
import sys
import threading
from uuid import UUID
from .client import AgentServerClient, BackendError
from .journal import Journal, TaskConflict
from .policy import Policy


class Broker:
    def __init__(self, policy, journal, client):
        self.policy, self.journal, self.client = policy, journal, client
        self.lock = threading.Lock()

    @staticmethod
    def validate_info(task, info):
        try:
            if UUID(info['id']) != UUID(task['id']): raise ValueError()
            workspace = info['workspace']['working_dir']
            p = PurePosixPath(workspace)
            if '..' in p.parts or not p.is_relative_to('/projects/shulker/worktrees') or p == PurePosixPath('/projects/shulker/worktrees'):
                raise ValueError()
            return workspace
        except (KeyError, TypeError, ValueError): raise BackendError('invalid_workspace') from None

    def public(self, row, *, include_result=False):
        value = {'task_id': row['id'], 'state': row['state'], 'workspace':row['workspace'],
                 'canvas_url':self.policy.canvas + '/canvas/conversations/' + row['id']}
        if include_result and row['state'] in ('completed','failed'): value['result'] = row['result']
        return value

    def dispatch(self, uid: int, request: dict) -> dict:
        if uid != self.policy.uid: return {'error':'unauthorized'}
        try:
            if not isinstance(request, dict): raise ValueError()
            op = request.get('operation')
            fields = {'operation','origin','project','task','request_id'} if op == 'submit' else {'operation','origin','task_id'}
            if op not in {'submit','status','result','pause'} or set(request) != fields: raise ValueError()
            if any(not isinstance(v,str) or not v or '\x00' in v for v in request.values()): raise ValueError()
            if len(request['origin'].encode()) > 1024: raise ValueError()
            if op == 'submit':
                if request['project'] != 'shulker' or len(request['task'].encode()) > 32768 or len(request['request_id']) > 256: raise ValueError()
            else: UUID(request['task_id'])
            with self.lock:
                return self._dispatch(request)
        except (ValueError, TypeError): return {'error':'invalid_request'}
        except TaskConflict: return {'error':'task_conflict'}
        except sqlite3.Error: return {'error':'journal_unavailable'}

    def _dispatch(self, request):
        op, origin = request['operation'], request['origin']
        if op == 'submit':
            digest = hashlib.sha256(request['task'].encode()).hexdigest()
            row, new = self.journal.reserve(origin, 'shulker', request['request_id'], digest, request['task'])
            if not new: return self.public(row)
            try:
                self.journal.mark(row['id'],'creating')
                info = self.client.create(row)
                workspace = self.validate_info(row,info)
                if info.get('execution_status') != 'idle': raise BackendError('unexpected_run')
                self.journal.mark(row['id'],'ready', workspace=workspace)
                # The /events run=True mutation both saves the message and starts execution.
                self.journal.mark(row['id'],'running')
                self.client.start(row)
            except BackendError:
                self.journal.mark(row['id'],'uncertain')
            return self.public(self.journal.get(row['id'],origin))
        row = self.journal.get(request['task_id'],origin)
        if row['state'] in ('completed','failed'): return self.public(row, include_result=op=='result')
        try:
            if op == 'pause':
                self.client.pause(row['id']); self.journal.mark(row['id'],'paused')
            else:
                info = self.client.inspect(row['id']); workspace = self.validate_info(row,info)
                status = info.get('execution_status')
                if status in ('finished','error','stuck'):
                    result = self.client.final_response(row['id'])
                    if len(result.encode()) > 262144: raise BackendError('oversized_response')
                    self.journal.mark(row['id'],'completed' if status=='finished' else 'failed',workspace=workspace,result=result)
                elif status == 'paused': self.journal.mark(row['id'],'paused',workspace=workspace)
                elif status == 'running': self.journal.mark(row['id'],'running',workspace=workspace)
                elif status not in ('idle','waiting_for_confirmation'): raise BackendError('invalid_status')
        except BackendError:
            if op == 'pause': self.journal.mark(row['id'],'uncertain')
            value = self.public(self.journal.get(row['id'],origin)); value['error']='backend_unavailable'; return value
        return self.public(self.journal.get(row['id'],origin),include_result=op=='result')


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        self.request.settimeout(5)
        try:
            _, uid, _ = struct.unpack('3i', self.request.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize('3i')))
            raw = self.rfile.readline(65537)
            if len(raw) > 65536 or not raw.endswith(b'\n'): return
            response = self.server.broker.dispatch(uid,json.loads(raw))
        except (ValueError, OSError): response={'error':'invalid_request'}
        data = json.dumps(response).encode()
        if len(data)>262144: data=b'{"error":"oversized_response"}'
        self.wfile.write(data+b'\n')


if __name__ == '__main__':
    policy = Policy.load(Path(sys.argv[1]))
    key = Path(os.environ['CREDENTIALS_DIRECTORY'], 'backend-key').read_text().strip()
    broker = Broker(policy, Journal(Path('/var/lib/openhands-broker/journal.db')), AgentServerClient(policy,key))
    path = '/run/openhands-broker/broker.sock'
    if os.path.exists(path): os.unlink(path)
    with socketserver.ThreadingUnixStreamServer(path,Handler) as server:
        os.chmod(path,0o660); server.broker=broker; server.daemon_threads=True
        server.serve_forever()
