"""Render literal KEY=value input into minimal, private container configuration."""
import json
import os
from pathlib import Path
import re
import sys
import tempfile


def render(source, target, base):
    required = {
        'DB_PASSWORD', 'JWT_SIGN', 'ENCRYPTION_KEY', 'CENTRIFUGO_API_KEY',
        'CENTRIFUGO_TOKEN_SECRET', 'SMTP_HOST', 'SMTP_PORT', 'SMTP_ENCRYPTION',
        'SMTP_FROM_NAME', 'SMTP_FROM_EMAIL', 'SMTP_USERNAME', 'SMTP_PASSWORD',
        'SSO_TRUSTED_DOMAINS',
    }
    values = {}
    for line in source.read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        key, separator, value = line.partition('=')
        if not separator or key not in required or key in values or not value or '\x00' in value:
            raise ValueError('invalid, duplicate, or unknown environment field')
        values[key] = value
    missing = required - values.keys()
    if missing:
        raise ValueError('missing fields: ' + ', '.join(sorted(missing)))
    if not re.fullmatch(r'[0-9a-fA-F]{64}', values['ENCRYPTION_KEY']):
        raise ValueError('ENCRYPTION_KEY must contain 64 hexadecimal characters')
    for key in ('JWT_SIGN', 'CENTRIFUGO_API_KEY', 'CENTRIFUGO_TOKEN_SECRET'):
        if len(values[key]) < 32:
            raise ValueError(key + ' must contain at least 32 characters')
    if not values['SMTP_PORT'].isdigit() or not 1 <= int(values['SMTP_PORT']) <= 65535:
        raise ValueError('invalid SMTP_PORT')
    if values['SMTP_ENCRYPTION'] not in ('ssl', 'tls'):
        raise ValueError('SMTP_ENCRYPTION must be ssl or tls')
    domain = r'[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+'
    if not re.fullmatch(domain + r'(,' + domain + r')*', values['SSO_TRUSTED_DOMAINS']):
        raise ValueError('SSO_TRUSTED_DOMAINS requires comma-separated exact domains')
    config = json.loads(base.read_text())
    config.setdefault('client', {})['token'] = {'hmac_secret_key': values['CENTRIFUGO_TOKEN_SECRET']}
    config['http_api'] = {'key': values['CENTRIFUGO_API_KEY']}
    payloads = {
        'api.env': ''.join(f'{key}={value}\n' for key, value in sorted(values.items())),
        'database.env': f"POSTGRES_PASSWORD={values['DB_PASSWORD']}\n",
        'migration.env': f"DB_PASSWORD={values['DB_PASSWORD']}\n",
        'centrifugo.json': json.dumps(config) + '\n',
    }
    target.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(target, 0o700)
    for name, content in payloads.items():
        fd, temporary = tempfile.mkstemp(dir=target, prefix='.config-')
        try:
            with os.fdopen(fd, 'w') as output:
                output.write(content)
            os.replace(temporary, target / name)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


if __name__ == '__main__':
    os.umask(0o077)
    try:
        render(*(Path(arg) for arg in sys.argv[1:]))
    except (ValueError, OSError):
        # Do not print input values, exception payloads, or secret file contents.
        print('TaskView runtime configuration failed; check required field names and format in the runbook.', file=sys.stderr)
        sys.exit(1)
