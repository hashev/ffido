#!/usr/bin/env python3
"""Isolated native/browser acceptance against the production TLS backend and Envoy."""
import argparse
import base64
import contextlib
import functools
import hashlib
import http.server
import json
import pathlib
import signal
import secrets
import socket
import ssl
import struct
import subprocess
import tempfile
import threading
import time
ROOT = pathlib.Path(__file__).resolve().parents[1]

def run(command, **kwargs):
    try:
        return subprocess.run(command, check=True, text=True, capture_output=True, timeout=60, **kwargs)
    except subprocess.CalledProcessError as error:
        import re
        print(re.sub(r'[0-9a-f]{64}', '<redacted>', error.stderr or ''))
        raise

def port():
    with socket.socket() as value:
        value.bind(('127.0.0.1', 0))
        return value.getsockname()[1]

def ready(process, number):
    until = time.monotonic()+30
    while time.monotonic() < until:
        if process.poll() is not None:
            raise RuntimeError('Test process exited before accepting connections')
        try:
            with socket.create_connection(('127.0.0.1', number), timeout=.2):
                return
        except OSError:
            time.sleep(.05)
    raise RuntimeError('Test process did not bind within 30 seconds')

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        body = b"<!doctype html><html><body>upstream unavailable</body></html>"
        self.send_response(502)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir', type=pathlib.Path, default=ROOT/'build/backend')
    parser.add_argument('--server', type=pathlib.Path, help='Test an unpacked server binary')
    parser.add_argument('--container', help='Test a local Docker image (native TLS and persistent state)')
    parser.add_argument('--native-only', action='store_true')
    parser.add_argument('--envoy')
    parser.add_argument('--chrome')
    parser.add_argument('--hpt')
    args = parser.parse_args()
    if args.container and not args.native_only:
        parser.error('--container requires --native-only')
    if not args.native_only and (not args.envoy or not args.chrome):
        parser.error('--envoy and --chrome are required unless --native-only is selected')
    build = args.build_dir.resolve()
    with tempfile.TemporaryDirectory(prefix='ffido-acceptance-') as directory, contextlib.ExitStack() as cleanup:
        root = pathlib.Path(directory).resolve()
        cert, key = root/'certificate.pem', root/'key.pem'
        ca, ca_key, csr = root/'ca.pem', root/'ca-key.pem', root/'server.csr'
        # Keep certificate extensions independent of the machine's OpenSSL defaults.
        extensions = root/'openssl.cnf'
        extensions.write_text('[req]\nprompt=no\ndistinguished_name=ffido_dn\n'
            '[ffido_dn]\nCN=localhost\n'
            '[ffido_ca]\nbasicConstraints=critical,CA:TRUE\n'
            'keyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\n'
            'authorityKeyIdentifier=keyid:always,issuer\n'
            '[ffido_server]\nbasicConstraints=critical,CA:FALSE\n'
            'keyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n'
            'subjectAltName=DNS:localhost,IP:127.0.0.1\nsubjectKeyIdentifier=hash\n'
            'authorityKeyIdentifier=keyid:always,issuer\n')
        run(['openssl', 'req', '-new', '-x509', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-days', '1', '-subj', '/CN=FFIDO temporary test CA', '-config', str(extensions), '-extensions', 'ffido_ca', '-out', str(ca), '-keyout', str(ca_key)])
        run(['openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-subj', '/CN=localhost', '-config', str(extensions), '-out', str(csr), '-keyout', str(key)])
        run(['openssl', 'x509', '-req', '-in', str(csr), '-CA', str(ca), '-CAkey', str(ca_key), '-CAcreateserial', '-sha256', '-days', '1', '-extfile', str(extensions), '-extensions', 'ffido_server', '-out', str(cert)])
        print(run(['openssl', 'version']).stdout.strip())
        for label, public_certificate in [('CA', ca), ('server', cert)]:
            print(label+': '+run(['openssl', 'x509', '-in', str(public_certificate), '-noout', '-subject', '-issuer', '-serial']).stdout.strip())
            lines = run(['openssl', 'x509', '-in', str(public_certificate), '-noout', '-text']).stdout.splitlines()
            for index, line in enumerate(lines):
                if 'Subject Key Identifier' in line or 'Authority Key Identifier' in line:
                    print(label+' '+line.strip()+' '+lines[index+1].strip())
        run(['openssl', 'verify', '-x509_strict', '-CAfile', str(ca), str(cert)])
        backend_port, gateway_port = port(), port()
        (root/'file.jhr').write_bytes(struct.pack('<7I', 0x004d414a, 123, 0, 0, 0xffffffff, 1, 0)+bytes(996))
        (root/'file.jdx').touch(); (root/'file.jdt').touch()
        (root/'areas.cfg').write_text('EchoArea RU.TEST file -b JAM -d "Isolated test"\n')
        config = root/'config.json'
        config.write_text(json.dumps({'server': {'ip': '127.0.0.1', 'port': backend_port, 'thread_num': 4, 'tls_certificate': str(cert), 'tls_private_key': str(key)}, 'ftn': {'areacfg_path': str(root/'areas.cfg'), 'jam_base_path': str(root), 'coordination_lock': str(root/'hpt.lock'), 'default_encoding': 'UTF-8'}, 'database': {'metadata_path': str(root/'metadata.db')}}))
        password_a, password_b = secrets.token_hex(16), secrets.token_hex(16)
        hpt_auth = root/'hpt-auth.cfg'
        hpt_auth.write_text('Name Fixture\nSysop Test\nLocation Test\nAddress 2:1/1\n'
            'Link A\nAKA 2:1/2\nOurAKA 2:1/1\nSessionPwd '+password_a+'\n'
            'Link B\nAKA 2:1/3\nOurAKA 2:1/1\nSessionPwd '+password_b+'\nEchoArea RU.TEST '+str(root/'file')+' -b JAM 2:1/2 2:1/3\n')
        hpt_auth.chmod(0o600)
        configuration = json.loads(config.read_text())
        configuration['auth'] = {'hpt_config_path': str(hpt_auth), 'session_key_path': str(root/'session.key')}
        if args.container:
            configuration['server']['ip'] = '0.0.0.0'
            # Linux daemon may not see macOS /var aliases; Docker shares /private/tmp.
            root.chmod(0o755)
        config.write_text(json.dumps(configuration))
        def backend_command():
            if not args.container:
                return [str(args.server.resolve() if args.server else build/'apps/backend/fidoback'), str(config)]
            import os
            return ['docker', 'run', '--rm', '--platform', 'linux/amd64',
                    '--user', f'{os.getuid()}:{os.getgid()}',
                    '--name', 'ffido-acceptance-'+root.name, '-v', f'{root}:{root}',
                    '-p', f'127.0.0.1:{backend_port}:{backend_port}', args.container, str(config)]
        def wait_backend(process):
            ready(process, backend_port)
            if args.container:
                # A Docker port proxy can accept TCP before the server is ready.
                context = ssl.create_default_context(cafile=str(ca))
                context.set_alpn_protocols(['h2'])
                until = time.monotonic()+30
                while True:
                    try:
                        with socket.create_connection(('127.0.0.1', backend_port), timeout=1) as transport:
                            with context.wrap_socket(transport, server_hostname='127.0.0.1') as connection:
                                assert connection.selected_alpn_protocol() == 'h2'
                        break
                    except (OSError, ssl.SSLError):
                        if process.poll() is not None or time.monotonic() >= until:
                            raise RuntimeError('Container did not become TLS-ready') from None
                        time.sleep(.1)
        logs = []
        def start(command, name):
            log = cleanup.enter_context((root/name).open('w'))
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
            logs.append(root/name)
            def stop():
                if process.poll() is None:
                    if args.container and command[0] == 'docker':
                        run(['docker', 'stop', '--time', '15', 'ffido-acceptance-'+root.name])
                    else:
                        process.send_signal(signal.SIGTERM)
                    try: process.wait(timeout=15)
                    except subprocess.TimeoutExpired: process.kill(); process.wait(timeout=5)
            cleanup.callback(stop)
            return process
        if args.container:
            command = backend_command()
            for failure in ('tls', 'state'):
                invalid = root/('invalid-'+failure+'.json')
                value = json.loads(config.read_text())
                if failure == 'tls':
                    value['server']['tls_private_key'] = str(root/'missing-key.pem')
                else:
                    # /proc is read-only even for uid 0 on Docker hosts.
                    value['database']['metadata_path'] = '/proc/ffido-smoke/metadata.db'
                invalid.write_text(json.dumps(value))
                result = subprocess.run([*command[:-1], str(invalid)], text=True, capture_output=True, timeout=30)
                assert result.returncode != 0 and result.stderr+result.stdout, 'Invalid '+failure+' accepted'
            print('PASS: missing TLS and unwritable state rejected')
        backend = start(backend_command(), 'backend.log')
        try:
            wait_backend(backend)
            # The fixture listens on IPv4; localhost may resolve to ::1 on CI.
            native_host = '127.0.0.1' if args.native_only else 'localhost'
            tls = ssl.create_default_context(cafile=str(ca))
            tls.set_alpn_protocols(['h2'])
            with socket.create_connection(('127.0.0.1', backend_port), timeout=10) as transport:
                with tls.wrap_socket(transport, server_hostname=native_host) as connection:
                    assert connection.selected_alpn_protocol() == 'h2'
            print('PASS: certificate verification and HTTP/2 ALPN on the configured loopback address')
            native = run(['dart', 'run', 'tool/native_acceptance.dart'], cwd=ROOT/'apps/frontend', input=json.dumps({'endpoint': f'https://{native_host}:{backend_port}', 'ca': str(ca), 'passwordA': password_a, 'passwordB': password_b}))
            print(native.stdout.strip())
            if args.container:
                probe_input = {'endpoint': f'https://{native_host}:{backend_port}', 'ca': str(ca),
                               'passwordA': password_a, 'state': str(root/'probe.json')}
                for phase in ('save', 'restore'):
                    result = run(['dart', 'run', 'tool/container_persistence.dart', phase],
                                 cwd=ROOT/'apps/frontend', input=json.dumps(probe_input))
                    print(result.stdout.strip())
                    run(['docker', 'stop', '--time', '15', 'ffido-acceptance-'+root.name])
                    assert backend.wait(timeout=20) == 0, 'Container did not stop cleanly'
                    if phase == 'save':
                        backend = start(backend_command(), 'container-restart.log')
                        wait_backend(backend)
                print('PASS: container SIGTERM and recreation with durable state')
            if args.native_only:
                return
            js = ROOT/'build/web-acceptance.js'
            if not js.is_file():
                raise RuntimeError('Compile tool/web_acceptance.dart first')
            (root/'acceptance.js').write_bytes(js.read_bytes())
            handler = functools.partial(Handler, directory=str(root))
            server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); context.load_cert_chain(cert, key)
            server.socket = context.wrap_socket(server.socket, server_side=True)
            web_port = server.server_address[1]
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            cleanup.callback(server.server_close); cleanup.callback(server.shutdown)
            origin = f'https://localhost:{web_port}'
            gateway = start(['python3', str(ROOT/'tools/gateway/run.py'), '--envoy', args.envoy, '--origin', origin, '--certificate', str(cert), '--private-key', str(key), '--backend-ca', str(ca), '--backend-port', str(backend_port), '--port', str(gateway_port), '--output', str(root/'envoy.json')], 'gateway.log')
            ready(gateway, gateway_port)
            pubkey = run(['openssl', 'x509', '-in', str(cert), '-pubkey', '-noout']).stdout
            der = subprocess.run(['openssl', 'pkey', '-pubin', '-outform', 'DER'], input=pubkey.encode(), capture_output=True, check=True).stdout
            pin = base64.b64encode(hashlib.sha256(der).digest()).decode()
            for mode in ("allowed", "foreign", "html"):
                foreign = mode == "foreign"
                html_response = mode == "html"
                html = '<!doctype html><meta charset="utf-8"><body id="result">RUNNING<script>'
                html += 'window.ffidoEndpoint='+json.dumps(f'https://localhost:{web_port if html_response else gateway_port}')+';'
                html += 'window.ffidoPasswordA='+json.dumps(password_a)+';window.ffidoPasswordB='+json.dumps(password_b)+';'
                html += 'window.ffidoHtmlResponse='+json.dumps(html_response)+';'
                html += 'window.ffidoRejectOrigin='+json.dumps(foreign)+';window.ffidoReport=(value)=>document.getElementById("result").textContent=value;'
                html += '</script><script src="acceptance.js"></script>'
                (root/'index.html').write_text(html); (root/'index.html').chmod(0o600)
                profile = root/('chrome-'+mode)
                url = f'https://{"127.0.0.1" if foreign else "localhost"}:{web_port}/index.html'
                browser = run([args.chrome, '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check', '--user-data-dir='+str(profile), '--ignore-certificate-errors-spki-list='+pin, '--virtual-time-budget=20000', '--dump-dom', url])
                expected = {'foreign': 'PASS: foreign origin denied', 'html': 'PASS: HTML gateway response is a controlled named RPC error', 'allowed': 'PASS: browser gRPC-Web Unicode Empty identity retry and trailers'}[mode]
                if expected not in browser.stdout:
                    # Do not print the page: its temporary bootstrap includes test tokens.
                    import re
                    result = re.search(r'<body[^>]*>([^<]*)', browser.stdout)
                    raise RuntimeError('Browser acceptance failed: '+(result.group(1) if result else 'no result'))
                print(expected)
            backend.send_signal(signal.SIGTERM); assert backend.wait(timeout=15) == 0
            header = (root/'file.jhr').read_bytes(); active = struct.unpack_from('<I', header, 12)[0]
            assert active == 4 and (root/'file.jdx').stat().st_size == 4*8
            print('PASS: four confirmed JAM messages; no duplicate retries; bounded shutdown')
            # Independent ACL phase; keep the original four-message HPT fixture unchanged.
            original_auth = hpt_auth.read_text()
            extra_areas = []
            for tag in ('FULL', 'READ', 'WRITE', 'PRIVATE', 'HIDDEN'):
                base = root/('acl-'+tag.lower())
                base.with_suffix('.jhr').write_bytes(struct.pack('<7I', 0x004d414a, 123, 0, 0, 0xffffffff, 1, 0)+bytes(996))
                base.with_suffix('.jdt').touch(); base.with_suffix('.jdx').touch()
                extra_areas.append('EchoArea ACL.'+tag+' '+str(base)+' -b JAM')
            with (root/'areas.cfg').open('a') as out:
                out.write('\n'.join(extra_areas)+'\n')
            acl_lines = [line+(' 2:1/2 2:1/3' if 'ACL.FULL ' in line else
                                    '' if 'ACL.HIDDEN ' in line else ' 2:1/2') for line in extra_areas]
            full_auth = original_auth+'\n'.join(acl_lines)+'\nReadOnly 2:1/2 ACL.READ\nWriteOnly 2:1/2 ACL.WRITE\n'
            hpt_auth.write_text(full_auth)
            backend = start([str(args.server.resolve() if args.server else build/'apps/backend/fidoback'), str(config)], 'acl-initial.log')
            ready(backend, backend_port)
            acl_input = {'endpoint': f'https://localhost:{backend_port}', 'ca': str(ca),
                         'passwordA': password_a, 'passwordB': password_b, 'phase': 'initial'}
            result = run(['dart', 'run', 'tool/echo_access_acceptance.dart'], cwd=ROOT/'apps/frontend', input=json.dumps(acl_input))
            saved = json.loads(result.stdout.split('FFIDO_ACL_RESULT:', 1)[1])
            backend.send_signal(signal.SIGTERM); assert backend.wait(timeout=15) == 0
            for phase in ('revoked', 'restored'):
                hpt_auth.write_text(full_auth.replace('ACL.FULL '+str(root/'acl-full')+' -b JAM 2:1/2 2:1/3',
                                                       'ACL.FULL '+str(root/'acl-full')+' -b JAM 2:1/3') if phase == 'revoked' else full_auth)
                backend = start([str(args.server.resolve() if args.server else build/'apps/backend/fidoback'), str(config)], 'acl-'+phase+'.log')
                ready(backend, backend_port)
                run(['dart', 'run', 'tool/echo_access_acceptance.dart'], cwd=ROOT/'apps/frontend',
                    input=json.dumps({**acl_input, **saved, 'phase': phase}))
                backend.send_signal(signal.SIGTERM); assert backend.wait(timeout=15) == 0
            print('PASS: HPT echo ACL; two points; read-only/write-only; direct RPC denial; session revocation and read-state restoration')
            if args.hpt:
                for name in ('inbound', 'protinbound', 'outbound', 'tmpin', 'tmpout', 'logs', 'dupes', 'nodelist'):
                    (root/name).mkdir()
                lines = ['Name FFIDO isolated acceptance', 'Sysop Test', 'Location Test', 'Address 2:1/2']
                for keyword, name in [('Inbound','inbound'),('ProtInbound','protinbound'),('Outbound','outbound'),('TempInbound','tmpin'),('TempOutbound','tmpout'),('LogFileDir','logs'),('DupeHistoryDir','dupes'),('NodelistDir','nodelist')]:
                    lines.append(keyword+' '+str(root/name))
                lines += ['MsgBaseDir '+str(root), 'EchoTossLog '+str(root/'logs/toss.log'), 'ImportLog '+str(root/'logs/import.log'), 'Link Downlink', 'AKA 2:1/4', 'OurAKA 2:1/2', 'AllowEmptyPktPwd on', 'EchoMailFlavour direct']
                for keyword, name in [('NetmailArea','NETMAIL'),('BadArea','BAD'),('DupeArea','DUPE')]:
                    lines.append(keyword+' '+name+' '+str(root/name.lower())+' -b JAM')
                lines.append('EchoArea RU.TEST '+str(root/'file')+' -b JAM -a 2:1/2 2:1/4')
                hpt_config = root/'hpt.cfg'; hpt_config.write_text('\n'.join(lines)+'\n')
                run(['python3', str(ROOT/'scripts/run_hpt.py'), '--config', str(config), '--', args.hpt, '-c', str(hpt_config), 'scan', '-w', '-a', 'RU.TEST'])
                packets = b''.join(path.read_bytes() for path in (root/'outbound').rglob('*') if path.is_file())
                assert packets.count(b'\x01MSGID: ') == 4 and packets.count(b'\x01REPLY: ') == 2
                assert 'Привет, мир!'.encode() in packets and 'Ответ по gRPC'.encode() in packets
                assert struct.unpack_from('<I', (root/'file.jhr').read_bytes(), 12)[0] == 4
                print('PASS: HPT exported all four native/browser messages with Unicode and FTN replies')

        except Exception:
            for log in logs:
                print(log.name+': '+log.read_text())
            raise

if __name__ == '__main__':
    main()
