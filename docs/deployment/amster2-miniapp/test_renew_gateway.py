import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('renew_gateway', Path(__file__).with_name('renew_gateway.py'))
renew = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renew)


class RenewalTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.base = self.root / 'main'
        (self.base / 'certs').mkdir(parents=True)
        (self.base / 'logs').mkdir()
        self.source = self.root / 'source'
        self.source.mkdir()
        self.write_pair(self.source, b'new')
        self.addCleanup(patch.stopall)
        patch.object(renew, 'BASE', self.base).start()
        patch.object(renew.os, 'chown').start()

    def write_pair(self, path, value):
        path.mkdir(parents=True, exist_ok=True)
        for name in renew.NAMES:
            (path / name).write_bytes(value + name.encode())

    def test_stopped_gateway_never_started(self):
        with patch.object(renew, 'validate_pair'), patch.object(renew, 'gateway_running', return_value=False), patch.object(renew, 'command') as cmd:
            renew.deploy(self.source)
        cmd.assert_not_called()
        self.assertTrue(renew.same_pair(self.source, self.base / 'certs/public'))
        self.assertEqual((self.base / 'certs/public/privkey.pem').stat().st_mode & 0o777, 0o640)

    def test_private_umask_preserves_gateway_directory_access(self):
        public = self.base / 'certs/public'
        previous_umask = os.umask(0o077)
        try:
            renew.install_pair(self.source, public)
        finally:
            os.umask(previous_umask)
        self.assertEqual(public.stat().st_mode & 0o777, 0o750)
        self.assertEqual((public / 'privkey.pem').stat().st_mode & 0o777, 0o640)

    def test_unchanged_pair_no_container_action(self):
        self.write_pair(self.base / 'certs/public', b'new')
        with patch.object(renew, 'validate_pair'), patch.object(renew, 'gateway_running') as running:
            renew.deploy(self.source)
        running.assert_not_called()

    def test_invalid_pair_does_not_touch_public(self):
        self.write_pair(self.base / 'certs/public', b'old')
        before = (self.base / 'certs/public/privkey.pem').read_bytes()
        with patch.object(renew, 'validate_pair', side_effect=RuntimeError), patch.object(renew, 'gateway_running') as running:
            with self.assertRaises(RuntimeError):
                renew.deploy(self.source)
        running.assert_not_called()
        self.assertEqual((self.base / 'certs/public/privkey.pem').read_bytes(), before)

    def test_running_gateway_reloaded_and_probed(self):
        self.write_pair(self.base / 'certs/public', b'old')
        with patch.object(renew, 'validate_pair'), patch.object(renew, 'gateway_running', return_value=True), patch.object(renew, 'command') as cmd, patch.object(renew, 'probe') as probe:
            renew.deploy(self.source)
        self.assertEqual([c.args[0][:2] for c in cmd.call_args_list], [['docker', 'stop'], ['docker', 'start']])
        probe.assert_called_once()
        self.assertTrue((self.base / 'certs/previous/privkey.pem').is_file())

    def test_failed_reload_restores_previous_pair(self):
        public = self.base / 'certs/public'
        self.write_pair(public, b'old')
        old = (public / 'privkey.pem').read_bytes()
        with patch.object(renew, 'validate_pair'), patch.object(renew, 'gateway_running', return_value=True), patch.object(renew, 'command'), patch.object(renew.time, 'sleep'), patch.object(renew, 'probe', side_effect=[RuntimeError()] * 10 + [None]):
            with self.assertRaises(RuntimeError):
                renew.deploy(self.source)
        self.assertEqual((public / 'privkey.pem').read_bytes(), old)
        self.assertEqual((self.base / 'certs/previous/privkey.pem').read_bytes(), old)

    def test_dry_run_never_deploys(self):
        lock = self.root / 'lock'
        lock.touch()
        with patch.object(renew, 'LOCK', lock), patch.object(renew.os, 'geteuid', return_value=0), patch('sys.argv', ['renew_gateway.py', 'dry-run']), patch.object(renew, 'command') as cmd, patch.object(renew, 'deploy') as deploy:
            self.assertEqual(renew.main(), 0)
        self.assertIn('--dry-run', cmd.call_args.args[0])
        deploy.assert_not_called()

    def test_busy_maintenance_does_not_run_certbot(self):
        lock = self.root / 'lock'
        lock.touch()
        with patch.object(renew, 'LOCK', lock), patch.object(renew.os, 'geteuid', return_value=0), patch('sys.argv', ['renew_gateway.py', 'renew']), patch.object(renew.fcntl, 'flock', side_effect=BlockingIOError), patch.object(renew, 'command') as cmd:
            self.assertEqual(renew.main(), 75)
        cmd.assert_not_called()

    def test_key_mismatch_rejected_before_envoy(self):
        with patch.object(renew, 'command', side_effect=[b'', b'public-one', b'public-two']) as cmd:
            with self.assertRaisesRegex(RuntimeError, 'mismatch'):
                renew.validate_pair(self.source)
        self.assertFalse(any(c.args[0][0] == 'docker' for c in cmd.call_args_list))


if __name__ == '__main__':
    unittest.main()
