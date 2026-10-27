#!/usr/bin/env python3
"""Isolated TLS native/gRPC-Web crosspost and lost-response/restart smoke.

Requires the project's Dart SDK, protoc, built fidoback and a local Envoy binary.
All credentials and FTN/SQLite files live in a temporary directory.
"""
import argparse
import contextlib
import http.client
import json
import pathlib
import re
import secrets
import signal
import ssl
import struct
import subprocess
import tempfile

from check_acceptance import ROOT, port, ready, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir', type=pathlib.Path, default=ROOT/'build/backend')
    parser.add_argument('--envoy', required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='ffido-crosspost-') as directory, contextlib.ExitStack() as cleanup:
        root = pathlib.Path(directory)
        cert, key = root/'cert.pem', root/'key.pem'
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
        backend_port, gateway_port = port(), port()
        areas, hpt_areas = [], []
        for tag in ('ONE', 'TWO', 'THREE'):
            base = root/tag.lower()
            base.with_suffix('.jhr').write_bytes(struct.pack('<7I', 0x004d414a, 123, 0, 0, 0xffffffff, 1, 0)+bytes(996))
            base.with_suffix('.jdt').touch(); base.with_suffix('.jdx').touch()
            area = 'EchoArea RU.'+tag+' '+str(base)+' -b JAM'
            areas.append(area); hpt_areas.append(area+' 2:1/2')
        (root/'areas.cfg').write_text('\n'.join(areas)+'\n')
        password = secrets.token_hex(16)
        (root/'hpt.cfg').write_text('Name Fixture\nSysop Test\nLocation Test\nAddress 2:1/1\n'
            'Link Alice\nAKA 2:1/2\nOurAKA 2:1/1\nSessionPwd '+password+'\n'+'\n'.join(hpt_areas)+'\n')
        (root/'hpt.cfg').chmod(0o600)
        config = root/'config.json'
        config.write_text(json.dumps({'server': {'ip':'127.0.0.1','port':backend_port,'thread_num':4,
            'tls_certificate':str(cert),'tls_private_key':str(key)},'ftn':{'areacfg_path':str(root/'areas.cfg'),
            'jam_base_path':str(root),'coordination_lock':str(root/'hpt.lock'),'default_encoding':'UTF-8'},
            'database':{'metadata_path':str(root/'metadata.db')},
            'auth':{'hpt_config_path':str(root/'hpt.cfg'),'session_key_path':str(root/'session.key')}}))

        def start(command, name):
            log = cleanup.enter_context((root/name).open('w'))
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
            def stop():
                if process.poll() is None:
                    process.send_signal(signal.SIGTERM)
                    try: process.wait(timeout=15)
                    except subprocess.TimeoutExpired: process.kill(); process.wait(timeout=5)
            cleanup.callback(stop)
            return process

        def backend():
            process = start([str(args.build_dir.resolve()/'apps/backend/fidoback'),str(config)],'backend.log')
            ready(process,backend_port)
            return process

        def restart(process):
            process.send_signal(signal.SIGTERM)
            assert process.wait(timeout=15) == 0
            return backend()

        def native(state=None):
            value = {'endpoint':f'https://127.0.0.1:{backend_port}','ca':str(ca),'password':password}
            if state: value.update(state)
            result = run(['dart','run','tool/crosspost_acceptance.dart'],cwd=ROOT/'apps/frontend',input=json.dumps(value))
            return json.loads(result.stdout.strip().splitlines()[-1])

        process = backend()
        state = native()  # Discard the response at the caller; retry the same operation after process restart.
        process = restart(process)
        assert native(state) == state
        print('PASS: native TLS three copies, stable MSGID and references after lost response/restart')
        origin = 'https://localhost:9443'
        gateway = start(['python3',str(ROOT/'tools/gateway/run.py'),'--envoy',args.envoy,'--origin',origin,
            '--certificate',str(cert),'--private-key',str(key),'--backend-ca',str(ca),'--backend-port',str(backend_port),
            '--port',str(gateway_port),'--output',str(root/'envoy.json')],'gateway.log')
        ready(gateway,gateway_port)

        def web(method, request_type, response_type, text):
            encoded = subprocess.run(['protoc','--proto_path='+str(ROOT/'contracts'),'--encode=ffido.v1.'+request_type,
                'ffido/v1/ffido.proto'],input=text.encode(),check=True,capture_output=True).stdout
            body = b'\0'+struct.pack('>I',len(encoded))+encoded
            connection = http.client.HTTPSConnection('localhost',gateway_port,context=ssl.create_default_context(cafile=str(ca)))
            connection.request('POST','/ffido.v1.Ffido/'+method,body,{'content-type':'application/grpc-web+proto',
                'x-grpc-web':'1','origin':origin,'authorization':'Bearer '+state['token']})
            response = connection.getresponse(); payload=response.read(); connection.close()
            assert response.status == 200
            messages, trailers = [], b''
            while payload:
                flag, size = payload[0], struct.unpack('>I',payload[1:5])[0]
                frame,payload=payload[5:5+size],payload[5+size:]
                if flag & 128: trailers += frame
                else: messages.append(frame)
            status = dict(line.split(b':', 1) for line in trailers.splitlines() if b':' in line)
            assert status.get(b'grpc-status', b'').strip() == b'0' and len(messages) == 1
            return subprocess.run(['protoc','--proto_path='+str(ROOT/'contracts'),'--decode=ffido.v1.'+response_type,
                'ffido/v1/ffido.proto'],input=messages[0],check=True,capture_output=True).stdout.decode()

        request = 'message { conference_id:"RU.ONE" operation_id:"web-crosspost" to_name:"All" subject:"Crosspost" body:"Text" } additional_conference_ids:"RU.TWO" additional_conference_ids:"RU.THREE"'
        first = web('CreateCrosspost','CreateCrosspostRequest','CreateCrosspostResponse',request)
        assert 'complete: true' in first and 'total: 3' in first and first.count('ftn_message_id:') == 3
        process = restart(process)
        repeated = web('CreateCrosspost','CreateCrosspostRequest','CreateCrosspostResponse',request)
        assert first == repeated
        references = re.findall(r'message \{\s*conference_id: "([^"]+)"\s*message_id: "([^"]+)"\s*\}',repeated)
        assert len(references) == 3
        for area, message in references:
            detail = web('GetMessage','MessageReference','Message',f'conference_id:"{area}" message_id:"{message}"')
            assert '* Originally in RU.ONE\\n* Crossposted in RU.THREE\\n* Crossposted in RU.TWO\\n\\nText' in detail
        for tag in ('one','two','three'):
            assert struct.unpack_from('<I',(root/(tag+'.jhr')).read_bytes(),12)[0] == 2
        print('PASS: Envoy gRPC-Web three copies, GoldED body and lost-response/restart retry without duplicates')


if __name__ == '__main__':
    main()
