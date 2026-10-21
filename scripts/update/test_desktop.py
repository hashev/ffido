import base64
import hashlib
import io
import json
import os
import pathlib
import shutil
import sys
import tarfile
import tempfile
import unittest
import zipfile
from unittest.mock import Mock, patch
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
import desktop


class DesktopTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.base = pathlib.Path(self.tmp.name).resolve(); self.root = self.base/'FFIDO'; self.root.mkdir()
        self.exe = 'fido.exe' if os.name == 'nt' else 'fido'
        self.helper = 'ffido-updater.exe' if os.name == 'nt' else 'ffido-updater'
        self.os_name = 'windows' if os.name == 'nt' else 'linux'
        self.runtime = 'flutter_windows.dll' if os.name == 'nt' else 'lib/libflutter_linux_gtk.so'
        self.asset = pathlib.Path('data/flutter_assets/assets/updates/identity.json')
        self.key = Ed25519PrivateKey.generate()
        self.keys = {'test': base64.b64encode(self.key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()}
        (self.base/'public_keys.json').write_text(json.dumps(self.keys))
        self.old = self.identity('1.0.0', 1001); self.new = self.identity('2.0.0', 1002)
        self.bundle(self.root, self.old)
        self.source = self.base/'new'; self.bundle(self.source, self.new)
        self.stage = self.base/'downloads'; self.stage.mkdir()
        self.archive = self.stage/('client.zip' if os.name == 'nt' else 'client.tar.gz')
        self.record()
        self.private_state = self.base/'profiles'; self.private_state.write_bytes(b'profile and session fixture')

    def identity(self, version, number):
        return {'version': version, 'build_number': number, 'tag': 'v'+version, 'stable': True, 'sha': 'a'*40}

    def bundle(self, root, identity):
        root.mkdir(exist_ok=True)
        (root/self.asset).parent.mkdir(parents=True)
        (root/self.asset).write_text(json.dumps(identity))
        for name in [self.exe, self.helper, self.runtime]:
            path = root/name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(b'binary fixture'); path.chmod(0o755)
        (root/'BUILD.json').write_text(json.dumps({**identity, 'component': 'client', 'platform': {'os': self.os_name, 'architecture': 'x86_64'}}))

    def record(self):
        compatibility = {'protocol_major': 1, 'client_protocol_min': 1, 'client_protocol_max': 1, 'server_protocol_min': 1, 'server_protocol_max': 1, 'state_schema_min': 9, 'state_schema_max': 9, 'config_format': 1, 'jam_format': 'JAM-1'}
        if os.name == 'nt':
            with zipfile.ZipFile(self.archive, 'w') as archive:
                for path in self.source.rglob('*'):
                    if path.is_file(): archive.write(path, path.relative_to(self.source))
        else:
            with tarfile.open(self.archive, 'w:gz') as archive: archive.add(self.source, arcname='ffido')
        package = {**self.new, 'id': 'client-'+self.os_name+'-x86_64', 'component': 'client', 'platform': {'os': self.os_name, 'architecture': 'x86_64'}, 'min_os': {'version': '10.0', 'build': 10240} if os.name == 'nt' else {'version': '24.04', 'distribution': 'ubuntu'}, 'compatibility': compatibility, 'size': self.archive.stat().st_size, 'file': self.archive.name, 'sha256': hashlib.sha256(self.archive.read_bytes()).hexdigest()}
        manifest = {'schema_version': 1, 'channel': 'stable', 'identity': self.new, 'update_sequence': 1002, 'packages': [package], 'compatibility': compatibility}
        raw = json.dumps(manifest).encode(); (self.stage/'release-manifest.json').write_bytes(raw)
        (self.stage/'release-manifest.sig').write_text(json.dumps({'algorithm': 'Ed25519', 'key_id': 'test', 'signature': base64.b64encode(self.key.sign(raw)).decode()}))

    def test_full_bundle_switch_preserves_external_state_and_previous_bundle(self):
        desktop.apply(self.root, self.archive, self.keys, self.exe)
        self.assertEqual(json.loads((self.root/self.asset).read_text())['tag'], 'v2.0.0')
        self.assertEqual(json.loads((self.base/'FFIDO.previous'/self.asset).read_text())['tag'], 'v1.0.0')
        self.assertEqual(self.private_state.read_bytes(), b'profile and session fixture')
        self.assertTrue((self.root/self.runtime).is_file())
        with self.assertRaisesRegex(ValueError, 'downgrade'): desktop.apply(self.root, self.archive, self.keys, self.exe)

    def test_failure_between_renames_restores_whole_previous_bundle(self):
        original = os.rename
        def fail(source, target):
            if pathlib.Path(target) == self.root and pathlib.Path(source).name != 'FFIDO.previous': raise OSError('switch interrupted')
            return original(source, target)
        with patch.object(desktop.os, 'rename', side_effect=fail), self.assertRaisesRegex(OSError, 'interrupted'):
            desktop.apply(self.root, self.archive, self.keys, self.exe)
        self.assertEqual(json.loads((self.root/self.asset).read_text())['tag'], 'v1.0.0')
        desktop.apply(self.root, self.archive, self.keys, self.exe)
        self.assertEqual(json.loads((self.root/self.asset).read_text())['tag'], 'v2.0.0')

    def test_interrupted_switch_recovers_previous_bundle_and_allows_retry(self):
        for switched in [False, True]:
            with self.subTest(switched=switched):
                backup = self.base/'FFIDO.previous'
                os.rename(self.root, backup)
                if switched: shutil.copytree(self.source, self.root)
                desktop.atomic_record(self.base/'.FFIDO-update.json', {
                    'phase': 'switched' if switched else 'prepared',
                    'root': str(self.root), 'backup': str(backup),
                    'before_tag': 'v1.0.0', 'tag': 'v2.0.0',
                })
                desktop.recover(self.root)
                desktop.recover(self.root)
                self.assertEqual(json.loads((self.root/self.asset).read_text())['tag'], 'v1.0.0')
                self.assertFalse(backup.exists())
                self.assertEqual(self.private_state.read_bytes(), b'profile and session fixture')
        desktop.apply(self.root, self.archive, self.keys, self.exe)
        self.assertEqual(json.loads((self.root/self.asset).read_text())['tag'], 'v2.0.0')

    def test_recovery_does_not_replace_unrelated_current_bundle(self):
        backup = self.base/'FFIDO.previous'; shutil.copytree(self.root, backup)
        desktop.atomic_record(self.base/'.FFIDO-update.json', {
            'phase': 'switched', 'root': str(self.root), 'backup': str(backup),
            'before_tag': 'v1.0.0', 'tag': 'v2.0.0',
        })
        with self.assertRaisesRegex(ValueError, 'unrelated'):
            desktop.recover(self.root)
        self.assertEqual(json.loads((self.root/self.asset).read_text())['tag'], 'v1.0.0')
        self.assertTrue(backup.exists())

    def test_preflight_checks_permissions_without_install_or_relaunch(self):
        import contextlib
        for writable in [True, False]:
            argv = ['desktop', '--root', str(self.root), '--package', str(self.archive), '--executable', self.exe, '--preflight']
            with patch.object(sys, 'argv', argv), patch.object(desktop.os, 'access', return_value=writable), patch.object(desktop, 'run_install') as install, contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(desktop.main(), 0 if writable else 1)
                install.assert_not_called()
            self.assertEqual(json.loads((self.root/self.asset).read_text())['tag'], 'v1.0.0')

    def test_second_updater_cannot_enter_an_active_operation(self):
        import contextlib
        import subprocess
        code = """import os,sys
f=open(sys.argv[1],'a+b');f.seek(0)
if os.name=='nt':
 import msvcrt;msvcrt.locking(f.fileno(),msvcrt.LK_NBLCK,1)
else:
 import fcntl;fcntl.lockf(f.fileno(),fcntl.LOCK_EX)
print('locked',flush=True)
sys.stdin.read(1)
"""
        child = subprocess.Popen([sys.executable, '-c', code, str(self.base/'.FFIDO-update.lock')], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.assertEqual(child.stdout.readline().strip(), 'locked')
            argv = ['desktop', '--root', str(self.root), '--package', str(self.archive), '--executable', self.exe]
            with patch.object(sys, 'argv', argv), patch.object(desktop, 'run_install') as install, contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(desktop.main(), 1)
                install.assert_not_called()
        finally: child.communicate('x', timeout=5)

    def test_disk_full_during_staging_preserves_installation_and_allows_retry(self):
        import errno
        with patch.object(desktop.common, 'safe_extract', side_effect=OSError(errno.ENOSPC, 'No space left on device')):
            with self.assertRaises(OSError) as failure:
                desktop.apply(self.root, self.archive, self.keys, self.exe)
            self.assertEqual(failure.exception.errno, errno.ENOSPC)
        self.assertEqual(json.loads((self.root/self.asset).read_text())['tag'], 'v1.0.0')
        self.assertEqual(self.private_state.read_bytes(), b'profile and session fixture')
        self.assertFalse(list(self.base.glob('.ffido-stage-*')))
        self.assertFalse((self.base/'FFIDO.previous').exists())
        desktop.apply(self.root, self.archive, self.keys, self.exe)
        self.assertEqual(json.loads((self.root/self.asset).read_text())['tag'], 'v2.0.0')

    def test_read_only_installation_parent_is_rejected_without_switch(self):
        with patch.object(desktop.os, 'access', return_value=False):
            with self.assertRaisesRegex(ValueError, 'not writable'):
                desktop.apply(self.root, self.archive, self.keys, self.exe)
        self.assertEqual(json.loads((self.root/self.asset).read_text())['tag'], 'v1.0.0')
        self.assertFalse((self.base/'FFIDO.previous').exists())

    def test_foreign_previous_directory_and_incomplete_bundle_are_preserved(self):
        backup = self.base/'FFIDO.previous'; backup.mkdir(); (backup/'user-file').write_text('keep')
        with self.assertRaisesRegex(ValueError, 'confirmed'): desktop.apply(self.root, self.archive, self.keys, self.exe)
        self.assertEqual((backup/'user-file').read_text(), 'keep')
        (self.source/self.runtime).unlink(); self.record()
        with self.assertRaisesRegex(ValueError, 'Incomplete'): desktop.apply(self.root, self.archive, self.keys, self.exe)
        self.assertEqual(json.loads((self.root/self.asset).read_text())['tag'], 'v1.0.0')

    def test_bad_signature_and_package_are_rejected_before_switch(self):
        original = (self.stage/'release-manifest.sig').read_bytes()
        (self.stage/'release-manifest.sig').write_text('{}')
        with self.assertRaises(ValueError): desktop.apply(self.root, self.archive, self.keys, self.exe)
        (self.stage/'release-manifest.sig').write_bytes(original)
        self.archive.write_bytes(b'corrupted')
        with self.assertRaises(ValueError): desktop.apply(self.root, self.archive, self.keys, self.exe)
        self.assertEqual(json.loads((self.root/self.asset).read_text())['tag'], 'v1.0.0')

    def test_new_client_start_failure_rolls_back_and_restarts_old_client(self):
        argv = ['desktop', '--root', str(self.root), '--package', str(self.archive), '--executable', self.exe]
        with patch.object(sys, 'argv', argv), patch.object(sys, '_MEIPASS', str(self.base), create=True), patch.object(desktop.subprocess, 'Popen', side_effect=[OSError('launch failed'), Mock()]) as launch:
            self.assertEqual(desktop.main(), 1)
        self.assertEqual(launch.call_count, 2)
        self.assertEqual(json.loads((self.root/self.asset).read_text())['tag'], 'v1.0.0')
        self.assertTrue((self.root/'.ffido-update-error').exists())

    def test_running_process_record_lock_blocks_update(self):
        import subprocess
        code = '''import os,sys
f=open(sys.argv[1],'a+b');f.seek(0)
if os.name=='nt':
 import msvcrt;msvcrt.locking(f.fileno(),msvcrt.LK_NBLCK,1)
else:
 import fcntl;fcntl.lockf(f.fileno(),fcntl.LOCK_SH)
print('locked',flush=True)
sys.stdin.read(1)
'''
        child = subprocess.Popen([sys.executable, '-c', code, str(self.root.parent/('.'+self.root.name+'-running.lock'))], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.assertEqual(child.stdout.readline().strip(), 'locked')
            with self.assertRaisesRegex(ValueError, 'Close all'):
                with desktop.install_lock(self.root, timeout=0): self.fail('Acquired a live process lock')
        finally:
            child.communicate('x', timeout=5)

    def test_failed_start_never_restores_over_a_new_running_window(self):
        import argparse
        import contextlib
        original_lock = desktop.install_lock
        calls = 0
        @contextlib.contextmanager
        def lock(*args, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 2: raise ValueError('Close all FFIDO windows before updating')
            with original_lock(*args, **kwargs): yield
        args = argparse.Namespace(root=self.root, package=self.archive, executable=self.exe)
        with patch.object(sys, '_MEIPASS', str(self.base), create=True), patch.object(desktop, 'install_lock', side_effect=lock), patch.object(desktop.subprocess, 'Popen', side_effect=OSError('launch failed')) as launch, contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(desktop.run_install(args), 1)
        self.assertEqual(launch.call_count, 1)
        self.assertIn('Закройте все окна', (self.root/'.ffido-update-error').read_text())
        self.assertEqual(json.loads((self.root/self.asset).read_text())['tag'], 'v2.0.0')
        self.assertEqual(json.loads((self.base/'FFIDO.previous'/self.asset).read_text())['tag'], 'v1.0.0')
