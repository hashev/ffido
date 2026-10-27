#!/usr/bin/env python3
"""Reuse only successful clang-tidy results with identical complete build inputs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

from cache_key import digest

ROOT = Path(__file__).resolve().parents[2]


def inputs(root, build, profile, tidy_version):
    # Include tracked and new non-ignored project inputs. Runtime/build data are
    # excluded by Git; the actual compilation database and native profile follow.
    names = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z',
                                     '--cached', '--others', '--exclude-standard', '--',
                                     'apps/backend', 'contracts', 'cmake', 'CMakeLists.txt',
                                     '.clang-tidy', 'scripts/check_cpp.py',
                                     'scripts/release/analysis_cache.py'], text=True).split('\0')
    files = {}
    for name in sorted(set(names)-{''}):
        path = root/name
        if path.is_file():
            files[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    raw = (build/'compile_commands.json').read_text()
    # Checkout paths are transport details, but every compiler argument remains.
    for spelling in sorted({str(root), str(root.resolve())}, key=len, reverse=True):
        raw = raw.replace(spelling, '${CHECKOUT}')
    database = json.loads(raw)
    for path in sorted((build/'contracts/generated').rglob('*')):
        if path.is_file():
            files['generated/'+path.relative_to(build/'contracts/generated').as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    for source in sorted((build/'_deps').glob('*-src')):
        for path in sorted(source.rglob('*')):
            if path.is_file() and path.suffix in {'.h', '.hpp', '.inc', '.inl'}:
                files['dependency/'+path.relative_to(build/'_deps').as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    lock = root/'scripts/release/dependencies.lock.json'
    if lock.is_file():
        files['dependency-lock'] = hashlib.sha256(lock.read_bytes()).hexdigest()
    return {'schema': 1, 'files': files, 'database': database, 'native': profile,
            'tidy': tidy_version}


def execute(record, key, command, force=False):
    if not force:
        try:
            proof = json.loads(record.read_text())
            if proof == {'schema': 1, 'key': key, 'result': 'success'}:
                print('C++ analysis cache hit: verified identical inputs', flush=True)
                return 0
        except (OSError, ValueError):
            pass
    print('C++ analysis cache miss: running complete platform analysis', flush=True)
    record.unlink(missing_ok=True)
    code = subprocess.run(command).returncode
    if code == 0:
        record.parent.mkdir(parents=True, exist_ok=True)
        record.write_text(json.dumps({'schema': 1, 'key': key, 'result': 'success'})+'\n')
    return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['key', 'run'])
    parser.add_argument('--build-dir', type=Path, default=ROOT/'build/backend')
    parser.add_argument('--force', action='store_true')
    args = parser.parse_args()
    profile = json.loads((ROOT/'build/native-profile.json').read_text())
    tidy = subprocess.check_output(['clang-tidy', '--version'], text=True).strip()
    value = inputs(ROOT, args.build_dir.resolve(), profile, tidy)
    key = digest(value)
    directory = ROOT/'build/analysis'
    directory.mkdir(parents=True, exist_ok=True)
    (directory/'inputs.json').write_text(json.dumps(value, indent=2)+'\n')
    if args.operation == 'key':
        print('Analysis inputs: '+str(directory/'inputs.json'))
        print('Analysis key: '+key)
        if os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'], 'a') as out:
                out.write('key='+key+'\n')
        return 0
    return execute(directory/'result/success.json', key,
                   [sys.executable, str(ROOT/'scripts/check_cpp.py'), '--skip-format',
                    '--build-dir', str(args.build_dir)], args.force)


if __name__ == '__main__':
    raise SystemExit(main())
