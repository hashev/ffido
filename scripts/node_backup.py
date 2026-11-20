#!/usr/bin/env python3
"""Create private stopped-node snapshots and their trusted restore manifests.

No service is stopped or started by this tool. All input paths are rooted in the
node layout; no credentials or helper diagnostics are printed.
"""
import argparse
import contextlib
import fcntl
import hashlib
import gzip
import json
import os
from pathlib import Path
import shutil
import sqlite3
import stat
import struct
import subprocess
import sys
import tarfile


REQUIRED_LAYOUT = ('f', 'spool', 'dupebase', 'flags', 'ffido/fileboxes',
                   'docker-compose.yaml', '.env', 'binkd.cfg', 't.sh',
                   'ffido/ops', 'ffido/updater', 'ffido/updates', 'ffido/acme/config',
                   'ffido/deployed-identity.json', 'ffido/update-transaction.json')


class SnapshotError(Exception):
    """The input is not a complete, stopped and verifiable snapshot."""


def require(condition, message='Snapshot verification failed'):
    if not condition:
        raise SnapshotError(message)


def relative(value):
    require(isinstance(value, str) and value and '\0' not in value)
    p = Path(value)
    require(not p.is_absolute() and all(x not in ('', '.', '..') for x in value.split('/')))
    return p


@contextlib.contextmanager
def open_file(root, name):
    parts = relative(name).parts
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for part in parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
        value = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
        with os.fdopen(value, 'rb') as source:
            info = os.fstat(source.fileno())
            require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1)
            yield source
    finally:
        os.close(fd)


def file_hash(root, name):
    with open_file(root, name) as source:
        before = os.fstat(source.fileno())
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
        after = os.fstat(source.fileno())
        require((before.st_size, before.st_mtime_ns, before.st_ctime_ns) ==
                (after.st_size, after.st_mtime_ns, after.st_ctime_ns))
        return digest, before


def dump(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=True, separators=(',', ':')).encode() + b'\n'


def offline_database(root, name):
    path = Path(root) / relative(name)
    with open_file(root, name):
        pass
    for suffix in ('-wal', '-shm', '-journal'):
        side = Path(str(path) + suffix)
        require(not side.exists() or (side.is_file() and not side.is_symlink() and side.stat().st_size == 0),
                'Snapshot requires a checkpointed stopped SQLite database')
    db = sqlite3.connect(path.as_uri() + '?immutable=1', uri=True)
    try:
        require(db.execute('pragma user_version').fetchone()[0] in (11, 12), 'Unsupported snapshot schema')
        require(db.execute('pragma integrity_check').fetchone()[0] == 'ok')
        require(not db.execute('pragma foreign_key_check').fetchall())
        return db
    except Exception:
        db.close()
        raise


def validate_manifest(manifest):
    require(manifest.get('version') == 1 and manifest.get('complete') is True)
    names = set()
    for row in manifest['files']:
        name = str(relative(row['path']))
        require(name not in names and len(row['sha256']) == 64)
        require(all(x in '0123456789abcdef' for x in row['sha256']))
        names.add(name)
    require(manifest['database'] in names and manifest['config'] in names)
    require(manifest['schema'] in (11, 12))
    require(len(manifest['locks']) == 3 and len(set(manifest['locks'])) == 3)
    require(manifest['database'] + '.lock' in manifest['locks'])
    for lock in manifest['locks']:
        require(str(relative(lock)) in names)
    bases = set()
    conferences = set()
    generations = set()
    for jam in manifest['jam']:
        base = str(relative(jam['base']))
        require(base not in bases and all(base + ext in names for ext in ('.jhr', '.jdt', '.jdx')))
        bases.add(base)
        generation = jam['generation']
        require(len(generation.split(':')) == 4 and all(x.isascii() and x.isdigit() for x in generation.split(':')))
        require(generation not in generations)
        generations.add(generation)
        for conference in jam['conferences']:
            require(conference and conference not in conferences)
            conferences.add(conference)
    addresses = set()
    for mailbox in manifest['mailboxes']:
        require(mailbox['address'] not in addresses)
        addresses.add(mailbox['address'])
        require(str(relative(manifest['jam_root'] + '/' + mailbox['base'])) in bases)


def verify(root, manifest, expected_digest):
    raw = Path(manifest).read_bytes()
    require(hashlib.sha256(raw).hexdigest() == expected_digest, 'Untrusted snapshot manifest')
    value = json.loads(raw)
    validate_manifest(value)
    for row in value['files']:
        require(file_hash(root, row['path'])[0] == row['sha256'], 'Snapshot content mismatch')
    return value


