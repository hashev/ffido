import json
import base64
import os
from pathlib import Path
import sys
import tempfile
import unittest
import sqlite3
import subprocess
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import deployment_backup
import pair_host


class PairHostTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.host = pair_host.Host.__new__(pair_host.Host)
        self.host.state = self.root
        self.host.image_bytes = 20

    def test_switch_and_rollback_preserve_worker_identity_owner_and_permissions(self):
        identity = self.root/'identity.json'
        original = b'{"tag":"original"}\n'
        identity.write_bytes(original)
        identity.chmod(0o640)
        pins = self.root/'pins.json'
        pins.write_bytes(b'{"services":{}}')
        pins.chmod(0o640)
        self.root.chmod(0o755)
        different_user = os.geteuid() == 0 and sys.platform == 'linux'
        if different_user:
            os.chown(identity, 1000, 1000)
            os.chown(pins, 1000, 1000)
        before = identity.stat()
        self.host.plan = {'identity_file': str(identity)}
        self.host.services = {'backend': 'backend', 'tosser': 'tosser'}
        self.host.gated = self.root/'gated.json'
        self.host.compose = Mock()
        self.host.compose.override = pins
        self.host.compose.command.return_value = json.dumps({'name': 'qa',
            'services': {'backend': {}, 'tosser': {}}})
        self.host.write_images = Mock()
        self.host.switch({'images': {'backend': 'new-backend', 'tosser': 'new-worker'},
                          'build': {'tag': 'new'}})
        def assert_readable():
            for path in (identity, pins):
                after = path.stat()
                self.assertEqual((after.st_uid, after.st_gid, after.st_mode & 0o777),
                                 (before.st_uid, before.st_gid, 0o640))
                if different_user:
                    subprocess.run([sys.executable, '-c',
                                    'import json,sys;json.load(open(sys.argv[1]))', str(path)],
                                   user=1000, group=1000, check=True, capture_output=True)
        assert_readable()
        source_build = {'tag': 'original'}
        baseline = {'source': {role: {'image_id': role, 'build': source_build}
                               for role in self.host.services}, 'override': base64.b64encode(pins.read_bytes()).decode(),
                    'identity': base64.b64encode(original).decode(), 'provenance': None}
        self.host.image_build = lambda image: ({'Id': image}, source_build)
        self.host.restore_pair(baseline)
        self.assertEqual(identity.read_bytes(), original)
        self.assertEqual(pins.read_bytes(), b'{"services":{}}')
        assert_readable()

    def test_invalid_build_mutable_base_and_failed_worker_never_stop_source(self):
        config = self.root/'config.json'
        config.write_text(json.dumps({'database': {'metadata_path': str(self.root/'metadata.db')}}))
        with sqlite3.connect(self.root/'metadata.db') as db:
            db.execute('pragma user_version=12')
        recipe = self.root/'Dockerfile'
        recipe.write_text('FROM ${FFIDO_IMAGE} AS ffido\nFROM ${HPT_IMAGE}\n')
        compat = {'protocol_major': 1, 'config_format': 1, 'jam_format': 'JAM-1',
                  'state_schema_min': 9, 'state_schema_max': 12}
        identity = {'version': '1.0.28', 'tag': 'v1.0.28', 'build_number': 1066,
                    'stable': True, 'sha': 'a'*40}
        manifest = {'identity': identity, 'compatibility': compat,
                    'container': {'image': 'docker.io/hashev/ffido', 'digest': 'sha256:'+'b'*64}}
        build = {**identity, 'compatibility': compat}
        info = {'Id': 'sha256:'+'c'*64, 'Config': {'Labels': {
            'org.opencontainers.image.version': identity['tag'],
            'org.opencontainers.image.revision': identity['sha']}}}
        self.host.root = self.root
        self.host.backup_options = {'config': 'config.json', 'mappings': []}
        self.host.actual_source = Mock(return_value={})
        for failure in ('build', 'mutable-base', 'worker'):
            with self.subTest(failure=failure):
                self.host.compose = Mock()
                self.host.compose.run.return_value = json.dumps([{'Id': 'sha256:'+'d'*64}])
                if failure == 'worker':
                    def run(*args):
                        if args[:2] == ('docker', 'build'):
                            raise ValueError('Worker build failed')
                        return json.dumps([{'Id': 'sha256:'+'d'*64}])
                    self.host.compose.run.side_effect = run
                self.host.image_build = Mock(return_value=(info, {**build,
                    'sha': 'e'*40} if failure == 'build' else build))
                self.host.plan = {'source': {}, 'files': {}, 'worker': {
                    'context': str(self.root), 'dockerfile': 'Dockerfile',
                    'files': {'Dockerfile': pair_host.node.file_hash(self.root, 'Dockerfile')[0]},
                    'hpt_image': 'latest' if failure == 'mutable-base' else 'sha256:'+'d'*64,
                    'hpt_image_id': 'sha256:'+'d'*64}}
                expected = {'build': 'BUILD differs', 'mutable-base': 'Mutable HPT base',
                            'worker': 'Worker build failed'}[failure]
                with self.assertRaisesRegex((ValueError, pair_host.node.SnapshotError), expected):
                    self.host.prepare(manifest)
                self.host.compose.command.assert_not_called()

    def test_space_failure_keeps_full_report_without_removing_anything(self):
        sentinel = self.root/'rollback-image'; sentinel.write_bytes(b'keep')
        usage = type('Usage', (), {'free': 1})()
        with patch.object(deployment_backup.shutil, 'disk_usage', return_value=usage):
            with self.assertRaises(deployment_backup.BudgetError):
                self.host.budget_report(30)
        value = json.loads((self.root/'space-budget.json').read_text())
        self.assertEqual(value['source_bytes'], 30)
        self.assertEqual(value['image_bytes'], 20)
        self.assertGreater(value['deficit_bytes'], 0)
        self.assertEqual(sentinel.read_bytes(), b'keep')

    def test_probe_diagnostics_are_private_and_not_in_public_error(self):
        secret = 'test-session-must-not-leak'
        self.host.plan = {'probes': {'private': [[sys.executable, '-c',
                           "print('"+secret+"');raise SystemExit(1)"]]}}
        with self.assertRaises(Exception) as error:
            self.host.probe('private')
        self.assertNotIn(secret, str(error.exception))
        path = self.root/'probe.private.log'
        self.assertIn(secret, path.read_text())
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_writer_stop_uses_sigint_for_jamnntpd_and_leaves_other_services(self):
        calls = []
        class Compose:
            def command(self, *args):
                calls.append(args)
                return 'a'*64 if args[:3] == ('ps', '-a', '-q') else ''
            def run(self, *args):
                calls.append(args)
                return json.dumps([{'State': {'Running': True}}])
        self.host.compose = Compose()
        self.host.writers = ['backend', 'tosser', 'jamnntpd']
        self.host.plan = {'jamnntpd_service': 'jamnntpd'}
        self.host.quiesce()
        self.assertIn(('docker', 'kill', '--signal=SIGINT', 'a'*64), calls)
        self.assertNotIn(('stop', 'jamnntpd'), calls)
        self.assertFalse(any('unrelated' in call for call in calls))

    def test_updater_inventory_adds_control_files_without_recursive_snapshots(self):
        state = self.root/'state'; state.mkdir()
        (state/'pair-operation.json').write_text('{}')
        (state/'snapshots').mkdir(); (state/'snapshots/private').write_bytes(b'not a control file')
        self.host.state = state
        self.host.plan = {'components': {'updater': {'root': str(self.root),
                                                   'required': ['state/pair-operation.json'],
                                                   'includes': ['state/pair-operation.json']}}}
        value = self.host.component_profile()['updater']['includes']
        self.assertEqual(value, ['state/pair-operation.json'])
