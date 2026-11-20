"""Private multi-root deployment bundle layered on stopped-node snapshots.

This module copies and verifies only. It never installs host policy or starts
services. An incomplete bundle has no deployment.json completion marker.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat

import node_backup as node

COMPONENTS = {'deployment', 'images', 'updater', 'gateway', 'tls', 'acme',
              'renewal', 'cron', 'firewall'}


class BudgetError(node.SnapshotError):
    def __init__(self, report):
        self.report = report
        super().__init__('Insufficient space; deficit bytes: '+str(report['deficit_bytes']))


def sync_directories(paths):
    for path in sorted(set(map(Path, paths)), key=lambda p: len(p.parts), reverse=True):
        fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)


def disk_budget(destination, source_bytes, image_bytes, reserve=2*1024**3):
    """Budget uncompressed snapshot+archive, staging and image temporary space."""
    node.require(all(type(x) is int and x >= 0 for x in (source_bytes, image_bytes, reserve)))
    required = source_bytes*4 + image_bytes*2 + reserve
    available = shutil.disk_usage(destination).free
    report = {'source_bytes': source_bytes, 'image_bytes': image_bytes,
              'reserve_bytes': reserve, 'required_bytes': required,
              'available_bytes': available, 'deficit_bytes': max(0, required-available)}
    if available < required:
        raise BudgetError(report)
    return report


def component_inventory(profile):
    node.require(set(profile) == COMPONENTS, 'Incomplete deployment profile')
    result = []
    for role, item in sorted(profile.items()):
        root = Path(item['root']).absolute()
        node.require(root.is_dir() and not root.is_symlink(), 'Invalid deployment root')
        root = root.resolve(strict=True)
        required = item['required']
        node.require(isinstance(required, list) and required, 'Missing required deployment inputs')
        for name in required:
            node.require((root/node.relative(name)).is_file(), 'Required deployment input missing')
        includes = item.get('includes', ['.'])
        node.require(isinstance(includes, list) and includes, 'Empty deployment selection')
        selected = set()
        for name in includes:
            path = root if name == '.' else root/node.relative(name)
            node.require(path.exists(), 'Deployment selection missing')
            selected.add(path)
            if path.is_dir() and not path.is_symlink():
                selected.update(path.rglob('*'))
        rows = []
        for path in sorted(selected - {root}):
            name = str(path.relative_to(root))
            node.relative(name)
            resolved = path
            if path.is_symlink():
                node.require(role == 'acme' and path.is_relative_to(root/'live'),
                             'Unsupported deployment link')
                resolved = path.resolve(strict=True)
                node.require(resolved.is_relative_to((root/'archive').resolve()),
                             'ACME link escapes archive')
                node.require(resolved.is_relative_to(root.resolve()) and resolved.is_file())
            elif path.is_dir():
                continue
            digest, info = node.file_hash(root, str(resolved.relative_to(root)))
            node.require(not info.st_mode & 0o6000, 'Privileged deployment input')
            rows.append({'path': name, 'source': str(resolved.relative_to(root)),
                         'sha256': digest, 'size': info.st_size, 'mode': stat.S_IMODE(info.st_mode),
                         'uid': info.st_uid, 'gid': info.st_gid})
        node.require(rows, 'Empty deployment component')
        node.require(set(required) <= {x['path'] for x in rows}, 'Required file outside selection')
        directories = {}
        directory_paths = {root, *(x for x in selected if x.is_dir())}
        for row in rows:
            directory_paths.update(root/p for p in Path(row['path']).parents if str(p) != '.')
        for path in sorted(directory_paths):
            node.require(not path.is_symlink(), 'Directory symlink is forbidden')
            info = path.stat()
            directories[str(path.relative_to(root))] = {'mode': stat.S_IMODE(info.st_mode),
                                                       'uid': info.st_uid, 'gid': info.st_gid}
        result.append({'role': role, 'root': str(root), 'required': required,
                       'includes': includes, 'files': rows, 'directories': directories})
    return result


def copy_verified(source, name, destination, digest, mode):
    node.require(node.file_hash(source, name)[0] == digest, 'Deployment input changed')
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with node.open_file(source, name) as inp, destination.open('xb') as out:
        shutil.copyfileobj(inp, out, 1024*1024)
        os.fchmod(out.fileno(), mode)
        out.flush()
        os.fsync(out.fileno())
    node.require(node.file_hash(source, name)[0] == digest and
                 node.file_hash(destination.parent, destination.name)[0] == digest,
                 'Deployment copy changed')


def complete(destination, node_digest, components):
    """Seal external components beside an already verified node/ snapshot."""
    destination = Path(destination)
    node_manifest = destination/'node/snapshot.json'
    node.verify(destination/'node', node_manifest, node_digest)
    node.require(not (destination/'deployment.json').exists())
    for component in components:
        target = destination/'components'/component['role']
        target.mkdir(mode=0o700, parents=True)
        for row in component['files']:
            copy_verified(Path(component['root']), row['source'], target/row['path'],
                          row['sha256'], row['mode'])
    # A changed external source invalidates the whole stopped-node snapshot.
    for component in components:
        for row in component['files']:
            node.require(node.file_hash(component['root'], row['source'])[0] == row['sha256'],
                         'Deployment input changed during snapshot')
    profile = {x['role']: {'root': x['root'], 'required': x['required'], 'includes': x['includes']} for x in components}
    node.require(component_inventory(profile) == components, 'Deployment inventory changed during snapshot')
    sync_directories([destination, destination.parent,
                      *(x for x in (destination/'components').rglob('*') if x.is_dir()),
                      destination/'components'])
    value = {'version': 1, 'profile': 'full-node-with-gateway', 'complete': True,
             'node_manifest_sha256': node_digest, 'components': components}
    raw = node.dump(value)
    pending = destination/'deployment.pending.json'
    with pending.open('xb') as out:
        os.fchmod(out.fileno(), 0o600)
        out.write(raw); out.flush(); os.fsync(out.fileno())
    digest = hashlib.sha256(raw).hexdigest()
    verify(destination, digest, pending.name)
    pending.rename(destination/'deployment.json')
    fd = os.open(destination, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)
    return digest


def verify(root, digest, name='deployment.json'):
    root = Path(root)
    with node.open_file(root, name) as source:
        raw = source.read()
    node.require(hashlib.sha256(raw).hexdigest() == digest, 'Untrusted deployment manifest')
    value = json.loads(raw)
    node.require(value.get('version') == 1 and value.get('complete') is True
                 and value.get('profile') == 'full-node-with-gateway')
    components = value['components']
    roles = [x['role'] for x in components]
    node.require(len(roles) == len(COMPONENTS) and set(roles) == COMPONENTS)
    node.verify(root/'node', root/'node/snapshot.json', value['node_manifest_sha256'])
    for component in components:
        paths = set()
        for row in component['files']:
            path = str(node.relative(row['path']))
            node.require(path not in paths)
            paths.add(path)
            node.require(node.file_hash(root/'components'/component['role'], path)[0] == row['sha256'],
                         'Deployment content mismatch')
            node.require(type(row['mode']) is int and 0 <= row['mode'] <= 0o777)
            node.require(all(type(row[x]) is int and row[x] >= 0 for x in ('uid', 'gid', 'size')))
        node.require(component['required'] and set(component['required']) <= paths,
                     'Required deployment input missing')
        node.require('.' in component['directories'])
        for directory, metadata in component['directories'].items():
            if directory != '.':
                node.relative(directory)
            node.require(type(metadata['mode']) is int and 0 <= metadata['mode'] <= 0o777)
            node.require(all(type(metadata[x]) is int and metadata[x] >= 0 for x in ('uid', 'gid')))
    return value


def restore(root, digest, destination):
    """Materialize only into a new staging directory; never apply host settings."""
    root, destination = Path(root), Path(destination)
    value = verify(root, digest)
    node.require(not destination.exists() and not destination.is_symlink(), 'Restore requires new staging')
    destination.mkdir(mode=0o700)
    snapshot = node.verify(root/'node', root/'node/snapshot.json', value['node_manifest_sha256'])
    components = [('node', snapshot['files'], snapshot['directory_metadata'])]
    components += [('components/'+x['role'], x['files'], x['directories']) for x in value['components']]
    for _, files, directories in components:
        for directory, metadata in directories.items():
            if directory != '.':
                node.relative(directory)
            node.require(type(metadata['mode']) is int and 0 <= metadata['mode'] <= 0o777)
            node.require(all(type(metadata[x]) is int and metadata[x] >= 0 for x in ('uid', 'gid')))
        for row in files:
            node.relative(row['path'])
            node.require(type(row['mode']) is int and 0 <= row['mode'] <= 0o777)
            node.require(all(type(row[x]) is int and row[x] >= 0 for x in ('uid', 'gid')))
    for prefix, files, directories in components:
        for directory in sorted(directories):
            (destination/prefix/directory).mkdir(mode=0o700, parents=True, exist_ok=True)
        for row in files:
            target = destination/prefix/row['path']
            copy_verified(root/prefix, row['path'], target, row['sha256'], row['mode'])
            os.chown(target, row['uid'], row['gid'])
        for directory in sorted(directories, key=lambda x: len(Path(x).parts), reverse=True):
            target = destination/prefix/directory
            metadata = directories[directory]
            os.chown(target, metadata['uid'], metadata['gid'])
            target.chmod(metadata['mode'])
    (destination/'node/snapshot.json').write_bytes((root/'node/snapshot.json').read_bytes())
    (destination/'node/snapshot.json').chmod(0o600)
    return value
