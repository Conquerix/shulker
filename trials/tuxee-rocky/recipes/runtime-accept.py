import os,sys,json,time,secrets,subprocess,urllib.request,urllib.error,http.cookiejar,socket,base64,hashlib,struct,pathlib
BASE='http://127.0.0.1:18443'; root=pathlib.Path('/workspace/tuxee-runtime'); user='tuxeeaccept'
def run(args,**kw): return subprocess.run(args,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,**kw)
evidence=[]
def record(name,**data):
 row=dict(test=name,**data); evidence.append(row); print(json.dumps(row),flush=True)
def request(method,path,data=None,expect=200,auth=True):
 headers={'Origin':BASE,'X-Tuxee-Client':'web','Content-Type':'application/json'}
 if auth and csrf: headers['X-Tuxee-CSRF']=csrf
 req=urllib.request.Request(BASE+'/api'+path,data=None if data is None else json.dumps(data).encode(),method=method,headers=headers)
 try: r=client.open(req,timeout=35)
 except urllib.error.HTTPError as e:r=e
 body=r.read(); assert r.code==expect,(method,path,r.code,body.decode()[:1000]); return json.loads(body) if body else None
csrf=''; jar=http.cookiejar.CookieJar(); client=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
class WS:
 def __init__(self,tid):
  self.s=socket.create_connection(('127.0.0.1',18443),timeout=35); self.f=self.s.makefile('rb'); key=base64.b64encode(secrets.token_bytes(16)).decode()
  cookie='; '.join(c.name+'='+c.value for c in jar)
  self.s.sendall(('GET /api/terminals/'+tid+'/ws HTTP/1.1\r\nHost: 127.0.0.1:18443\r\nOrigin: '+BASE+'\r\nCookie: '+cookie+'\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: '+key+'\r\nSec-WebSocket-Version: 13\r\n\r\n').encode())
  status=self.f.readline(); assert b'101' in status,status
  while self.f.readline()!=b'\r\n':pass
 def send(self,data,opcode=1):
  if isinstance(data,str):data=data.encode()
  mask=secrets.token_bytes(4); n=len(data); hdr=bytes([128|opcode,128|(n if n<126 else 126)])+(struct.pack('!H',n) if n>=126 else b'')
  self.s.sendall(hdr+mask+bytes(x^mask[i%4] for i,x in enumerate(data)))
 def frame(self):
  h=self.f.read(2); assert len(h)==2,'closed WS'; op=h[0]&15;n=h[1]&127
  if n==126:n=struct.unpack('!H',self.f.read(2))[0]
  if n==127:n=struct.unpack('!Q',self.f.read(8))[0]
  data=self.f.read(n);assert len(data)==n,'short WS frame'
  return bool(h[0]&128),op,data
 def read(self):
  parts=[];kind=None
  while True:
   fin,op,data=self.frame()
   if op==9:self.send(data,10);continue
   if op==10:continue
   if op==8:raise RuntimeError('WS closed')
   if op in (1,2):assert kind is None;kind=op
   else:assert op==0 and kind is not None,('invalid continuation',op)
   parts.append(data)
   if fin:break
  data=b''.join(parts)
  if kind==2:seq=struct.unpack('!Q',data[:8])[0]; event={'type':'data','data':data[8:].decode(errors='replace')}
  else:
   event=json.loads(data);seq=event.get('sequence',0)
   if event.get('data'):event['data']=base64.b64decode(event['data']).decode(errors='replace')
  if seq:self.send(json.dumps({'type':'rendered','sequence':seq}))
  return event
 def until(self,marker):
  text=''
  while marker not in text:
   e=self.read();text+=e.get('data','')
   assert len(text)<2000000
  return text
 def close(self):self.s.close();self.f.close()
