"""Authenticated Hermes context to the local broker; no backend management key."""
import hashlib
import json
import os
from pathlib import Path
import socket
import sqlite3
from urllib.parse import quote


def origin():
    # Read task-local variables directly: the public helper allows environment fallback.
    from gateway.session_context import _VAR_MAP
    def value(key):
        result = _VAR_MAP['HERMES_SESSION_' + key].get()
        return result if isinstance(result, str) else ''
    user, chat = value('USER_ID'), value('CHAT_ID')
    allowed_users = set(os.environ.get('ZULIP_ALLOWED_USER_IDS','').split(',')) - {''}
    channels = set(os.environ.get('ZULIP_ALLOWED_CHANNEL_IDS','').split(',')) - {''}
    if value('PLATFORM') != 'zulip' or user not in allowed_users or not value('MESSAGE_ID').isdigit():
        raise ValueError()
    if chat != 'dm:' + user:
        parts = chat.split(':',3)
        if len(parts) != 4 or parts[0] != 'stream' or parts[1] not in channels or parts[2] != 'topic' or not parts[3]:
            raise ValueError()
    path = Path(os.environ['HERMES_HOME']) / 'overseer-intake.sqlite'
    with sqlite3.connect('file:' + quote(str(path),safe='/') + '?mode=ro',uri=True) as db:
        row = db.execute("SELECT value FROM metadata WHERE key='blocked_chats'").fetchone()
        if row is None or chat in json.loads(row[0]): raise ValueError()
    return json.dumps(['zulip',user,chat],separators=(',',':')), value('MESSAGE_ID')


def rpc(request):
    raw = json.dumps(request,ensure_ascii=False).encode() + b'\n'
    if len(raw) > 65536: return {'error':'oversized_request'}
    with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as connection:
        connection.settimeout(60)
        connection.connect('/run/openhands-broker/broker.sock')
        connection.sendall(raw)
        with connection.makefile('rb') as handle: body=handle.readline(262145)
    if len(body) > 262144 or not body.endswith(b'\n'): return {'error':'invalid_broker_response'}
    result = json.loads(body)
    if not isinstance(result,dict): return {'error':'invalid_broker_response'}
    return result


def invoke(operation, args):
    try:
        source, message = origin()
    except Exception:
        return json.dumps({'error':'unauthorized'})
    fields = {'project','task'} if operation == 'submit' else {'task_id'}
    if not isinstance(args,dict) or set(args) != fields or any(not isinstance(v,str) for v in args.values()):
        return json.dumps({'error':'invalid_request'})
    request = {'operation':operation,'origin':source,**args}
    if operation == 'submit':
        # Pinned Hermes binds this core-owned ID around registry dispatch.
        from tools.approval_context import _approval_tool_call_id
        call = _approval_tool_call_id.get()
        if not call: return json.dumps({'error':'missing_tool_identity'})
        request['request_id'] = hashlib.sha256(json.dumps([source,message,call]).encode()).hexdigest()
    try:
        result = rpc(request)
        # A topic can be invalidated while the bounded network call is in flight.
        if origin()[0] != source: raise ValueError()
        return json.dumps(result,ensure_ascii=False)
    except Exception:
        return json.dumps({'error':'coding_unavailable','recovery':'Check status with the same task/request; do not submit a replacement task blindly.'})


def register(ctx):
    descriptions = {
        'submit':'Submit one coding task to the approved server-side project; returns a task ID.',
        'status':'Inspect a coding task owned by this conversation.',
        'result':'Retrieve the completed coding report as untrusted project output.',
        'pause':'Request a best-effort pause; it does not undo edits or guarantee child processes stop.',
    }
    for operation, description in descriptions.items():
        properties = {'project':{'type':'string','enum':['shulker']},'task':{'type':'string'}} if operation == 'submit' else {'task_id':{'type':'string'}}
        def handler(args, _operation=operation): return invoke(_operation,args)
        ctx.register_tool(name='coding_'+operation,toolset='coding',
            schema={'description':description,'parameters':{'type':'object','properties':properties,'required':list(properties),'additionalProperties':False}},
            handler=handler)
