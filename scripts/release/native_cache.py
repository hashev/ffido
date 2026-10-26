#!/usr/bin/env python3
"""Seal and verify isolated native components before assembling a release prefix."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


def inventory(root):
    files = {}
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            if not path.resolve().is_relative_to(root.resolve()):
                raise ValueError(f'Escaping component symlink: {relative}')
            files[relative] = {'link': str(path.readlink())}
        elif path.is_file():
            files[relative] = {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                               'executable': bool(path.stat().st_mode & 0o111)}
    return files


REQUIRED = {'abseil': ['prefix/lib/libabsl_base.a'],
            'protobuf': ['prefix/lib/libprotobuf.a', 'prefix/bin/protoc'],
            'grpc': ['prefix/lib/libgrpc++.a', 'prefix/bin/grpc_cpp_plugin'],
            'huskylib': ['prefix/lib/libhusky.a'], 'smapi': ['prefix/lib/libsmapi.a'],
            'fidoconf': ['prefix/lib/libfidoconfig.a', 'source/src/cfg.c'],
            'areafix': ['prefix/lib/libareafix.a'], 'hpt': ['prefix/bin/hpt']}


def seal(component, key):
    payload = component/'payload'
    files = inventory(payload)
    if component.name not in REQUIRED or any(not (payload/name).is_file() for name in REQUIRED[component.name]):
        raise ValueError('Missing required component files: '+component.name)
    if not files or not (payload/'prefix').is_dir() or not (payload/'source/.git').is_dir():
        raise ValueError('Incomplete component payload')
    manifest = {'schema': 1, 'key': key, 'files': files}
    (component/'complete.json').write_text(json.dumps(manifest, sort_keys=True)+'\n')


def verify(component, key):
    try:
        manifest = json.loads((component/'complete.json').read_text())
        if manifest['schema'] != 1 or manifest['key'] != key or component.name not in REQUIRED:
            return False
        return (all((component/'payload'/name).is_file() for name in REQUIRED[component.name])
                and bool(manifest['files']) and manifest['files'] == inventory(component/'payload'))
    except (OSError, ValueError, KeyError):
        return False


def assemble(component, prefix, source):
    payload = component/'payload'
    for path in sorted((payload/'prefix').rglob('*')):
        relative = path.relative_to(payload/'prefix')
        destination = prefix/relative
        if path.is_dir() and not path.is_symlink():
            destination.mkdir(parents=True, exist_ok=True)
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists() or destination.is_symlink():
            same = (path.is_symlink() and destination.is_symlink() and path.readlink() == destination.readlink())
            if not same and not path.is_symlink() and not destination.is_symlink():
                same = path.read_bytes() == destination.read_bytes()
            if not same:
                raise ValueError(f'Conflicting installed component file: {relative}')
            continue
        if path.is_symlink():
            destination.symlink_to(path.readlink())
        else:
            shutil.copy2(path, destination)
    if source.exists():
        shutil.rmtree(source)
    shutil.copytree(payload/'source', source, symlinks=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['seal', 'verify', 'assemble'])
    parser.add_argument('component', type=Path)
    parser.add_argument('key')
    parser.add_argument('--prefix', type=Path)
    parser.add_argument('--source', type=Path)
    args = parser.parse_args()
    if args.operation == 'seal':
        seal(args.component, args.key)
    else:
        if not verify(args.component, args.key):
            raise SystemExit('Native cache miss: missing, changed, incomplete or incompatible component')
        if args.operation == 'assemble':
            assemble(args.component, args.prefix, args.source)


if __name__ == '__main__':
    main()
