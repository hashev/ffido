#!/usr/bin/env python3
"""Bridge exact verified Docker-native component caches across hosted runners."""
import argparse
import json
import os
from pathlib import Path
import shutil

from native_cache import verify

PROFILE = Path('build/docker-native-profile/native-profile.json')
CACHE = Path('build/docker-native-cache')
EXPORT = Path('build/docker-native-cache-export')
LOOKUPS = PROFILE.with_name('lookups.json')


def emit(values):
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as out:
            for name, value in values.items():
                out.write(f'{name}={value}\n')


def ready(cache, keys, lookups):
    return {name: 'true' for name, key in keys.items()
            if not lookups.get(name, False) and verify(cache/name, key)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['profile', 'lookups', 'save'])
    args = parser.parse_args()
    profile = json.loads(PROFILE.read_text())
    keys = profile['components']
    if args.operation == 'profile':
        emit(keys)
        print(json.dumps(profile, indent=2))
    elif args.operation == 'lookups':
        steps = json.loads(os.environ['CACHE_STEPS'])
        lookups = {name: steps.get('restore-'+name, {}).get('outputs', {}).get('cache-hit') == 'true'
                   for name in keys}
        LOOKUPS.write_text(json.dumps(lookups)+'\n')
        for name, hit in lookups.items():
            print(f'Docker {name}: exact cache '+('hit' if hit else 'miss'))
    else:
        lookups = json.loads(LOOKUPS.read_text())
        # Keep restore/save paths identical: Actions cache versions include paths.
        if CACHE.exists():
            shutil.rmtree(CACHE)
        shutil.move(str(EXPORT), str(CACHE))
        completed = ready(CACHE, keys, lookups)
        emit(completed)
        print('Verified new Docker components: '+', '.join(completed))


if __name__ == '__main__':
    main()
