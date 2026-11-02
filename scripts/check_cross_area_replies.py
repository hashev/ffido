#!/usr/bin/env python3
"""Cross-area reply acceptance on isolated TLS/JAM/point mailboxes."""
import json
import pathlib
import secrets
import struct
import subprocess
import tempfile
from check_acceptance import ROOT, port, ready, run


def main():
    with tempfile.TemporaryDirectory(prefix='ffido-cross-area-') as directory:
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
        for tag in ['SOURCE', 'OTHER', 'INGRESS', 'OUT']:
            base = root / tag.lower()
            base.with_suffix('.jhr').write_bytes(struct.pack('<7I', 0x004d414a, 123, 0, 0, 0xffffffff, 1, 0) + bytes(996))
            base.with_suffix('.jdt').touch()
            base.with_suffix('.jdx').touch()
            areas.append(f'{"EchoArea" if tag in ("SOURCE", "OTHER") else "NetmailArea"} {tag} {base} -b JAM')
        (root / 'areas.cfg').write_text('\n'.join(areas[:2]) + '\n')
        passwords = [secrets.token_hex(16) for _ in range(3)]
        addresses = ['2:1/2.2', '2:1/2.3', '2:1/4']
        (root / 'hpt.cfg').write_text('Name Fixture\nSysop Test\nLocation Test\nAddress 2:1/2\n' +
            ''.join(f'Link Test{i}\nAKA {address}\nOurAKA 2:1/2\nSessionPwd {password}\n'
                    for i, (address, password) in enumerate(zip(addresses, passwords))) +
            '\n'.join(area + (' 2:1/2.2 2:1/2.3 2:1/4' if i < 2 else ' -dupeCheck off')
                       for i, area in enumerate(areas)) + '\n')
        with (root / 'hpt.cfg').open('a') as hpt:
            for directive, folder in [('Inbound', 'inbound'), ('ProtInbound', 'protinbound'),
                                      ('Outbound', 'outbound'), ('TempInbound', 'tmpin'),
                                      ('TempOutbound', 'tmpout'), ('LogFileDir', 'logs'),
                                      ('DupeHistoryDir', 'dupes'), ('NodelistDir', 'nodelist')]:
                (root/folder).mkdir()
                hpt.write(f'{directive} {root/folder}\n')
            hpt.write('KeepTrsMail on\nPackNetMailOnScan off\nRoute nopack 2:1/2.2 2:1/2.3\nRoute normal noroute *\n')
        (root / 'hpt.cfg').chmod(0o600)
        config = root / 'config.json'
        config.write_text(json.dumps({
            'server': {'ip': '127.0.0.1', 'port': number, 'thread_num': 4,
                       'tls_certificate': str(cert), 'tls_private_key': str(key)},
            'ftn': {'areacfg_path': str(root / 'areas.cfg'), 'jam_base_path': str(root),
                    'coordination_lock': str(root / 'hpt.lock'), 'default_encoding': 'CP866',
                    'jam_encoding_overrides': {}},
            'database': {'metadata_path': str(root / 'metadata.db')},
            'point_mail': {'enabled': True, 'ingress_areas': ['INGRESS'], 'egress_area': 'OUT',
                           'points': [{'address': address, 'jam_base': f'points/p{i}'}
                                      for i, address in enumerate(addresses[:2])]},
            'auth': {'hpt_config_path': str(root / 'hpt.cfg'), 'session_key_path': str(root / 'session.key')}}))
        run([str(ROOT / 'build/backend/apps/backend/ffido-admin'), 'provision-mailboxes', str(config)])
        with (root / 'server.log').open('w') as log:
            process = subprocess.Popen([str(ROOT / 'build/backend/apps/backend/fidoback'), str(config)],
                                       stdout=log, stderr=subprocess.STDOUT)
            try:
                ready(process, number)
                result = run(['dart', 'run', 'tool/cross_area_reply_acceptance.dart'], cwd=ROOT / 'apps/frontend',
                             input=json.dumps({'endpoint': f'https://127.0.0.1:{number}', 'ca': str(ca),
                                               'passwords': passwords}))
                print(result.stdout.strip())
                # Independent JAM wire checks: each reply is record 2, with no parent or REPLY subfield.
                import sys
                sys.path.insert(0, str(ROOT / 'apps/backend/tests/support'))
                from hpt_routing_fixture import records
                for base in (root/'other', root/'points/p0'):
                    rows = records(base)
                    assert len(rows) == 2, f'Unexpected duplicate in {base.name}'
                    flags, fields, body = rows[1]
                    index = base.with_suffix('.jdx').read_bytes()
                    offset = struct.unpack_from('<I', index, 12)[0]
                    assert struct.unpack_from('<I', base.with_suffix('.jhr').read_bytes(), offset + 24)[0] == 0
                    assert not fields.get(5), 'Foreign FTN REPLY'
                assert len(records(root/'source')) == 1, 'Source was modified'
                print('Independent JAM oracle: standalone replies, no duplicates, source count unchanged')
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
