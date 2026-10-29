#!/usr/bin/env python3
"""Real signed Docker upgrade + backup restore and footer/HPT acceptance.

All FTN data are generated in a fresh private directory. Never uses production
mounts or credentials. Requires Docker, the pinned Dart SDK, Python update
requirements and a native HPT executable for the isolated scan.
"""
import argparse
import contextlib
import base64
import functools
import http.server
import threading
import hashlib
import json
import os
from pathlib import Path
import secrets
import sqlite3
import shutil
import subprocess
import sys
import time

from check_acceptance import ROOT, port


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--hpt', type=Path, required=True)
    parser.add_argument('--local-candidate', action='store_true', help='Use corrected metadata in a private signed loopback fixture')
    parser.add_argument('--android', help='Booted Android emulator ID for reader acceptance')
    args = parser.parse_args()
    os.umask(0o077)
    work = args.directory.resolve()
    work.mkdir(mode=0o700, parents=True, exist_ok=False)
    project = 'ffido-footer-' + secrets.token_hex(5)
    compose_file = work/'compose.json'
    base = ['docker', 'compose', '-p', project, '-f', str(compose_file)]
    state = work/'updates'
    override = state/'image-override.json'
    def run(command, **kwargs):
        result = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=240, **kwargs)
        if result.returncode:
            # Never print command input/session secrets.
            raise RuntimeError('Fixture command failed: '+str(command[0])+'\n'+result.stderr[-2000:])
        return result.stdout
    def compose(*command):
        return run(base + (['-f',str(override)] if override.exists() else []) + list(command))
    def identity():
        return json.loads(compose('exec','-T','ffido','cat','/opt/ffido/BUILD.json'))
    def ready():
        for _ in range(90):
            value=json.loads(run(['docker','inspect',compose('ps','-q','ffido').strip()]))[0]
            if value['State'].get('Health',{}).get('Status')=='healthy': return
            time.sleep(1)
        raise RuntimeError('TLS gRPC readiness timed out')
    for folder in ['fido','state','tls']:
        (work/folder).mkdir()
    tls=work/'tls'
    extensions=tls/'openssl.cnf'
    extensions.write_text('[req]\nprompt=no\ndistinguished_name=dn\n[dn]\nCN=localhost\n[ca]\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always,issuer\n[server]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always,issuer\n')
    run(['openssl','req','-new','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=Footer test CA','-config',extensions,'-extensions','ca','-out',tls/'ca.pem','-keyout',tls/'ca-key.pem'])
    run(['openssl','req','-new','-newkey','rsa:2048','-nodes','-subj','/CN=localhost','-out',tls/'server.csr','-keyout',tls/'server-key.pem'])
    run(['openssl','x509','-req','-in',tls/'server.csr','-CA',tls/'ca.pem','-CAkey',tls/'ca-key.pem','-CAcreateserial','-days','1','-extfile',extensions,'-extensions','server','-out',tls/'server.pem'])
    import struct
    for name in ['one','two']:
        (work/f'fido/{name}.jhr').write_bytes(struct.pack('<7I',0x004d414a,123,0,0,0xffffffff,1,0)+bytes(996))
        (work/f'fido/{name}.jdt').touch(); (work/f'fido/{name}.jdx').touch()
    password=secrets.token_hex(16)
    (work/'fido/areas.cfg').write_text('EchoArea RU.ONE /srv/fido/one -b JAM\nEchoArea RU.TWO /srv/fido/two -b JAM\n')
    (work/'fido/hpt.cfg').write_text('Name Fixture\nSysop Test\nLocation Isolated\nAddress 2:1/1\nLink Alice\nAKA 2:1/2\nOurAKA 2:1/1\nSessionPwd '+password+'\nLink Sender\nAKA 2:1/3\nOurAKA 2:1/1\nSessionPwd '+password+'\nEchoArea RU.ONE /srv/fido/one -b JAM 2:1/2 2:1/3\nEchoArea RU.TWO /srv/fido/two -b JAM 2:1/2 2:1/3\n')
    config={'server':{'ip':'0.0.0.0','port':8080,'tls_certificate':'/etc/ffido/tls/server.pem','tls_private_key':'/etc/ffido/tls/server-key.pem'},'ftn':{'areacfg_path':'/srv/fido/areas.cfg','jam_base_path':'/srv/fido','coordination_lock':'/srv/fido/hpt.lock','default_encoding':'UTF-8'},'auth':{'hpt_config_path':'/srv/fido/hpt.cfg','session_key_path':'/var/lib/ffido/session.key'},'database':{'metadata_path':'/var/lib/ffido/metadata.db'}}
    (work/'config.json').write_text(json.dumps(config))
    number=port()
    before='docker.io/hashev/ffido@sha256:df275d0bbb39efb9be70c74dc5a771b73844053fcec9f28a2d11193439b1b834'
    compose_file.write_text(json.dumps({'services':{'ffido':{'image':before,'platform':'linux/amd64','user':'0:0','ports':[f'127.0.0.1:{number}:8080'],'volumes':[f'{work}/config.json:/etc/ffido/config.json:ro',f'{tls}:/etc/ffido/tls:ro',f'{work}/state:/var/lib/ffido',f'{work}/fido:/srv/fido'],'healthcheck':{'test':['CMD','fidoback','--check-ready','127.0.0.1:8080','/etc/ffido/tls/ca.pem','localhost'],'interval':'2s','timeout':'10s','retries':30}}}}))
    payload=json.dumps({'endpoint':f'https://127.0.0.1:{number}','ca':str(tls/'ca.pem'),'state':str(work/'session.json'),'password':password})
    def probe(phase):
        run(['dart','run','tool/footer_upgrade_acceptance.dart',phase],cwd=ROOT/'apps/frontend',input=payload)
        print('PASS: '+phase,flush=True)
    env={**os.environ,'COMPOSE_PROJECT_NAME':project}
    updater=[sys.executable,ROOT/'scripts/update/ffido-docker-update.py']
    options=['--compose-file',compose_file,'--service','ffido','--state-dir',state,'--channel','stable']
    registry = project+'-registry'
    candidate = None
    try:
        if args.local_candidate:
            sys.path.insert(0, str(ROOT/'scripts/update'))
            from footer_candidate_fixture import prepare
            launcher, candidate = prepare(work, run, registry, port())
            updater = [sys.executable, launcher]
        compose('up','-d');ready();assert identity()['version']=='1.0.4'
        probe('seed')
        compose('stop','ffido')
        backup=work/'backup';backup.mkdir()
        for folder in ['state','fido']: shutil.copytree(work/folder,backup/folder)
        original=(work/'fido/one.jdt').read_bytes()
        compose('start','ffido');ready()
        if args.local_candidate:
            compose('stop','ffido')
            with sqlite3.connect(work/'state/metadata.db') as db: db.execute('PRAGMA user_version=11')
            failed = subprocess.run(list(map(str, updater+['apply']+options)), env=env, capture_output=True, text=True, timeout=240)
            assert failed.returncode != 0 and 'incompatible' in failed.stderr
            assert not override.exists()
            compose('stop','ffido')
            with sqlite3.connect(work/'state/metadata.db') as db: db.execute('PRAGMA user_version=10')
            compose('start','ffido');ready()
        run(updater+['apply']+options,env=env)
        ready();after=identity();assert after['version']=='1.0.7', 'Expected tested release 1.0.7; revalidate the candidate'
        operation=json.loads((state/'operation.json').read_text())
        assert operation['phase']=='complete'
        if candidate: assert operation['selected']==candidate
        probe('footer')
        if args.android:
            class Images(http.server.SimpleHTTPRequestHandler):
                def log_message(self, *args): pass
            handler = functools.partial(Images, directory=str(ROOT/'apps/frontend/integration_test/fixtures'))
            images_server = http.server.ThreadingHTTPServer(('0.0.0.0', 0), handler)
            thread = threading.Thread(target=images_server.serve_forever, daemon=True); thread.start()
            defines = work/'android-defines.json'
            defines.write_text(json.dumps({'FFIDO_TEST_ENDPOINT':f'https://localhost:{number}',
                'FFIDO_TEST_PASSWORD':password,'FFIDO_TEST_CA':base64.b64encode((tls/'ca.pem').read_bytes()).decode(),
                'FFIDO_TEST_IMAGE':f'http://10.0.2.2:{images_server.server_port}/link-preview.jpg'}))
            try:
                result = subprocess.run(['flutter','drive','--driver=test_driver/reader_acceptance.dart',
                    '--target=integration_test/reader_acceptance_test.dart','-d',args.android,
                    '--dart-define-from-file='+str(defines)],cwd=ROOT/'apps/frontend',capture_output=True,text=True,timeout=360,env={**os.environ,'FFIDO_SCREENSHOT_DIR':str(work)})
                (work/'android.log').write_text((result.stdout+result.stderr).replace(password,'<redacted>'))
                if result.returncode: raise RuntimeError('Android acceptance failed; see private fixture android.log')
                print('PASS: Android reader acceptance',flush=True)
            finally:
                defines.unlink(missing_ok=True); images_server.shutdown(); images_server.server_close(); thread.join(timeout=5)
        compose('stop','ffido')
        scan=work/'scan.cfg'
        lines=['Name Fixture','Sysop Test','Location Isolated','Address 2:1/1',f'MsgBaseDir {work}',f'EchoTossLog {work}/logs/toss.log']
        for key,name in [('Inbound','inbound'),('ProtInbound','protinbound'),('Outbound','outbound'),('TempInbound','tmpin'),('TempOutbound','tmpout'),('LogFileDir','logs'),('DupeHistoryDir','dupes'),('NodelistDir','nodelist')]:
            (work/name).mkdir();lines.append(f'{key} {work/name}')
        lines += [f'BadArea BAD {work}/BAD -b JAM', f'DupeArea DUPE {work}/DUPE -b JAM', f'NetmailArea NETMAIL {work}/NETMAIL -b JAM']
        lines+=['Link Peer','AKA 2:1/2','OurAKA 2:1/1','Password fixture','AllowEmptyPktPwd on']
        lines += [f'EchoArea RU.{name.upper()} {work}/fido/{name} -b JAM -dupeCheck off 2:1/2' for name in ['one','two']]
        scan.write_text('\n'.join(lines)+'\n')
        run([args.hpt.resolve(),'-c',scan,'scan','-w'])
        compose('start','ffido');ready();probe('verify')
        assert (work/'fido/one.jdt').read_bytes().startswith(original)
        compose('stop','ffido')
        for folder in ['state','fido']:
            shutil.rmtree(work/folder);shutil.copytree(backup/folder,work/folder)
        override.write_text(json.dumps({'services':{'ffido':{'image':before}}}))
        compose('up','-d');ready();probe('restored')
        assert (work/'fido/one.jdt').read_bytes()==original
        result={'before':'1.0.4','after':after['version'],'selected':operation['selected'],'signed_update':True,'local_candidate':args.local_candidate,'session_restored':True,'footer_and_crosspost':True,'hpt_scan':True,'backup_restored':True,'legacy_text_sha256':hashlib.sha256(original).hexdigest()}
        (work/'result.json').write_text(json.dumps(result,indent=2)+'\n')
        print(json.dumps(result),flush=True)
    finally:
        with contextlib.suppress(Exception): compose('down')
        if args.local_candidate:
            with contextlib.suppress(Exception): run(['docker','rm','-f',registry])
            if candidate:
                with contextlib.suppress(Exception): run(['docker','image','rm',candidate.split('@')[0]+':candidate',candidate])
        # All fixture secrets remain private during the run and are removed on exit.
        for path in [work/'session.json',work/'fido/hpt.cfg',work/'state/session.key',backup/'state/session.key' if 'backup' in locals() else work/'unused',backup/'fido/hpt.cfg' if 'backup' in locals() else work/'unused']:
            path.unlink(missing_ok=True)
        for path in tls.glob('*key*'):path.unlink()


if __name__=='__main__':main()
