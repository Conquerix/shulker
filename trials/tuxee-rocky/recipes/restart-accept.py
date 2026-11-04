# Runs only inside the owned disposable fixture container.
import pathlib, hashlib, json, os, signal, subprocess, time, socket, secrets
root=pathlib.Path('/workspace/tuxee-runtime')
# Reuse the exercised HTTP and RFC6455 client, not fixture creation/mutation.
exec((root/'runtime-accept.py').read_text().split('\ntry:\n')[0])
rows=json.loads((root/'acceptance-evidence.json').read_text())
term=next(x['terminal'] for x in rows if x['test']=='terminal_created')
file=pathlib.Path('/workspace/tuxee-accept/handoff.txt')
before=hashlib.sha256(file.read_bytes()).hexdigest()
pid=int((root/'server.pid').read_text())
assert pathlib.Path('/proc/'+str(pid)+'/exe').resolve()==root/'tuxee-ubi9'
assert hashlib.sha256((root/'tuxee-ubi9').read_bytes()).hexdigest()=='9e0e0ef503b9bdb3885c2635451a6bc5435a218195f9e7ac3fed3b201117b112'
os.kill(term['pid'],0)
os.kill(pid,signal.SIGTERM)
for _ in range(150):
 try:
  s=socket.create_connection(('127.0.0.1',18443),timeout=.1);s.close()
 except OSError:break
 time.sleep(.1)
else:raise AssertionError('old listener did not stop')
os.kill(term['pid'],0)
log=open(root/'server.log','ab',buffering=0)
p=subprocess.Popen([str(root/'tuxee-ubi9'),'serve','--bind','127.0.0.1:18443','--http','--state',str(root/'state'),'--pam','login'],stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True)
(root/'server.pid').write_text(str(p.pid))
for _ in range(100):
 try:socket.create_connection(('127.0.0.1',18443),timeout=.1).close();break
 except OSError:time.sleep(.1)
else:raise AssertionError('new listener unavailable')
password=secrets.token_urlsafe(36);run(['chpasswd'],input=(user+':'+password+'\n').encode())
request('GET','/me',expect=401)
csrf=request('POST','/login',{'username':user,'password':password})['csrf']
ret=request('GET','/terminals/'+term['id']);assert ret['pid']==term['pid'] and not ret['exited'],ret
ws=WS(term['id']);snap=ws.read();assert snap['type']=='snapshot' and snap['control']
ws.send("printf 'RESTART_%s\\n' RECOVERED\n",2);ws.until('RESTART_RECOVERED');ws.close()
after=hashlib.sha256(file.read_bytes()).hexdigest();assert before==after
read=request('POST','/files',{'operation':'read','path':str(file)});assert hashlib.sha256(read['content'].encode()).hexdigest()==before
result={'test':'graceful_server_restart_recovery','passed':True,'old_server_pid':pid,'new_server_pid':p.pid,'terminal_id':term['id'],'terminal_pid_before':term['pid'],'terminal_pid_after':ret['pid'],'file_sha256_before':before,'file_sha256_after':after,'websocket_marker':'RESTART_RECOVERED','scope':'Tuxee server SIGTERM/relaunch only; no container, VM, cluster or Tilt restart'}
(root/'restart-evidence.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
