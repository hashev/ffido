#!/usr/bin/env python3
"""Regression checks for private snapshot validation and safe file access."""
import copy
import fcntl
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest

import node_backup as backup
import deployment_backup as deployment
from unittest.mock import patch


class SnapshotValidationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        names = ['config.json', 'metadata.db', 'maintenance.lock', 'metadata.db.lock', 'hpt.lock',
                 'jam/p1.jhr', 'jam/p1.jdt', 'jam/p1.jdx']
        rows = []
        for name in names:
            p = self.root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(name.encode())
            rows.append({'path': name, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()})
        self.value = {'version': 1, 'complete': True, 'schema': 11, 'database': 'metadata.db',
                      'config': 'config.json', 'jam_root': 'jam', 'files': rows,
                      'locks': ['maintenance.lock', 'metadata.db.lock', 'hpt.lock'],
                      'jam': [{'base': 'jam/p1', 'generation': '1:2:3:1', 'conferences': ['mail1']}],
                      'mailboxes': [{'address': '2:1/2.1', 'base': 'p1'}]}
        self.manifest = self.root / 'manifest.json'

    def write_manifest(self):
        raw = backup.dump(self.value)
        self.manifest.write_bytes(raw)
        return hashlib.sha256(raw).hexdigest()

    def test_external_digest_and_complete_inventory(self):
        digest = self.write_manifest()
        result = backup.verify(self.root, self.manifest, digest)
        self.assertEqual(result['schema'], 11)
        before = {p: p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        backup.verify(self.root, self.manifest, digest)
        self.assertEqual(before, {p: p.read_bytes() for p in before})
        self.value['schema'] = 12
        self.write_manifest()
        with self.assertRaises(backup.SnapshotError):
            backup.verify(self.root, self.manifest, digest)

    def test_rejects_unknown_format_duplicates_and_incomplete_snapshot(self):
        for field, value in [('version', 2), ('complete', False), ('schema', 13)]:
            bad = copy.deepcopy(self.value)
            bad[field] = value
            with self.subTest(field=field), self.assertRaises(backup.SnapshotError):
                backup.validate_manifest(bad)
        bad = copy.deepcopy(self.value)
        bad['files'].append(bad['files'][0])
        with self.assertRaises(backup.SnapshotError):
            backup.validate_manifest(bad)
        self.value['files'] = self.value['files'][:-1]
        with self.assertRaises(backup.SnapshotError):
            backup.validate_manifest(self.value)

    def test_rejects_absolute_traversal_and_unsafe_components(self):
        for name in ['/tmp/mail', '../mail', 'jam/../mail', 'jam//mail', './mail', 'jam/./mail', 'mail\0']:
            with self.subTest(name=repr(name)), self.assertRaises(backup.SnapshotError):
                backup.relative(name)

    def test_detects_missing_and_corrupt_content_without_values_in_error(self):
        digest = self.write_manifest()
        private = 'private-password-must-not-appear'
        (self.root / 'config.json').write_text(private)
        with self.assertRaises(backup.SnapshotError) as caught:
            backup.verify(self.root, self.manifest, digest)
        self.assertNotIn(private, str(caught.exception))
        (self.root / 'config.json').unlink()
        with self.assertRaises(FileNotFoundError):
            backup.verify(self.root, self.manifest, digest)

    def test_rejects_symlink_and_hardlink_files(self):
        digest = self.write_manifest()
        name = self.root / 'config.json'
        name.rename(self.root / 'original')
        name.symlink_to('original')
        with self.assertRaises(OSError):
            backup.verify(self.root, self.manifest, digest)
        name.unlink()
        os.link(self.root / 'original', name)
        with self.assertRaises(backup.SnapshotError):
            backup.verify(self.root, self.manifest, digest)

    def test_rejects_directory_alias(self):
        digest = self.write_manifest()
        (self.root / 'jam').rename(self.root / 'elsewhere')
        (self.root / 'jam').symlink_to('elsewhere', target_is_directory=True)
        with self.assertRaises(OSError):
            backup.verify(self.root, self.manifest, digest)

    def test_held_lock_prevents_snapshot(self):
        with backup.open_file(self.root, 'maintenance.lock') as held:
            import fcntl
            fcntl.flock(held.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(backup.SnapshotError):
                with backup.stopped(self.root, ['maintenance.lock']):
                    self.fail('a held lock must not be ignored')

    def test_maps_only_explicit_runtime_roots(self):
        self.assertEqual(backup.relative_input(self.root, '/runtime/metadata.db',
                                              [('/runtime', str(self.root))]), 'metadata.db')
        with self.assertRaises(backup.SnapshotError):
            backup.relative_input(self.root, '/other/metadata.db', [])

    def test_snapshot_inherits_only_a_held_exclusive_maintenance_lease(self):
        locks = ['maintenance.lock', 'metadata.db.lock', 'hpt.lock']
        with (self.root/'maintenance.lock').open('rb') as lease:
            with self.assertRaises(backup.SnapshotError):
                with backup.stopped(self.root, locks, {'maintenance.lock': lease.fileno()}):
                    self.fail('unheld descriptor accepted')
            fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with backup.stopped(self.root, locks, {'maintenance.lock': lease.fileno()}):
                pass
            with (self.root/'maintenance.lock').open('rb') as other:
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(other, fcntl.LOCK_EX | fcntl.LOCK_NB)


class DeploymentTest(unittest.TestCase):
    def setUp(self):
        SnapshotValidationTest.setUp(self)
        self.bundle = self.root/'bundle'
        self.bundle.mkdir(mode=0o700)
        node = self.bundle/'node'
        node.mkdir(mode=0o700)
        for row in self.value['files']:
            source = self.root/row['path']
            target = node/row['path']
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
            info = target.stat()
            row.update(mode=0o600, uid=info.st_uid, gid=info.st_gid)
        self.value['directories'] = ['jam']
        self.value['directory_metadata'] = {'jam': {'mode': 0o700, 'uid': os.getuid(), 'gid': os.getgid()}}
        raw = backup.dump(self.value)
        (node/'snapshot.json').write_bytes(raw)
        self.node_digest = hashlib.sha256(raw).hexdigest()
        self.profile = {}
        for role in deployment.COMPONENTS:
            source = self.root/('source-'+role)
            source.mkdir(mode=0o700)
            (source/'input').write_bytes(role.encode())
            (source/'input').chmod(0o600)
            self.profile[role] = {'root': str(source), 'required': ['input']}

    def seal(self):
        return deployment.complete(self.bundle, self.node_digest,
                                   deployment.component_inventory(self.profile))

    def test_full_bundle_and_staging_preserve_content_permissions(self):
        digest = self.seal()
        value = deployment.verify(self.bundle, digest)
        self.assertEqual({x['role'] for x in value['components']}, deployment.COMPONENTS)
        staged = self.root/'staged'
        deployment.restore(self.bundle, digest, staged)
        target = staged/'components/acme/input'
        self.assertEqual(target.read_bytes(), b'acme')
        self.assertEqual(target.stat().st_mode & 0o777, 0o600)
        self.assertEqual((staged/'node/jam/p1.jhr').read_bytes(), b'jam/p1.jhr')
        with self.assertRaises(backup.SnapshotError):
            deployment.restore(self.bundle, digest, staged)

    def test_directory_sync_failure_never_publishes_complete_bundle(self):
        with patch.object(deployment, 'sync_directories', side_effect=OSError('fsync failed')):
            with self.assertRaisesRegex(OSError, 'fsync failed'):
                self.seal()
        self.assertFalse((self.bundle/'deployment.json').exists())

    def test_required_components_corruption_and_traversal(self):
        incomplete = dict(self.profile)
        del incomplete['gateway']
        with self.assertRaises(backup.SnapshotError):
            deployment.component_inventory(incomplete)
        self.profile['gateway']['required'] = ['../outside']
        with self.assertRaises(backup.SnapshotError):
            deployment.component_inventory(self.profile)
        self.profile['gateway']['required'] = ['input']
        digest = self.seal()
        (self.bundle/'components/gateway/input').write_bytes(b'corruption')
        with self.assertRaises(backup.SnapshotError):
            deployment.verify(self.bundle, digest)
        with self.assertRaises(backup.SnapshotError):
            deployment.verify(self.bundle, '0'*64)

    def test_acme_links_are_bounded_and_materialized(self):
        source = Path(self.profile['acme']['root'])
        (source/'live/example').mkdir(parents=True)
        (source/'archive/example').mkdir(parents=True)
        (source/'archive/example/key1.pem').write_bytes(b'qa-private-key')
        link = source/'live/example/privkey.pem'
        link.symlink_to('../../archive/example/key1.pem')
        digest = self.seal()
        copy = self.bundle/'components/acme/live/example/privkey.pem'
        self.assertFalse(copy.is_symlink())
        deployment.verify(self.bundle, digest)
        link.unlink(); link.symlink_to(self.root/'config.json')
        with self.assertRaises(backup.SnapshotError):
            deployment.component_inventory(self.profile)

    def test_budget_blocks_before_mutation_and_keeps_reserve(self):
        usage = type('Usage', (), {'free': 2*1024**3+4*100+2*50-1})()
        with patch.object(deployment.shutil, 'disk_usage', return_value=usage):
            with self.assertRaisesRegex(backup.SnapshotError, 'deficit bytes: 1'):
                deployment.disk_budget(self.root, 100, 50)
            usage.free += 1
            self.assertEqual(deployment.disk_budget(self.root, 100, 50)['deficit_bytes'], 0)

    def test_changed_source_does_not_publish_completion(self):
        inventory = deployment.component_inventory(self.profile)
        (Path(self.profile['renewal']['root'])/'input').write_bytes(b'changed')
        with self.assertRaises(backup.SnapshotError):
            deployment.complete(self.bundle, self.node_digest, inventory)
        self.assertFalse((self.bundle/'deployment.json').exists())

    def test_explicit_selection_excludes_runtime_logs_but_not_required_inputs(self):
        source = Path(self.profile['gateway']['root'])
        (source/'runtime.log').write_bytes(b'live log')
        self.profile['gateway']['includes'] = ['input']
        digest = self.seal()
        self.assertFalse((self.bundle/'components/gateway/runtime.log').exists())
        deployment.verify(self.bundle, digest)


if __name__ == '__main__':
    unittest.main()
