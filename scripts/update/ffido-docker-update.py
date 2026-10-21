#!/usr/bin/env python3
"""Update one Compose service using the authenticated FFIDO image digest."""
import argparse
import json
import pathlib
import re
import subprocess
import sys
import time
import common
import discovery
from server import atomic_json, locked

SCHEMA_PROBE = '''import contextlib,json,pathlib,sqlite3,sys
p=pathlib.Path(sys.argv[1]);c=json.loads(p.read_text());d=pathlib.Path(c.get('database',{}).get('metadata_path','./data/metadata.db'));d=d if d.is_absolute() else p.parent/d
with contextlib.closing(sqlite3.connect(d.resolve().as_uri()+'?mode=ro',uri=True)) as db: print(db.execute('PRAGMA user_version').fetchone()[0])
'''


class Compose:
    def __init__(self, file, service, state):
        self.file, self.service, self.state = file.resolve(strict=True), service, state
        self.override = state/'image-override.json'

    def run(self, *args):
        result = subprocess.run(list(args), cwd=self.file.parent, capture_output=True, text=True)
        if result.returncode: raise RuntimeError('Docker command failed; inspect the service logs locally')
        if len(result.stdout) > common.MAX_METADATA: raise ValueError('Docker response exceeds size limit')
        return result.stdout.strip()

    def command(self, *args, override=True):
        base = ['docker', 'compose', '-f', str(self.file)]
        if override and self.override.exists(): base += ['-f', str(self.override)]
        return self.run(*base, *args)

    def inspect(self):
        container = self.command('ps', '-a', '-q', self.service)
        if not re.fullmatch('[0-9a-f]{12,64}', container): raise ValueError('Expected exactly one existing FFIDO container')
        info = json.loads(self.run('docker', 'inspect', container))[0]
        version_probe = "from pathlib import Path;print(Path('/opt/ffido/BUILD.json').read_text())"
        version = self.run('docker', 'exec', container, 'python3', '-c', version_probe) if info.get('State', {}).get('Running') else self.run('docker', 'run', '--rm', '--entrypoint', 'python3', info['Image'], '-c', version_probe)
        build = common.strict_json(version.encode())
        common.version_key(build)
        image = json.loads(self.run('docker', 'image', 'inspect', info['Image']))[0]
        digests = [value for value in image.get('RepoDigests', []) if re.fullmatch(r'(?:docker.io/)?hashev/ffido@sha256:[0-9a-f]{64}', value)]
        return build, digests[0] if digests else None, info

    def schema(self, config):
        output = self.command('run', '--rm', '--no-deps', '--entrypoint', 'python3', self.service, '-c', SCHEMA_PROBE, config)
        if not re.fullmatch(r'\d+', output): raise ValueError('Cannot identify container state schema')
        return int(output)

    def ready(self, digest, timeout=90):
        deadline = time.monotonic()+timeout
        while time.monotonic() < deadline:
            container = self.command('ps', '-a', '-q', self.service)
            if container:
                info = json.loads(self.run('docker', 'inspect', container))[0]
                status = info.get('State', {})
                if status.get('Health', {}).get('Status') == 'healthy':
                    actual = json.loads(self.run('docker', 'image', 'inspect', info['Image']))[0]
                    if not any(value.endswith('@'+digest) for value in actual.get('RepoDigests', [])):
                        raise ValueError('Running image digest differs from selected release')
                    return
                if status.get('Status') in {'exited', 'dead'}: break
            time.sleep(1)
        raise ValueError('New server is not ready; previous digest is recorded, automatic rollback is disabled')


