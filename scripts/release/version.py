#!/usr/bin/env python3
"""Validate release refs and derive one client/server build identity."""
import argparse
import json
import os
import pathlib
import re
import subprocess
ROOT = pathlib.Path(__file__).resolve().parents[2]


def identity(version, sha, number, ref, event, reachable):
    if not re.fullmatch(r'[0-9a-f]{40}', sha) or not 0 < number < 2_000_000_000:
        raise ValueError('Invalid SHA/build number')
    if not reachable:
        raise ValueError('Release commit is outside master history')
    if ref.startswith('refs/tags/'):
        tag = ref.removeprefix('refs/tags/')
        if not re.fullmatch(r'v\d+\.\d+\.\d+', tag) or tag != 'v'+version:
            raise ValueError('Stable tag does not match source version')
        if event != 'push':
            raise ValueError('Stable releases require a tag push')
        stable = True
    elif ref == 'refs/heads/master' and event in {'push', 'workflow_dispatch'}:
        tag, stable = f'v{version}-dev.{number}.{sha[:12]}', False
    else:
        raise ValueError('Release requires master or a stable tag')
    return {'version': version, 'sha': sha, 'build_number': number, 'tag': tag, 'stable': stable}


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--output', type=pathlib.Path, required=True)
    a = p.parse_args()
    version = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+', (ROOT/'apps/frontend/pubspec.yaml').read_text(), re.M)[1]
    sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    subprocess.run(['git', 'fetch', 'origin', 'master'], check=True)
    reachable = subprocess.run(['git', 'merge-base', '--is-ancestor', sha, 'origin/master']).returncode == 0
    settings = json.loads((ROOT/'scripts/release/settings.json').read_text())
    data = identity(version, sha, int(os.environ['GITHUB_RUN_NUMBER'])+settings['android_build_offset'],
                    os.environ['GITHUB_REF'], os.environ['GITHUB_EVENT_NAME'], reachable)
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(data, indent=2)+'\n')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as out:
            for key, value in data.items():
                out.write(f'{key}={str(value).lower() if isinstance(value, bool) else value}\n')
