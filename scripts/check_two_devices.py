#!/usr/bin/env python3
"""Exercise real Android/macOS plugins and persisted sessions on isolated JAM/HPT.

Requires a booted Android emulator and the macOS Flutter target.
No working FTN data or user account credentials are used.
"""
import argparse
import base64
import json
import os
import pathlib
import secrets
import signal
import struct
import subprocess
import tempfile

from check_acceptance import ROOT, port, ready, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--android', default='emulator-5554')
    parser.add_argument('--build-dir', type=pathlib.Path, default=ROOT/'build/backend')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='ffido-two-devices-') as temporary:
        root = pathlib.Path(temporary)
        ca, ca_key, cert, key = (root/name for name in ('ca.pem', 'ca-key.pem', 'cert.pem', 'key.pem'))
        csr = root/'server.csr'
        run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', '-subj', '/CN=FFIDO fixture CA', '-addext', 'basicConstraints=critical,CA:TRUE', '-addext', 'keyUsage=critical,keyCertSign,cRLSign', '-out', str(ca), '-keyout', str(ca_key)])
        run(['openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes', '-subj', '/CN=localhost', '-out', str(csr), '-keyout', str(key)])
        extensions = root/'extensions.cnf'
        extensions.write_text('basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n')
        run(['openssl', 'x509', '-req', '-in', str(csr), '-CA', str(ca), '-CAkey', str(ca_key), '-CAcreateserial', '-days', '1', '-extfile', str(extensions), '-out', str(cert)])
        password = secrets.token_hex(16)
        (root/'hpt.cfg').write_text('Name Fixture\nSysop Test\nLocation Test\nAddress 2:1/1\nLink Client\nAKA 2:1/2\nOurAKA 2:1/1\nSessionPwd '+password+'\nEchoArea RU.TEST '+str(root/'file')+' -b JAM 2:1/2\n')
        (root/'hpt.cfg').chmod(0o600)
        (root/'file.jhr').write_bytes(struct.pack('<7I', 0x004d414a, 123, 0, 0, 0xffffffff, 1, 0)+bytes(996))
        (root/'file.jdx').touch(); (root/'file.jdt').touch()
        (root/'areas.cfg').write_text('EchoArea RU.TEST file -b JAM\n')
        number = port()
        config = {'server': {'ip': '127.0.0.1', 'port': number, 'thread_num': 4,
                            'tls_certificate': str(cert), 'tls_private_key': str(key)},
                  'auth': {'hpt_config_path': str(root/'hpt.cfg'), 'session_key_path': str(root/'session.key')},
                  'ftn': {'areacfg_path': str(root/'areas.cfg'), 'jam_base_path': str(root),
                          'coordination_lock': str(root/'hpt.lock'), 'default_encoding': 'UTF-8'},
                  'database': {'metadata_path': str(root/'metadata.db')}}
        (root/'config.json').write_text(json.dumps(config))
        with (root/'backend.log').open('w') as log:
            server = subprocess.Popen([str(args.build_dir.resolve()/'apps/backend/fidoback'), str(root/'config.json')], stdout=log, stderr=subprocess.STDOUT)
            try:
                ready(server, number)
                for phase, device in [('laptop_setup', 'macos'), ('phone_send', args.android),
                                      ('laptop_continue', 'macos'), ('phone_logout', args.android),
                                      ('laptop_check', 'macos')]:
                    defines = {'FFIDO_TEST_PHASE': phase, 'FFIDO_TEST_ENDPOINT': f'https://localhost:{number}',
                               'FFIDO_TEST_HOST': 'localhost' if device == 'macos' else '10.0.2.2',
                               'FFIDO_TEST_CA': base64.b64encode(ca.read_bytes()).decode()}
                    if phase in ('laptop_setup', 'phone_send'):
                        defines['FFIDO_TEST_PASSWORD'] = password
                    (root/'defines.json').write_text(json.dumps(defines))
                    (root/'defines.json').chmod(0o600)
                    result = subprocess.run(['flutter', 'drive', '--driver=test_driver/two_devices.dart',
                        '--target=integration_test/two_devices_test.dart', '--keep-app-running', '-d', device,
                        '--no-pub', '--dart-define-from-file='+str(root/'defines.json')], cwd=ROOT/'apps/frontend',
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=300)
                    # The default Flutter test cleanup uninstalls Android apps.
                    # Preserve app data and stop only the process between phases.
                    if device == 'macos':
                        binary = str(ROOT/'apps/frontend/build/macos/Build/Products/Debug/fido.app/Contents/MacOS/fido')
                        for entry in subprocess.run(['ps', '-axo', 'pid=,comm='], capture_output=True, text=True).stdout.splitlines():
                            fields = entry.strip().split(None, 1)
                            if len(fields) == 2 and fields[1] == binary:
                                try:
                                    os.kill(int(fields[0]), signal.SIGTERM)
                                except ProcessLookupError:
                                    pass
                    else:
                        subprocess.run(['adb', '-s', device, 'shell', 'am', 'force-stop', 'io.github.hashev.ffido'], check=True)
                    if result.returncode:
                        print(result.stdout.replace(password, '<redacted>'))
                        raise RuntimeError('Two-device phase failed: '+phase)
                    print('PASS: '+phase+' ('+device+')', flush=True)
            finally:
                server.terminate()
                try:
                    server.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    server.kill(); server.wait(timeout=5)


if __name__ == '__main__':
    main()
