#!/usr/bin/env python3
"""Fingerprint significant native build inputs, excluding runner labels and kernel."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import subprocess

from dependency_lock import load

ROOT = Path(__file__).resolve().parents[2]


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def probe(command):
    result = subprocess.run(command, capture_output=True, text=True, check=True)
    return result.stdout.strip()


def validate_profile(values, lock):
    system = values['system']
    if system == 'Linux':
        expected = lock['tools']['linux_clang']
        if not re.search(r'clang version '+re.escape(expected)+r'\.', values['cxx']):
            raise ValueError(f'Unsupported compiler: expected Linux Clang {expected}; actual {values["cxx"]}')
    elif system == 'Darwin':
        expected = 'Xcode '+lock['tools']['xcode']
        if values['xcode'].splitlines()[0] != expected:
            raise ValueError(f'Unsupported SDK toolchain: expected {expected}; actual {values["xcode"]}')
    else:
        raise ValueError(f'Unsupported native system: {system}')


def collect():
    cxx = shlex.split(os.environ.get('CXX', 'c++'))
    cc = shlex.split(os.environ.get('CC', 'cc'))
    system = platform.system()
    values = {'schema': 2, 'system': system, 'arch': platform.machine(),
              'target': os.environ.get('MACOSX_DEPLOYMENT_TARGET', '15.0' if system == 'Darwin' else ''),
              'cc': probe([*cc, '--version']), 'cxx': probe([*cxx, '--version']),
              'target_triple': probe([*cxx, '-dumpmachine']),
              'cmake': probe(['cmake', '--version']),
              'flags': {k: os.environ.get(k, '') for k in
                        ('CFLAGS', 'CXXFLAGS', 'CPPFLAGS', 'LDFLAGS', 'SDKROOT', 'CMAKE_GENERATOR')},
              'system_libraries': {name: probe(['pkg-config', '--modversion', name])
                                   for name in ('re2', 'libcares', 'openssl', 'zlib')}}
    # Predefined macros cover the selected standard-library ABI and compiler target.
    result = subprocess.run([*cxx, '-std=c++23', '-dM', '-E', '-x', 'c++', '-'],
                            input='#include <version>\n', capture_output=True, text=True, check=True)
    values['abi'] = '\n'.join(sorted(line for line in result.stdout.splitlines()
                                   if re.search(r'LIBCPP|GLIBCXX|__GLIBC|__SIZEOF_POINTER__|__BYTE_ORDER__', line)))
    if system == 'Darwin':
        values['sdk'] = probe(['xcrun', '--show-sdk-version'])
        values['xcode'] = probe(['xcodebuild', '-version'])
    elif system == 'Linux':
        values['libc'] = platform.libc_ver()
        values['os_release'] = platform.freedesktop_os_release().get('ID', '')
    return values


def fingerprint(values, lock, recipes):
    # Components consume their own source and upstream keys; a lock change in an
    # unrelated component must not invalidate the toolchain profile itself.
    return digest({'environment': values, 'tools': lock['tools'], 'recipes': recipes})


UPSTREAM = {'abseil': [], 'protobuf': ['abseil'], 'grpc': ['abseil', 'protobuf'],
            'huskylib': [], 'smapi': ['huskylib'], 'fidoconf': ['huskylib', 'smapi'],
            'areafix': ['huskylib', 'smapi', 'fidoconf'],
            'hpt': ['huskylib', 'smapi', 'fidoconf', 'areafix']}


def component_keys(profile, lock):
    keys = {}
    for name, upstream in UPSTREAM.items():
        keys[name] = digest({'profile': profile, 'source': lock['native'][name],
                             'upstream': {dep: keys[dep] for dep in upstream}})
    return keys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--describe', action='store_true')
    args = parser.parse_args()
    lock, values = load(), collect()
    validate_profile(values, lock)
    recipes = {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in
               ('scripts/release/dependencies.sh', 'scripts/release/dependency_record.py',
                'scripts/release/cache_key.py', 'scripts/release/native_cache.py')}
    key = fingerprint(values, lock, recipes)
    components = component_keys(key, lock)
    record = {'key': key, 'components': components, 'inputs': values, 'recipes': recipes}
    output = ROOT/'build/native-profile.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(record, indent=2)+'\n')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as out:
            out.write('key='+digest(components)+'\n')
            out.write('toolchain='+key+'\n')
            for name, component_key in components.items():
                out.write(name+'='+component_key+'\n')
    print(json.dumps(record, indent=2) if args.describe else key)


if __name__ == '__main__':
    main()
