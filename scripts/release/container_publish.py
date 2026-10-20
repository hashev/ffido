#!/usr/bin/env python3
"""Publish the smoke-tested OCI archive, preserving digests and immutable tags."""
import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess

IMAGE = 'docker.io/hashev/ffido'


def tags(identity):
    version, sha, tag = (identity[key] for key in ('version', 'sha', 'tag'))
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise ValueError('Invalid container identity')
    stable = identity['stable']
    if not isinstance(stable, bool):
        raise ValueError('Invalid stable flag')
    expected = 'v'+version
    if stable:
        if tag != expected:
            raise ValueError('Stable container tag differs from version')
    elif not re.fullmatch(re.escape(expected)+r'-dev\.\d+\.'+sha[:12], tag):
        raise ValueError('Only release identities can be published')
    return [version if stable else tag.removeprefix('v'), 'sha-'+sha]


def immutable(existing, wanted):
    if existing is not None and existing != wanted:
        raise ValueError('Published container version has a different digest')
    return existing is None


def latest_allowed(current, candidate):
    if current is None:
        return True
    current = current.removeprefix('v')
    if not re.fullmatch(r'\d+\.\d+\.\d+', current):
        raise ValueError('Cannot identify existing latest stable version')
    return tuple(map(int, candidate.split('.'))) >= tuple(map(int, current.split('.')))


class Registry:
    def command(self, *args):
        auth = os.environ.get('DOCKER_CONFIG', str(pathlib.Path.home()/'.docker'))
        return ['skopeo', *args, '--authfile', str(pathlib.Path(auth)/'config.json')]

    def inspect(self, tag):
        result = subprocess.run(self.command('inspect', 'docker://'+IMAGE+':'+tag),
                                text=True, capture_output=True)
        if result.returncode:
            # Authentication/network errors must never be treated as an absent tag.
            if 'manifest unknown' in result.stderr.lower() or 'name unknown' in result.stderr.lower():
                return None
            raise RuntimeError('Cannot inspect Docker Hub tag '+tag+': '+result.stderr)
        return json.loads(result.stdout)

    def copy(self, archive, tag):
        subprocess.run(self.command('copy', '--all', '--preserve-digests',
                                   'oci-archive:'+str(archive), 'docker://'+IMAGE+':'+tag), check=True)


def publish(registry, archive, identity, digest):
    version_tag, sha_tag = tags(identity)
    current = registry.inspect(version_tag)
    publish_version = immutable(current['Digest'] if current else None, digest)
    sha_image = registry.inspect(sha_tag)
    if sha_image is not None and (sha_image.get('Labels') or {}).get('org.opencontainers.image.revision') != identity['sha']:
        raise ValueError('SHA tag refers to another source revision')
    # The SHA tag keeps the first checked image of a commit, including when a
    # later stable release of that commit has different version metadata.
    publish_latest = False
    if identity['stable']:
        current = registry.inspect('latest')
        version = (current.get('Labels') or {}).get('org.opencontainers.image.version') if current else None
        if current is not None and version is None:
            raise ValueError('Missing latest version label')
        publish_latest = latest_allowed(version, identity['version'])
    # Validate all existing tags before performing the first registry mutation.
    if publish_version:
        registry.copy(archive, version_tag)
    if sha_image is None:
        registry.copy(archive, sha_tag)
    if publish_latest:
        registry.copy(archive, 'latest')
    result = registry.inspect(version_tag)
    if result is None or result['Digest'] != digest:
        raise ValueError('Published container digest differs from tested archive')
    return {'image': IMAGE, 'tag': version_tag, 'digest': digest,
            'sha': identity['sha'], 'version': identity['version'], 'release_tag': identity['tag']}


def inspect_archive(archive, identity):
    raw = subprocess.check_output(['skopeo', 'inspect', '--raw', 'oci-archive:'+str(archive)])
    digest = 'sha256:'+hashlib.sha256(raw).hexdigest()
    info = json.loads(subprocess.check_output(['skopeo', 'inspect', 'oci-archive:'+str(archive)], text=True))
    labels = info.get('Labels') or {}
    if (labels.get('org.opencontainers.image.revision') != identity['sha'] or
            labels.get('org.opencontainers.image.version') != identity['tag'] or
            info['Architecture'] != 'amd64' or info['Os'] != 'linux'):
        raise ValueError('Tested archive identity/platform differs from release')
    return digest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=pathlib.Path)
    parser.add_argument('--identity', type=pathlib.Path, required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    if os.environ.get('FFIDO_PUBLICATION_READY') != 'true':
        parser.exit(1, 'Container publication disabled\n')
    identity = json.loads(args.identity.read_text())
    tags(identity)
    result = publish(Registry(), args.archive, identity, inspect_archive(args.archive, identity))
    args.output.write_text(json.dumps(result, indent=2)+'\n')
