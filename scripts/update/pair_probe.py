"""Bounded HTTPS/gRPC-Web/CORS acceptance probe without session diagnostics."""
import argparse
import http.client
import json
import ssl
import struct
import urllib.parse


class GrpcError(ValueError):
    def __init__(self, status):
        self.status = status
        super().__init__('Unexpected gRPC status '+str(status)+' in acceptance probe')


def call(endpoint, ca, origin, method, payload=b'', token=None, expected_status=0):
    uri = urllib.parse.urlsplit(endpoint)
    if (uri.scheme != 'https' or not uri.hostname or uri.username or uri.password
            or uri.path or uri.query or uri.fragment):
        raise ValueError('Expected an HTTPS origin')
    connection = http.client.HTTPSConnection(uri.hostname, uri.port or 443,
        context=ssl.create_default_context(cafile=ca), timeout=10)
    headers = {'content-type': 'application/grpc-web+proto', 'x-grpc-web': '1', 'origin': origin}
    if token:
        headers['authorization'] = 'Bearer '+token
    try:
        connection.request('POST', '/ffido.v1.Ffido/'+method,
                           b'\0'+struct.pack('>I', len(payload))+payload, headers)
        response = connection.getresponse()
        if response.status != 200 or response.getheader('access-control-allow-origin') != origin:
            raise ValueError('Gateway HTTPS/CORS acceptance failed')
        data = response.read(1024*1024+1)
        status = response.getheader('grpc-status')
    finally:
        connection.close()
    if len(data) > 1024*1024:
        raise ValueError('Oversized gateway response')
    messages = []
    while data:
        if len(data) < 5:
            raise ValueError('Truncated gRPC-Web response')
        flag, size = data[0], struct.unpack('>I', data[1:5])[0]
        if size > len(data)-5:
            raise ValueError('Truncated gRPC-Web frame')
        value, data = data[5:5+size], data[5+size:]
        if flag == 0:
            messages.append(value)
        elif flag == 128:
            trailers = dict(x.split(':', 1) for x in value.decode('ascii').split('\r\n') if ':' in x)
            status = trailers.get('grpc-status', status)
        else:
            raise ValueError('Unsupported gRPC-Web response')
    if status is None or len(messages) > 1:
        raise ValueError('Missing gRPC status or non-unary response')
    status = status.strip()
    if not status.isascii() or not status.isdigit() or len(status) > 2 or int(status) > 16:
        raise ValueError('Invalid gRPC status')
    if int(status) != expected_status:
        raise GrpcError(int(status))
    return messages[0] if messages else b''


def gateway(endpoint, ca, origin):
    call(endpoint, ca, origin, 'GetServerCapabilities')
    uri = urllib.parse.urlsplit(endpoint)
    connection = http.client.HTTPSConnection(uri.hostname, uri.port or 443,
        context=ssl.create_default_context(cafile=ca), timeout=10)
    try:
        connection.request('OPTIONS', '/ffido.v1.Ffido/GetServerCapabilities', headers={
            'origin': 'https://not-allowed.invalid', 'access-control-request-method': 'POST',
            'access-control-request-headers': 'content-type,x-grpc-web'})
        response = connection.getresponse()
        if response.status != 403 or response.getheader('access-control-allow-origin'):
            raise ValueError('Gateway permits an untrusted origin')
        response.read()
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--endpoint', required=True)
    parser.add_argument('--ca', required=True)
    parser.add_argument('--origin', required=True)
    args = parser.parse_args()
    gateway(args.endpoint, args.ca, args.origin)
    print('HTTPS/gRPC-Web/CORS accepted')


if __name__ == '__main__':
    main()
