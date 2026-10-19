#!/usr/bin/env python3
"""UUE integration fixture. Only newly created temporary HPT/JAM/SQLite/TLS files."""
import argparse
import base64
import binascii
import hashlib
import json
import os
import pathlib
import signal
import struct
import subprocess
import sys
import tempfile
import zlib

from check_acceptance import ROOT, port, ready, run
sys.path.insert(0, str(ROOT / 'apps/backend/tests/support'))
from hpt_routing_fixture import RoutingFixture, records
from point_cycle_fixture import empty_jam


def create(build, hpt):
    temporary = pathlib.Path(tempfile.mkdtemp(prefix='ffido-uue-'))
    fixture = RoutingFixture(temporary / 'fixture', 'nopack', hpt, str(ROOT/'scripts/run_hpt.py'))
    root = fixture.root
    config = '\n'.join(line for line in (root/'hpt.cfg').read_text().splitlines() if not line.startswith('LocalArea P1'))+'\n'
    config = config.replace('-dupeCheck del', '-dupeCheck off')
    config += f'PackNetMailOnScan off\nNetmailArea OUT {root}/out -b JAM -dupeCheck off\n'
    config += f'EchoArea ECHO {root}/echo -b JAM 2:1/2.1 2:1/2.2 2:1/9\n'
    (root/'hpt.cfg').write_text(config)
    for name in ('ingress','out','bad','dupe','echo'): empty_jam(root/name)
    (root/'areas.cfg').write_text(f'EchoArea ECHO {root}/echo -b JAM\n')
    ca, cert, key = root/'ca.pem', root/'cert.pem', root/'key.pem'
    run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=FFIDO UUE fixture CA',
         '-addext','basicConstraints=critical,CA:TRUE','-keyout',str(root/'ca.key'),'-out',str(ca)])
    run(['openssl','req','-new','-newkey','rsa:2048','-nodes','-subj','/CN=localhost','-keyout',str(key),'-out',str(root/'cert.csr')])
    (root/'extensions').write_text('basicConstraints=critical,CA:FALSE\nsubjectAltName=DNS:localhost,IP:127.0.0.1\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n')
    run(['openssl','x509','-req','-days','1','-in',str(root/'cert.csr'),'-CA',str(ca),'-CAkey',str(root/'ca.key'),'-CAcreateserial','-extfile',str(root/'extensions'),'-out',str(cert)])
    number = port()
    document = {'auth':{'hpt_config_path':'hpt.cfg','session_key_path':'session.key'},
      'server':{'ip':'127.0.0.1','port':number,'tls_certificate':'cert.pem','tls_private_key':'key.pem'},
      'ftn':{'areacfg_path':'areas.cfg','jam_base_path':'.','default_encoding':'cp866','coordination_lock':'hpt.lock'},
      'database':{'metadata_path':'metadata.db'},
      'point_mail':{'enabled':True,'ingress_areas':['INGRESS'],'egress_area':'OUT',
        'points':[{'address':f'2:1/2.{p}','jam_base':f'points/p{p}'} for p in (1,2)]},
      'uue':{'part_body_bytes':4096,'max_parts':512}}
    (root/'config.json').write_text(json.dumps(document))
    run([str(build/'apps/backend/ffido-admin'),'provision-mailboxes',str(root/'config.json')])
    binary = bytes(range(256))*200
    (root/'binary.bin').write_bytes(binary)
    def chunk(tag,data): return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data))
    image = b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',1,1,8,6,0,0,0))
    image += chunk(b'tEXt', b'Fixture\0'+b'Synthetic FFIDO UUE preview. '*450)
    image += chunk(b'IDAT',zlib.compress(b'\0\xff\0\0\xff'))+chunk(b'IEND',b'')
    (root/'image.bin').write_bytes(image)
    info={'root':str(root),'endpoint':f'https://127.0.0.1:{number}','ca':str(ca),'port':number,
          'FFIDO_UUE_ENDPOINT':f'https://127.0.0.1:{number}', 'FFIDO_UUE_CA':base64.b64encode(ca.read_bytes()).decode()}
    (root/'fixture.json').write_text(json.dumps(info))
    for path in (root/'ca.key',key,root/'hpt.cfg',root/'fixture.json',root/'config.json'): path.chmod(0o600)
    return fixture, info


