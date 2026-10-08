"""Execute the secret renderer with synthetic punctuation and invalid inputs."""
import json, pathlib, subprocess, sys, tempfile
renderer=pathlib.Path(sys.argv[1])
assert renderer.exists(), 'Secret renderer missing'
with tempfile.TemporaryDirectory() as tmp:
    root=pathlib.Path(tmp); source=root/'secrets.json'; output=root/'rendered'
    names=['postgres_password','memcached_password','rabbitmq_password','redis_password','secret_key','email_password','social_auth_oidc_secret']
    values={name:"literal'$()\\value\"" for name in names}
    source.write_text(json.dumps(values))
    result=subprocess.run([sys.executable,str(renderer),str(source),str(output)],capture_output=True)
    assert result.returncode==0, result.stderr
    for name in names: assert (output/('zulip__'+name)).read_text()==values[name]
    values['../escape']='invalid'; source.write_text(json.dumps(values))
    result=subprocess.run([sys.executable,str(renderer),str(source),str(output)],capture_output=True)
    assert result.returncode!=0 and b'literal' not in result.stderr
    del values['../escape'];values['secret_key']='line\nbreak';source.write_text(json.dumps(values))
    assert subprocess.run([sys.executable,str(renderer),str(source),str(output)],capture_output=True).returncode!=0
print('Zulip secret rendering passed')
