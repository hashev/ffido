#!/usr/bin/env python3
"""Offline restore CLI regressions using disposable, genuinely provisioned databases."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
from unittest import mock
import subprocess
import sys
import tempfile
import unittest

import node_backup

ADMIN = None
FAULT = None


class MailboxRestoreTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ffido-restore-test-')
        self.addCleanup(self.temp.cleanup)
        self.parent = Path(self.temp.name)
        self.source = self.parent / 'source'
        self.source.mkdir()
        root = self.source
        (root / 'hpt.cfg').write_text('Name Restore fixture\nSysop Fixture\nLocation Test\nAddress 2:1/2\n'
                                     'Link Point1\nAKA 2:1/2.1\nOurAKA 2:1/2\nPassword fixture1\n'
                                     'Link Point2\nAKA 2:1/2.2\nOurAKA 2:1/2\nPassword fixture2\n'
                                     'KeepTrsMail on\nPackNetMailOnScan off\nRoute nopack 2:1/2.1 2:1/2.2\nRoute normal noroute *\n'
                                     f'NetmailArea IN {root}/IN -b JAM -dupeCheck off\nNetmailArea OUT {root}/OUT -b JAM -dupeCheck off\n')
        (root / 'areas.cfg').write_text('')
        (root / 'jam').mkdir()
        config = {'auth': {'hpt_config_path': str(root / 'hpt.cfg'), 'session_key_path': str(root / 'session.key')},
                  'ftn': {'areacfg_path': str(root / 'areas.cfg'), 'jam_base_path': str(root / 'jam'),
                          'coordination_lock': str(root / 'hpt.lock')},
                  'database': {'metadata_path': str(root / 'metadata.db')},
                  'point_mail': {'enabled': True, 'ingress_areas': ['IN'], 'egress_area': 'OUT',
                                 'points': [{'address': f'2:1/2.{p}', 'jam_base': f'points/p{p}'} for p in (1, 2)]}}
        (root / 'config.json').write_text(json.dumps(config))
        result = subprocess.run([ADMIN, 'provision-mailboxes', str(root / 'config.json')], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in ['maintenance.lock', 'hpt.lock', 'metadata.db.lock']:
            (root / name).touch(exist_ok=True)
        with sqlite3.connect(root / 'metadata.db') as db:
            rows = [dict(zip(('address', 'base', 'generation', 'files'), row)) for row in
                    db.execute('select address,base,generation,files from mailbox_bindings order by address')]
        db.close()
        self.manifest = {'version': 1, 'complete': True, 'schema': 12, 'database': 'metadata.db',
                         'config': 'config.json', 'jam_root': 'jam',
                         'locks': ['maintenance.lock', 'metadata.db.lock', 'hpt.lock'], 'jam': [], 'mailboxes': rows}
        for row in rows:
            self.manifest['jam'].append({'base': 'jam/' + row['base'], 'generation': row['generation'],
                                         'conferences': ['@ffido/mailbox/' + row['address'].encode().hex()]})
        self.root = self.parent / 'restored'
        self.refresh()
        shutil.copytree(root, self.root)

    def refresh(self):
        self.manifest['files'] = [{'path': str(p.relative_to(self.source)),
                                   'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                                  for p in sorted(self.source.rglob('*')) if p.is_file()]
        self.manifest_path = self.parent / 'trusted.json'
        raw = node_backup.dump(self.manifest)
        self.manifest_path.write_bytes(raw)
        self.digest = hashlib.sha256(raw).hexdigest()

    def run_cli(self, mode='check', plan=None, digest=None, ok=True, lease=None):
        args = [ADMIN, 'mailbox-restore', str(self.root), str(self.manifest_path), digest or self.digest, mode]
        if plan is not None:
            args.append(plan)
        if lease is not None:
            args += ['--maintenance-lock-fd', str(lease)]
        result = subprocess.run(args, capture_output=True, timeout=15,
                                pass_fds=() if lease is None else (lease,))
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(b'fixture1', result.stderr)
        return result

    def test_inherited_maintenance_lease_keeps_parent_exclusive(self):
        with (self.root/'maintenance.lock').open('rb') as lease:
            fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.run_cli(ok=False)  # Reproduce refusal without inherited description.
            plan = self.run_cli(lease=lease.fileno())
            self.run_cli('apply', plan=plan['plan_digest'], lease=lease.fileno())
            with (self.root/'maintenance.lock').open('rb') as competitor:
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(competitor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.run_cli(lease=lease.fileno())

    def test_invalid_inherited_lease_never_assigns_mailboxes(self):
        before = self.contents()
        for lock_name, kind in [('maintenance.lock', None), ('maintenance.lock', fcntl.LOCK_SH),
                                ('hpt.lock', fcntl.LOCK_EX)]:
            with self.subTest(lock=lock_name, kind=kind), (self.root/lock_name).open('rb') as lease:
                if kind is not None:
                    fcntl.flock(lease, kind | fcntl.LOCK_NB)
                self.run_cli(ok=False, lease=lease.fileno())
        self.assertEqual(self.contents(), before)

    def contents(self):
        return {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}

    def test_check_apply_and_repeat_preserve_schema_and_logical_generation(self):
        before = self.contents()
        plan = self.run_cli()['plan_digest']
        self.assertEqual(before, self.contents())
        self.run_cli('apply', plan)
        applied = self.contents()
        self.assertTrue(self.run_cli()['already_applied'])
        self.assertTrue(self.run_cli('apply', plan)['already_applied'])
        self.assertEqual(applied, self.contents())
        with sqlite3.connect(self.root / 'metadata.db') as db:
            self.assertEqual(db.execute('pragma user_version').fetchone()[0], 12)
            restored = db.execute('select base,physical_generation,logical_generation from restored_generations').fetchall()
            self.assertEqual(len(restored), 2)
            for base, physical, logical in restored:
                original = next(x for x in self.manifest['mailboxes'] if x['base'] == base)
                self.assertEqual(original['generation'], logical)
                self.assertNotEqual(physical, logical)
                self.assertEqual(db.execute('select generation from mailbox_bindings where base=?', (base,)).fetchone()[0], physical)
        db.close()
        for path, data in before.items():
            if path != 'metadata.db':
                self.assertEqual((self.root / path).read_bytes(), data)

    def test_crash_boundaries_and_backup_fsync_failure_are_retryable(self):
        self.assertIsNotNone(FAULT, 'fault library must be supplied for the release gate')
        pristine = self.contents()
        for stage, action in [('before-commit', 'exit'), ('transaction', 'exit'),
                              ('after-commit', 'exit'), ('before-commit', 'fail')]:
            with self.subTest(stage=stage, action=action):
                shutil.rmtree(self.root)
                shutil.copytree(self.source, self.root)
                plan = self.run_cli()['plan_digest']
                env = dict(os.environ)
                env['DYLD_INSERT_LIBRARIES' if sys.platform == 'darwin' else 'LD_PRELOAD'] = FAULT
                env.update(FFIDO_TEST_RESTORE_ROOT=str(self.root.resolve()), FFIDO_TEST_RESTORE_STAGE=stage,
                           FFIDO_TEST_RESTORE_ACTION=action)
                args = [ADMIN, 'mailbox-restore', str(self.root), str(self.manifest_path), self.digest, 'apply', plan]
                result = subprocess.run(args, env=env, capture_output=True, timeout=15)
                self.assertEqual(result.returncode, 86 if action == 'exit' else 1, result.stderr)
                if stage == 'before-commit':
                    self.assertEqual((self.root / 'metadata.db').read_bytes(), pristine['metadata.db'])
                # Explicit apply reconciles either a rolled-back transaction or its committed receipt.
                retry = self.run_cli('apply', plan)
                self.assertTrue(retry.get('applied') or retry['already_applied'])
                self.assertTrue(self.run_cli()['already_applied'])
                for name, data in pristine.items():
                    if name != 'metadata.db':
                        self.assertEqual((self.root / name).read_bytes(), data)

    def test_schema11_is_not_migrated(self):
        with sqlite3.connect(self.source / 'metadata.db') as db:
            db.executescript('drop trigger telegram_binding_delete; drop table telegram_bindings; '
                             'alter table tokens drop column telegram_revision; pragma user_version=11;')
        db.close()
        self.manifest['schema'] = 11
        self.refresh()
        shutil.rmtree(self.root)
        shutil.copytree(self.source, self.root)
        self.run_cli('apply', self.run_cli()['plan_digest'])
        with sqlite3.connect(self.root / 'metadata.db') as db:
            self.assertEqual(db.execute('pragma user_version').fetchone()[0], 11)
            self.assertFalse(db.execute("select name from sqlite_master where name='telegram_bindings'").fetchall())
        db.close()

    def test_rejects_stale_plan_and_untrusted_manifest_without_changes(self):
        before = self.contents()
        self.run_cli(digest='0' * 64, ok=False)
        self.run_cli('apply', '0' * 64, ok=False)
        self.run_cli('apply', ok=False)
        self.assertEqual(before, self.contents())
        plan = self.run_cli()['plan_digest']
        target = self.root / 'jam/points/p1.jhr'
        data = target.read_bytes()
        target.rename(target.with_suffix('.saved'))
        target.write_bytes(data)
        before = self.contents()
        self.run_cli('apply', plan, ok=False)
        self.assertEqual(before, self.contents())

    def test_rejects_foreign_config_and_corrupt_header(self):
        for name in ['config.json', 'jam/points/p1.jhr', 'metadata.db']:
            target = self.root / name
            original = target.read_bytes()
            target.write_bytes(b'foreign')
            before = self.contents()
            self.run_cli(ok=False)
            self.assertEqual(before, self.contents())
            target.write_bytes(original)

    def test_busy_locks_and_links_are_rejected(self):
        for name in self.manifest['locks']:
            with (self.root / name).open('rb') as held:
                fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
                self.run_cli(ok=False)
        target = self.root / 'jam/points/p1.jhr'
        target.rename(self.root / 'saved.jhr')
        target.symlink_to(self.root / 'saved.jhr')
        self.run_cli(ok=False)
        target.unlink()
        os.link(self.root / 'saved.jhr', target)
        self.run_cli(ok=False)

    def test_pending_state_and_unknown_schema_fail_before_backup(self):
        for statement in ['pragma user_version=13', 'update mail_pipeline set state=2']:
            original = (self.source / 'metadata.db').read_bytes()
            with sqlite3.connect(self.source / 'metadata.db') as db:
                db.executescript(statement)
            db.close()
            self.refresh()
            shutil.copyfile(self.source / 'metadata.db', self.root / 'metadata.db')
            before = self.contents()
            self.run_cli(ok=False)
            self.assertEqual(before, self.contents())
            (self.source / 'metadata.db').write_bytes(original)

    def prepare_snapshot_source(self):
        root = self.source
        config = json.loads((root / 'config.json').read_text())
        config['server'] = {'tls_certificate': str(root / 'tls/server.pem'),
                            'tls_private_key': str(root / 'tls/server-key.pem')}
        config['ftn']['jam_message_encoding_corrections_path'] = str(root / 'corrections.jsonl')
        (root / 'config.json').write_text(json.dumps(config))
        content = (root / 'hpt.cfg').read_text().replace(str(root) + '/IN', str(root) + '/jam/IN')
        content = content.replace(str(root) + '/OUT', str(root) + '/jam/OUT')
        (root / 'areas.cfg').write_text(content + f'Intab {root}/spool/intab\nOuttab {root}/spool/outtab\n')
        (root / 'hpt.cfg').write_text(f'Include {root}/areas.cfg\n')
        directories = {'f', 'spool', 'dupebase', 'flags', 'ffido/fileboxes', 'ffido/ops',
                       'ffido/updater', 'ffido/updates', 'ffido/acme/config'}
        for name in directories:
            (root / name).mkdir(parents=True, exist_ok=True)
        for name in set(node_backup.REQUIRED_LAYOUT) - directories | {
                'session.key', 'tls/server.pem', 'tls/server-key.pem', 'corrections.jsonl',
                'spool/intab', 'spool/outtab'}:
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(bytes(range(256)))
        for name in ['IN', 'OUT']:
            for ext in ['.jhr', '.jdt', '.jdx']:
                shutil.copyfile(root / ('jam/points/p1' + ext), root / ('jam/' + name + ext))
        (root / 'ffido/backups/special').mkdir(parents=True)
        (root / 'ffido/backups/special/referenced').write_bytes(b'protected snapshot')
        return str(Path(ADMIN).parent / 'ffido-hpt-auth')

    def take_snapshot(self, destination, helper):
        return node_backup.snapshot(self.source, destination, 'config.json', helper, [], [], 'maintenance.lock')

    def test_file_changed_during_snapshot_is_never_complete(self):
        helper = self.prepare_snapshot_source()
        original_copy = node_backup.shutil.copyfileobj
        changed = False
        def copy_and_change(source, target, length):
            nonlocal changed
            original_copy(source, target, length)
            if not changed:
                changed = True
                (self.source / '.env').write_bytes(b'changed-during-copy')
        destination = self.parent / 'changed-snapshot'
        with mock.patch.object(node_backup.shutil, 'copyfileobj', side_effect=copy_and_change):
            with self.assertRaises(node_backup.SnapshotError):
                self.take_snapshot(destination, helper)
        self.assertFalse((destination / 'snapshot.json').exists())

    def test_trusted_manifest_rejects_unsafe_paths_and_foreign_assignment(self):
        original = json.loads(json.dumps(self.manifest))
        for path in ['../source/config.json', '/tmp/config.json', 'jam//points/p1.jhr', 'jam/../config.json']:
            self.manifest = json.loads(json.dumps(original))
            self.manifest['files'][0]['path'] = path
            raw = node_backup.dump(self.manifest)
            self.manifest_path.write_bytes(raw)
            self.digest = hashlib.sha256(raw).hexdigest()
            before = self.contents()
            self.run_cli(ok=False)
            self.assertEqual(before, self.contents())
        self.manifest = original
        self.manifest['mailboxes'][1]['base'] = self.manifest['mailboxes'][0]['base']
        self.refresh()
        before = self.contents()
        self.run_cli(ok=False)
        self.assertEqual(before, self.contents())

    def test_unmapped_historical_generation_is_rejected_without_writes(self):
        with sqlite3.connect(self.source / 'metadata.db') as db:
            db.execute("insert into users(user_id,name,ftn_address) values('A','Fixture','2:1/2.1')")
            db.execute("insert into read_status(user_id,conference_id,generation,message_id) values(?,?,?,?)",
                       ('A', self.manifest['jam'][0]['conferences'][0], '1:2:3:4', '1:2:3:4#1'))
        db.close()
        self.refresh()
        shutil.copyfile(self.source / 'metadata.db', self.root / 'metadata.db')
        before = self.contents()
        self.run_cli(ok=False)
        self.assertEqual(before, self.contents())

    def test_trusted_manifest_rejects_repeated_generation_and_bad_header(self):
        original = json.loads(json.dumps(self.manifest))
        self.manifest['jam'][1]['generation'] = self.manifest['jam'][0]['generation']
        self.refresh()
        before = self.contents()
        self.run_cli(ok=False)
        self.assertEqual(before, self.contents())
        self.manifest = original
        header = self.source / 'jam/points/p1.jhr'
        raw = bytearray(header.read_bytes())
        raw[:4] = b'BAD!'
        header.write_bytes(raw)
        self.refresh()
        shutil.copyfile(header, self.root / 'jam/points/p1.jhr')
        before = self.contents()
        self.run_cli(ok=False)
        self.assertEqual(before, self.contents())

    def test_complete_snapshot_discovers_hpt_dependencies_and_restores(self):
        helper = self.prepare_snapshot_source()
        destination = self.parent / 'snapshot'
        result = self.take_snapshot(destination, helper)
        value = node_backup.verify(destination, destination / 'snapshot.json', result['manifest_sha256'])
        names = {x['path'] for x in value['files']}
        self.assertTrue({'hpt.cfg', 'areas.cfg', 'spool/intab', 'spool/outtab', 'corrections.jsonl',
                         'tls/server-key.pem', 'session.key'} <= names)
        self.assertEqual(destination.stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.source / 'ffido/backups/special/referenced').read_bytes(), b'protected snapshot')
        self.assertFalse(any('backups' in Path(name).parts for name in names))
        # The archive, not the source tree, must be independently restorable.
        import tarfile
        with tarfile.open(destination / 'snapshot.tar.gz') as archive:
            archive.extractall(self.parent / 'archive-copy', filter='data')
        self.root = self.parent / 'archive-copy'
        self.manifest_path = self.root / 'snapshot.json'
        self.digest = result['manifest_sha256']
        self.run_cli('apply', self.run_cli()['plan_digest'])

    def test_copied_legacy_source_needs_external_provenance(self):
        helper = self.prepare_snapshot_source()
        original = self.source
        hashes = {str(p.relative_to(original)): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in original.rglob('*') if p.is_file()}
        legacy = self.parent / 'legacy-source'
        shutil.copytree(original, legacy)
        proof = self.parent / 'legacy-proof.json'
        raw = node_backup.dump(hashes)
        proof.write_bytes(raw)
        digest = hashlib.sha256(raw).hexdigest()
        maps = [(str(original), str(legacy))]
        def snapshot(name, *provenance):
            return node_backup.snapshot(legacy, self.parent / name, 'config.json', helper, maps, [],
                                        'maintenance.lock', *provenance)
        with self.assertRaises(node_backup.SnapshotError):
            snapshot('unverified-legacy')
        with self.assertRaises(node_backup.SnapshotError):
            snapshot('wrong-proof', proof, '0' * 64)
        result = snapshot('verified-legacy', proof, digest)
        value = node_backup.verify(self.parent / 'verified-legacy', self.parent / 'verified-legacy/snapshot.json',
                                   result['manifest_sha256'])
        self.assertEqual(value['legacy_provenance_sha256'], digest)

    def test_snapshot_materializes_only_contained_certbot_links(self):
        helper = self.prepare_snapshot_source()
        archive = self.source / 'ffido/acme/config/archive/example'
        archive.mkdir(parents=True)
        (archive / 'cert1.pem').write_bytes(b'fixture certificate')
        live = self.source / 'ffido/acme/config/live/example'
        live.mkdir(parents=True)
        (live / 'cert.pem').symlink_to('../../archive/example/cert1.pem')
        destination = self.parent / 'acme-snapshot'
        result = self.take_snapshot(destination, helper)
        node_backup.verify(destination, destination / 'snapshot.json', result['manifest_sha256'])
        materialized = destination / 'ffido/acme/config/live/example/cert.pem'
        self.assertFalse(materialized.is_symlink())
        self.assertEqual(materialized.read_bytes(), b'fixture certificate')
        (live / 'cert.pem').unlink()
        (live / 'cert.pem').symlink_to(self.source / 'session.key')
        with self.assertRaises(node_backup.SnapshotError):
            self.take_snapshot(self.parent / 'escaped-acme', helper)

    def test_snapshot_errors_never_leave_completion_manifest(self):
        helper = self.prepare_snapshot_source()
        for stage, patch in [('copy', mock.patch.object(node_backup.shutil, 'copyfileobj', side_effect=OSError('full'))),
                             ('archive', mock.patch.object(node_backup.tarfile, 'open', side_effect=OSError('full'))),
                             ('writer', mock.patch.object(node_backup, 'running_writers', side_effect=[False, True]))]:
            destination = self.parent / stage
            with self.subTest(stage=stage), patch, self.assertRaises((OSError, node_backup.SnapshotError)):
                self.take_snapshot(destination, helper)
            self.assertFalse((destination / 'snapshot.json').exists())
        (self.source / 'spool/intab').unlink()
        with self.assertRaises((OSError, node_backup.SnapshotError)):
            self.take_snapshot(self.parent / 'missing', helper)
        self.assertFalse((self.parent / 'missing/snapshot.json').exists())

    def test_incomplete_schema_is_rejected_without_migration_or_writes(self):
        pristine = (self.source / 'metadata.db').read_bytes()
        for statement in ['drop table bookmarks', 'alter table history rename column viewed_at to missing_time',
                          'drop table bookmarks; create view bookmarks as select user_id,user_id as conference_id,registered_at as added_at from users']:
            (self.source / 'metadata.db').write_bytes(pristine)
            with sqlite3.connect(self.source / 'metadata.db') as db:
                db.executescript(statement)
            db.close()
            self.refresh()
            shutil.copyfile(self.source / 'metadata.db', self.root / 'metadata.db')
            before = self.contents()
            self.run_cli(ok=False)
            self.assertEqual(before, self.contents())

    def test_incomplete_metadata_cannot_complete_a_snapshot(self):
        helper = self.prepare_snapshot_source()
        with sqlite3.connect(self.source / 'metadata.db') as db:
            db.execute('drop table bookmarks')
        db.close()
        destination = self.parent / 'incomplete-schema'
        with self.assertRaises(node_backup.SnapshotError):
            self.take_snapshot(destination, helper)
        self.assertFalse((destination / 'snapshot.json').exists())

    def test_missing_database_does_not_create_it(self):
        (self.root / 'metadata.db').unlink()
        before = self.contents()
        self.run_cli(ok=False)
        self.assertEqual(before, self.contents())


if __name__ == '__main__':
    ADMIN = str(Path(sys.argv.pop(1)).absolute())
    if len(sys.argv) > 1 and not sys.argv[1].startswith('-'):
        FAULT = str(Path(sys.argv.pop(1)).absolute())
    unittest.main()
