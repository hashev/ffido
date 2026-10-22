import base64
import contextlib
import fcntl
import io
import json
import os
import pathlib
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
import server
import common


class ManagedServerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.base = pathlib.Path(self.tmp.name); self.root = self.base/'install'; self.root.mkdir()
        self.key = Ed25519PrivateKey.generate()
        self.keys = {'test': base64.b64encode(self.key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()}
        self.old = self.release('1.0.0', 1001); self.new = self.release('2.0.0', 1002)
        (self.root/'current').symlink_to('releases/v1.0.0')
        self.database = self.base/'metadata.db'
        with contextlib.closing(sqlite3.connect(self.database)) as db: db.execute('PRAGMA user_version=9')
        pathlib.Path(str(self.database)+'.lock').touch()
        self.config = self.base/'config.json'; self.config.write_text(json.dumps({'database': {'metadata_path': 'metadata.db'}}))
        self.compatibility = patch.object(server, 'compatible', return_value=True); self.compatibility.start(); self.addCleanup(self.compatibility.stop)

    def release(self, version, number):
        identity = {'version': version, 'sha': 'a'*40, 'tag': 'v'+version, 'stable': True, 'build_number': number}
        compatibility = {'protocol_major': 1, 'client_protocol_min': 1, 'client_protocol_max': 1, 'server_protocol_min': 1, 'server_protocol_max': 1, 'state_schema_min': 9, 'state_schema_max': 9, 'config_format': 1, 'jam_format': 'JAM-1'}
        package = {**identity, 'component': 'server', 'id': 'server-linux-x86_64', 'platform': {'os': 'linux', 'architecture': 'x86_64'}, 'min_os': {'version': '24.04', 'distribution': 'ubuntu'}, 'compatibility': compatibility, 'file': 'server.tar.gz', 'sha256': 'b'*64, 'size': 3}
        data = {'schema_version': 1, 'channel': 'stable', 'update_sequence': number, 'identity': identity, 'packages': [package], 'compatibility': compatibility}
        release = self.root/'releases'/identity['tag']; (release/'.update').mkdir(parents=True)
        raw = (json.dumps(data)+'\n').encode()
        (release/'.update/manifest.json').write_bytes(raw)
        (release/'.update/manifest.sig').write_text(json.dumps({'key_id': 'test', 'algorithm': 'Ed25519', 'signature': base64.b64encode(self.key.sign(raw)).decode()}))
        (release/'BUILD.json').write_text(json.dumps(package))
        return release

    def test_atomic_upgrade_and_compatible_rollback_preserve_state(self):
        before = self.database.read_bytes()
        server.switch(self.root, 'releases/v2.0.0', self.config, self.keys)
        self.assertEqual(os.readlink(self.root/'current'), 'releases/v2.0.0')
        self.assertEqual(server.read(self.root/'.previous-update.json')['target'], 'releases/v1.0.0')
        with self.assertRaisesRegex(ValueError, 'downgrade'):
            server.switch(self.root, 'releases/v1.0.0', self.config, self.keys)
        server.switch(self.root, 'releases/v1.0.0', self.config, self.keys, rollback=True)
        self.assertEqual(self.database.read_bytes(), before)

    def test_running_instance_and_installation_lock_block_switch(self):
        for path in [self.root/'.running.lock', pathlib.Path(str(self.database)+'.lock')]:
            with path.open('a+b') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with self.assertRaisesRegex(ValueError, 'still running'):
                    server.switch(self.root, 'releases/v2.0.0', self.config, self.keys)
            self.assertEqual(os.readlink(self.root/'current'), 'releases/v1.0.0')

    def test_incompatible_schema_signature_and_escaped_target_are_rejected(self):
        with contextlib.closing(sqlite3.connect(self.database)) as db: db.execute('PRAGMA user_version=10')
        with self.assertRaisesRegex(ValueError, 'schema'):
            server.switch(self.root, 'releases/v2.0.0', self.config, self.keys)
        (self.new/'.update/manifest.sig').write_text('{}')
        with self.assertRaises(ValueError): server.switch(self.root, 'releases/v2.0.0', self.config, self.keys)
        for target in ['../outside', 'releases/../../outside', '/tmp/outside']:
            with self.assertRaises(ValueError): server.release_path(self.root, target)

    def test_pre_switch_failure_keeps_current_and_retry_succeeds(self):
        original = os.replace
        def fail(source, target):
            if pathlib.Path(target) == self.root/'current': raise OSError('interrupted')
            return original(source, target)
        with patch.object(server.os, 'replace', side_effect=fail), self.assertRaises(OSError):
            server.switch(self.root, 'releases/v2.0.0', self.config, self.keys)
        self.assertEqual(os.readlink(self.root/'current'), 'releases/v1.0.0')
        self.assertEqual(server.read(self.root/'.update-journal.json')['phase'], 'prepared')
        server.switch(self.root, 'releases/v2.0.0', self.config, self.keys)
        self.assertEqual(server.read(self.root/'.update-journal.json')['phase'], 'complete')

    def test_ordinary_layout_and_state_inside_release_are_rejected(self):
        (self.root/'current').unlink(); (self.root/'current').mkdir()
        with self.assertRaisesRegex(ValueError, 'managed layout'): server.current_target(self.root)
        bad = self.new/'config.json'; bad.write_text('{}')
        with self.assertRaisesRegex(ValueError, 'outside release'): server.config_state(bad, self.root)

    def test_version_does_not_load_runtime_configuration_or_update_dependencies(self):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(server.main(['version'], distribution=self.old), 0)
        self.assertEqual(json.loads(output.getvalue())['tag'], 'v1.0.0')

    def test_staging_validates_full_bundle_and_can_be_repeated(self):
        import hashlib
        import shutil
        import tarfile
        from unittest.mock import Mock
        shutil.rmtree(self.new)
        source = self.base/'bundle'; (source/'bin').mkdir(parents=True)
        (source/'lib').mkdir(); (source/'lib/runtime.so').write_bytes(b'runtime fixture')
        (source/'share/ffido').mkdir(parents=True)
        for name in ('fidoback', 'ffido-admin', 'ffido-hpt-auth', 'ffido-run-hpt', 'ffido-update'):
            path = source/'bin'/name; path.write_text('#!/bin/sh\nexit 0\n'); path.chmod(0o755)
        old_data = common.strict_json((self.old/'.update/manifest.json').read_bytes())
        data = json.loads(json.dumps(old_data))
        for value in [data['identity'], data['packages'][0]]:
            value.update(version='2.0.0', tag='v2.0.0', build_number=1002)
        data['update_sequence'] = 1002
        (source/'BUILD.json').write_text(json.dumps(data['packages'][0]))
        archive = self.base/'server.tar.gz'
        with tarfile.open(archive, 'w:gz') as output: output.add(source, arcname='ffido-bundle')
        data['packages'][0]['size'] = archive.stat().st_size
        data['packages'][0]['sha256'] = hashlib.sha256(archive.read_bytes()).hexdigest()
        raw = json.dumps(data).encode()
        signature = json.dumps({'key_id': 'test', 'algorithm': 'Ed25519', 'signature': base64.b64encode(self.key.sign(raw)).decode()}).encode()
        with patch.object(server, 'TRUSTED_KEYS', self.keys), patch.object(common, 'download', return_value=archive):
            self.assertEqual(server.stage(self.root, data, raw, signature), 'v2.0.0')
            self.assertEqual(server.stage(self.root, data, raw, signature), 'v2.0.0')
            self.assertTrue((self.new/'lib/runtime.so').is_file())
        self.assertEqual(server.read(self.root/'.selected-update.json')['target'], 'releases/v2.0.0')
        with patch.object(common, 'download', return_value=archive), patch.object(server.shutil, 'disk_usage', return_value=Mock(free=0)):
            with self.assertRaisesRegex(ValueError, 'free space'): server.stage(self.root, data, raw, signature)

    def test_operator_ownership_is_checked_before_download(self):
        with patch.object(server.os, 'geteuid', return_value=self.root.stat().st_uid+1), patch.object(server.discovery, 'releases') as remote:
            with self.assertRaisesRegex(ValueError, 'owned and writable'):
                server.main(['download', '--install-root', str(self.root)], distribution=self.old)
            remote.assert_not_called()

    def test_cli_apply_and_rollback_use_managed_layout(self):
        server.atomic_json(self.root/'.selected-update.json', {'target': 'releases/v2.0.0'})
        original = server.read
        def read(path): return self.keys if pathlib.Path(path).name == 'public_keys.json' else original(path)
        with patch.object(server, 'read', side_effect=read), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(server.main(['apply', '--install-root', str(self.root), '--config', str(self.config)], distribution=self.old), 0)
            self.assertEqual(os.readlink(self.root/'current'), 'releases/v2.0.0')
            self.assertEqual(server.main(['rollback', '--install-root', str(self.root), '--config', str(self.config)], distribution=self.new), 0)
            self.assertEqual(os.readlink(self.root/'current'), 'releases/v1.0.0')
