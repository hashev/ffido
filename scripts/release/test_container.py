import importlib.util
import pathlib
import unittest
from unittest.mock import patch
import subprocess
import base64
import io
import json
import os
import contextlib

spec = importlib.util.spec_from_file_location('container_publish', pathlib.Path(__file__).with_name('container_publish.py'))
container = importlib.util.module_from_spec(spec)
spec.loader.exec_module(container)


def identity(version='1.2.3', stable=True):
    return {'version': version, 'sha': 'a'*40, 'stable': stable,
            'tag': 'v'+version+('' if stable else '-dev.1234.'+'a'*12)}


class Registry:
    def __init__(self, record, digest='sha256:new'):
        self.record, self.digest, self.images, self.copied = record, digest, {}, []

    def inspect(self, tag):
        return self.images.get(tag)

    def copy(self, archive, tag):
        self.copied.append(tag)
        self.images[tag] = {'Digest': self.digest, 'Labels': {
            'org.opencontainers.image.revision': self.record['sha'],
            'org.opencontainers.image.version': self.record['tag']}}


class ContainerPublishTest(unittest.TestCase):
    def test_tags_and_rejected_identities(self):
        self.assertEqual(container.tags(identity()), ['1.2.3', 'sha-'+'a'*40])
        self.assertEqual(container.tags(identity(stable=False))[0], '1.2.3-dev.1234.'+'a'*12)
        for change in ({'sha': 'bad'}, {'tag': 'latest'}, {'stable': 'false'}, {'version': '../bad'}):
            with self.assertRaises(ValueError):
                container.tags({**identity(), **change})

    def test_idempotent_version_and_sha_with_latest(self):
        record = identity()
        registry = Registry(record)
        container.publish(registry, 'archive', record, registry.digest)
        self.assertEqual(registry.copied, ['1.2.3', 'sha-'+'a'*40, 'latest'])
        registry.copied.clear()
        container.publish(registry, 'archive', record, registry.digest)
        self.assertEqual(registry.copied, ['latest'])
        with self.assertRaises(ValueError):
            container.publish(registry, 'archive', record, 'sha256:different')

    def test_prerelease_then_stable_preserves_first_sha(self):
        registry = Registry(identity(stable=False), 'sha256:pre')
        container.publish(registry, 'archive', registry.record, registry.digest)
        self.assertNotIn('latest', registry.images)
        registry.record, registry.digest = identity(), 'sha256:stable'
        container.publish(registry, 'archive', registry.record, registry.digest)
        self.assertEqual(registry.images['sha-'+'a'*40]['Digest'], 'sha256:pre')
        self.assertEqual(registry.images['latest']['Digest'], 'sha256:stable')

    def test_serialized_late_old_release_cannot_roll_latest_back(self):
        registry = Registry(identity('2.0.0'))
        container.publish(registry, 'new', registry.record, registry.digest)
        registry.record, registry.digest = identity('1.9.9'), 'sha256:old'
        container.publish(registry, 'old', registry.record, registry.digest)
        self.assertEqual(registry.images['latest']['Labels']['org.opencontainers.image.version'], 'v2.0.0')

    def test_conflicting_sha_and_unknown_latest_fail(self):
        registry = Registry(identity())
        registry.images['sha-'+'a'*40] = {'Digest': 'sha256:bad', 'Labels': {}}
        with self.assertRaises(ValueError):
            container.publish(registry, 'archive', registry.record, registry.digest)
        self.assertEqual(registry.copied, [])
        with self.assertRaises(ValueError):
            container.latest_allowed('unversioned', '1.2.3')

    def test_registry_does_not_treat_auth_failure_as_missing_tag(self):
        registry = container.Registry()
        with patch.object(container.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'unauthorized')):
            with self.assertRaises(RuntimeError):
                registry.inspect('1.2.3')
        with patch.object(container.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'manifest unknown')):
            self.assertIsNone(registry.inspect('1.2.3'))


class DockerHubCredentialsTest(unittest.TestCase):
    def test_pull_only_is_rejected_and_credentials_are_not_printed(self):
        source = pathlib.Path(__file__).with_name('check_dockerhub.py')
        spec = importlib.util.spec_from_file_location('check_dockerhub', source)
        check = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(check)
        for actions in (['pull'], ['pull', 'push']):
            payload = base64.urlsafe_b64encode(json.dumps({'access': [
                {'type': 'repository', 'name': 'hashev/ffido', 'actions': actions}]}).encode()).decode().rstrip('=')
            response = io.BytesIO(json.dumps({'token': 'header.'+payload+'.signature'}).encode())
            output = io.StringIO()
            with patch.dict(os.environ, {'DOCKERHUB_USERNAME': 'fixture', 'DOCKERHUB_TOKEN': 'private-test-value'}), \
                    patch.object(check.urllib.request, 'urlopen', return_value=response), contextlib.redirect_stdout(output):
                if actions == ['pull']:
                    with self.assertRaises(ValueError):
                        check.check()
                else:
                    check.check()
            self.assertNotIn('private-test-value', output.getvalue())
            self.assertNotIn(payload, output.getvalue())


if __name__ == '__main__':
    unittest.main()
