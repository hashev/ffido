#!/usr/bin/env python3
"""Publish a complete same-run manifest through a draft, never replace public assets."""
import argparse
import hashlib
import json
import os
import pathlib
import subprocess
import tempfile
ROOT = pathlib.Path(__file__).resolve().parents[2]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory(directory, identity, expected):
    rows = []
    for sidecar in directory.glob('*.package.json'):
        row = json.loads(sidecar.read_text())
        if row['sha'] != identity['sha'] or row['tag'] != identity['tag']:
            raise ValueError('Package belongs to a different commit/run')
        name = row['file']
        if pathlib.Path(name).name != name or not (directory/name).is_file():
            raise ValueError('Invalid/missing package file')
        if digest(directory/name) != row['sha256']:
            raise ValueError('Package checksum mismatch')
        if row['id'] == 'client-android-universal' and row['signing'] != 'release':
            raise ValueError('Public APK is not release-signed')
        rows.append(row)
    if sorted(r['id'] for r in rows) != sorted(expected):
        raise ValueError('Incomplete or duplicated release matrix')
    if len({r['file'] for r in rows}) != len(rows):
        raise ValueError('Duplicated package filename')
    return sorted(rows, key=lambda row: row['id'])


class GitHub:
    def __init__(self, repo):
        self.repo = repo

    def run(self, *args, **kwargs):
        return subprocess.run(['gh', *args, '--repo', self.repo], text=True, check=True, **kwargs)

    def view(self, tag):
        result = subprocess.run(['gh', 'release', 'view', tag, '--repo', self.repo,
                                 '--json', 'isDraft,body,targetCommitish'], text=True, capture_output=True)
        if result.returncode:
            if 'release not found' not in result.stderr.lower():
                raise RuntimeError('Cannot inspect release: '+result.stderr)
            return None
        return json.loads(result.stdout)


def publish(api, directory, identity, rows):
    directory = pathlib.Path(directory)
    marker = f"FFIDO SHA {identity['sha']} tag {identity['tag']}"
    manifest = directory/'release-manifest.json'
    data = {'identity': identity, 'packages': rows}
    container_file = directory/'container.json'
    if container_file.exists():
        container = json.loads(container_file.read_text())
        if container['sha'] != identity['sha'] or container['release_tag'] != identity['tag']:
            raise ValueError('Container belongs to a different release')
        data['container'] = container
    manifest.write_text(json.dumps(data, indent=2)+'\n')
    sums = directory/'SHA256SUMS'
    names = [r['file'] for r in rows]+[manifest.name, 'LICENSE', 'THIRD_PARTY_NOTICES.md']
    for name in ('LICENSE', 'THIRD_PARTY_NOTICES.md'):
        (directory/name).write_bytes((ROOT/name).read_bytes())
    sums.write_text(''.join(f'{digest(directory/name)}  {name}\n' for name in names))
    current = api.view(identity['tag'])
    if current:
        if marker not in current['body']:
            raise ValueError('Release identity conflicts with existing version')
        if not current['isDraft']:
            # Idempotent retry only if the already-public manifest is identical.
            with tempfile.TemporaryDirectory() as tmp:
                api.run('release', 'download', identity['tag'], '--pattern', manifest.name, '--dir', tmp)
                if digest(pathlib.Path(tmp)/manifest.name) != digest(manifest):
                    raise ValueError('Published release differs; use a new version')
            return
    else:
        api.run('release', 'create', identity['tag'], '--draft', '--target', identity['sha'],
                '--title', identity['tag'], '--notes', marker+'\nDesktop: unsigned (macOS ad-hoc), not notarized. Android: permanent release key.')
    files = [str(directory/name) for name in names]+[str(sums)]
    api.run('release', 'upload', identity['tag'], *files, '--clobber')  # drafts only
    with tempfile.TemporaryDirectory() as tmp:
        api.run('release', 'download', identity['tag'], '--dir', tmp)
        if {p.name for p in pathlib.Path(tmp).iterdir()} != {pathlib.Path(p).name for p in files}:
            raise ValueError('Remote asset set differs')
        for file in files:
            if digest(pathlib.Path(tmp)/pathlib.Path(file).name) != digest(pathlib.Path(file)):
                raise ValueError('Uploaded asset checksum differs')
    api.run('release', 'edit', identity['tag'], '--draft=false',
            '--prerelease='+str(not identity['stable']).lower(),
            '--latest='+str(identity['stable']).lower())


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('directory', type=pathlib.Path)
    p.add_argument('--identity', type=pathlib.Path, required=True)
    p.add_argument('--check-only', action='store_true', help='Validate packages without publishing')
    a = p.parse_args()
    if os.environ.get('FFIDO_PUBLICATION_READY') != 'true':
        p.exit(1, 'Public release disabled: FFIDO_PUBLICATION_READY is not true\n')
    settings = json.loads((ROOT/'scripts/release/settings.json').read_text())
    data = json.loads(a.identity.read_text())
    rows = inventory(a.directory, data, settings['expected_packages'])
    if a.check_only:
        print('PASS: complete release package inventory')
        raise SystemExit(0)
    publish(GitHub(settings['repository']), a.directory, data, rows)
