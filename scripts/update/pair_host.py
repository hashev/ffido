"""Compose adapter for an explicitly registered stopped-node pair transition."""
import base64
import contextlib
import copy
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sqlite3
import time
import tempfile
import uuid

import common
import deployment_backup as deployment
import node_backup as node
from server import atomic_bytes, atomic_json

BUILD_PROBE = "from pathlib import Path;print(Path('/opt/ffido/BUILD.json').read_text())"
WORKER_GATE = '''import contextlib,json,pathlib,signal,socket,sqlite3,subprocess,sys
config_path=pathlib.Path(sys.argv[1]);config=json.loads(config_path.read_text())
expected=json.loads(pathlib.Path(sys.argv[2]).read_text())
actual=json.loads(pathlib.Path('/opt/ffido/BUILD.json').read_text())
assert all(actual[k]==expected[k] for k in ('tag','sha','build_number'))
for args in (['/opt/ffido/bin/ffido-admin','--help'],
 ['/opt/ffido/bin/ffido-hpt-auth',config['auth']['hpt_config_path'],json.dumps(config['ftn'].get('path_mappings',[]))]):
 result=subprocess.run(args,capture_output=True,timeout=15)
 if result.returncode:raise SystemExit(3)
database=pathlib.Path(config['database']['metadata_path'])
database=database if database.is_absolute() else config_path.parent/database
with contextlib.closing(sqlite3.connect(database.resolve().as_uri()+'?mode=ro',uri=True)) as db:
 schema=db.execute('pragma user_version').fetchone()[0]
 assert actual['compatibility']['state_schema_min']<=schema<=actual['compatibility']['state_schema_max']
stop=False
def done(*args):
 global stop
 stop=True
signal.signal(signal.SIGTERM,done);signal.signal(signal.SIGINT,done)
ready=socket.socket();ready.bind(('127.0.0.1',34891));ready.listen();ready.settimeout(.1)
while not stop:
 try:connection,_=ready.accept()
 except TimeoutError:continue
 connection.close()
ready.close()
'''


def export_images(archive, images):
    """Atomically export Docker's lossless gzip load format inside the budget."""
    with tempfile.TemporaryDirectory(prefix='.image-export-', dir=archive.parent) as temporary:
        raw, compressed = Path(temporary)/'images.tar', Path(temporary)/'images.gz'
        subprocess.run(['docker', 'save', '--output', str(raw), *images],
                       check=True, capture_output=True, timeout=600)
        with raw.open('rb') as source, compressed.open('xb') as destination:
            os.fchmod(destination.fileno(), 0o600)
            with gzip.GzipFile(filename='', fileobj=destination, mode='wb', compresslevel=1, mtime=0) as output:
                shutil.copyfileobj(source, output, 1024*1024)
            destination.flush()
            os.fsync(destination.fileno())
        compressed.replace(archive)


