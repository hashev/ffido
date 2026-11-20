"""Run signed synthetic Telegram RPCs through an isolated TLS Envoy gateway."""
import base64
import http.client
import json
import pathlib
import socket
import ssl
import struct
import subprocess
import sys
import time
from types import SimpleNamespace

ROOT = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'tools/gateway'))
from run import config


def call(port: int, trust: ssl.SSLContext, request: dict[str, str]) -> dict[str, int | str]:
    payload = base64.b64decode(request['payload'], validate=True)
    headers = {'content-type': 'application/grpc-web+proto', 'x-grpc-web': '1', 'origin': 'https://localhost'}
    if request.get('token'):
        headers['authorization'] = 'Bearer ' + request['token']
    connection = http.client.HTTPSConnection('localhost', port, context=trust, timeout=10)
    try:
        connection.request('POST', '/ffido.v1.Ffido/' + request['method'],
                           b'\0' + struct.pack('>I', len(payload)) + payload, headers)
        response = connection.getresponse()
        if response.status != 200:
            raise RuntimeError('Unexpected gateway HTTP status')
        data = response.read(1024 * 1024 + 1)
        if len(data) > 1024 * 1024:
            raise RuntimeError('Oversized gateway response')
        status = response.getheader('grpc-status')
    finally:
        connection.close()
    messages = []
    while data:
        if len(data) < 5:
            raise RuntimeError('Truncated gRPC-Web frame')
        flags, size = data[0], struct.unpack('>I', data[1:5])[0]
        if size > len(data) - 5:
            raise RuntimeError('Invalid gRPC-Web frame length')
        value, data = data[5:5 + size], data[5 + size:]
        if flags == 128:
            trailers = dict(line.split(':', 1) for line in value.decode('ascii').split('\r\n') if ':' in line)
            status = trailers.get('grpc-status', status)
        elif flags == 0:
            messages.append(value)
        else:
            raise RuntimeError('Unsupported gRPC-Web frame')
    if status is None or len(messages) > 1:
        raise RuntimeError('Missing status or non-unary gateway response')
    return {'status': int(status), 'payload': base64.b64encode(messages[0] if messages else b'').decode('ascii')}


def main() -> None:
    manifest_path = pathlib.Path(sys.argv[1])
    manifest = json.loads(manifest_path.read_text())
    root = manifest_path.parent
    with socket.socket() as available:
        available.bind(('127.0.0.1', 0))
        port = available.getsockname()[1]
    certificate = root / 'certificate.pem'
    args = SimpleNamespace(origin='https://localhost', certificate=str(certificate),
        private_key=str(root / 'key.pem'), backend_ca=str(certificate), backend_host='localhost',
        backend_port=manifest['backend_port'], port=port)
    gateway = root / 'telegram-envoy.json'
    gateway.write_text(json.dumps(config(args)))
    with (root / 'telegram-envoy.log').open('w') as log:
        process = subprocess.Popen([manifest['envoy'], '-c', str(gateway), '--concurrency', '2'], stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 15
            while True:
                if process.poll() is not None:
                    raise RuntimeError('Gateway exited before readiness')
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=.2):
                        break
                except OSError:
                    if time.monotonic() >= deadline:
                        raise RuntimeError('Gateway readiness timeout')
                    time.sleep(.05)
            trust = ssl.create_default_context(cafile=str(certificate))
            results = [call(port, trust, request) for request in manifest['requests']]
            (root / 'telegram-web-results.json').write_text(json.dumps(results))
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


if __name__ == '__main__':
    main()
