"""Exercise snapshot ordering and recovery without touching a live service."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

runtime = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    bindir = root / 'bin'
    bindir.mkdir()
    data = root / 'data'
    data.mkdir()
    stub = '''import os,sys
from pathlib import Path
name=Path(sys.argv[0]).name
args=sys.argv[1:]
with open(os.environ['CALLS'],'a') as f: f.write(name+' '+' '.join(args)+'\\n')
mode=os.environ['CASE']
if name=='validate' and mode=='bad-mount': sys.exit(65)
if name=='zfs' and args[0]=='list': sys.exit(1)
if name=='zfs' and args[0]=='snapshot' and mode=='snapshot-fails': sys.exit(1)
if name=='compose' and args[:1]==['ps']:
 print('server' if mode!='inactive' else '')
if name=='compose' and args[:1]==['up'] and mode=='restart-fails': sys.exit(1)
'''
    for name in ['flock', 'validate', 'zfs', 'compose']:
        p = bindir / name
        p.write_text('#!' + sys.executable + '\n' + stub)
        p.chmod(0o755)
    for mode in ['bad-mount', 'inactive', 'snapshot-fails', 'restart-fails', 'ok']:
        calls = root / 'calls'
        calls.write_text('')
        env = dict(os.environ, PATH=str(bindir) + ':' + os.environ['PATH'], CASE=mode, CALLS=str(calls))
        p = subprocess.run(['bash', str(runtime), 'backup', str(root), 'pool/kitchenowl', str(root / 'lock'),
                            str(bindir / 'compose'), str(bindir / 'validate')], env=env, capture_output=True)
        log = calls.read_text()
        assert (p.returncode == 0) == (mode == 'ok'), (mode, p.stderr.decode())
        if mode in ('bad-mount', 'inactive'):
            assert 'compose stop' not in log, (mode, log)
        else:
            assert 'compose stop server' in log, (mode, log)
            assert 'compose up' in log, ('must recover stopped app', mode, log)
        if mode == 'restart-fails':
            assert 'zfs destroy pool/kitchenowl@borgmatic' in log, log
        if mode == 'ok':
            assert log.index('compose stop server') < log.index('zfs snapshot') < log.index('compose up'), log
    print('KitchenOwl backup: ordering, mount refusal, inactive refusal, snapshot and restart failure recovery passed')
