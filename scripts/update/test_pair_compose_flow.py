#!/usr/bin/env python3
"""Real isolated local-pair -> signed QA image -> restore/rollback rehearsal.

Creates only loopback listeners, private fixture data and local QA artifacts.
The QA image alone substitutes Telegram's public key; production sources and
trust stores are never changed. No working node mounts or FTN network are used.
"""
import argparse
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys
import time
from types import SimpleNamespace
from unittest.mock import patch

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PrivateFormat, PublicFormat, NoEncryption

import pair_acceptance
import pair_probe

ROOT = Path(__file__).resolve().parents[2]


def port():
    with socket.socket() as available:
        available.bind(('127.0.0.1', 0))
        return available.getsockname()[1]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def run(args):
    work = args.directory.resolve()
    work.mkdir(mode=0o700, parents=True, exist_ok=False)
    log = (work/'commands.private.log').open('w'); os.fchmod(log.fileno(), 0o600)
    def command(*argv, success=True):
        log.write(json.dumps(list(map(str, argv)))+'\n'); log.flush()
        result = subprocess.run(list(map(str, argv)), capture_output=True, text=True)
        log.write(result.stdout+result.stderr); log.flush()
        if success and result.returncode:
            raise RuntimeError('QA command failed; inspect private command log')
        return result.stdout.strip() if success else result
    def private(path, value):
        pair_acceptance.private_json(path, value)
    project = 'ffido-pair-qa-'+secrets.token_hex(5)
    registry = project+'-registry'
    registry_port, backend_port, gateway_port = port(), port(), port()
    repository = '127.0.0.1:'+str(registry_port)+'/hashev/ffido'
    gateway = None
    fixture = None
    succeeded = False
    compose_file = None
    compose = []
    try:
        sys.path.insert(0, str(ROOT/'scripts'))
        source_tests = module('pair_restore_fixture', ROOT/'scripts/test_mailbox_restore.py')
        source_tests.ADMIN = str(args.admin.resolve(strict=True))
        fixture = source_tests.MailboxRestoreTest()
        def owned_directory(**kwargs):
            path = source_tests.tempfile.mkdtemp(dir=work, **kwargs)
            return SimpleNamespace(name=path, cleanup=lambda: shutil.rmtree(path))
        with patch.object(source_tests.tempfile, 'TemporaryDirectory', side_effect=owned_directory):
            fixture.setUp()
        helper = fixture.prepare_snapshot_source()
        root = fixture.source
        source_backend = json.loads(command('docker', 'image', 'inspect', args.source_backend))[0]['Id']
        source_worker = args.source_worker
        def build(image):
            return json.loads(command('docker', 'run', '--rm', '--platform', 'linux/amd64',
                '--network', 'none', '--entrypoint', 'python3', image, '-c',
                "from pathlib import Path;print(Path('/opt/ffido/BUILD.json').read_text())"))
        source_build = build(source_backend)
        if source_build['tag'].startswith('v'):
            raise ValueError('Rehearsal requires a genuine non-release local source')
        telegram_key = (Ed25519PrivateKey.from_private_bytes(bytes.fromhex(json.loads(
            args.telegram_key_file.read_text())['telegram_key'])) if args.telegram_key_file
            else Ed25519PrivateKey.generate())
        release_key = Ed25519PrivateKey.generate()
        context = work/'image-context'; context.mkdir()
        for name in ('src/admin.cpp', 'src/storage/mailbox_restore.cpp', 'include/storage/mailbox_restore.hpp'):
            target = context/name; target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT/'apps/backend'/name, target)
        key_source = (ROOT/'apps/backend/src/service/telegram_auth.cpp').read_text()
        qa_public = telegram_key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw).hex()
        official_key = 'e7bf03a2fa4602af4580703d88dda5bb59f32ed8b02a56c187fe7d34caed242d'
        if official_key not in key_source:
            raise ValueError('QA Telegram substitution requires source review')
        (context/'src/service').mkdir(parents=True, exist_ok=True)
        (context/'src/service/telegram_auth.cpp').write_text(key_source.replace(official_key, qa_public))
        target_build = {**source_build, 'version': '1.0.28', 'tag': 'v1.0.28',
                        'build_number': 1066, 'sha': 'b'*40, 'stable': True}
        private(context/'BUILD.json', target_build)
        builder = json.loads(command('docker', 'image', 'inspect', args.builder))[0]['Id']
        # Every base is an already available local image. Build never uses the network.
        command('docker', 'tag', builder, project+'-builder:local')
        command('docker', 'tag', source_backend, project+'-source:local')
        (context/'Dockerfile').write_text(
            'FROM '+project+'-builder:local AS builder\nCOPY src/ /src/apps/backend/src/\n'
            'COPY include/ /src/apps/backend/include/\n'
            'RUN cmake --build /src/build/backend --parallel 4 --target ffido-admin fidoback '
            '&& cp /src/build/backend/apps/backend/ffido-admin /tmp/ffido-admin '
            '&& cp /src/build/backend/apps/backend/fidoback /tmp/fidoback '
            "&& patchelf --set-rpath '$ORIGIN/../lib' /tmp/ffido-admin "
            "&& patchelf --set-rpath '$ORIGIN/../lib' /tmp/fidoback\n"
            'FROM '+project+'-source:local\nUSER root\n'
            'COPY --from=builder /tmp/ffido-admin /opt/ffido/bin/ffido-admin\n'
            'COPY --from=builder /tmp/fidoback /opt/ffido/bin/fidoback\n'
            'COPY BUILD.json /opt/ffido/BUILD.json\n'
            'LABEL org.opencontainers.image.revision="'+target_build['sha']+'" '
            'org.opencontainers.image.version="'+target_build['tag']+'"\n')
        qa_tag = project+'-target:local'
        if args.target_image:
            command('docker', 'tag', args.target_image, qa_tag)
            if build(qa_tag) != target_build:
                raise ValueError('Prepared QA target identity differs')
        else:
            command('docker', 'build', '--platform', 'linux/amd64', '--network=none',
                    '--pull=false', '-t', qa_tag, str(context))
        command('docker', 'run', '-d', '--name', registry, '-p',
                '127.0.0.1:'+str(registry_port)+':5000', 'registry:3.0.0')
        command('docker', 'tag', qa_tag, repository+':qa')
        for attempt in range(20):
            if command('docker', 'push', repository+':qa', success=False).returncode == 0:
                break
            time.sleep(.5)
        else:
            raise ValueError('Loopback registry unavailable')
        target_info = json.loads(command('docker', 'image', 'inspect', repository+':qa'))[0]
        reference = next(x for x in target_info['RepoDigests'] if x.startswith(repository+'@'))
        for _ in range(60):
            available = command('docker', 'image', 'inspect', source_worker, success=False)
            if available.returncode == 0:
                source_worker = json.loads(available.stdout)[0]['Id']
                break
            time.sleep(5)
        else:
            raise ValueError('Import the prepared source worker archive before rehearsal')
        if build(source_worker) != source_build:
            raise ValueError('Source worker/backend distributions differ')
        tls = root/'tls'
        (tls/'extensions').write_text('subjectAltName=DNS:localhost\nbasicConstraints=critical,CA:TRUE\n')
        command('openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost',
                '-keyout', tls/'server-key.pem', '-out', tls/'server.pem')
        shutil.copyfile(tls/'server.pem', tls/'ca.pem')
        config = json.loads((root/'config.json').read_text())
        config['server'].update(ip='0.0.0.0', port=8080)
        config['ftn']['default_encoding'] = 'UTF-8'
        config['auth']['telegram'] = {'bot_id': 123456789}
        (root/'session.key').write_bytes(b'k'*32)
        (root/'session.key').chmod(0o600)
        (tls/'server-key.pem').chmod(0o600)
        (root/'corrections.jsonl').write_text(json.dumps({'kind': 'manifest', 'version': 1,
            'count': 0, 'source_sha256': hashlib.sha256(b'isolated fixture').hexdigest()})+'\n')
        private(root/'config.json', config)
        for name in ('QA.A', 'QA.B'):
            for ext in ('.jhr', '.jdt', '.jdx'):
                shutil.copyfile(root/('jam/points/p1'+ext), root/('jam/'+name+ext))
            with (root/'areas.cfg').open('a') as area:
                area.write('EchoArea '+name+' '+str(root/'jam'/name)+
                           ' -b JAM -d "'+name+'" 2:1/2.1 2:1/2.2\n')
        private(root/'ffido/deployed-identity.json', source_build)
        (root/'.env').write_text('')
        marker = secrets.token_hex(16); (root/'.ffido-isolated-pair-fixture').write_text(marker)
        hpt_digest = command('docker', 'run', '--rm', '--platform', 'linux/amd64', '--network', 'none',
                             '--entrypoint', 'sha256sum', source_worker, '/usr/local/bin/hpt').split()[0]
        worker_script = root/'ffido/ops/worker.py'
        worker_script.write_text('''import hashlib,json,pathlib,signal,subprocess,time
root=pathlib.Path(__file__).parents[2]
expected=json.loads((root/'ffido/deployed-identity.json').read_text())
actual=json.loads(pathlib.Path('/opt/ffido/BUILD.json').read_text())
assert actual==expected
with open('/usr/local/bin/hpt','rb') as f: assert hashlib.file_digest(f,'sha256').hexdigest()=='''+repr(hpt_digest)+'''
import sqlite3,contextlib
with contextlib.closing(sqlite3.connect((root/'metadata.db').as_uri()+'?mode=ro',uri=True)) as db: assert db.execute('pragma user_version').fetchone()[0]==12
stop=False
def done(*args):
 global stop
 stop=True
signal.signal(signal.SIGTERM,done);signal.signal(signal.SIGINT,done)
pathlib.Path('/tmp/pair-worker-ready').touch()
while not stop: time.sleep(.1)
''')
        health = {'test': ['CMD', 'fidoback', '--check-ready', '127.0.0.1:8080',
                           str(tls/'ca.pem'), 'localhost'], 'interval': '1s', 'timeout': '10s', 'retries': 30}
        source_service = {'image': source_backend, 'platform': 'linux/amd64', 'user': '0:0',
            'entrypoint': ['/opt/ffido/bin/fidoback'], 'command': [str(root/'config.json')],
            'working_dir': str(root), 'volumes': [str(root)+':'+str(root)],
            'ports': ['127.0.0.1:'+str(backend_port)+':8080'], 'healthcheck': health,
            'stop_grace_period': '30s'}
        worker_service = {'image': source_worker, 'platform': 'linux/amd64', 'user': '0:0',
            'entrypoint': ['python3', str(worker_script)], 'network_mode': 'none',
            'volumes': [str(root)+':'+str(root)], 'healthcheck': {
                'test': ['CMD', 'python3', '-c', "from pathlib import Path;assert Path('/tmp/pair-worker-ready').is_file()"],
                'interval': '1s', 'timeout': '5s', 'retries': 15}}
        idle = {'image': source_backend, 'entrypoint': ['python3', '-c', 'import time;time.sleep(3600)'],
                'network_mode': 'none', 'platform': 'linux/amd64'}
        compose_file = root/'docker-compose.yaml'
        private(compose_file, {'name': project, 'services': {'backend': source_service,
            'tosser': worker_service, 'mailer': idle, 'unrelated': idle}})
        compose = ['docker', 'compose', '-p', project, '-f', str(compose_file)]
        command(*compose, 'up', '-d', 'backend', 'tosser', 'unrelated')
        unrelated = command(*compose, 'ps', '-q', 'unrelated')
        gateway_root = work/'gateway'; gateway_root.mkdir()
        generator = module('pair_gateway_generator', ROOT/'tools/gateway/run.py')
        gateway_config = generator.config(SimpleNamespace(certificate=str(tls/'server.pem'),
            private_key=str(tls/'server-key.pem'), backend_ca=str(tls/'ca.pem'),
            origin='https://hashev.github.io', backend_host='localhost',
            backend_port=backend_port, port=gateway_port))
        private(gateway_root/'envoy.json', gateway_config)
        gateway_log = (work/'gateway.private.log').open('w')
        gateway = subprocess.Popen([str(args.envoy.resolve()), '-c', str(gateway_root/'envoy.json'),
                                    '--concurrency', '1', '--disable-hot-restart'],
                                   stdout=gateway_log, stderr=gateway_log)
        fixture_config = {'isolated': True, 'isolation_id': marker, 'root': str(root),
            'state': str(work/'session.private.json'), 'endpoint': 'https://localhost:'+str(gateway_port),
            'ca': str(tls/'ca.pem'), 'origin': 'https://hashev.github.io', 'bot_id': 123456789,
            'telegram_key': telegram_key.private_bytes(Encoding.Raw, PrivateFormat.Raw, NoEncryption()).hex()}
        fixture_path = work/'fixture.private.json'; private(fixture_path, fixture_config)
        def acceptance(mode):
            command(sys.executable, ROOT/'scripts/update/pair_acceptance.py', mode, '--fixture', fixture_path)
        for _ in range(90):
            try:
                pair_probe.gateway(fixture_config['endpoint'], fixture_config['ca'], fixture_config['origin'])
                break
            except (OSError, ValueError): time.sleep(.5)
        else: raise ValueError('Source backend/gateway did not become ready')
        acceptance('seed')
        command(*compose, 'stop', 'backend')
        acceptance('seed-telegram'); acceptance('capture-state')
        command(*compose, 'up', '-d', 'backend')
        for _ in range(60):
            result = command(sys.executable, ROOT/'scripts/update/pair_acceptance.py',
                             'verify-source', '--fixture', fixture_path, success=False)
            if result.returncode == 0: break
            time.sleep(.5)
        else: raise ValueError('Source identity/receipt acceptance failed')
        shadow = work/'shadow/scripts/update'; shadow.mkdir(parents=True)
        for source in (ROOT/'scripts/update').glob('*.py'):
            text = source.read_text().replace('docker.io/hashev/ffido', repository)
            (shadow/source.name).write_text(text)
        for name in ('node_backup.py', 'deployment_backup.py'):
            shutil.copyfile(ROOT/'scripts'/name, shadow.parent/name)
        private(shadow/'public_keys.json', {'qa': base64.b64encode(release_key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()})
        def signed(build_info, path, digest=None):
            identity = {key: build_info[key] for key in ('version', 'tag', 'sha', 'stable', 'build_number')}
            compatibility = build_info['compatibility']
            package = {**identity, 'id': 'server-linux-x86_64', 'component': 'server',
                'platform': {'os': 'linux', 'architecture': 'x86_64'},
                'min_os': {'version': '24.04', 'distribution': 'ubuntu'}, 'file': 'qa.bin',
                'size': 1, 'sha256': hashlib.sha256(b'q').hexdigest(), 'compatibility': compatibility}
            value = {'schema_version': 1, 'identity': identity, 'channel': 'stable',
                     'update_sequence': identity['build_number'], 'compatibility': compatibility, 'packages': [package]}
            if digest:
                value['container'] = {'image': repository, 'digest': digest, 'sha': identity['sha'],
                    'release_tag': identity['tag'], 'version': identity['version'], 'tag': identity['tag'][1:]}
            raw = json.dumps(value).encode(); path.write_bytes(raw)
            private(path.with_suffix('.sig'), {'algorithm': 'Ed25519', 'key_id': 'qa',
                'signature': base64.b64encode(release_key.sign(raw)).decode()})
        signed({**target_build, 'version': '1.0.27', 'tag': 'v1.0.27', 'build_number': 1065,
                'compatibility': {**target_build['compatibility'], 'state_schema_max': 11}}, work/'previous.json')
        signed(target_build, work/'target.json', reference.split('@')[1])
        worker_context = work/'worker-context'; worker_context.mkdir()
        (worker_context/'Dockerfile').write_text('ARG FFIDO_IMAGE=scratch\nARG HPT_IMAGE=scratch\nFROM ${FFIDO_IMAGE} AS release\nFROM ${HPT_IMAGE}\nUSER root\nRUN rm -rf /opt/ffido\nCOPY --from=release /opt/ffido/ /opt/ffido/\n')
        state = work/'state'; state.mkdir(mode=0o700)
        override = root/'ffido/updates/image-override.json'
        private(override, {'services': {'backend': {'image': source_backend},
                                       'tosser': {'image': source_worker}}, 'x-operator-note': 'preserve'})
        override.chmod(0o640)
        private(state/'sequence.json', {'value': 1065})
        def digest(path):
            with Path(path).open('rb') as source: return hashlib.file_digest(source, 'sha256').hexdigest()
        components = {}
        for role in ('renewal', 'cron', 'firewall', 'acme'):
            directory = work/role; directory.mkdir()
            (directory/'fixture').write_text('Isolated '+role+' configuration\n')
            components[role] = {'root': str(directory), 'required': ['fixture']}
        components.update({
            'deployment': {'root': str(root), 'required': ['docker-compose.yaml', 'config.json', 'ffido/deployed-identity.json'],
                           'includes': ['docker-compose.yaml', '.env', 'config.json', 'ffido/deployed-identity.json']},
            'images': {'root': str(state/'rollback-images'), 'required': ['images.tar', 'images.json']},
            'updater': {'root': str(work), 'required': ['shadow/scripts/update/public_keys.json', 'previous.json', 'previous.sig'],
                        'includes': ['shadow/scripts', 'previous.json', 'previous.sig']},
            'gateway': {'root': str(gateway_root), 'required': ['envoy.json']},
            'tls': {'root': str(tls), 'required': ['ca.pem', 'server.pem', 'server-key.pem']}})
        probes = [str(sys.executable), str(ROOT/'scripts/update/pair_acceptance.py')]
        plan = {'version': 1, 'source': {role: {'image_id': image, 'build': source_build, 'platform': 'linux/amd64'}
                for role, image in [('backend', source_backend), ('tosser', source_worker)]},
            'files': {str(path): digest(path) for path in (compose_file, root/'config.json', root/'ffido/deployed-identity.json', override)},
            'services': {'backend': 'backend', 'tosser': 'tosser'}, 'writers': ['backend', 'tosser', 'mailer'],
            'identity_file': str(root/'ffido/deployed-identity.json'),
            'container_config': str(root/'config.json'),
            'container_identity_file': str(root/'ffido/deployed-identity.json'),
            'signed_floor': {'manifest': str(work/'previous.json'), 'signature': str(work/'previous.sig')},
            'worker': {'context': str(worker_context), 'dockerfile': 'Dockerfile',
                'files': {'Dockerfile': digest(worker_context/'Dockerfile')}, 'hpt_image': source_worker, 'hpt_image_id': source_worker},
            'backup': {'root': str(root), 'config': 'config.json', 'maintenance_lock': 'maintenance.lock',
                'helper': helper, 'admin': str(args.admin.resolve()), 'mappings': [], 'includes': ['tls/ca.pem']},
            'components': components, 'require_full_restore': True,
            'extra_images': [args.toolkit_image] if args.toolkit_image else [],
            'probes': {'private': [[*probes, 'verify-state', '--fixture', str(fixture_path)]],
                       'public': [[*probes, 'verify-target', '--fixture', str(fixture_path)]],
                       'rollback_private': [[*probes, 'verify-state', '--fixture', str(fixture_path)]],
                       'rollback_public': [[*probes, 'verify-source', '--fixture', str(fixture_path)]],
                       'pair': [[*probes, 'verify-target', '--fixture', str(fixture_path)]]}}
        private(work/'plan.json', plan)
        cli = [str(sys.executable), str(shadow/'ffido-docker-update.py')]
        options = ['--compose-file', str(compose_file), '--service', 'backend', '--state-dir', str(state),
                   '--image-override', str(override),
                   '--pair-plan', str(work/'plan.json'), '--pair-plan-sha256', digest(work/'plan.json'),
                   '--target-manifest', str(work/'target.json'), '--target-signature', str(work/'target.sig'), '--target-tag', 'v1.0.28']
        original_backend = command(*compose, 'ps', '-q', 'backend')
        signature = (work/'target.sig').read_bytes()
        (work/'target.sig').write_text('{}')
        if command(*cli, 'apply', *options, success=False).returncode == 0:
            raise ValueError('Invalid signature accepted')
        if command(*compose, 'ps', '-q', 'backend') != original_backend:
            raise ValueError('Signature rejection interrupted source')
        (work/'target.sig').write_bytes(signature)
        recipe = (worker_context/'Dockerfile').read_bytes()
        (worker_context/'Dockerfile').write_bytes(recipe+b'# changed input\n')
        if command(*cli, 'apply', *options, success=False).returncode == 0:
            raise ValueError('Changed worker recipe accepted')
        (worker_context/'Dockerfile').write_bytes(recipe)
        if command(*compose, 'ps', '-q', 'backend') != original_backend:
            raise ValueError('Worker preparation failure interrupted source')
        command(*cli, 'check', *options)
        # Kill only the isolated controller after backend start, before worker start.
        launcher = shadow/'crash-launch.py'
        launcher.write_text('''import importlib,os,sys
updater=importlib.import_module('ffido-docker-update')
original=updater.Compose.run
def run(self,*args):
 result=original(self,*args)
 if 'gated-compose.json' in ' '.join(args) and 'up' in args and args[-1]=='backend':os._exit(86)
 return result
updater.Compose.run=run
raise SystemExit(updater.main(sys.argv[1:]))
''')
        if command(sys.executable, launcher, 'apply', *options, success=False).returncode != 86:
            raise ValueError('Controller crash injection did not reach pair startup')
        pending = json.loads((state/'pair-operation.json').read_text())
        if pending['phase'] != 'switching' or pending['admitted']:
            raise ValueError('Unsafe crash journal')
        current = command(*compose, 'ps', '-a', '-q', 'backend')
        status = json.loads(command('docker', 'inspect', current))[0]['State']
        if status['Running']:
            command('docker', 'kill', '--signal=SIGTERM', current)
            command('docker', 'wait', current)
        # A failed target can leave incompatible SQLite sidecars. Restore must
        # preserve those privately and never replay them over the trusted DB.
        (root/'metadata.db-wal').write_bytes(b'isolated-incompatible-wal')
        command(*cli, 'resume', *options)
        if json.loads((state/'pair-operation.json').read_text())['phase'] != 'rolled-back':
            raise ValueError('Interrupted pair not rolled back')
        acceptance('verify-state'); acceptance('verify-source')
        if not any(x.read_bytes() == b'isolated-incompatible-wal'
                   for x in state.glob('failed-database-*/metadata.db-wal')):
            raise ValueError('Failed target WAL was not quarantined')
        command(*cli, 'apply', *options)
        acceptance('verify-state'); acceptance('verify-target')
        if override.stat().st_mode & 0o777 != 0o640 or json.loads(override.read_text())['x-operator-note'] != 'preserve':
            raise ValueError('Canonical override metadata or unmanaged fields changed')
        admitted_state = pair_acceptance.state_hashes(root/'metadata.db')
        saved_baseline = json.loads(Path(fixture_config['state']).read_text())['baseline']
        if len(admitted_state['tokens']) <= len(saved_baseline['tokens']):
            raise ValueError('Fresh admitted Telegram session was not created')
        if command(*compose, 'ps', '-q', 'unrelated') != unrelated:
            raise ValueError('Unrelated service recreated')
        if gateway.poll() is not None:
            raise ValueError('Separate gateway exited')
        # An admitted target has new Telegram sessions. Returning the old snapshot
        # must fail and preserve a separate complete snapshot of those new writes.
        if command(*cli, 'rollback', *options, success=False).returncode == 0:
            raise ValueError('Admitted writes were overwritten by snapshot rollback')
        marker = json.loads((state/'reconciliation-required.json').read_text())
        if 'backup' not in marker:
            raise ValueError('Post-admission state was not preserved')
        if pair_acceptance.state_hashes(root/'metadata.db') != admitted_state:
            raise ValueError('Admitted state changed during forbidden snapshot rollback')
        saved_node = Path(marker['backup']['root'])/'node/metadata.db'
        if pair_acceptance.state_hashes(saved_node) != admitted_state:
            raise ValueError('Post-admission backup omitted new state')
        acceptance('verify-state')
        result = {'local_pair_to_signed_target': True, 'signed_sequence': 1066,
                  'source_build_unmodified': source_build['tag'], 'schema': 12,
                  'https_grpc_web_cors': True, 'telegram_hpt_sessions_mailboxes_receipts': True,
                  'unrelated_service_unchanged': True, 'gateway_pid_unchanged': True,
                  'invalid_signature_and_worker_change_rejected': True,
                  'controller_crash_full_restore_rollback': True,
                  'snapshot_rollback_after_admission_blocked': True,
                  'ftn_network': False, 'production_published': False}
        private(work/'result.json', result)
        succeeded = True
        print(json.dumps(result))
    finally:
        if gateway is not None:
            gateway.terminate(); gateway.wait(timeout=20)
        if compose_file is not None:
            command(*compose, 'logs', '--no-color', success=False)
            command(*compose, 'down', success=False)
        command('docker', 'rm', '-f', registry, success=False)
        if fixture is not None and succeeded:
            fixture.doCleanups()
        log.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--source-backend', default='ffido-safe-restore:candidate-schema-20261118')
    parser.add_argument('--source-worker', required=True)
    parser.add_argument('--builder', default='ffido-safe-restore-builder:candidate-validated-20261118')
    parser.add_argument('--admin', type=Path, default=ROOT/'build/backend/apps/backend/ffido-admin')
    parser.add_argument('--envoy', type=Path, default=ROOT/'build/tools/envoy/1.39.3/bin/envoy')
    parser.add_argument('--toolkit-image', help='Immutable QA host image to include in the full backup')
    parser.add_argument('--target-image', help='Reuse a prepared isolated QA target')
    parser.add_argument('--telegram-key-file', type=Path, help='Private fixture file for that QA target')
    options = parser.parse_args()
    if sys.platform != 'linux':
        parser.error('Run the controller in the isolated Linux QA host; JAM identities are kernel-specific')
    if options.target_image and not options.telegram_key_file:
        parser.error('--target-image requires its private --telegram-key-file')
    run(options)
