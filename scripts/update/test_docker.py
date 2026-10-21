import importlib.util
import json
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('docker_update', pathlib.Path(__file__).with_name('ffido-docker-update.py'))
updater = importlib.util.module_from_spec(spec); spec.loader.exec_module(updater)


class FakeCompose:
    def __init__(self, root):
        self.state = root; self.override = root/'image-override.json'; self.service = 'ffido'
        self.calls = []; self.schema_value = 9; self.healthy = True
    def run(self, *args):
        self.calls.append(args)
        if args[:3] == ('docker', 'image', 'inspect'):
            return json.dumps([{'Architecture': 'amd64', 'Os': 'linux', 'Config': {'Labels': {'org.opencontainers.image.revision': 'a'*40, 'org.opencontainers.image.version': 'v2.0.0'}}}])
        return ''
    def command(self, *args): return self.run(*args)
    def schema(self, config): self.calls.append(('schema', config)); return self.schema_value
    def ready(self, digest):
        self.calls.append(('ready', digest))
        if not self.healthy: raise ValueError('not ready')


class DockerUpdateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name); self.compose = FakeCompose(self.root)
        self.manifest = {'identity': {'sha': 'a'*40, 'tag': 'v2.0.0'}, 'compatibility': {'protocol_major': 1, 'config_format': 1, 'jam_format': 'JAM-1', 'state_schema_min': 9, 'state_schema_max': 9}, 'container': {'image': 'docker.io/hashev/ffido', 'digest': 'sha256:'+'a'*64}}
    def apply(self): updater.apply(self.compose, self.manifest, b'manifest', b'signature', '/etc/ffido/config.json', 'hashev/ffido@sha256:'+'b'*64)
    def test_only_image_is_overridden_and_ready_is_required(self):
        original = self.root/'compose.yaml'; original.write_text('operator mounts and UID')
        self.apply()
        self.assertEqual(original.read_text(), 'operator mounts and UID')
        self.assertEqual(json.loads(self.compose.override.read_text()), {'services': {'ffido': {'image': 'docker.io/hashev/ffido@sha256:'+'a'*64}}})
        self.assertIn(('up', '-d', '--no-deps', 'ffido'), self.compose.calls)
        self.assertEqual(json.loads((self.root/'operation.json').read_text())['phase'], 'complete')
    def test_incompatible_state_restarts_same_service_without_switching(self):
        self.compose.schema_value = 10
        with self.assertRaisesRegex(ValueError, 'incompatible'): self.apply()
        self.assertIn(('start', 'ffido'), self.compose.calls)
        self.assertFalse(self.compose.override.exists())
        self.assertNotIn(('up', '-d', '--no-deps', 'ffido'), self.compose.calls)
    def test_readiness_failure_preserves_digest_and_pending_manifest(self):
        self.compose.healthy = False
        with self.assertRaisesRegex(ValueError, 'not ready'): self.apply()
        operation = json.loads((self.root/'operation.json').read_text())
        self.assertEqual(operation['phase'], 'prepared')
        self.assertEqual(operation['previous_digest'], 'hashev/ffido@sha256:'+'b'*64)
        self.assertEqual((self.root/'selected-manifest.json').read_bytes(), b'manifest')
    def test_wrong_digest_or_unknown_migration_does_not_stop_service(self):
        self.manifest['container']['digest'] = 'latest'
        with self.assertRaises(ValueError): self.apply()
        self.assertEqual(self.compose.calls, [])
        self.manifest['compatibility']['config_format'] = 2
        with self.assertRaises(ValueError): self.apply()
        self.assertEqual(self.compose.calls, [])

    def test_healthy_process_is_not_inferred_from_running_status(self):
        from unittest.mock import patch
        real = updater.Compose.__new__(updater.Compose)
        real.service = 'ffido'
        real.command = lambda *args: 'a'*64
        real.run = lambda *args: json.dumps([{'State': {'Status': 'running', 'Health': {'Status': 'starting'}}}])
        with patch.object(updater.time, 'monotonic', side_effect=[0, 1, 100]), patch.object(updater.time, 'sleep'):
            with self.assertRaisesRegex(ValueError, 'not ready'): real.ready('sha256:'+'a'*64)

    def test_interrupted_operation_reverifies_saved_manifest_before_resuming(self):
        import contextlib
        import io
        from unittest.mock import patch
        compose = self.compose
        installed = {'version': '1.0.0', 'tag': 'v1.0.0', 'sha': 'a'*40, 'stable': True, 'build_number': 1001}
        compose.inspect = lambda: (installed, 'hashev/ffido@sha256:'+'b'*64, {'Mounts': [{'Destination': value} for value in ['/etc/ffido/config.json', '/etc/ffido/tls', '/var/lib/ffido', '/srv/fido']]})
        original = compose.command
        def command(*args):
            if args == ('config', '--format', 'json'):
                return json.dumps({'services': {'ffido': {'healthcheck': {'test': ['CMD', 'fidoback', '--check-ready', '127.0.0.1:8080', '/etc/ffido/tls/ca.pem', 'fido.test']}}}})
            return original(*args)
        compose.command = command
        reference = 'docker.io/hashev/ffido@sha256:'+'a'*64
        (self.root/'operation.json').write_text(json.dumps({'phase': 'prepared', 'selected': reference, 'previous_digest': 'hashev/ffido@sha256:'+'b'*64}))
        (self.root/'selected-manifest.json').write_bytes(b'fixture')
        (self.root/'selected-manifest.sig').write_bytes(b'signature')
        args = ['apply', '--compose-file', str(self.root/'compose.yaml'), '--service', 'ffido', '--state-dir', str(self.root)]
        keys = {'qa': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='}
        (self.root/'public_keys.json').write_text(json.dumps(keys))
        with patch.object(updater, '__file__', str(self.root/'ffido-docker-update.py')), patch.object(updater, 'Compose', return_value=compose), patch.object(updater.common, 'verify_manifest', side_effect=ValueError('bad signature')):
            with self.assertRaisesRegex(ValueError, 'bad signature'): updater.main(args)
        self.assertEqual(compose.calls, [])
        with patch.object(updater, '__file__', str(self.root/'ffido-docker-update.py')), patch.object(updater, 'Compose', return_value=compose), patch.object(updater.common, 'verify_manifest', return_value=self.manifest) as verify, patch.object(updater.discovery, 'releases') as remote, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(updater.main(args), 0)
            verify.assert_called_once_with(b'fixture', b'signature', keys)
            remote.assert_not_called()
        self.assertEqual(json.loads((self.root/'operation.json').read_text())['phase'], 'complete')

    def test_signed_inputs_exist_before_stop_and_prepared_journal(self):
        from unittest.mock import patch
        original = self.compose.command
        def command(*args):
            if args == ('stop', 'ffido'):
                self.assertEqual((self.root/'selected-manifest.json').read_bytes(), b'manifest')
                self.assertEqual((self.root/'selected-manifest.sig').read_bytes(), b'signature')
                self.assertFalse((self.root/'operation.json').exists())
            return original(*args)
        with patch.object(self.compose, 'command', side_effect=command): self.apply()

    def test_metadata_write_failure_does_not_stop_server(self):
        from unittest.mock import patch
        with patch.object(pathlib.Path, 'write_bytes', side_effect=OSError('disk full')):
            with self.assertRaises(OSError): self.apply()
        self.assertNotIn(('stop', 'ffido'), self.compose.calls)
        self.assertFalse((self.root/'operation.json').exists())

    def test_journal_write_failure_restarts_previous_server(self):
        from unittest.mock import patch
        with patch.object(updater, 'atomic_json', side_effect=OSError('disk full')):
            with self.assertRaises(OSError): self.apply()
        self.assertIn(('start', 'ffido'), self.compose.calls)
        self.assertNotIn(('up', '-d', '--no-deps', 'ffido'), self.compose.calls)
