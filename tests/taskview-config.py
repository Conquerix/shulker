"""The renderer must preserve literal secrets and never publish partial config."""
import json
import pathlib
import subprocess
import sys
import tempfile

renderer = pathlib.Path(sys.argv[1])
assert renderer.is_file(), 'TaskView secret renderer is not implemented'
fields = {'DB_PASSWORD': 'db$literal#value', 'JWT_SIGN': 'j'*64,
          'ENCRYPTION_KEY': 'ab'*32, 'CENTRIFUGO_API_KEY': 'a'*64,
          'CENTRIFUGO_TOKEN_SECRET': 'c'*64, 'SMTP_HOST': 'smtp.example.test',
          'SMTP_PORT': '465', 'SMTP_ENCRYPTION': 'ssl', 'SMTP_FROM_NAME': 'Household Tasks',
          'SMTP_FROM_EMAIL': 'tasks@example.test', 'SMTP_USERNAME': 'account@example.test',
          'SMTP_PASSWORD': 'mail$literal#value',
          'SSO_TRUSTED_DOMAINS': 'household.example,mail.example'}
with tempfile.TemporaryDirectory() as temporary:
    root = pathlib.Path(temporary)
    source, target = root/'input', root/'runtime'
    base = root/'base.json'
    base.write_text(json.dumps({'http_server': {'port': 8000, 'internal_port': '9000'}}))
    def run(values):
        source.write_text(''.join(f'{k}={v}\n' for k,v in values.items()))
        return subprocess.run([sys.executable, str(renderer), str(source), str(target), str(base)], capture_output=True, text=True)
    missing = dict(fields); del missing['DB_PASSWORD']
    result = run(missing)
    assert result.returncode != 0 and not target.exists()
    assert all(value not in result.stdout+result.stderr for value in fields.values())
    result = run(fields)
    assert result.returncode == 0, result.stderr
    assert 'POSTGRES_PASSWORD=db$literal#value\n' == (target/'database.env').read_text()
    assert 'SMTP_PASSWORD=mail$literal#value\n' in (target/'api.env').read_text()
    assert 'SSO_TRUSTED_DOMAINS=household.example,mail.example\n' in (target/'api.env').read_text()
    assert 'SSO_TRUSTED_DOMAINS' not in (target/'database.env').read_text()
    assert 'SMTP' not in (target/'migration.env').read_text()
    assert 'JWT' not in (target/'migration.env').read_text()
    conf=json.loads((target/'centrifugo.json').read_text())
    assert conf['client']['token']['hmac_secret_key'] == fields['CENTRIFUGO_TOKEN_SECRET']
    assert conf['http_server']['internal_port'] == '9000'
    assert (target/'api.env').stat().st_mode & 0o777 == 0o600
    previous=(target/'api.env').read_bytes()
    for domains in ('*', 'https://mail.example', 'mail.example,,household.example'):
        invalid=dict(fields); invalid['SSO_TRUSTED_DOMAINS']=domains
        assert run(invalid).returncode != 0
        assert (target/'api.env').read_bytes() == previous
    invalid=dict(fields); invalid['ENCRYPTION_KEY']='invalid'
    assert run(invalid).returncode != 0
    assert (target/'api.env').read_bytes() == previous
print('TaskView secrets: missing/invalid inputs refused, literal values preserved, per-container scope checked')