class Host:
    def __init__(self, compose, plan, write_images):
        self.compose, self.plan, self.write_images = compose, plan, write_images
        self.state = compose.state
        self.services = plan['services']
        self.root = Path(plan['backup']['root']).resolve(strict=True)
        self.backup_options = plan['backup']
        required = {str(compose.file), str(self.root/node.relative(self.backup_options['config'])),
                    plan['identity_file']}
        node.require(required <= set(plan['files']), 'Register Compose, config and deployed identity hashes')
        self.maintenance_fd = None
        self.prepared = None
        node.require(set(self.services) == {'backend', 'tosser'} and
                     len(set(self.services.values())) == 2 and
                     self.services['backend'] == compose.service, 'Invalid pair services')
        self.writers = plan['writers']
        node.require(set(self.services.values()) <= set(self.writers) and
                     all(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,62}', x) for x in self.writers))
        self.gated = self.state/'gated-compose.json'

    def image_build(self, image):
        info = json.loads(self.compose.run('docker', 'image', 'inspect', image))[0]
        node.require(info['Os'] == 'linux' and info['Architecture'] == 'amd64', 'Wrong image platform')
        raw = self.compose.run('docker', 'run', '--rm', '--network', 'none', '--entrypoint',
                               'python3', info['Id'], '-c', BUILD_PROBE)
        return info, common.strict_json(raw.encode())

    def actual_source(self):
        result = {}
        for role, service in self.services.items():
            build, _, info = self.compose.inspect_image(service)
            result[role] = self.compose.local_identity(build, info)
        return result

    def assert_known_state(self, operation):
        for role, service in self.services.items():
            container = self.compose.command('ps', '-a', '-q', service)
            if container:
                info = json.loads(self.compose.run('docker', 'inspect', container))[0]
                allowed = {operation['baseline']['source'][role]['image_id'],
                           operation['prepared']['images'][role]}
                if operation['phase'] == 'complete':
                    allowed = {operation['prepared']['images'][role]}
                elif operation['phase'] in {'rolled-back', 'aborted'}:
                    allowed = {operation['baseline']['source'][role]['image_id']}
                node.require(info['Image'] in allowed, 'Unknown image in interrupted pair')
            else:
                node.require(operation['phase'] not in {'complete', 'rolled-back'},
                             'Accepted pair container is missing')

    def prepare(self, manifest):
        common.verify_local_pair(self.plan, self.actual_source())
        compatibility = manifest['compatibility']
        node.require(compatibility['protocol_major'] == 1 and compatibility['config_format'] == 1
                     and compatibility['jam_format'] == 'JAM-1', 'Unknown format migration')
        with node.open_file(self.root, self.backup_options['config']) as source:
            config = json.load(source)
        database = node.relative_input(self.root, config['database']['metadata_path'], self.backup_options['mappings'])
        with contextlib.closing(sqlite3.connect((self.root/database).as_uri()+'?mode=ro', uri=True)) as db:
            schema = db.execute('pragma user_version').fetchone()[0]
        node.require(compatibility['state_schema_min'] <= schema <= compatibility['state_schema_max'],
                     'Target is incompatible with current state')
        image = manifest['container']
        reference = image['image']+'@'+image['digest']
        self.compose.run('docker', 'pull', reference)
        target_info, target_build = self.image_build(reference)
        common.version_key(target_build)
        node.require(all(target_build.get(k) == v for k, v in manifest['identity'].items()),
                     'Pulled backend BUILD differs from signed target')
        node.require(target_build['compatibility'] == compatibility, 'Image compatibility differs from manifest')
        labels = target_info.get('Config', {}).get('Labels', {})
        node.require(labels.get('org.opencontainers.image.revision') == manifest['identity']['sha']
                     and labels.get('org.opencontainers.image.version') == manifest['identity']['tag'],
                     'Pulled image labels differ from manifest')
        worker = self.plan['worker']
        context = Path(worker['context']).resolve(strict=True)
        for name, digest in worker['files'].items():
            node.require(node.file_hash(context, name)[0] == digest, 'Worker recipe input changed')
        dockerfile = str(node.relative(worker['dockerfile']))
        node.require(dockerfile in worker['files'], 'Dockerfile must be pinned')
        recipe = (context/dockerfile).read_text()
        bases = re.findall(r'^FROM\s+(\S+)', recipe, re.I | re.M)
        node.require(bases == ['${FFIDO_IMAGE}', '${HPT_IMAGE}'], 'Use the pinned two-stage worker recipe')
        node.require(not re.search(r'^\s*ADD\s', recipe, re.I | re.M) and
                     all(x.strip() == 'rm -rf /opt/ffido' for x in re.findall(r'^RUN\s+(.+)$', recipe, re.I | re.M)),
                     'Worker recipe must reuse the pinned HPT runtime without mutable downloads')
        base = worker['hpt_image']
        node.require(re.fullmatch(r'(?:[^\s]+@)?sha256:[0-9a-f]{64}', base), 'Mutable HPT base')
        base_info = json.loads(self.compose.run('docker', 'image', 'inspect', base))[0]
        node.require(base_info['Id'] == worker['hpt_image_id'], 'HPT base identity changed')
        tag = 'ffido-pair-hpt-base:'+base_info['Id'].split(':')[1]
        self.compose.run('docker', 'tag', base_info['Id'], tag)
        worker_tag = 'ffido-pair-worker:'+hashlib.sha256((reference+recipe).encode()).hexdigest()
        self.compose.run('docker', 'build', '--platform', 'linux/amd64', '--network=none', '--pull=false', '-f', str(context/dockerfile),
                         '--build-arg', 'FFIDO_IMAGE='+reference, '--build-arg', 'HPT_IMAGE='+tag,
                         '-t', worker_tag, str(context))
        worker_info, worker_build = self.image_build(worker_tag)
        node.require(worker_build == target_build, 'Worker distribution differs from target backend')
        result = {'images': {'backend': target_info['Id'], 'tosser': worker_info['Id']},
                  'reference': reference, 'build': target_build,
                  'hpt_image_id': base_info['Id'], 'recipe_sha256': worker['files'][dockerfile]}
        extra = {}
        for reference in self.plan.get('extra_images', []):
            node.require(re.fullmatch(r'(?:[^\s]+@)?sha256:[0-9a-f]{64}', reference),
                         'Deployment image must use an immutable identity')
            info = json.loads(self.compose.run('docker', 'image', 'inspect', reference))[0]
            extra[reference] = info
        result['extra_images'] = {key: info['Id'] for key, info in extra.items()}
        exports = self.state/'rollback-images'
        node.require(not exports.is_relative_to(self.root), 'Image exports must be outside node data')
        exports.mkdir(mode=0o700, exist_ok=True)
        self.image_bytes = sum(x['Size'] for x in (target_info, worker_info))
        source_ids = [x['image_id'] for x in self.plan['source'].values()]
        self.image_bytes += sum(json.loads(self.compose.run('docker', 'image', 'inspect', x))[0]['Size'] for x in source_ids)
        self.image_bytes += sum(info['Size'] for info in extra.values())
        deployment.disk_budget(self.state, 0, self.image_bytes)
        archive = exports/'images.tar'
        metadata = exports/'images.json'
        cached = common.strict_json(metadata.read_bytes()) if metadata.exists() else {}
        reusable = (archive.is_file() and cached.get('source') == self.plan['source']
                    and cached.get('target') == result
                    and node.file_hash(exports, 'images.tar')[0] == cached.get('archive_sha256'))
        if not reusable:
            export_images(archive, [*source_ids, *result['images'].values(),
                                   *(info['Id'] for info in extra.values())])
            atomic_json(metadata, {'source': self.plan['source'], 'target': result,
                                  'archive_sha256': node.file_hash(exports, 'images.tar')[0]})
        node.require(Path(self.plan['components']['images']['root']).resolve() == exports.resolve(),
                     'Image backup component must refer to the prepared export')
        self.prepared = result
        return result

    def preflight(self):
        common.verify_local_pair(self.plan, self.actual_source())
        help_text = subprocess.run([self.backup_options['admin'], '--help'], check=True,
                                   capture_output=True, timeout=15).stdout
        node.require(b'--maintenance-lock-fd' in help_text, 'Restore toolkit lacks maintenance lease support')
        components = deployment.component_inventory(self.component_profile())
        source_bytes = node.estimated_input_bytes(self.root, self.backup_options['config'],
                                                  self.backup_options['helper'], self.backup_options['mappings'],
                                                  self.backup_options.get('includes', []),
                                                  self.backup_options['maintenance_lock'])
        source_bytes += sum(row['size'] for x in components for row in x['files'])
        self.budget = self.budget_report(source_bytes)

    def component_profile(self):
        profile = copy.deepcopy(self.plan['components'])
        updater = profile['updater']
        root = Path(updater['root']).resolve(strict=True)
        state = self.state.resolve(strict=True)
        node.require(state.is_relative_to(root), 'Updater component must cover transaction state')
        if 'includes' in updater:
            names = set(updater['includes'])
            for path in state.iterdir():
                if path.is_file() and not path.is_symlink():
                    names.add(str(path.relative_to(root)))
            updater['includes'] = sorted(names)
        return profile

    def budget_report(self, source_bytes):
        try:
            report = deployment.disk_budget(self.state, source_bytes, getattr(self, 'image_bytes', 0))
        except deployment.BudgetError as error:
            atomic_json(self.state/'space-budget.json', error.report)
            raise
        atomic_json(self.state/'space-budget.json', report)
        return report

    def baseline(self):
        statuses = {}
        for service in self.writers:
            container = self.compose.command('ps', '-a', '-q', service)
            statuses[service] = bool(container and json.loads(self.compose.run('docker', 'inspect', container))[0]['State']['Running'])
        node.require(statuses[self.services['backend']], 'Pair transition requires an active source backend')
        return {'running': statuses, 'source': self.plan['source'],
                'override': base64.b64encode(self.compose.override.read_bytes()).decode() if self.compose.override.exists() else None,
                'identity': base64.b64encode(Path(self.plan['identity_file']).read_bytes()).decode(),
                'provenance': common.strict_json((self.state/'pair-provenance.json').read_bytes())
                    if (self.state/'pair-provenance.json').exists() else None}

    def quiesce(self):
        for service in reversed(self.writers):
            self.stop_service(service)

    def stop_service(self, service):
        container = self.compose.command('ps', '-a', '-q', service)
        if not container:
            return
        info = json.loads(self.compose.run('docker', 'inspect', container))[0]
        if info['State']['Running']:
            signal = 'SIGINT' if service == self.plan.get('jamnntpd_service') else 'SIGTERM'
            self.compose.run('docker', 'kill', '--signal='+signal, container)
            self.compose.run('docker', 'wait', container)

    def backup(self, name='backup'):
        profile = self.component_profile()
        components = deployment.component_inventory(profile)
        source_bytes = node.estimated_input_bytes(self.root, self.backup_options['config'],
                                                  self.backup_options['helper'], self.backup_options['mappings'],
                                                  self.backup_options.get('includes', []),
                                                  self.backup_options['maintenance_lock'])
        source_bytes += sum(row['size'] for x in components for row in x['files'])
        self.budget_report(source_bytes)
        components = deployment.component_inventory(self.component_profile())
        snapshots = self.state/'snapshots'
        snapshots.mkdir(mode=0o700, exist_ok=True)
        destination = snapshots/(name+'-'+uuid.uuid4().hex)
        destination.mkdir(mode=0o700)
        options = self.backup_options
        result = node.snapshot(self.root, destination/'node', options['config'], options['helper'],
                               options['mappings'], options.get('includes', []), options['maintenance_lock'],
                               held_locks={options['maintenance_lock']: self.maintenance_fd})
        digest = deployment.complete(destination, result['manifest_sha256'], components)
        return {'root': str(destination), 'sha256': digest}

    def switch(self, prepared, preserve_identity=False):
        self.prepared = prepared
        self.write_images(self.compose.override, {self.services[k]: v for k, v in prepared['images'].items()})
        if not preserve_identity:
            identity = Path(self.plan['identity_file'])
            atomic_json(identity, prepared['build'], metadata=identity.stat(follow_symlinks=False))
        effective = json.loads(self.compose.command('config', '--format', 'json'))
        self.project = effective['name']
        for role, service in self.services.items():
            value = effective['services'][service]
            value.pop('networks', None)
            value.update(network_mode='none', ports=[], restart='no')
            if role == 'tosser':
                value['entrypoint'] = ['python3', '-c', WORKER_GATE,
                    self.plan.get('container_config', '/etc/ffido/config.json'),
                    self.plan.get('container_identity_file', '/home/fido/ffido/deployed-identity.json')]
                value['command'] = []
                value['healthcheck'] = {'test': ['CMD', 'python3', '-c',
                    "import socket;socket.create_connection(('127.0.0.1',34891),timeout=2).close()"],
                    'interval': '1s', 'timeout': '5s', 'retries': 10}
        atomic_json(self.gated, effective)
        for service in self.services.values():
            self.compose.run('docker', 'compose', '-p', self.project, '-f', str(self.gated),
                             'up', '-d', '--no-deps', service)

    def probe(self, group):
        probes = self.plan['probes'][group]
        node.require(probes and all(isinstance(x, list) and x for x in probes), 'Missing acceptance probes')
        for args in probes:
            result = subprocess.run(args, capture_output=True, timeout=120)
            if result.returncode:
                path = self.state/'probe.private.log'
                with path.open('wb') as diagnostics:
                    os.fchmod(diagnostics.fileno(), 0o600)
                    diagnostics.write(result.stdout+result.stderr)
            node.require(result.returncode == 0, 'Acceptance probe failed; inspect private diagnostics')

    def wait_health(self, images):
        for role, image in images.items():
            service = self.services[role]
            for _ in range(90):
                container = self.compose.command('ps', '-a', '-q', service)
                info = json.loads(self.compose.run('docker', 'inspect', container))[0]
                node.require(info['Image'] == image, 'Mixed pair image identity')
                if info['State'].get('Health', {}).get('Status') == 'healthy':
                    break
                node.require(info['State']['Running'], 'Gated service exited')
                time.sleep(1)
            else:
                raise ValueError('Pair readiness timeout')
    def validate_private(self, group='private'):
        self.wait_health(self.prepared['images'])
        self.probe(group)

    def open_ingress(self):
        self.compose.command('up', '-d', '--no-deps', self.services['backend'])
        self.wait_health({'backend': self.prepared['images']['backend']})

    def validate_public(self):
        self.probe('public')

    def commit(self, sequence):
        from pair_update import commit_floor
        commit_floor(self.state, sequence)
        atomic_json(self.state/'pair-provenance.json',
                    {'signed': self.signed_evidence, 'build': self.prepared['build'],
                     'source': {role: {'image_id': image, 'build': self.prepared['build'],
                                       'platform': 'linux/amd64'}
                                for role, image in self.prepared['images'].items()}})

    def release_writers(self, baseline):
        for service, running in baseline['running'].items():
            if running:
                self.compose.command('up', '-d', '--no-deps', service)
            else:
                self.stop_service(service)
        self.wait_health({role: self.prepared['images'][role] for role, service in self.services.items()
                          if baseline['running'][service]})
        self.probe('pair')

    def return_original(self, baseline):
        for service, running in baseline['running'].items():
            if running:
                self.compose.command('up', '-d', '--no-deps', service)
            else:
                self.stop_service(service)
        self.wait_health({role: baseline['source'][role]['image_id'] for role, service in self.services.items()
                          if baseline['running'][service]})

    def validate_rollback_public(self):
        self.probe('rollback_public')

    def open_rollback_ingress(self, baseline):
        self.compose.command('up', '-d', '--no-deps', self.services['backend'])
        self.wait_health({'backend': baseline['source']['backend']['image_id']})

    def preserve_current(self):
        marker = self.state/'reconciliation-required.json'
        value = {'automatic_restore_blocked': True, 'writers_stopped': True}
        if marker.exists():
            previous = common.strict_json(marker.read_bytes())
            if 'backup' in previous:
                deployment.verify(previous['backup']['root'], previous['backup']['sha256'])
                return
        atomic_json(marker, value)
        value['backup'] = self.backup('post-admission-backup')
        atomic_json(marker, value)

    def rollback_compatible(self, baseline):
        self.quiesce()
        with node.open_file(self.root, self.backup_options['config']) as source:
            config = json.load(source)
        database = node.relative_input(self.root, config['database']['metadata_path'], self.backup_options['mappings'])
        with contextlib.closing(sqlite3.connect((self.root/database).as_uri()+'?mode=ro', uri=True)) as db:
            schema = db.execute('pragma user_version').fetchone()[0]
        return all(x['build'].get('compatibility', {}).get('state_schema_min', 999) <= schema <=
                   x['build'].get('compatibility', {}).get('state_schema_max', -1)
                   and x['build']['compatibility'].get('jam_format') == 'JAM-1'
                   and x['build']['compatibility'].get('config_format') == 1
                   for x in baseline['source'].values()) and not self.plan.get('require_full_restore', False)

    def restore_pair(self, baseline):
        images = {}
        for role, registered in baseline['source'].items():
            try:
                info, build = self.image_build(registered['image_id'])
            except RuntimeError:
                operation = common.strict_json((self.state/'pair-operation.json').read_bytes())
                backup = operation['backup']
                deployment.verify(backup['root'], backup['sha256'])
                archive = Path(backup['root'])/'components/images/images.tar'
                subprocess.run(['docker', 'load', '--input', str(archive)], check=True,
                                capture_output=True, timeout=600)
                info, build = self.image_build(registered['image_id'])
            node.require(info['Id'] == registered['image_id'] and build == registered['build'], 'Rollback image changed')
            images[self.services[role]] = registered['image_id']
        if baseline['override'] is None:
            self.compose.override.unlink(missing_ok=True)
        else:
            # Parse authenticated original bytes before making a durable restore.
            original_override = base64.b64decode(baseline['override'], validate=True)
            common.strict_json(original_override)
            atomic_bytes(self.compose.override, original_override,
                         metadata=self.compose.override.stat(follow_symlinks=False) if self.compose.override.exists() else None)
        self.write_images(self.compose.override, images)
        identity = base64.b64decode(baseline['identity'], validate=True)
        common.strict_json(identity)
        identity_file = Path(self.plan['identity_file'])
        atomic_bytes(identity_file, identity, metadata=identity_file.stat(follow_symlinks=False))
        if baseline.get('provenance'):
            atomic_json(self.state/'pair-provenance.json', baseline['provenance'])
        else:
            (self.state/'pair-provenance.json').unlink(missing_ok=True)

    def validate_rollback(self):
        # Probe before returning FTN writers; use the original registered pair.
        prepared = {'images': {k: x['image_id'] for k, x in self.plan['source'].items()},
                    'build': self.plan['source']['backend']['build']}
        self.switch(prepared, preserve_identity=True)
        self.validate_private('rollback_private')

    def restore(self, backup):
        value = deployment.verify(backup['root'], backup['sha256'])
        staging = self.state/'restore-staging'
        if staging.exists():
            node.require(not staging.is_symlink() and (self.state/'pair-operation.json').is_file(),
                         'Unknown restore staging')
            shutil.rmtree(staging)
        deployment.restore(backup['root'], backup['sha256'], staging)
        manifest = staging/'node/snapshot.json'
        snapshot = node.verify(staging/'node', manifest, value['node_manifest_sha256'])
        for component in value['components']:
            if component['role'] in {'deployment', 'updater', 'images'}:
                continue
            for row in component['files']:
                node.require(node.file_hash(component['root'], row['source'])[0] == row['sha256'],
                             'External deployment changed; inspect staged baseline before host restore')
        # Hold instance/HPT locks during file replacement. Keep maintenance leased
        # across the subsequent admin recheck, which reacquires and verifies all files.
        with node.stopped(self.root, snapshot['locks'],
                          {self.backup_options['maintenance_lock']: self.maintenance_fd}):
            changed_directories = {self.root, self.state}
            quarantine = self.state/('failed-database-'+uuid.uuid4().hex)
            quarantine.mkdir(mode=0o700)
            for suffix in ('', '-wal', '-shm', '-journal'):
                name = snapshot['database']+suffix
                target = self.root/name
                if target.exists():
                    digest, info = node.file_hash(self.root, name)
                    deployment.copy_verified(self.root, name, quarantine/target.name,
                                              digest, info.st_mode & 0o777)
                    target.unlink()
                    changed_directories.update({target.parent, quarantine})
            for row in snapshot['files']:
                target = self.root/row['path']
                if row['path'] in snapshot['locks'] or target.is_relative_to(self.state):
                    continue
                target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                temporary = target.with_name(target.name+'.pair-restore')
                temporary.unlink(missing_ok=True)
                deployment.copy_verified(staging/'node', row['path'], temporary, row['sha256'], row['mode'])
                os.chown(temporary, row['uid'], row['gid'])
                temporary.replace(target)
                changed_directories.update(p for p in target.parents if p.is_relative_to(self.root))
            deployment.sync_directories(changed_directories)
        node.verify(self.root, manifest, value['node_manifest_sha256'])
        # External components remain staged: installing host cron/firewall is explicit.
        args = [self.backup_options['admin'], 'mailbox-restore', str(self.root), str(manifest),
                value['node_manifest_sha256']]
        lease = ['--maintenance-lock-fd', str(self.maintenance_fd)]
        result = subprocess.run([*args, 'check', *lease], pass_fds=(self.maintenance_fd,),
                                capture_output=True, timeout=120)
        if result.returncode:
            with (self.state/'restore-admin.private.log').open('wb') as log:
                os.fchmod(log.fileno(), 0o600)
                log.write(result.stdout+result.stderr)
            raise ValueError('Restore admin check failed; inspect private diagnostics')
        plan_digest = common.strict_json(result.stdout)['plan_digest']
        result = subprocess.run([*args, 'apply', plan_digest, *lease], pass_fds=(self.maintenance_fd,),
                                capture_output=True, timeout=120)
        if result.returncode:
            with (self.state/'restore-admin.private.log').open('wb') as log:
                os.fchmod(log.fileno(), 0o600)
                log.write(result.stdout+result.stderr)
            raise ValueError('Restore admin apply failed; inspect private diagnostics')
