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
 def __init__(self,tid,gui=False):
  self.s=socket.create_connection(('127.0.0.1',18443),timeout=35); self.f=self.s.makefile('rb'); key=base64.b64encode(secrets.token_bytes(16)).decode()
  cookie='; '.join(c.name+'='+c.value for c in jar)
  self.s.sendall(('GET /api/terminals/'+tid+('/display/ws' if gui else '/ws')+' HTTP/1.1\r\nHost: 127.0.0.1:18443\r\nOrigin: '+BASE+'\r\nCookie: '+cookie+'\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: '+key+'\r\nSec-WebSocket-Version: 13\r\n\r\n').encode())
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

class VNC(WS):
 def __init__(self,tid):super().__init__(tid,True);self.buffer=b''
 def recv(self,n):
  while len(self.buffer)<n:
   fin,op,data=self.frame()
   if op==9:self.send(data,10);continue
   assert op in (0,2),(op,data[:100]);self.buffer+=data
  ret,self.buffer=self.buffer[:n],self.buffer[n:];return ret
 def out(self,b):self.send(b,2)
password=secrets.token_urlsafe(36);run(['chpasswd'],input=(user+':'+password+'\n').encode())
login=request('POST','/login',{'username':user,'password':password});csrf=login['csrf']
info=request('POST','/terminals',{'directory':'/workspace/tuxee-accept','name':'Real UBI9 GUI','columns':100,'rows':30},201);tid=info['id'];record('gui_terminal',terminal=info)
ws=WS(tid);assert ws.read()['control'];ws.send('LD_LIBRARY_PATH=/opt/tuxee-gui/lib:/opt/tuxee-gui/lib64:/opt/tuxee-gui/deps /opt/tuxee-gui/bin/tuxee-gui-probe > gui-app.log 2>&1 &\n',2)
for _ in range(80):
 event=ws.read()
 display=event.get('display',{})
 ret=event
 if display.get('windows'):break
 time.sleep(.25)
record('window_state',terminal=ret)
assert display.get('windows'),ret
creds=request('GET','/terminals/'+tid+'/display');v=VNC(tid)
banner=v.recv(12);assert banner==b'RFB 003.008\n',banner;v.out(banner)
n=v.recv(1)[0];security=v.recv(n);assert 2 in security,security;v.out(b'\x02');challenge=v.recv(16)
# VNC DES key reverses bits within each password byte; retain credentials in memory only.
key=bytes(int(f'{b:08b}'[::-1],2) for b in creds['password'].encode()[:8].ljust(8,b'\0'))
p=run(['openssl','enc','-des-ecb','-provider','legacy','-nopad','-K',key.hex()],input=challenge)
v.out(p.stdout);assert v.recv(4)==b'\0'*4;v.out(b'\x01')
init=v.recv(24);width,height=struct.unpack('!HH',init[:4]);name=v.recv(struct.unpack('!I',init[20:])[0]);record('rfb_authenticated',width=width,height=height,desktop_name=name.decode())
# Select raw encoding, request an actual framebuffer.
v.out(struct.pack('!BBHi',2,0,1,0));v.out(struct.pack('!BBHHHH',3,0,0,0,width,height))
def framebuffer():
 while True:
  typ=v.recv(1)[0]
  if typ==0:
   count=struct.unpack('!H',v.recv(3)[1:])[0];pixels=b''
   for _ in range(count):
    x,y,w,h,encoding=struct.unpack('!HHHHi',v.recv(12));assert encoding==0,encoding;pixels+=v.recv(w*h*4)
   if pixels:return pixels
  elif typ==2:continue
  elif typ==3:
   hdr=v.recv(7);v.recv(struct.unpack('!I',hdr[3:])[0])
  else:raise AssertionError(typ)
pixels=framebuffer();record('framebuffer',bytes=len(pixels),sha256=hashlib.sha256(pixels).hexdigest(),distinct_bytes=len(set(pixels)));assert len(set(pixels))>1
# Explicit window activation then actual RFB keyboard events.
window=display['windows'][0];request('POST','/terminals/'+tid+'/display/window',{'id':window['id']});time.sleep(.3)
marker='GUI_KEY_OK'
for c in marker:
 for down in (1,0):v.out(struct.pack('!BBHI',4,down,0,ord(c)))
fixture=pathlib.Path('/workspace/tuxee-accept/gui-input.txt')
for _ in range(40):
 if fixture.exists() and fixture.read_text()==marker:break
 time.sleep(.1)
assert fixture.read_text()==marker,fixture.read_text() if fixture.exists() else 'missing'
record('gui_keyboard_independent_file',content=fixture.read_text(),uid=fixture.stat().st_uid,sha256=hashlib.sha256(fixture.read_bytes()).hexdigest())
for _ in range(20):
 ret=ws.read()
 if marker in json.dumps(ret.get('display',{})):break
 time.sleep(.1)
assert marker in json.dumps(ret.get('display',{}));record('window_title_after_input',display=ret['display'])
v.out(struct.pack('!BBHHHH',3,0,0,0,width,height));after=framebuffer();record('framebuffer_after',sha256=hashlib.sha256(after).hexdigest(),bytes=len(after));assert pixels!=after
request('POST','/logout',{});ws.close();v.close()
record('gui_complete',terminal_id=tid,retained=True)
(root/'gui/acceptance-evidence.json').write_text(json.dumps(evidence,indent=2)+'\n')
