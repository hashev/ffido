#!/usr/bin/env python3
"""Native TLS search acceptance on temporary CP866/UTF-8 JAM areas only."""
import json
import pathlib
import secrets
import struct
import subprocess
import tempfile
from check_acceptance import ROOT, port, ready, run


def main():
    with tempfile.TemporaryDirectory(prefix='ffido-message-search-') as directory:
        root = pathlib.Path(directory)
        cert, key = root / 'cert.pem', root / 'key.pem'
        ca, ca_key, csr = root/'ca.pem', root/'ca-key.pem', root/'server.csr'
        extensions = root/'openssl.cnf'
        extensions.write_text('[req]\nprompt=no\ndistinguished_name=dn\n[dn]\nCN=localhost\n'
            '[ca]\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n'
            'subjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always,issuer\n'
            '[server]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\n'
            'extendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n'
            'subjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always,issuer\n')
        run(['openssl','req','-new','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=FFIDO test CA',
            '-config',str(extensions),'-extensions','ca','-out',str(ca),'-keyout',str(ca_key)])
        run(['openssl','req','-new','-newkey','rsa:2048','-nodes','-subj','/CN=localhost','-config',str(extensions),
            '-out',str(csr),'-keyout',str(key)])
        run(['openssl','x509','-req','-in',str(csr),'-CA',str(ca),'-CAkey',str(ca_key),'-CAcreateserial','-days','1',
            '-extfile',str(extensions),'-extensions','server','-out',str(cert)])
        number = port()
        areas = []
        for tag in ['CP866', 'UTF8']:
            base = root / tag.lower()
            base.with_suffix('.jhr').write_bytes(struct.pack('<7I', 0x004d414a, 123, 0, 0, 0xffffffff, 1, 0) + bytes(996))
            base.with_suffix('.jdt').touch()
            base.with_suffix('.jdx').touch()
            areas.append(f'EchoArea RU.{tag} {base} -b JAM')
        (root / 'areas.cfg').write_text('\n'.join(areas) + '\n')
        passwords = [secrets.token_hex(16), secrets.token_hex(16)]
        (root / 'hpt.cfg').write_text('Name Fixture\nSysop Test\nLocation Test\nAddress 2:1/1\n' +
            ''.join(f'Link Test{i}\nAKA 2:1/{i + 2}\nOurAKA 2:1/1\nSessionPwd {password}\n'
                    for i, password in enumerate(passwords)) +
            '\n'.join(area + ' 2:1/2 2:1/3' for area in areas) + '\n')
        (root / 'hpt.cfg').chmod(0o600)
        config = root / 'config.json'
        config.write_text(json.dumps({
            'server': {'ip': '127.0.0.1', 'port': number, 'thread_num': 4,
                       'tls_certificate': str(cert), 'tls_private_key': str(key)},
            'ftn': {'areacfg_path': str(root / 'areas.cfg'), 'jam_base_path': str(root),
                    'coordination_lock': str(root / 'hpt.lock'), 'default_encoding': 'CP866',
                    'jam_encoding_overrides': {'utf8': 'UTF-8'}},
            'database': {'metadata_path': str(root / 'metadata.db')},
            'auth': {'hpt_config_path': str(root / 'hpt.cfg'), 'session_key_path': str(root / 'session.key')}}))
        with (root / 'server.log').open('w') as log:
            process = subprocess.Popen([str(ROOT / 'build/backend/apps/backend/fidoback'), str(config)],
                                       stdout=log, stderr=subprocess.STDOUT)
            try:
                ready(process, number)
                result = run(['dart', 'run', 'tool/message_search_acceptance.dart'], cwd=ROOT / 'apps/frontend',
                             input=json.dumps({'endpoint': f'https://127.0.0.1:{number}', 'ca': str(ca),
                                               'passwords': passwords}))
                print(result.stdout.strip())
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()


if __name__ == '__main__':
    main()