def apply(compose, manifest, raw, signature, config, old_digest):
    compatibility = manifest['compatibility']
    if compatibility['protocol_major'] != 1 or compatibility['config_format'] != 1 or compatibility['jam_format'] != 'JAM-1':
        raise ValueError('Unknown format migration')
    image = manifest.get('container', {})
    reference = image.get('image', '')+'@'+image.get('digest', '')
    if not re.fullmatch(r'docker.io/hashev/ffido@sha256:[0-9a-f]{64}', reference): raise ValueError('Missing verified container image')
    compose.run('docker', 'pull', reference)
    actual = json.loads(compose.run('docker', 'image', 'inspect', reference))[0]
    labels = actual.get('Config', {}).get('Labels', {})
    if (actual.get('Architecture') != 'amd64' or actual.get('Os') != 'linux'
            or labels.get('org.opencontainers.image.revision') != manifest['identity']['sha']
            or labels.get('org.opencontainers.image.version') != manifest['identity']['tag']):
        raise ValueError('Pulled image identity/platform differs from signed manifest')
    # Persist the signed inputs before stopping A or publishing a resumable journal.
    (compose.state/'selected-manifest.json').write_bytes(raw)
    (compose.state/'selected-manifest.sig').write_bytes(signature)
    # Read schema with the old distribution after a graceful stop, before replacing it.
    compose.command('stop', compose.service)
    try:
        schema = compose.schema(config)
        if not compatibility['state_schema_min'] <= schema <= compatibility['state_schema_max']: raise ValueError('Container state schema is incompatible')
    except Exception:
        compose.command('start', compose.service)
        raise
    try:
        record = {'phase': 'prepared', 'previous_digest': old_digest, 'selected': reference}
        atomic_json(compose.state/'operation.json', record)
        atomic_json(compose.override, {'services': {compose.service: {'image': reference}}})
    except Exception:
        compose.command('start', compose.service)
        raise
    compose.command('up', '-d', '--no-deps', compose.service)
    compose.ready(image['digest'])
    atomic_json(compose.state/'operation.json', {**record, 'phase': 'complete'})


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['check', 'apply', 'rollback'])
    parser.add_argument('--compose-file', type=pathlib.Path, required=True)
    parser.add_argument('--service', required=True)
    parser.add_argument('--state-dir', type=pathlib.Path)
    parser.add_argument('--container-config', default='/etc/ffido/config.json')
    parser.add_argument('--channel', choices=['stable', 'dev'])
    args = parser.parse_args(argv)
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,62}', args.service): parser.error('Invalid service name')
    state = (args.state_dir or args.compose_file.resolve().parent/'.ffido-update').resolve()
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    compose = Compose(args.compose_file, args.service, state)
    keys = common.strict_json(pathlib.Path(__file__).with_name('public_keys.json').read_bytes())
    with locked(state/'operation.lock'):
        installed, old_digest, info = compose.inspect()
        configuration = json.loads(compose.command('config', '--format', 'json'))['services'][args.service]
        health = configuration.get('healthcheck', {})
        test = health.get('test', [])
        if (health.get('disable') or len(test) != 6 or test[0] != 'CMD'
                or test[1] not in {'fidoback', '/opt/ffido/bin/fidoback'} or test[2] != '--check-ready'):
            raise ValueError('Configure the documented TLS gRPC healthcheck before updating')
        targets = {mount['Destination'] for mount in info.get('Mounts', [])}
        if not {'/etc/ffido/config.json', '/etc/ffido/tls', '/var/lib/ffido', '/srv/fido'} <= targets:
            raise ValueError('Required persistent mounts are missing; use the documented Compose layout')
        if args.action == 'rollback':
            record = common.strict_json((state/'operation.json').read_bytes())
            previous = record.get('previous_digest')
            if not isinstance(previous, str) or not re.fullmatch(r'(?:docker.io/)?hashev/ffido@sha256:[0-9a-f]{64}', previous): raise ValueError('No previous published digest')
            # Inspect the previous image metadata without starting a second writer.
            compose.run('docker', 'pull', previous)
            previous_build = common.strict_json(compose.run('docker', 'run', '--rm', '--entrypoint', 'python3', previous, '-c', "from pathlib import Path;print(Path('/opt/ffido/BUILD.json').read_text())").encode())
            compatibility = previous_build.get('compatibility', {})
            if compatibility.get('config_format') != 1 or compatibility.get('jam_format') != 'JAM-1': raise ValueError('Unknown previous state format')
            compose.command('stop', args.service)
            try:
                schema = compose.schema(args.container_config)
                if not compatibility.get('state_schema_min', 999999) <= schema <= compatibility.get('state_schema_max', -1): raise ValueError('Rollback requires a compatible backup')
            except Exception: compose.command('start', args.service); raise
            atomic_json(compose.override, {'services': {args.service: {'image': previous}}})
            compose.command('up', '-d', '--no-deps', args.service)
            compose.ready(previous.split('@')[1])
            atomic_json(state/'operation.json', {'phase': 'complete', 'previous_digest': old_digest, 'selected': previous})
            print('Rollback ready: '+previous); return 0
        operation = state/'operation.json'
        if args.action == 'apply' and operation.exists():
            pending = common.strict_json(operation.read_bytes())
            if pending.get('phase') == 'prepared':
                raw = (state/'selected-manifest.json').read_bytes()
                signature = (state/'selected-manifest.sig').read_bytes()
                manifest = common.verify_manifest(raw, signature, keys)
                if pending.get('selected') != manifest['container']['image']+'@'+manifest['container']['digest']:
                    raise ValueError('Interrupted update record differs from signed manifest')
                apply(compose, manifest, raw, signature, args.container_config, pending.get('previous_digest'))
                print('Interrupted update completed'); return 0
        sequence = common.strict_json((state/'sequence.json').read_bytes())['value'] if (state/'sequence.json').exists() else 0
        sequence = max(sequence, installed['build_number'])
        choices = discovery.releases(installed, keys, args.channel or ('stable' if installed['stable'] else 'dev'), sequence)
        chosen = next((item for item in choices if item[0].get('container')), None)
        print(json.dumps({'current': installed['tag'], 'available': chosen[0]['identity']['tag'] if chosen else None}))
        if chosen is None: return 0
        atomic_json(state/'sequence.json', {'value': chosen[0]['update_sequence']})
        if args.action == 'apply': apply(compose, *chosen, args.container_config, old_digest)
        return 0


if __name__ == '__main__':
    try: raise SystemExit(main())
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        print('Docker update failed: '+str(error), file=sys.stderr); raise SystemExit(1)