def incoming(root):
    data = bytearray(58)
    for offset,value in {0:9,2:2,4:2026,6:9,8:19,18:2,20:1,22:1,34:2,36:2,44:1,46:2,48:2}.items(): struct.pack_into('<H',data,offset,value)
    data[40:42]=b'\0\1'
    for group,(filename,subject,verified) in enumerate([
        ('binary.bin','uue-external',True),
        ('binary.bin','uue-legacy',False),
        ('image.bin','uue-legacy-image',False),
    ],1):
        binary=(root/filename).read_bytes()
        text=b'begin 644 '+filename.encode()+b'\r'+b''.join(binascii.b2a_uu(binary[i:i+45],backtick=True).replace(b'\n',b'\r') for i in range(0,len(binary),45))+b'`\rend\r'
        lines=text.splitlines(keepends=True)
        parts=[b''.join(lines[i:i+40]) for i in range(0,len(lines),40)]
        for n,body in reversed(list(enumerate(parts,1))):
            prefix=(f'\1INTL 2:1/2 2:1/9\r\1FMPT 7\r\1TOPT 2\r\1MSGID: 2:1/9.7 {group*4096+n:08x}\r'
                    f'\1CHRS: CP866 2\r').encode()
            if verified:
                prefix += (f'\1FFIDO-UUE: 1 {"c"*32} {n}/{len(parts)} {len(binary)} {hashlib.sha256(binary).hexdigest()} {filename}\r').encode()
            data += struct.pack('<7H',2,9,2,1,1,1,0)+b'19 Oct 26  12:00:00\0Point2\0Remote\0'
            data += f'{subject} [{n}/{len(parts)}]'.encode()+b'\0'+prefix+body+b'\0'
    (root/'protinbound/uue-input.pkt').write_bytes(data+b'\0\0')


def oracle(root,base,expected):
    groups={}
    for _,fields,body in records(base):
        for line in fields.get(2000,[]):
            if line.startswith(b'FFIDO-UUE: 1 '):
                tokens=line.split(); number=int(tokens[3].split(b'/')[0]); groups.setdefault(tokens[2],{})[number]=body
    for parts in groups.values():
        stream=b''.join(parts[n] for n in sorted(parts))
        # Ignore FTN prose/tearline; decode only classic rows between begin and zero/end.
        decoded=bytearray(); active=False
        for line in stream.splitlines():
            if line.startswith(b'begin '): active=True; continue
            if not active: continue
            if line in (b'`',b' '): break
            if not line or line.startswith((b'--- ',b' * Origin:',b'SEEN-BY:',b'\1')): continue
            decoded.extend(binascii.a2b_uu(line))
        if bytes(decoded)==expected: return
    raise AssertionError(f'Independent UUE oracle could not recover expected bytes from temporary {base.name}')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir',type=pathlib.Path,default=ROOT/'build/backend')
    parser.add_argument('--hpt',default=os.environ.get('FFIDO_TEST_HPT'))
    parser.add_argument('--flutter',default='flutter')
    parser.add_argument('--keep',action='store_true')
    args=parser.parse_args()
    if not args.hpt: parser.error('--hpt is required')
    fixture, info=create(args.build_dir.resolve(),args.hpt)
    root=fixture.root; server=None
    def start():
        output=(root/'server.log').open('a')
        process=subprocess.Popen([str(args.build_dir.resolve()/'apps/backend/fidoback'),str(root/'config.json')],stdout=output,stderr=subprocess.STDOUT,start_new_session=True)
        output.close();ready(process,info['port']);return process
    try:
        server=start()
        if args.keep:
            info['pid']=server.pid
            print(json.dumps(info));return
        dart=str(pathlib.Path(args.flutter).resolve().parent/'dart') if '/' in args.flutter else 'dart'
        def driver(phase):
            result=subprocess.run([dart,'run','tool/uue_acceptance.dart',str(root/'fixture.json'),phase],cwd=ROOT/'apps/frontend',capture_output=True,text=True,timeout=90)
            if result.returncode: raise RuntimeError(result.stdout+'\n'+result.stderr)
            print(result.stdout.strip())
        driver('send')
        server.send_signal(signal.SIGTERM);server.wait(timeout=15);server=None
        incoming(root)
        run([sys.executable,str(ROOT/'scripts/run_hpt.py'),'--config',str(root/'config.json'),'--cycle',
             '--admin',str(args.build_dir.resolve()/'apps/backend/ffido-admin'),'--hpt',args.hpt])
        oracle(root,root/'echo',(root/'image.bin').read_bytes())
        oracle(root,root/'points/p2',(root/'binary.bin').read_bytes())
        server=start();driver('receive')
        print('PASS: temporary HPT scan/toss, independent binascii, point isolation and fresh-client reconstruction')
    finally:
        if not args.keep:
            if server is not None: server.send_signal(signal.SIGTERM);server.wait(timeout=15)
            import shutil
            shutil.rmtree(root.parent)

if __name__=='__main__': main()
