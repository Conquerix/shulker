import os,pathlib,subprocess,socket,struct,time,tempfile
root=pathlib.Path(__file__).parent
with tempfile.TemporaryDirectory(prefix='keeper-',dir=root) as d:
 os.chmod(d,0o700)
 fd=os.open(d,os.O_RDONLY|os.O_DIRECTORY)
 assert fd==3,fd
 p=subprocess.Popen([str(root/'source/internal/keeper/keeper.bin')],pass_fds=(3,))
 try:
  for i in range(40):
   if (pathlib.Path(d)/'keeper.sock').exists():break
   if p.poll() is not None:raise RuntimeError('keeper exited '+str(p.returncode))
   time.sleep(.05)
  s=socket.socket(socket.AF_UNIX,socket.SOCK_SEQPACKET);s.connect(d+'/keeper.sock')
  s.send(struct.pack('>IIIIQQ',0x54584b32,0,0,0,0,0))
  b=s.recv(65536);h=struct.unpack('>IIIIQQ',b[:32]);print('HELLO',h,'payload',len(b)-32)
  assert h[0]==0x54584b32 and h[1]==0x80000000 and h[3]==0
 finally:
  p.terminate();p.wait(timeout=5);os.close(fd)
print('static PIE guardian launched, protocol HELLO passed, stopped')
