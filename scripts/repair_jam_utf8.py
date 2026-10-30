#!/usr/bin/env python3
"""Diagnose and explicitly reverse historical CP866-to-KOI8-R damage to UTF-8 JAM."""
import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import stat
import struct
import sys
import tempfile

EXTENSIONS = ('.jhr', '.jdt', '.jdx', '.jlr')
MAX_FILE = 64 * 1024 * 1024
MAX_TEXT = 4 * 1024 * 1024
STOPPED = {'backend', 'hpt', 'jamnntpd', 'cron'}


class RepairError(ValueError):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()


def write_all(fd, data):
    offset = 0
    while offset < len(data):
        count = os.pwrite(fd, data[offset:offset + 65536], offset)
        if count <= 0:
            raise RepairError('Short write')
        offset += count
    os.ftruncate(fd, len(data))
    os.fsync(fd)


def save_new(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        write_all(fd, data)
    finally:
        os.close(fd)


def save_manifest(folder, value):
    fd, temporary_name = tempfile.mkstemp(prefix='manifest-', dir=folder)
    temporary = Path(temporary_name)
    try:
        write_all(fd, json_bytes(value))
        os.close(fd)
        fd = None
        os.replace(temporary, folder / 'manifest.json')
    finally:
        if fd is not None:
            os.close(fd)
        temporary.unlink(missing_ok=True)
    fd = os.open(folder, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def read_fd(fd):
    size = os.fstat(fd).st_size
    if size > MAX_FILE:
        raise RepairError('JAM file exceeds diagnostic limit')
    data = bytearray()
    while len(data) < size:
        part = os.pread(fd, min(65536, size - len(data)), len(data))
        if not part:
            raise RepairError('JAM changed or short read')
        data.extend(part)
    if os.fstat(fd).st_size != size:
        raise RepairError('JAM changed during read')
    return bytes(data)


@contextlib.contextmanager
def open_base(root, base, writable=False):
    parts = Path(base).parts
    if not parts or Path(base).is_absolute() or any(x in ('.', '..') for x in base.split('/')):
        raise RepairError('Base must be a relative configured name without dot segments')
    with contextlib.ExitStack() as stack:
        directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        stack.callback(os.close, directory)
        for part in parts[:-1]:
            directory = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
            stack.callback(os.close, directory)
        files = {}
        for extension in EXTENSIONS:
            name = parts[-1] + extension
            try:
                fd = os.open(name, (os.O_RDWR if writable else os.O_RDONLY) | os.O_NOFOLLOW, dir_fd=directory)
            except FileNotFoundError:
                if extension == '.jlr':
                    continue
                raise
            stack.callback(os.close, fd)
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                raise RepairError('JAM must consist of regular unaliased files')
            files[extension] = fd
        yield files, directory, parts[-1]


def snapshot(files):
    return {extension: read_fd(fd) for extension, fd in files.items()}


def identities(files):
    return {ext: [os.fstat(fd).st_dev, os.fstat(fd).st_ino] for ext, fd in files.items()}


def check_paths(files, directory, name):
    for ext, fd in files.items():
        path_info = os.stat(name + ext, dir_fd=directory, follow_symlinks=False)
        info = os.fstat(fd)
        if not stat.S_ISREG(path_info.st_mode) or (info.st_dev, info.st_ino) != (path_info.st_dev, path_info.st_ino):
            raise RepairError('JAM path identity changed')
    if '.jlr' not in files:
        try:
            os.stat(name + '.jlr', dir_fd=directory, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            raise RepairError('JAM file set changed')


def plan(data):
    header, text, index = (data[x] for x in ('.jhr', '.jdt', '.jdx'))
    if len(header) < 1024 or header[:4] != b'JAM\0' or len(index) % 8 or len(index) // 8 > 1000000:
        raise RepairError('Invalid JAM base header or index')
    base_number = struct.unpack_from('<I', header, 20)[0]
    if not base_number or base_number + len(index) // 8 > 2**32:
        raise RepairError('Invalid JAM numbering')
    edits, ranges, counts = [], {'.jhr': [], '.jdt': []}, {'messages': 0, 'valid_values': 0}

    def value(ext, offset, length, number, field):
        if length > MAX_TEXT:
            raise RepairError(f'Message {number} field {field}: text limit exceeded')
        raw = data[ext][offset:offset + length]
        try:
            raw.decode('utf-8')
            counts['valid_values'] += 1
            return
        except UnicodeDecodeError:
            pass
        try:
            fixed = raw.decode('koi8-r').encode('cp866')
            fixed.decode('utf-8')
            if len(fixed) != length or fixed.decode('cp866').encode('koi8-r') != raw:
                raise ValueError()
        except (UnicodeError, ValueError):
            raise RepairError(f'Message {number} field {field}: not reversibly damaged UTF-8') from None
        edits.append({'file': ext, 'offset': offset, 'length': length, 'message': number,
                      'field': field, 'before_sha256': digest(raw), 'after_sha256': digest(fixed)})

    for slot in range(len(index) // 8):
        at = struct.unpack_from('<I', index, slot * 8 + 4)[0]
        if at == 0xffffffff:
            continue
        if at < 1024 or at + 76 > len(header) or header[at:at + 4] != b'JAM\0':
            raise RepairError('Invalid JAM message header')
        revision = struct.unpack_from('<H', header, at + 4)[0]
        length = struct.unpack_from('<I', header, at + 8)[0]
        number = struct.unpack_from('<I', header, at + 48)[0]
        attrs = struct.unpack_from('<I', header, at + 52)[0]
        body, size = struct.unpack_from('<II', header, at + 60)
        end = at + 76 + length
        if revision != 1 or number != base_number + slot or end > len(header) or body + size > len(text):
            raise RepairError('Invalid JAM message bounds or number')
        ranges['.jhr'].append((at, end))
        if size:
            ranges['.jdt'].append((body, body + size))
        current = at + 76
        while current < end:
            if current + 8 > end:
                raise RepairError('Truncated JAM subfield')
            low, high, count = struct.unpack_from('<HHI', header, current)
            current += 8
            if current + count > end:
                raise RepairError('Invalid JAM subfield length')
            if not attrs & 0x80000000 and high == 0 and low in (2, 3, 6):
                value('.jhr', current, count, number, str(low))
            current += count
        if not attrs & 0x80000000:
            counts['messages'] += 1
            value('.jdt', body, size, number, 'body')
    for ext, spans in ranges.items():
        spans.sort()
        if any(left[1] > right[0] for left, right in zip(spans, spans[1:])):
            raise RepairError('Overlapping JAM ranges: ' + ext)
    return counts, edits


def repaired(data, edits):
    result = {ext: bytearray(raw) for ext, raw in data.items()}
    for edit in edits:
        ext, offset, length = (edit[key] for key in ('file', 'offset', 'length'))
        raw = data[ext][offset:offset + length]
        result[ext][offset:offset + length] = raw.decode('koi8-r').encode('cp866')
    return {ext: bytes(raw) for ext, raw in result.items()}


def report_for(data, files, config_digest, base):
    counts, edits = plan(data)
    return {'version': 1, 'config_sha256': config_digest, 'base': base,
            'files': {ext: digest(raw) for ext, raw in data.items()},
            'identities': identities(files), **counts, 'changes': edits}


@contextlib.contextmanager
def exclusive_lock(path):
    fd = os.open(path, os.O_RDWR | os.O_NOFOLLOW)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise RepairError('Coordination lock must be regular and already exist')
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        current = os.stat(path, follow_symlinks=False)
        if (info.st_dev, info.st_ino) != (current.st_dev, current.st_ino):
            raise RepairError('Coordination lock changed')
        yield
    finally:
        os.close(fd)


def maintain(marker, expected):
    declaration = json.loads(marker.read_bytes())
    if declaration.get('report_sha256') != digest(json_bytes(expected)) or set(declaration.get('stopped', [])) != STOPPED:
        raise RepairError('Maintenance declaration must match report and confirm backend/hpt/jamnntpd/cron stopped')


def apply_repair(files, directory, name, data, expected, backup):
    fixed = repaired(data, expected['changes'])
    if plan(fixed)[1]:
        raise RepairError('Post-repair plan is not empty')
    backup.mkdir(mode=0o700, parents=False, exist_ok=False)
    parent_fd = os.open(backup.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(parent_fd)
    finally:
        os.close(parent_fd)
    for ext, raw in data.items():
        save_new(backup / ('base' + ext), raw)
        if (backup / ('base' + ext)).read_bytes() != raw:
            raise RepairError('Backup verification failed')
    manifest = {'state': 'prepared', 'report': expected}
    save_manifest(backup, manifest)
    # Recheck after backup, immediately before the first JAM write.
    check_paths(files, directory, name)
    if snapshot(files) != data:
        raise RepairError('JAM changed after report or during backup')
    manifest['state'] = 'applying'
    save_manifest(backup, manifest)
    try:
        for ext, raw in fixed.items():
            if raw != data[ext]:
                write_all(files[ext], raw)
        check_paths(files, directory, name)
        if snapshot(files) != fixed or plan(snapshot(files))[1]:
            raise RepairError('Post-repair verification failed')
    except BaseException:
        # Keep inodes: generation and SQLite references depend on the .jhr inode.
        try:
            for ext, raw in data.items():
                write_all(files[ext], raw)
            if snapshot(files) != data:
                raise RepairError('Rollback verification failed')
            manifest['state'] = 'rolled-back'
            save_manifest(backup, manifest)
        except BaseException as error:
            raise RepairError('Rollback incomplete; KEEP MAINTENANCE, restore verified backup') from error
        raise
    manifest['state'] = 'complete'
    save_manifest(backup, manifest)


def restore(files, directory, name, backup, expected):
    manifest = json.loads((backup / 'manifest.json').read_bytes())
    if manifest['report'] != expected:
        raise RepairError('Backup manifest does not match report')
    data = {ext: (backup / ('base' + ext)).read_bytes() for ext in expected['files']}
    if {ext: digest(raw) for ext, raw in data.items()} != expected['files']:
        raise RepairError('Backup hashes do not match')
    fixed = repaired(data, expected['changes'])
    current = snapshot(files)
    # A crash may leave any prefix of either file written. Refuse later arrivals
    # or edits outside planned byte values instead of discarding new messages.
    for ext, raw in data.items():
        if len(current[ext]) != len(raw) or any(c not in (a, b) for c, a, b in zip(current[ext], raw, fixed[ext])):
            raise RepairError('JAM has new or unrelated data; automatic rollback refused')
    check_paths(files, directory, name)
    for ext, raw in data.items():
        write_all(files[ext], raw)
    if snapshot(files) != data:
        raise RepairError('Rollback verification failed; KEEP MAINTENANCE')
    manifest['state'] = 'rolled-back'
    save_manifest(backup, manifest)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--base', required=True, help='Relative base with an explicit UTF-8 override')
    parser.add_argument('--report', type=Path, required=True, help='New dry-run output, or existing apply report')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--apply', action='store_true')
    mode.add_argument('--restore', action='store_true')
    parser.add_argument('--maintenance-file', type=Path)
    parser.add_argument('--backup', type=Path)
    args = parser.parse_args(argv)
    try:
        config_bytes = args.config.read_bytes()
        config = json.loads(config_bytes)
        ftn = config['ftn']
        override = ftn.get('jam_encoding_overrides', {}).get(args.base, '').upper()
        if override not in ('UTF-8', 'UTF8'):
            raise RepairError('Base must have an explicit UTF-8 override')
        config_root = args.config.absolute().parent
        root = (config_root / ftn['jam_base_path']).resolve(strict=True)
        lock = config_root / ftn['coordination_lock']
        writing = args.apply or args.restore
        if writing and (args.maintenance_file is None or args.backup is None):
            raise RepairError('Apply/restore requires maintenance declaration and backup directory')
        # A shared diagnostic lock would also permit concurrent backend appends.
        # Exclusive locking makes the multi-file dry-run a coherent snapshot too.
        with exclusive_lock(lock):
            with open_base(root, args.base, writing) as (files, directory, name):
                data = snapshot(files)
                if writing:
                    expected = json.loads(args.report.read_bytes())
                    if expected['config_sha256'] != digest(config_bytes) or expected['base'] != args.base or expected['identities'] != identities(files):
                        raise RepairError('Report configuration/base/identity mismatch')
                    maintain(args.maintenance_file, expected)
                    if args.restore:
                        restore(files, directory, name, args.backup, expected)
                    else:
                        actual = report_for(data, files, digest(config_bytes), args.base)
                        if actual != expected:
                            raise RepairError('Source changed since report')
                        apply_repair(files, directory, name, data, expected, args.backup)
                    print(json.dumps({'state': 'restored' if args.restore else 'complete', 'changes': len(expected['changes'])}))
                else:
                    report = report_for(data, files, digest(config_bytes), args.base)
                    check_paths(files, directory, name)
                    if snapshot(files) != data:
                        raise RepairError('JAM changed during diagnostic')
                    save_new(args.report, json_bytes(report))
                    print(json.dumps({'state': 'dry-run', 'messages': report['messages'], 'changes': len(report['changes'])}))
        return 0
    except RepairError as error:
        print(str(error) + '; keep maintenance after any apply/restore failure.', file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, TypeError, OverflowError):
        # Do not include codec exceptions, config values or private text in output.
        print('JAM repair refused or failed; keep maintenance after any apply/restore failure. Check report, backup and operator prerequisites.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
