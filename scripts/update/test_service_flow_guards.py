"""Guard private supervisor QA against false systemd claims and leaked units."""
import argparse
import pathlib
import subprocess
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch
import test_service_flow as flow


class ServiceFlowGuardsTest(unittest.TestCase):
    def args(self, manager='systemd', user='ffido-qa'):
        return argparse.Namespace(manager=manager, service_user=user)

    def test_manager_must_match_native_platform(self):
        with patch.object(flow.sys, 'platform', 'darwin'), patch.object(flow.test_server_flow, 'run') as prepare:
            with self.assertRaisesRegex(RuntimeError, 'native service manager'):
                flow.run(self.args())
            prepare.assert_not_called()

    def test_systemd_service_cannot_default_to_root(self):
        with patch.object(flow.sys, 'platform', 'linux'), patch.object(flow.test_server_flow, 'run') as prepare:
            for user in (None, 'root'):
                with self.assertRaisesRegex(RuntimeError, 'unprivileged'):
                    flow.run(self.args(user=user))
            prepare.assert_not_called()

    def test_systemd_cli_without_real_pid_one_is_rejected_before_writes(self):
        with patch.object(flow.sys, 'platform', 'linux'), \
             patch.object(pathlib.Path, 'read_text', return_value='tini\n'), \
             patch.object(flow.test_server_flow, 'run') as prepare:
            with self.assertRaisesRegex(RuntimeError, 'real systemd as PID 1'):
                flow.run(self.args())
            prepare.assert_not_called()

    def test_failed_timer_validation_removes_its_private_unit(self):
        with tempfile.TemporaryDirectory() as directory:
            unit_root = pathlib.Path(directory)
            def fail(*cmd, **kwargs):
                raise RuntimeError('invalid unit fixture')
            with patch.object(flow, 'pathlib', SimpleNamespace(Path=lambda value: unit_root)):
                with self.assertRaisesRegex(RuntimeError, 'invalid unit fixture'):
                    flow.HptTimer(SimpleNamespace(label='private-qa'), fail)
            self.assertEqual(list(unit_root.iterdir()), [])

    def test_cleanup_stops_even_failed_unit_and_removes_definition(self):
        with tempfile.TemporaryDirectory() as directory:
            service = object.__new__(flow.Service)
            service.manager = 'systemd'; service.label = 'private-qa'
            service.path = pathlib.Path(directory)/'private-qa.service'
            service.path.write_text('invalid private unit')
            calls = []
            def invoke(*cmd, **kwargs):
                calls.append(cmd)
                return subprocess.CompletedProcess(cmd, 0, '', '')
            service.invoke = invoke
            service.close()
            self.assertEqual(calls[0], ('systemctl', 'stop', 'private-qa.service'))
            self.assertFalse(service.path.exists())
            self.assertEqual(calls[-1], ('systemctl', 'daemon-reload'))

    def test_cleanup_attempts_all_services_and_never_hides_failure(self):
        attempted = []
        def broken():
            attempted.append('hpt')
            raise RuntimeError('private stop failed')
        services = [SimpleNamespace(close=lambda: attempted.append('server')), SimpleNamespace(close=broken)]
        with self.assertRaisesRegex(RuntimeError, 'cleanup failed'):
            flow.close_services(services)
        self.assertEqual(attempted, ['hpt', 'server'])

    def test_readiness_wait_is_bounded(self):
        with patch.object(flow.time, 'monotonic', side_effect=[0, 0, 2]), patch.object(flow.time, 'sleep'):
            with self.assertRaisesRegex(RuntimeError, 'readiness timed out'):
                flow.wait_for(lambda: False, 'readiness', timeout=1)

    def test_ready_probe_returns_without_sleep(self):
        with patch.object(flow.time, 'sleep') as sleep:
            flow.wait_for(lambda: True, 'readiness')
            sleep.assert_not_called()


if __name__ == '__main__':
    unittest.main()
