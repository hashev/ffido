#!/usr/bin/env python3
"""Explain exact native cache lookups and rejected file inventories."""
import json
import os
from pathlib import Path

from native_cache import inventory
from dependency_lock import load


def reason(component, key):
    try:
        manifest = json.loads((component/'complete.json').read_text())
        if manifest.get('schema') != 1:
            return 'rejected: unsupported completion manifest schema'
        if manifest.get('key') != key:
            return 'miss: source/toolchain/recipe key differs; current inputs are in native-profile.json'
        expected, actual = manifest['files'], inventory(component/'payload')
        changed = sorted(name for name in set(expected) | set(actual) if expected.get(name) != actual.get(name))
        if changed:
            return 'rejected: missing/changed/extra files: '+', '.join(changed[:10])
        return 'restored: complete inventory matches'
    except (OSError, ValueError, KeyError) as error:
        return f'miss: no readable complete compatible component ({type(error).__name__})'


def main():
    profile = json.loads(Path('build/native-profile.json').read_text())
    lines = ['## Native cache lookup', '', '| Component | Lookup |', '|---|---|']
    lock = load()
    for name, key in profile['components'].items():
        message = reason(Path('build/release-deps/components')/name, key)
        print(name+': '+message+'; source '+lock['native'][name]['revision']+'; expected key '+key)
        lines.append(f'| {name} | {message} |')
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as out:
            out.write('\n'.join(lines)+'\n')


if __name__ == '__main__':
    main()
