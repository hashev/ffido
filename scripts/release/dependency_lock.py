#!/usr/bin/env python3
"""Read the checked-in dependency lock without modifying it."""
import argparse
import json
import hashlib
import os
from pathlib import Path

LOCK = Path(__file__).with_name('dependencies.lock.json')


def load(path=LOCK):
    value = json.loads(path.read_text())
    if value.get('schema') != 1:
        raise ValueError('Unsupported dependency lock schema')
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('keys', nargs='*')
    parser.add_argument('--github-output', action='store_true')
    args = parser.parse_args()
    value = load()
    if args.github_output:
        with open(os.environ['GITHUB_OUTPUT'], 'a') as out:
            for key, version in value['tools'].items():
                out.write(f'{key}={version}\n')
            if 'compiler_cache' in value:
                key = hashlib.sha256(json.dumps(value['compiler_cache'], sort_keys=True).encode()).hexdigest()
                out.write(f'compiler_cache_key={key}\n')
            for name, item in value.get('android', {}).items():
                key = hashlib.sha256(json.dumps(item, sort_keys=True).encode()).hexdigest()
                out.write(f'android_{name}_key={key}\n')
                if 'package' in item:
                    out.write(f'android_{name}_path='+ '/'.join(item['package'].split(';'))+'\n')
    else:
        for key in args.keys:
            value = value[key]
        print(value if isinstance(value, str) else json.dumps(value, sort_keys=True))


if __name__ == '__main__':
    main()
