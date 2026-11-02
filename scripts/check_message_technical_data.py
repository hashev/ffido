#!/usr/bin/env python3
"""Message diagnostics acceptance on isolated TLS/JAM/SQLite."""
import json
import pathlib
import secrets
import struct
import subprocess
import tempfile
from check_acceptance import ROOT, port, ready, run


def main():
    with tempfile.TemporaryDirectory(prefix='ffido-technical-') as directory:
        root = pathlib.Path(directory).resolve()
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
            'server': {'ip': '0.0.0.0', 'port': number, 'thread_num': 4,
                       'tls_certificate': str(cert), 'tls_private_key': str(key)},
            'ftn': {'areacfg_path': str(root / 'areas.cfg'), 'jam_base_path': str(root),
                    'coordination_lock': str(root / 'hpt.lock'), 'default_encoding': 'CP866',
                    'jam_encoding_overrides': {'other': 'KOI8-R'}},
            'database': {'metadata_path': str(root / 'metadata.db')},
            'point_mail': {'enabled': True, 'ingress_areas': ['INGRESS'], 'egress_area': 'OUT',
                           'points': [{'address': address, 'jam_base': f'points/p{i}'}
                                      for i, address in enumerate(addresses[:2])]},
            'auth': {'hpt_config_path': str(root / 'hpt.cfg'), 'session_key_path': str(root / 'session.key')}}))
        run([str(ROOT / 'build/backend/apps/backend/ffido-admin'), 'provision-mailboxes', str(config)])
        fixtures = []
        def seed(base, conference, chrs_rows):
            headers = bytearray(base.with_suffix('.jhr').read_bytes())
            index, text = bytearray(), bytearray()
            for number, declarations in enumerate(chrs_rows, 1):
                fields = [(4, 0, b'2:1/2 original'), (5, 0, b'2:9/9 external'),
                          *[(2000, 0, value) for value in declarations],
                          (2000, 9, b''), (2000, 0, b'X: \xff\x00\r\n\t\x1b\\'),
                          (2000, 0, b'X: duplicate'), (2000, 0, b'X: duplicate'),
                          (2000, 0, b'URL: https://example.invalid/')]
                subfields = b''.join(struct.pack('<HHI', low, high, len(value)) + value
                                     for low, high, value in fields)
                header = bytearray(76)
                struct.pack_into('<IHHI', header, 0, 0x004d414a, 1, 0, len(subfields))
                struct.pack_into('<I', header, 48, number)
                struct.pack_into('<IIII', header, 52, 0x04000008, 0xffffffff, len(text), 1)
                index += struct.pack('<II', 0xffffffff, len(headers))
                headers += header + subfields
                text += b'\xff'  # Invalid UTF-8 body, never needed for diagnostics.
                fixtures.append({'conference': conference, 'number': number, 'id': f'{base.with_suffix(".jhr").stat().st_dev}:{base.with_suffix(".jhr").stat().st_ino}:{struct.unpack_from("<I", headers, 4)[0]}:1#{number}',
                                 'fields': [[low, high, list(value)] for low, high, value in fields]})
            struct.pack_into('<I', headers, 12, len(chrs_rows))
            base.with_suffix('.jhr').write_bytes(headers)
            base.with_suffix('.jdx').write_bytes(index)
            base.with_suffix('.jdt').write_bytes(text)
        seed(root/'source', 'SOURCE', [[b'CHRS: CP866 2'], [b'CHRS: UNKNOWN 2'],
                                      [b'CHRS: CP866 2', b'CHRS: UTF-8 4'], [b'CHRS: UTF-8 4'], []])
        seed(root/'other', 'OTHER', [[b'CHRS: UNKNOWN 2']])
        seed(root/'points/p0', '@ffido/point/2:1/2.2', [[b'CHRS: CP866 2']])
        import sys
        sys.path.insert(0, str(ROOT/'tools/gateway'))
        from run import config as gateway_config
        from types import SimpleNamespace
        gateway_port = port()
        gateway = gateway_config(SimpleNamespace(origin='https://localhost', certificate=str(cert),
            private_key=str(key), backend_ca=str(ca), backend_host='localhost', backend_port=number,
            port=gateway_port))
        gateway['static_resources']['listeners'][0]['address']['socket_address']['address'] = '0.0.0.0'
        endpoint = gateway['static_resources']['clusters'][0]['load_assignment']['endpoints'][0]['lb_endpoints'][0]
        endpoint['endpoint']['address']['socket_address']['address'] = 'host.docker.internal'
        (root/'envoy.json').write_text(json.dumps(gateway))
        container = 'ffido-technical-' + secrets.token_hex(6)
        run(['docker','run','-d','--name',container,'--user','0','-p',f'127.0.0.1:{gateway_port}:{gateway_port}',
             '-v',f'{root}:{root}:ro','envoyproxy/envoy:v1.29.0','-c',str(root/'envoy.json'),'--concurrency','2'])
        with (root / 'server.log').open('w') as log:
            process = subprocess.Popen([str(ROOT / 'build/backend/apps/backend/fidoback'), str(config)],
                                       stdout=log, stderr=subprocess.STDOUT)
            try:
                ready(process, number)
                ready(process, gateway_port)
                result = run(['dart', 'run', 'tool/message_technical_acceptance.dart'], cwd=ROOT / 'apps/frontend',
                             input=json.dumps({'endpoint': f'https://127.0.0.1:{number}', 'ca': str(ca),
                                               'passwords': passwords, 'root': str(root), 'fixtures': fixtures, 'web': f'https://127.0.0.1:{gateway_port}'}))
                print(result.stdout.strip())
            except Exception:
                print('\n'.join(subprocess.run(['docker','logs',container],capture_output=True,text=True).stderr.splitlines()[-8:]))
                raise
            finally:
                subprocess.run(['docker','rm','-f',container], capture_output=True)
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()


if __name__ == '__main__':
    main()
