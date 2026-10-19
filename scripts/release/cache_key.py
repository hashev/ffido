#!/usr/bin/env python3
"""Fingerprint the native compiler, runner image, SDK and external libraries."""
import hashlib
import json
import os
import platform
import subprocess

values = {'image': os.environ.get('ImageVersion', 'local'), 'os': platform.platform(),
          'arch': platform.machine(), 'target': os.environ.get('MACOSX_DEPLOYMENT_TARGET', '')}
commands = [[os.environ.get('CXX', 'c++'), '--version'], ['cmake', '--version'],
            ['pkg-config', '--modversion', 're2', 'libcares', 'openssl']]
if platform.system() == 'Darwin':
    commands.append(['xcrun', '--show-sdk-version'])
for command in commands:
    result = subprocess.run(command, capture_output=True, text=True)
    values[' '.join(command)] = [result.returncode, result.stdout, result.stderr]
key = hashlib.sha256(json.dumps(values, sort_keys=True).encode()).hexdigest()
if os.environ.get('GITHUB_OUTPUT'):
    with open(os.environ['GITHUB_OUTPUT'], 'a') as out:
        out.write('key='+key+'\n')
print(key)