try:
 try:
  run(['id',user]); assert (root/'acceptance-evidence.json').exists() and pathlib.Path('/workspace/tuxee-accept').is_dir(), 'unowned fixture'
 except subprocess.CalledProcessError:run(['useradd','-m','-s','/bin/bash',user])
 password=secrets.token_urlsafe(36)
 run(['chpasswd'],input=(user+':'+password+'\n').encode())
 uid=int(run(['id','-u',user]).stdout);gid=int(run(['id','-g',user]).stdout)
 work=pathlib.Path('/workspace/tuxee-accept');work.mkdir(exist_ok=True);os.chown(work,uid,gid)
 log=open(root/'server.log','ab',buffering=0)
 if (root/'server.pid').exists():
  pid=int((root/'server.pid').read_text());assert pathlib.Path('/proc/'+str(pid)+'/exe').resolve()==root/'tuxee-ubi9';os.kill(pid,0)
 else:
  proc=subprocess.Popen([str(root/'tuxee-ubi9'),'serve','--bind','127.0.0.1:18443','--http','--state',str(root/'state'),'--pam','login'],stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True)
  pid=proc.pid;(root/'server.pid').write_text(str(pid))
 for _ in range(50):
  try: socket.create_connection(('127.0.0.1',18443),timeout=.2).close();break
  except OSError:time.sleep(.2)
 record('runtime',pid=pid,binary_sha256=hashlib.sha256((root/'tuxee-ubi9').read_bytes()).hexdigest(),bind=BASE)
 request('GET','/me',expect=401);record('anonymous_denied',status=401)
 login=request('POST','/login',{'username':user,'password':password});csrf=login['csrf'];record('native_pam_login',status=200,user=login['user'])
 fixture=work/'handoff.txt'
 if not fixture.exists():fixture.touch();os.chown(fixture,uid,gid)
 original=request('POST','/files',{'operation':'read','path':str(fixture)})
 request('POST','/files',{'operation':'write','path':str(fixture),'content':'from-tuxee-api\n','version':original['version'],'page':original['page']})
 read=request('POST','/files',{'operation':'read','path':str(work/'handoff.txt')});assert read['content']=='from-tuxee-api\n';record('file_write_read',path=str(work/'handoff.txt'))
 info=request('POST','/terminals',{'directory':str(work),'name':'UBI acceptance','columns':100,'rows':30},201);tid=info['id'];record('terminal_created',terminal=info)
 ws=WS(tid);e=ws.read();assert e['type']=='snapshot' and e['control'];record('websocket_snapshot',control=True)
 ws.send("printf 'from-terminal\\n' >> handoff.txt; printf 'TERM_%s\\n' OK\n",2);ws.until('TERM_OK');record('terminal_input_output',marker='TERM_OK')
 request('POST','/logout',{});request('GET','/terminals',expect=401)
 try:
  while True: ws.read()
 except (RuntimeError,AssertionError,ConnectionError) as e:
  record('logout_revokes_websocket',closed=True)
 ws.close()
 login=request('POST','/login',{'username':user,'password':password});csrf=login['csrf'];ret=request('GET','/terminals/'+tid);assert ret['pid']==info['pid'] and not ret.get('exited');record('logout_retains_terminal',id=tid,pid=ret['pid'])
 ws=WS(tid);e=ws.read();assert e['type']=='snapshot' and e['control'];ws.send("printf 'RECONNECT_%s\\n' OK\n",2);ws.until('RECONNECT_OK');record('terminal_reconnected',marker='RECONNECT_OK');ws.close()
 home=pathlib.Path('/home')/user;sshdir=home/'.ssh';sshdir.mkdir(mode=0o700);os.chown(sshdir,uid,gid)
 key=root/'fixture-ssh-key';run(['ssh-keygen','-q','-t','ed25519','-N','','-f',str(key)])
 pub=key.with_suffix('.pub').read_text();(sshdir/'authorized_keys').write_text(pub);os.chown(sshdir/'authorized_keys',uid,gid);os.chmod(sshdir/'authorized_keys',0o600)
 known=root/'fixture-known-hosts';hostkey=pathlib.Path('/etc/ssh/ssh_host_ed25519_key.pub').read_text().split();known.write_text('127.0.0.1 '+hostkey[0]+' '+hostkey[1]+'\n')
 ssh=['ssh','-i',str(key),'-o','IdentitiesOnly=yes','-o','StrictHostKeyChecking=yes','-o','UserKnownHostsFile='+str(known),user+'@127.0.0.1']
 output=run(ssh+["cd /workspace/tuxee-accept && printf 'from-ssh\\n' >> handoff.txt && cat handoff.txt && stat -c '%i:%u:%g' handoff.txt"]).stdout.decode();assert 'from-tuxee-api\nfrom-terminal\nfrom-ssh\n' in output
 read=request('POST','/files',{'operation':'read','path':str(work/'handoff.txt')});assert read['content']=='from-tuxee-api\nfrom-terminal\nfrom-ssh\n';record('ssh_same_file',content=read['content'],stat=output.strip().splitlines()[-1],sha256=hashlib.sha256(read['content'].encode()).hexdigest())
 display=request('GET','/terminals/'+tid+'/display',expect=409);record('gui_not_running',status=409,response=display,passed=False)
 record('complete',terminal_id=tid,retained=True)
except Exception as e:
 record('failure',error=str(e));raise
finally:
 (root/'acceptance-evidence.json').write_text(json.dumps(evidence,indent=2)+'\n')