def relative_input(root, path, mappings):
    p = Path(path)
    for source, target in sorted(mappings, key=lambda x: -len(x[0])):
        try:
            p = Path(target) / p.relative_to(source)
            break
        except ValueError:
            continue
    require(p.is_absolute(), 'Runtime input must be absolute')
    try:
        return str(relative(str(p.relative_to(root))))
    except ValueError as error:
        raise SnapshotError('Dependency is outside the node layout; specify an explicit mapping') from error


def running_writers(root):
    """Detect same-user writable Linux FDs; locks are the primary coordination."""
    proc = Path('/proc')
    if not proc.exists():
        return False  # Non-Linux supervisors must enforce their stopped-state contract.
    for process in proc.iterdir():
        if not process.name.isdigit() or int(process.name) == os.getpid():
            continue
        try:
            if process.stat().st_uid != os.getuid():
                continue
            for fd in (process / 'fd').iterdir():
                target = Path(os.readlink(fd))
                if target.is_relative_to(root):
                    lines = (process / 'fdinfo' / fd.name).read_text().splitlines()
                    flags = next(int(x.split()[1], 8) for x in lines if x.startswith('flags:'))
                    if flags & os.O_ACCMODE in (os.O_WRONLY, os.O_RDWR):
                        return True
        except (FileNotFoundError, ProcessLookupError):
            continue
        except PermissionError:
            # A same-user writer cannot be verified safely if its FD inventory is hidden.
            raise SnapshotError('Cannot verify writer state') from None
    return False


