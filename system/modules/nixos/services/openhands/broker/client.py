"""Fixed native profile launch payload for the pinned Agent Server API."""
def create_payload(conversation_id: str, task: str, profile_id: str) -> dict:
    return {
        'conversation_id': conversation_id,
        'workspace': {'working_dir': '/projects/shulker/repository'},
        'worktree': True,
        'agent_profile_id': str(UUID(profile_id)),
        'autotitle': False,
    }


import json
from pathlib import Path
from uuid import UUID
import httpx


class BackendError(Exception):
    """Only a closed error code, never a response body or credential."""


class AgentServerClient:
    def __init__(self, policy, key: str, *, transport=None):
        if not key.strip() or any(ord(c) < 33 for c in key):
            raise ValueError('Invalid backend credential')
        self.policy = policy
        self.http = httpx.Client(base_url=policy.backend, headers={'X-Session-API-Key': key},
                                 timeout=15, follow_redirects=False, transport=transport,
                                 trust_env=False)

    def request(self, method: str, path: str, payload=None):
        try:
            with self.http.stream(method, path, json=payload) as response:
                if not 200 <= response.status_code < 300:
                    raise BackendError('backend_rejected')
                body = bytearray()
                for chunk in response.iter_bytes():
                    body.extend(chunk)
                    if len(body) > 262144: raise BackendError('oversized_response')
                value = json.loads(body)
                if not isinstance(value, dict): raise BackendError('invalid_response')
                return value
        except (httpx.HTTPError, ValueError):
            raise BackendError('backend_unavailable') from None

    def create(self, task):
        return self.request('POST', '/api/conversations', create_payload(task['id'], task['task'], self.policy.profile_id))

    def inspect(self, task_id):
        return self.request('GET', '/api/conversations/' + str(UUID(task_id)))

    def start(self, task):
        response = self.request('POST', '/api/conversations/' + str(UUID(task['id'])) + '/events',
                               {'role':'user', 'content':[{'type':'text', 'text':task['task']}], 'run':True})
        if response.get('success') is not True: raise BackendError('backend_rejected')

    def final_response(self, task_id):
        response = self.request('GET', '/api/conversations/' + str(UUID(task_id)) + '/agent_final_response')
        value = response.get('response')
        if not isinstance(value, str): raise BackendError('invalid_response')
        return value

    def pause(self, task_id):
        response = self.request('POST', '/api/conversations/' + str(UUID(task_id)) + '/pause')
        if response.get('success') is not True: raise BackendError('backend_rejected')
