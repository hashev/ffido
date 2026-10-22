#!/usr/bin/env python3
"""Real loopback registry/Compose QA; never contacts a publication registry.

Only an isolated updater copy substitutes the registry allowlist and discovery
transport. Signature, manifest validation and all Docker operations remain real.
"""
import argparse
import base64
import json
import os
import pathlib
import secrets
import socket
import struct
import subprocess
import sys
import time
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

ROOT = pathlib.Path(__file__).resolve().parents[2]


def port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0)); return sock.getsockname()[1]


def run(args):
    work = args.directory.resolve(); work.mkdir(parents=True, exist_ok=False, mode=0o700)
    log = (work/'commands.log').open('w')
    def command(*cmd, input=None, cwd=None, success=True):
        log.write(json.dumps(list(map(str, cmd)))+'\n'); log.flush()
        result = subprocess.run(list(map(str, cmd)), input=input, cwd=cwd, text=True, capture_output=True)
        log.write(result.stdout+result.stderr); log.flush()
        if success and result.returncode: raise RuntimeError('Command failed; see '+str(work/'commands.log'))
        return result.stdout.strip() if success else result
    registry = 'ffido-update-registry-'+secrets.token_hex(4)
    project = 'ffido-update-qa-'+secrets.token_hex(4)
    legacy = project+'-legacy'; registry_port, backend_port = port(), port()
    repository = f'127.0.0.1:{registry_port}/hashev/ffido'
    compose_file = work/'compose.json'
    compose = ['docker', 'compose', '-p', project, '-f', str(compose_file)]
    refs = []
    try:
        command('docker', 'run', '-d', '--name', registry, '-p', f'127.0.0.1:{registry_port}:5000', '--tmpfs', '/var/lib/registry', 'registry:3.0.0')
        for _ in range(30):
            import urllib.request
            try:
                urllib.request.urlopen(f'http://127.0.0.1:{registry_port}/v2/', timeout=2).close(); break
            except OSError: time.sleep(1)
        identities = []
        for image, name in [(args.before, 'a'), (args.after, 'b')]:
            build = json.loads(command('docker', 'run', '--rm', '--entrypoint', 'cat', image, '/opt/ffido/BUILD.json'))
            # A local pre-release image can have a local OCI label; align only QA
            # image labels with its existing compiled BUILD identity.
            dockerfile = work/('Dockerfile.'+name)
            if name == 'a' and build['tag'] == 'local':
                build.update(tag='v1.0.0', stable=True, build_number=41001)
            (work/('BUILD.'+name+'.json')).write_text(json.dumps(build))
            dockerfile.write_text(f'FROM {image}\nCOPY BUILD.{name}.json /opt/ffido/BUILD.json\nLABEL org.opencontainers.image.version="{build["tag"]}"\nLABEL org.opencontainers.image.revision="{build["sha"]}"\n')
            ref = repository+':'+name; refs.append(ref)
            command('docker', 'build', '--platform', 'linux/amd64', '-f', dockerfile, '-t', ref, work)
            command('docker', 'push', ref)
            command('docker', 'pull', ref)
            info = json.loads(command('docker', 'image', 'inspect', ref))[0]
            digest = next(v.split('@')[1] for v in info['RepoDigests'] if v.startswith(repository+'@'))
            identities.append((build, repository+'@'+digest))
        a, b = identities
        assert a[0]['tag'] != b[0]['tag'] and a[1] != b[1]
        for folder in ['tls', 'state', 'fido', 'shadow']:
            (work/folder).mkdir()
        tls = work/'tls'
        extensions = tls/'openssl.cnf'
        extensions.write_text('[req]\nprompt=no\ndistinguished_name=dn\n[dn]\nCN=localhost\n[ca]\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always,issuer\n[server]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always,issuer\n')
        command('openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', '-subj', '/CN=FFIDO QA CA', '-config', extensions, '-extensions', 'ca', '-keyout', tls/'ca-key.pem', '-out', tls/'ca.pem')
        command('openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes', '-subj', '/CN=localhost', '-keyout', tls/'server-key.pem', '-out', tls/'server.csr')
        command('openssl', 'x509', '-req', '-in', tls/'server.csr', '-CA', tls/'ca.pem', '-CAkey', tls/'ca-key.pem', '-CAcreateserial', '-days', '1', '-extfile', extensions, '-extensions', 'server', '-out', tls/'server.pem')
        password = secrets.token_hex(16)
        fido = work/'fido'
        (fido/'file.jhr').write_bytes(struct.pack('<7I', 0x004d414a, 123, 0, 0, 0xffffffff, 1, 0)+bytes(996))
        for ext in ['jdx', 'jdt']: (fido/('file.'+ext)).touch()
        (fido/'areas.cfg').write_text('EchoArea RU.TEST file -b JAM -d "Isolated test"\n')
        (fido/'hpt.cfg').write_text('Name Fixture\nSysop Test\nLocation Test\nAddress 2:1/1\nLink A\nAKA 2:1/2\nOurAKA 2:1/1\nSessionPwd '+password+'\nEchoArea RU.TEST /srv/fido/file -b JAM 2:1/2\n')
        config = json.loads((ROOT/'apps/backend/config.container.example.json').read_text())
        config['ftn']['default_encoding'] = 'UTF-8'
        (work/'config.json').write_text(json.dumps(config))
        mounts = [f'{work}/config.json:/etc/ffido/config.json:ro', f'{tls}:/etc/ffido/tls:ro', f'{work}/state:/var/lib/ffido', f'{fido}:/srv/fido']
        health = {'test': ['CMD', 'fidoback', '--check-ready', '127.0.0.1:8080', '/etc/ffido/tls/ca.pem', 'localhost'], 'interval': '1s', 'timeout': '12s', 'retries': 5}
        service = {'image': a[1], 'platform': 'linux/amd64', 'user': '0:0', 'ports': [f'127.0.0.1:{backend_port}:8080'], 'volumes': mounts, 'healthcheck': health, 'stop_grace_period': '20s'}
        original = json.dumps({'services': {'ffido': service, 'unrelated': {'image': 'alpine:3.24', 'command': ['sleep', '3600']}}}, indent=2)
        compose_file.write_text(original)
        # Documented docker run -> Compose transition with the same bind mounts.
        legacy_cmd = ['docker', 'run', '-d', '--name', legacy, '--user', '0:0', '-p', f'127.0.0.1:{backend_port}:8080']
        for mount in mounts: legacy_cmd += ['-v', mount]
        command(*legacy_cmd, a[1])
        def ready(container):
            for _ in range(90):
                result = command('docker', 'exec', container, 'fidoback', '--check-ready', '127.0.0.1:8080', '/etc/ffido/tls/ca.pem', 'localhost', success=False)
                if result.returncode == 0: return
                time.sleep(1)
            raise RuntimeError('TLS readiness timeout')
        ready(legacy)
        session = work/'session.json'
        payload = json.dumps({'endpoint': f'https://localhost:{backend_port}', 'ca': str(tls/'ca.pem'), 'state': str(session), 'passwordA': password})
        def persistence(phase): command('dart', 'run', 'tool/container_persistence.dart', phase, input=payload, cwd=ROOT/'apps/frontend')
        persistence('save')
        command('docker', 'stop', '--time', '20', legacy); command('docker', 'rm', legacy)
        command(*compose, 'up', '-d')
        container = command(*compose, 'ps', '-q', 'ffido'); ready(container)
        unrelated = command(*compose, 'ps', '-q', 'unrelated')
        def runtime_layout():
            current = command(*compose, 'ps', '-q', 'ffido')
            info = json.loads(command('docker', 'inspect', current))[0]
            return {'user': info['Config']['User'], 'ports': info['HostConfig']['PortBindings'],
                    'mounts': sorted((m['Source'], m['Destination'], m['RW']) for m in info['Mounts'])}
        layout = runtime_layout()

        persistence('verify')
        key = Ed25519PrivateKey.generate(); shadow = work/'shadow'
        for name in ['common.py', 'discovery.py', 'server.py', 'ffido-docker-update.py']:
            source = (ROOT/'scripts/update'/name).read_text()
            source = source.replace('(?:docker.io/)?hashev/ffido', __import__('re').escape(repository)).replace('docker.io/hashev/ffido', repository)
            (shadow/name).write_text(source)
        (shadow/'public_keys.json').write_text(json.dumps({'qa': base64.b64encode(key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()}))
        package = {**b[0], 'id': 'server-linux-x86_64', 'component': 'server', 'platform': {'os': 'linux', 'architecture': 'x86_64'}, 'min_os': {'version': '24.04', 'distribution': 'ubuntu'}, 'file': 'qa.tar.gz', 'size': 1, 'sha256': '0'*64}
        manifest = {'schema_version': 1, 'identity': {k: b[0][k] for k in ['tag', 'version', 'sha', 'stable', 'build_number']}, 'channel': 'stable', 'update_sequence': b[0]['build_number'], 'compatibility': b[0]['compatibility'], 'packages': [package], 'container': {'image': repository, 'digest': b[1].split('@')[1], 'sha': b[0]['sha'], 'release_tag': b[0]['tag'], 'version': b[0]['version'], 'tag': b[0]['tag'][1:]}}
        raw = json.dumps(manifest).encode()
        (shadow/'manifest.json').write_bytes(raw)
        (shadow/'manifest.sig').write_text(json.dumps({'algorithm': 'Ed25519', 'key_id': 'qa', 'signature': base64.b64encode(key.sign(raw)).decode()}))
        # Fixture transport preserves official URL/asset consistency checks.
        launcher = shadow/'launch.py'
        launcher.write_text('''import json,pathlib,runpy,discovery,common
root=pathlib.Path(__file__).parent
original=discovery.releases
def fetch(url,limit=common.MAX_METADATA):
 if url.startswith('https://api.github.com/'):
  tag=json.loads((root/'manifest.json').read_bytes())['identity']['tag']
  return json.dumps([{'draft':False,'prerelease':False,'tag_name':tag,'assets':[{'name':n,'browser_download_url':common.asset_url(tag,n),'size':1} for n in ['release-manifest.json','release-manifest.sig','qa.tar.gz']]}]).encode()
 return (root/('manifest.sig' if url.endswith('.sig') else 'manifest.json')).read_bytes()
discovery.releases=lambda *a,**kw:original(*a,**kw,fetch=fetch)
runpy.run_path(str(root/'ffido-docker-update.py'),run_name='__main__')
''')
        def update(action, success=True):
            # CLI inherits the project selection just as documented operator use.
            old = os.environ.get('COMPOSE_PROJECT_NAME'); os.environ['COMPOSE_PROJECT_NAME'] = project
            try: return command(sys.executable, launcher, action, '--compose-file', compose_file, '--service', 'ffido', success=success)
            finally:
                if old is None: os.environ.pop('COMPOSE_PROJECT_NAME', None)
                else: os.environ['COMPOSE_PROJECT_NAME'] = old
        signature = (shadow/'manifest.sig').read_bytes()
        (shadow/'manifest.sig').write_text(json.dumps({'algorithm': 'Ed25519', 'key_id': 'qa', 'signature': base64.b64encode(bytes(64)).decode()}))
        assert update('apply', success=False).returncode != 0
        assert command(*compose, 'ps', '-q', 'ffido') == container
        assert not (work/'.ffido-update/image-override.json').exists()
        (shadow/'manifest.sig').write_bytes(signature)
        incompatible = json.loads(raw)
        incompatible['compatibility']['state_schema_min'] = 10
        incompatible['compatibility']['state_schema_max'] = 10
        incompatible['packages'][0]['compatibility'] = incompatible['compatibility']
        invalid_raw = json.dumps(incompatible).encode()
        (shadow/'manifest.json').write_bytes(invalid_raw)
        (shadow/'manifest.sig').write_text(json.dumps({'algorithm': 'Ed25519', 'key_id': 'qa', 'signature': base64.b64encode(key.sign(invalid_raw)).decode()}))
        assert update('apply', success=False).returncode != 0
        ready(container)
        assert command(*compose, 'ps', '-q', 'ffido') == container
        assert not (work/'.ffido-update/image-override.json').exists()
        (shadow/'manifest.json').write_bytes(raw)
        (shadow/'manifest.sig').write_bytes(signature)
        check = json.loads(update('check')); assert check['available'] == b[0]['tag']
        update('apply'); persistence('verify')
        assert runtime_layout() == layout
        assert command(*compose, 'ps', '-q', 'unrelated') == unrelated
        assert compose_file.read_text() == original
        override = work/'.ffido-update/image-override.json'
        assert json.loads(override.read_text())['services']['ffido']['image'] == b[1]
        update('rollback'); persistence('verify')
        assert runtime_layout() == layout
        assert json.loads(override.read_text())['services']['ffido']['image'] == a[1]
        assert command(*compose, 'ps', '-q', 'unrelated') == unrelated
        assert compose_file.read_text() == original
        result = {'registry': 'loopback only', 'discovery': 'signed local transport fixture', 'from': a[0]['tag'], 'to': b[0]['tag'], 'docker_run_to_compose': True, 'check_apply_rollback': True, 'tls_grpc_ready': True, 'session_message_metadata_uploads_preserved': True, 'unrelated_container_unchanged': True, 'compose_unchanged': True, 'runtime_mounts_user_ports_unchanged': True, 'invalid_signature_rejected': True, 'incompatible_schema_rejected_and_a_restarted': True, 'a_metadata_normalized_from_local_build': True}
        (work/'result.json').write_text(json.dumps(result, indent=2)+'\n'); print(json.dumps(result))
    finally:
        if compose_file.exists(): command(*compose, 'down', success=False)
        command('docker', 'rm', '-f', legacy, success=False)
        command('docker', 'rm', '-f', registry, success=False)
        for ref in refs: command('docker', 'image', 'rm', ref, success=False)
        (work/'session.json').unlink(missing_ok=True)
        for key_file in (work/'tls').glob('*key*'): key_file.unlink()
        if (work/'fido/hpt.cfg').exists(): (work/'fido/hpt.cfg').unlink()
        log.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', default='ffido:managed-updates')
    parser.add_argument('--after', default='ffido:managed-updates-final')
    parser.add_argument('--directory', type=pathlib.Path, required=True)
    run(parser.parse_args())