@contextlib.contextmanager
def stopped(root, locks, held_locks=None):
    with contextlib.ExitStack() as stack:
        for lock in locks:
            source = stack.enter_context(open_file(root, lock))
            held = (held_locks or {}).get(lock)
            if held is not None:
                a, b = os.fstat(source.fileno()), os.fstat(held)
                require((a.st_dev, a.st_ino) == (b.st_dev, b.st_ino), 'Held lock identity changed')
                try:
                    fcntl.flock(source.fileno(), fcntl.LOCK_SH | fcntl.LOCK_NB)
                except BlockingIOError:
                    pass
                else:
                    raise SnapshotError('Inherited lock must already be exclusive')
                try:
                    fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError as error:
                    raise SnapshotError('Inherited descriptor does not own the lock') from error
                continue
            try:
                fcntl.flock(source.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise SnapshotError('Snapshot requires stopped writers and free coordination locks') from error
        require(not running_writers(root), 'A writer still has the snapshot data open')
        yield
        require(not running_writers(root), 'Writer state changed during snapshot')


def configuration_inventory(root, config_name, helper, mappings):
    with open_file(root, config_name) as source:
        config = json.load(source)
    convert = lambda p: relative_input(root, p, mappings)
    hpt_name = convert(config['auth']['hpt_config_path'])
    result = subprocess.run([helper, str(root / hpt_name), json.dumps([{'from': a, 'to': b} for a, b in mappings])],
                            capture_output=True, timeout=15)
    require(result.returncode == 0, 'HPT dependency inventory unavailable')
    hpt = json.loads(result.stdout)
    require('backup_files' in hpt, 'HPT helper does not support backup inventory')
    dependencies = {config_name, hpt_name, convert(config['ftn']['areacfg_path']),
                    convert(config['auth']['session_key_path']), convert(config['server']['tls_certificate']),
                    convert(config['server']['tls_private_key'])}
    dependencies.update(convert(x) for x in hpt['backup_files'])
    corrections = config['ftn'].get('jam_message_encoding_corrections_path')
    if corrections:
        dependencies.add(convert(corrections))
    database = convert(config['database']['metadata_path'])
    dependencies.add(database)
    jam_root = convert(config['ftn']['jam_base_path'])
    dependencies.add(jam_root)
    if str(Path(database).parent) != '.':
        dependencies.add(str(Path(database).parent))
    areas = {}
    for area in hpt['echoes']:
        name = convert(area['filename'])
        areas.setdefault(name, []).append(area['name'])
    kinds = {'netmail': 1, 'local': 2, 'bad': 3, 'dupe': 4, 'robots': 5}
    for area in hpt['private_areas']:
        if area['format'] == 'JAM':
            name = convert(area['filename'])
            key = '@ffido/' + str(kinds[area['kind']]) + '/' + area['name'].lower().encode().hex()
            areas.setdefault(name, []).append(key)
    return config, dependencies, database, jam_root, areas


def inventory(root, config_name, helper, mappings, legacy_files=None):
    config, dependencies, database, jam_root, areas = configuration_inventory(root, config_name, helper, mappings)
    with contextlib.closing(offline_database(root, database)) as db:
        # Reuse the restore schema contract; this read-only command never calls Init.
        schema_check = subprocess.run([str(Path(shutil.which(helper) or helper).resolve().parent / 'ffido-admin'), 'metadata-schema-check',
                                       str(root / database)], capture_output=True, timeout=15)
        require(schema_check.returncode == 0, 'Incomplete or unsupported metadata schema')
        rows = [dict(zip(('address', 'base', 'generation', 'files'), row)) for row in
                db.execute('select address,base,generation,files from mailbox_bindings order by address')]
        configured = {(x['address'], x['jam_base']) for x in config['point_mail']['points']}
        require(configured == {(x['address'], x['base']) for x in rows})
        generations = {}
        references = [('read_status', 'conference_id', 'generation'), ('reading_positions', 'conference', 'generation'),
                      ('operations', 'conference', 'generation'), ('mail_provenance', 'conference', 'generation'),
                      ('mail_transfers', 'source_conference', 'source_generation'),
                      ('bulk_read_operations', 'conference', 'generation')]
        for table, conference, generation in references:
            for key, value in db.execute(f'select distinct {conference},{generation} from {table}'):
                generations.setdefault(key, set()).add(value)
        for row in rows:
            key = '@ffido/mailbox/' + row['address'].encode().hex()
            areas.setdefault(jam_root + '/' + row['base'], []).append(key)
            generations.setdefault(key, set()).add(row['generation'])
        aliases = {}
        if db.execute("select name from sqlite_master where name='restored_generations'").fetchone():
            aliases = {jam_root + '/' + base: (physical, logical) for base, physical, logical in
                       db.execute('select base,physical_generation,logical_generation from restored_generations')}
        schema = db.execute('pragma user_version').fetchone()[0]
    jam = []
    for base, conferences in sorted(areas.items()):
        identities = []
        for ext in ('.jhr', '.jdt', '.jdx'):
            dependencies.add(base + ext)
            with open_file(root, base + ext) as source:
                identities.append(os.fstat(source.fileno()))
                if ext == '.jhr':
                    header = source.read(1024)
        require(len(header) == 1024 and header[:4] == b'JAM\0')
        date, number = struct.unpack_from('<I', header, 4)[0], struct.unpack_from('<I', header, 20)[0]
        suffix = f':{date}:{number}'
        known = set().union(*(generations.get(x, set()) for x in conferences))
        require(all(x.endswith(suffix) for x in known), 'Ambiguous snapshot generation')
        physical = f'{identities[0].st_dev}:{identities[0].st_ino}{suffix}'
        if base in aliases:
            expected, logical = aliases[base]
            require(expected == physical, 'Restored snapshot physical identity changed')
            # mailbox_bindings intentionally holds physical identity, whereas receipts stay logical.
            known.discard(expected)
            require(not known or known == {logical}, 'Ambiguous restored logical generation')
            gen = logical
        else:
            require(len(known) <= 1, 'Ambiguous snapshot generation')
            gen = next(iter(known)) if known else physical
            if gen != physical:
                require(legacy_files is not None, 'Copied legacy generations require explicit trusted provenance')
                for name in [database, config_name, *(base + ext for ext in ('.jhr', '.jdt', '.jdx'))]:
                    require(name in legacy_files and file_hash(root, name)[0] == legacy_files[name],
                            'Legacy provenance does not cover the copied generation')
        jam.append({'base': base, 'conferences': sorted(conferences), 'generation': gen})
    return config, dependencies, database, jam_root, jam, rows, schema


def select_snapshot_files(root, dependencies, database):
    files = set()
    sources = {}
    directories = set()
    for name in dependencies:
        path = root / name
        require(path.exists() and not path.is_symlink(), 'Required snapshot dependency unavailable')
        if path.is_dir():
            directories.add(name)
            for child in path.rglob('*'):
                rel = str(child.relative_to(root))
                if child.is_symlink():
                    # Certbot's live links are the sole supported aliases. Materialize only
                    # verified archive files, so restore never traverses a live dependency.
                    require(child.is_relative_to(root / 'ffido/acme/config/live'),
                            'Snapshot input contains an unsupported symbolic link')
                    resolved = child.resolve(strict=True)
                    require(resolved.is_relative_to((root / 'ffido/acme/config/archive').resolve()),
                            'ACME certificate link escapes its archive')
                    require(resolved.is_relative_to(root.resolve()))
                    sources[rel] = str(resolved.relative_to(root.resolve()))
                    with open_file(root, sources[rel]):
                        pass
                if child.is_dir():
                    directories.add(rel)
                else:
                    files.add(rel)
        else:
            files.add(name)
    files.difference_update(database + suffix for suffix in ('-wal', '-shm', '-journal'))
    for name in files:
        for parent in Path(name).parents:
            if str(parent) != '.':
                directories.add(str(parent))
    require(not any('backups' in Path(x).parts for x in files), 'Recursive backup input is forbidden')
    return files, sources, directories


def estimated_input_bytes(root, config_name, helper, mappings, includes, maintenance_lock):
    """Size the snapshot selection without requiring a stopped/checkpointed database."""
    config, dependencies, database, _, areas = configuration_inventory(root, config_name, helper, mappings)
    dependencies.update(str(relative(x)) for x in (*REQUIRED_LAYOUT, *includes))
    dependencies.update((maintenance_lock, database + '.lock',
                         relative_input(root, config['ftn']['coordination_lock'], mappings)))
    for base in areas:
        dependencies.update(base + suffix for suffix in ('.jhr', '.jdt', '.jdx'))
    files, sources, _ = select_snapshot_files(root, dependencies, database)
    size = 0
    for name in files:
        with open_file(root, sources.get(name, name)) as source:
            size += os.fstat(source.fileno()).st_size
    # Live WAL can become database pages by shutdown. Count it conservatively too.
    for suffix in ('-wal', '-shm', '-journal'):
        name = database + suffix
        try:
            with open_file(root, name) as source:
                size += os.fstat(source.fileno()).st_size
        except FileNotFoundError:
            pass
    return size


def snapshot(root, destination, config_name, helper, mappings, includes, maintenance_lock,
             legacy_manifest=None, legacy_digest=None, held_locks=None):
    root = Path(root).absolute()
    destination = Path(destination).absolute()
    require(not destination.exists() and not destination.is_relative_to(root), 'Destination must be new and outside source')
    legacy_files = None
    if legacy_manifest is not None:
        raw = Path(legacy_manifest).read_bytes()
        require(legacy_digest and hashlib.sha256(raw).hexdigest() == legacy_digest, 'Untrusted legacy provenance')
        legacy_files = json.loads(raw)
        require(isinstance(legacy_files, dict))
        for name in legacy_files:
            relative(name)
    with open_file(root, config_name) as source:
        config = json.load(source)
    convert = lambda p: relative_input(root, p, mappings)
    database = convert(config['database']['metadata_path'])
    locks = [maintenance_lock, database + '.lock', convert(config['ftn']['coordination_lock'])]
    require(len(set(locks)) == 3)
    try:
        with stopped(root, locks, held_locks):
            _, dependencies, database, jam_root, jam, mailboxes, schema = inventory(root, config_name, helper, mappings, legacy_files)
            dependencies.update(locks)
            dependencies.update(str(relative(x)) for x in (*REQUIRED_LAYOUT, *includes))
            files, sources, directories = select_snapshot_files(root, dependencies, database)
            destination.mkdir(mode=0o700)
            try:
                for directory in sorted(directories):
                    (destination / directory).mkdir(mode=0o700, parents=True, exist_ok=True)
                records = []
                for name in sorted(files):
                    source_name = sources.get(name, name)
                    digest, before = file_hash(root, source_name)
                    target = destination / name
                    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                    with open_file(root, source_name) as source, target.open('xb') as output:
                        os.fchmod(output.fileno(), stat.S_IMODE(before.st_mode))
                        shutil.copyfileobj(source, output, 1024 * 1024)
                        output.flush()
                        os.fsync(output.fileno())
                    require(file_hash(root, source_name)[0] == digest and file_hash(destination, name)[0] == digest,
                            'Snapshot file changed during copying')
                    records.append({'path': name, 'sha256': digest, 'uid': before.st_uid, 'gid': before.st_gid,
                                    'mode': stat.S_IMODE(before.st_mode), 'source': source_name})
                directory_metadata = {}
                for directory in sorted(directories):
                    info = (root / directory).stat()
                    directory_metadata[directory] = {'uid': info.st_uid, 'gid': info.st_gid,
                                                     'mode': stat.S_IMODE(info.st_mode)}
                manifest = {'version': 1, 'complete': True, 'schema': schema, 'database': database,
                            'legacy_provenance_sha256': legacy_digest, 'config': config_name, 'jam_root': jam_root, 'locks': locks, 'files': records,
                            'directories': sorted(directories), 'directory_metadata': directory_metadata, 'jam': jam, 'mailboxes': mailboxes}
                validate_manifest(manifest)
                raw = dump(manifest)
                digest = hashlib.sha256(raw).hexdigest()
                with (destination / 'snapshot.pending.json').open('xb') as output:
                    os.fchmod(output.fileno(), 0o600)
                    output.write(raw)
                    output.flush()
                    os.fsync(output.fileno())
                with (destination / 'snapshot.tar.gz').open('xb') as output:
                    os.fchmod(output.fileno(), 0o600)
                    with tarfile.open(fileobj=output, mode='w:gz') as archive:
                        for directory in sorted(directories):
                            info = archive.gettarinfo(destination / directory, arcname=directory)
                            info.uid, info.gid = directory_metadata[directory]['uid'], directory_metadata[directory]['gid']
                            info.mode = directory_metadata[directory]['mode']
                            info.uname = info.gname = ''
                            archive.addfile(info)
                        ownership = {x['path']: x for x in records}
                        for name in sorted(files | {'snapshot.json'}):
                            content_path = destination / ('snapshot.pending.json' if name == 'snapshot.json' else name)
                            info = archive.gettarinfo(content_path, arcname=name)
                            if name in ownership:
                                info.uid, info.gid = ownership[name]['uid'], ownership[name]['gid']
                                info.uname = info.gname = ''
                            with content_path.open('rb') as content:
                                archive.addfile(info, content)
                    output.flush()
                    os.fsync(output.fileno())
                expected = {row['path']: row['sha256'] for row in records}
                expected['snapshot.json'] = digest
                seen = set()
                with tarfile.open(destination / 'snapshot.tar.gz', 'r:gz') as archive:
                    for member in archive:
                        require(member.name not in seen)
                        seen.add(member.name)
                        if member.isfile():
                            require(member.name in expected)
                            with archive.extractfile(member) as source:
                                require(hashlib.file_digest(source, 'sha256').hexdigest() == expected[member.name])
                        else:
                            require(member.isdir() and member.name in directories)
                require(seen == set(expected) | directories)
                with gzip.open(destination / 'snapshot.tar.gz', 'rb') as source:
                    hashlib.file_digest(source, 'sha256') # Force the gzip CRC/trailer check through EOF.
                verify(destination, destination / 'snapshot.pending.json', digest)
                for directory in sorted(directories, reverse=True) + ['.']:
                    fd = os.open(destination / directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
                    try:
                        os.fsync(fd)
                    finally:
                        os.close(fd)
                require(not running_writers(root), 'Writer state changed before snapshot completion')
                (destination / 'snapshot.pending.json').rename(destination / 'snapshot.json')
                fd = os.open(destination, os.O_RDONLY | os.O_DIRECTORY)
                try:
                    os.fsync(fd)
                finally:
                    os.close(fd)
                return {'manifest_sha256': digest, 'files': len(records), 'schema': schema}
            except Exception:
                # Retain evidence of an incomplete copy, without a complete manifest.
                (destination / 'snapshot.json').unlink(missing_ok=True)
                (destination / 'snapshot.pending.json').unlink(missing_ok=True)
                raise
    except Exception:
        (destination / 'snapshot.json').unlink(missing_ok=True)
        (destination / 'snapshot.pending.json').unlink(missing_ok=True)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['snapshot', 'verify'])
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--expected-digest')
    parser.add_argument('--destination', type=Path)
    parser.add_argument('--config', default='ffido/config.json')
    parser.add_argument('--helper')
    parser.add_argument('--map', action='append', default=[], dest='path_maps')
    parser.add_argument('--include', action='append', default=[])
    parser.add_argument('--legacy-manifest', type=Path)
    parser.add_argument('--legacy-digest')
    parser.add_argument('--maintenance-lock', default='ffido/maintenance.lock')
    args = parser.parse_args()
    try:
        if args.command == 'verify':
            require(args.manifest and args.expected_digest)
            value = verify(args.root, args.manifest, args.expected_digest)
            result = {'verified': True, 'schema': value['schema']}
        else:
            require(args.destination and args.helper)
            mappings = [x.split('=', 1) for x in args.path_maps]
            require(all(len(x) == 2 for x in mappings))
            result = snapshot(args.root, args.destination, args.config, args.helper, mappings,
                              args.include, args.maintenance_lock, args.legacy_manifest, args.legacy_digest)
        print(json.dumps(result))
        return 0
    except (SnapshotError, OSError, ValueError, KeyError, sqlite3.Error, subprocess.SubprocessError):
        print('Snapshot verification failed; inspect the private node layout and stopped writers', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
