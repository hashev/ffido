"""Managed, offline-applicable updates of the full native FFIDO distribution."""
import argparse
import contextlib
import fcntl
import json
import os
import pathlib
import platform
import shutil
import sqlite3
import stat
import sys
import tempfile
import common
import discovery


def read(path):
    return common.strict_json(pathlib.Path(path).read_bytes())


def atomic_json(path, value):
    path = pathlib.Path(path)
    fd, temporary = tempfile.mkstemp(prefix='.update-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as out:
            json.dump(value, out, indent=2); out.write('\n'); out.flush(); os.fsync(out.fileno())
        os.replace(temporary, path)
    finally:
        pathlib.Path(temporary).unlink(missing_ok=True)


@contextlib.contextmanager
def locked(path, create=True):
    fd = os.open(path, os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC | (os.O_CREAT if create else 0), 0o600)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ValueError('Lock must be a regular file')
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError('Server or another update operation is still running; stop it first') from error
        yield
    finally:
        os.close(fd)


def compatible(package):
    target = package['platform']
    os_name = {'Darwin': 'macos', 'Linux': 'linux'}.get(platform.system())
    arch = {'aarch64': 'arm64', 'AMD64': 'x86_64'}.get(platform.machine(), platform.machine())
    if target != {'os': os_name, 'architecture': arch} or package['component'] != 'server':
        return False
    minimum = package['min_os']
    def numbers(version): return tuple(map(int, version.split('.')))
    if os_name == 'macos':
        return numbers(platform.mac_ver()[0]) >= numbers(minimum['version'])
    if os_name == 'linux':
        info = platform.freedesktop_os_release()
        return info.get('ID') == minimum['distribution'] and numbers(info['VERSION_ID']) >= numbers(minimum['version'])
    return False


def config_state(config_path, root):
    root = root.resolve(strict=True)
    config_path = pathlib.Path(config_path).resolve(strict=True)
    if config_path.is_relative_to(root/'releases'):
        raise ValueError('Configuration must be outside release directories')
    config = read(config_path)
    database = pathlib.Path(config.get('database', {}).get('metadata_path', './data/metadata.db'))
    if not database.is_absolute(): database = config_path.parent/database
    database = database.resolve(strict=True)
    if database.is_relative_to(root/'releases'):
        raise ValueError('State must be outside release directories')
    return database


def check_state(database, compatibility):
    if (compatibility.get('protocol_major') != 1 or compatibility.get('config_format') != 1
            or compatibility.get('jam_format') != 'JAM-1'):
        raise ValueError('Unknown protocol/config/JAM migration; follow a separate migration procedure')
    # mode=ro reads WAL correctly without invoking the server's migrating store.
    with contextlib.closing(sqlite3.connect(database.as_uri()+'?mode=ro', uri=True)) as connection:
        schema = connection.execute('PRAGMA user_version').fetchone()[0]
    if not compatibility['state_schema_min'] <= schema <= compatibility['state_schema_max']:
        raise ValueError('Incompatible state schema; restore an agreed backup or perform a documented migration')


def release_path(root, target):
    if not isinstance(target, str) or pathlib.PurePosixPath(target).parts[:1] != ('releases',):
        raise ValueError('Invalid managed release target')
    result = root/target
    if len(pathlib.PurePosixPath(target).parts) != 2 or not result.resolve().is_relative_to((root/'releases').resolve()):
        raise ValueError('Release target escapes managed installation')
    return result


def current_target(root):
    current = root/'current'
    if not current.is_symlink(): raise ValueError('Expected managed layout ROOT/current -> releases/VERSION; see bootstrap instructions')
    target = os.readlink(current)
    release_path(root, target)
    return target


def package_record(manifest):
    packages = [row for row in manifest['packages'] if compatible(row)]
    if len(packages) != 1: raise ValueError('Release has no unique compatible server package')
    return packages[0]


def stage(root, manifest, raw, signature):
    package = package_record(manifest)
    tag = manifest['identity']['tag']
    downloads = root/'.downloads'/tag
    downloads.mkdir(parents=True, exist_ok=True)
    archive = common.download(package, downloads)
    if shutil.disk_usage(root).free < max(archive.stat().st_size * 3, 64 * 1024**2):
        raise ValueError('Not enough free space to stage update')
    target = root/'releases'/tag
    if target.exists():
        stored = target/'.update/manifest.json'
        if not stored.is_file() or stored.read_bytes() != raw: raise ValueError('Existing release differs; use a new version')
        common.verify_manifest(stored.read_bytes(), (target/'.update/manifest.sig').read_bytes(), TRUSTED_KEYS)
        atomic_json(root/'.selected-update.json', {'target': 'releases/'+tag})
        return tag
    work = pathlib.Path(tempfile.mkdtemp(prefix='.stage-', dir=root))
    try:
        unpacked = common.safe_extract(archive, work/'unpacked')
        roots = list(unpacked.iterdir())
        if len(roots) != 1 or not roots[0].is_dir() or roots[0].is_symlink(): raise ValueError('Expected one full server bundle')
        bundle = roots[0]
        build = read(bundle/'BUILD.json')
        for key in ('version', 'sha', 'tag', 'stable', 'build_number', 'component', 'platform', 'compatibility'):
            if build.get(key) != package.get(key): raise ValueError('BUILD.json differs from signed package')
        for name in ('fidoback', 'ffido-admin', 'ffido-hpt-auth', 'ffido-run-hpt', 'ffido-update'):
            binary = bundle/'bin'/name
            if not binary.is_file() or binary.is_symlink() or not os.access(binary, os.X_OK): raise ValueError('Incomplete server bundle: '+name)
        if not (bundle/'lib').is_dir() or not (bundle/'share/ffido').is_dir(): raise ValueError('Missing runtime or share directory')
        (bundle/'.update').mkdir()
        (bundle/'.update/manifest.json').write_bytes(raw)
        (bundle/'.update/manifest.sig').write_bytes(signature)
        (root/'releases').mkdir(exist_ok=True)
        os.rename(bundle, target)
        atomic_json(root/'.selected-update.json', {'target': 'releases/'+tag})
        return tag
    finally:
        shutil.rmtree(work)


def switch(root, target, config_path, keys, rollback=False):
    release = release_path(root, target)
    data = (release/'.update/manifest.json').read_bytes()
    signature = (release/'.update/manifest.sig').read_bytes()
    manifest = common.verify_manifest(data, signature, keys)
    package_record(manifest)
    if manifest['identity']['tag'] != release.name: raise ValueError('Managed release identity mismatch')
    database = config_state(config_path, root)
    with locked(root/'.running.lock'), locked(str(database)+'.lock', create=False):
        check_state(database, manifest['compatibility'])
        old = current_target(root)
        if old == target: return
        if not rollback:
            current = read(release_path(root, old)/'BUILD.json')
            if not common.newer(manifest['identity'], current, 'dev'):
                raise ValueError('Apply cannot downgrade; use explicit compatible rollback')
        atomic_json(root/'.update-journal.json', {'from': old, 'to': target, 'phase': 'prepared'})
        temporary = root/'.current-next'
        temporary.unlink(missing_ok=True)
        temporary.symlink_to(target)
        os.replace(temporary, root/'current')
        atomic_json(root/'.previous-update.json', {'target': old})
        atomic_json(root/'.update-journal.json', {'from': old, 'to': target, 'phase': 'complete'})


TRUSTED_KEYS = {}


def main(argv=None, distribution=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['version', 'check', 'download', 'apply', 'rollback'])
    parser.add_argument('--install-root', type=pathlib.Path)
    parser.add_argument('--config', type=pathlib.Path)
    parser.add_argument('--channel', choices=['stable', 'dev'])
    parser.add_argument('--version')
    args = parser.parse_args(argv)
    distribution = pathlib.Path(distribution or pathlib.Path(__file__).resolve().parents[3])
    try:
        build = read(distribution/'BUILD.json')
    except FileNotFoundError:
        if args.action == 'version': print('FFIDO server (development build)'); return 0
        parser.error('Use an installed release distribution with BUILD.json')
    if args.action == 'version': print(json.dumps(build)); return 0
    global TRUSTED_KEYS
    TRUSTED_KEYS = read(pathlib.Path(__file__).with_name('public_keys.json'))
    installed = {key: build[key] for key in ('version', 'sha', 'tag', 'stable', 'build_number')}
    channel = args.channel or ('stable' if installed['stable'] else 'dev')
    if args.action == 'check':
        choices = discovery.releases(installed, TRUSTED_KEYS, channel, installed['build_number'])
        match = next((value for value in choices if any(compatible(p) for p in value[0]['packages'])), None)
        print(json.dumps({'current': installed, 'available': match[0]['identity'] if match else None, 'channel': channel}))
        return 0
    if (distribution/'share/ffido/container-distribution').exists(): raise ValueError('Update this container from the host with ffido-docker-update.py')
    if args.install_root is None: parser.error('--install-root is required')
    root = args.install_root.resolve(strict=True)
    if root.stat().st_uid != os.geteuid() or root.stat().st_mode & 0o022 or not os.access(root, os.W_OK): raise ValueError('Installation must be owned and writable by the update operator')
    with locked(root/'.update.lock'):
        current_target(root)
        if args.action == 'download':
            choices = discovery.releases(installed, TRUSTED_KEYS, channel, installed['build_number'])
            chosen = next((item for item in choices if (not args.version or item[0]['identity']['tag'] == args.version) and any(compatible(row) for row in item[0]['packages'])), None)
            if chosen is None: raise ValueError('No compatible newer release')
            print(stage(root, *chosen)); return 0
        if args.config is None: parser.error('--config is required')
        # Finish bookkeeping after a crash that occurred just after the atomic switch.
        journal_file = root/'.update-journal.json'
        if journal_file.exists():
            journal = read(journal_file)
            if journal.get('phase') == 'prepared' and current_target(root) == journal.get('to'):
                atomic_json(root/'.previous-update.json', {'target': journal['from']})
                atomic_json(journal_file, {**journal, 'phase': 'complete'})
        record = read(root/('.selected-update.json' if args.action == 'apply' else '.previous-update.json'))
        target = record['target']
        switch(root, target, args.config, TRUSTED_KEYS, rollback=args.action == 'rollback')
        print('Switched to '+target+'; start the service and run --check-ready')
        return 0


if __name__ == '__main__':
    try: raise SystemExit(main())
    except (OSError, ValueError, KeyError, sqlite3.Error) as error:
        print('Update failed: '+str(error), file=sys.stderr); raise SystemExit(1)
