import argparse
import json
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import test_android_flow as android


class AndroidFixturesTest(unittest.TestCase):
    def test_complete_fixture_identity_and_integrity(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            (directory/'www').mkdir()
            for name in ('A', 'B', 'foreign-key', 'foreign-id', 'lower'):
                (directory/'www'/(name+'.apk')).write_bytes(name.encode())
            manifest = android.fixture_manifest(directory)
            (directory/'fixtures.json').write_text(json.dumps(manifest))
            self.assertEqual(android.read_fixtures(directory), manifest)
            for key, value in [('sha', 'wrong'), ('from', 1), ('to', 2)]:
                (directory/'fixtures.json').write_text(json.dumps({**manifest, key: value}))
                with self.assertRaises(ValueError):
                    android.read_fixtures(directory)
            (directory/'fixtures.json').write_text(json.dumps(manifest))
            (directory/'www/B.apk').write_bytes(b'corrupt')
            with self.assertRaises(ValueError):
                android.read_fixtures(directory)
            (directory/'www/B.apk').write_bytes(b'B')
            manifest['origin'] = 'http://127.0.0.1:1'
            (directory/'fixtures.json').write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):
                android.read_fixtures(directory)

    def test_private_keys_and_unknown_apks_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            (directory/'www').mkdir()
            for name in ('A', 'B', 'foreign-key', 'foreign-id', 'lower'):
                (directory/'www'/(name+'.apk')).write_bytes(name.encode())
            (directory/'fixtures.json').write_text(json.dumps(android.fixture_manifest(directory)))
            (directory/'trusted.jks').write_text('private')
            with self.assertRaises(ValueError):
                android.read_fixtures(directory)
            (directory/'trusted.jks').unlink()
            (directory/'www/unexpected.apk').write_text('unexpected')
            with self.assertRaises(ValueError):
                android.read_fixtures(directory)

    def test_production_and_shared_modes_are_disjoint(self):
        for args in (argparse.Namespace(prepare_only=True, production_keys='keys', fixtures=None),
                     argparse.Namespace(prepare_only=False, production_keys='keys', fixtures='fixtures')):
            with self.assertRaises(ValueError):
                android.run(args)

    def test_port_conflict_is_explicit(self):
        import http.server
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            directory = root/'fixtures'
            (directory/'www').mkdir(parents=True)
            for name in ('A', 'B', 'foreign-key', 'foreign-id', 'lower'):
                (directory/'www'/(name+'.apk')).write_bytes(name.encode())
            server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), http.server.BaseHTTPRequestHandler)
            try:
                with patch.object(android, 'QA_PORT', server.server_port):
                    (directory/'fixtures.json').write_text(json.dumps(android.fixture_manifest(directory)))
                    args = argparse.Namespace(prepare_only=False, fixtures=directory, production_keys=None,
                                              serial='emulator-5554', directory=root/'output', flutter=None)
                    with self.assertRaises(OSError):
                        android.run(args)
                    self.assertFalse((root/'output/result.json').exists())
            finally:
                server.server_close()


class ADBRecoveryTest(unittest.TestCase):
    def test_transport_recovers_but_never_retries_install_or_assertions(self):
        error = subprocess.CalledProcessError(1, ['adb'], output='error: device offline')
        with patch.object(android.subprocess, 'check_output', side_effect=[error, 'ready']) as output, \
                patch.object(android.subprocess, 'run') as recovery:
            self.assertEqual(android.adb_command('adb', 'emulator-5554', ('logcat', '-c')), 'ready')
            self.assertEqual(output.call_count, 2)
            recovery.assert_called_once()
        for command, failure in [(('install', 'A.apk'), error),
                                 (('logcat', '-d'), subprocess.CalledProcessError(1, [], output='assertion failed'))]:
            with patch.object(android.subprocess, 'check_output', side_effect=failure) as output, \
                    patch.object(android.subprocess, 'run') as recovery:
                with self.assertRaises(subprocess.CalledProcessError):
                    android.adb_command('adb', 'emulator-5554', command)
                self.assertEqual(output.call_count, 1)
                recovery.assert_not_called()

    def test_window_dump_uses_file_transfer_and_rejects_truncated_xml(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            for content in ('<hierarchy><node text="Install"/></hierarchy>', '<hierarchy><node'):
                calls = []
                def device(*command):
                    calls.append(command)
                    if command[0] == 'pull':
                        pathlib.Path(command[2]).write_text(content)
                if content.endswith('</hierarchy>'):
                    self.assertEqual(android.window_nodes(device, directory)[0].get('text'), 'Install')
                else:
                    with self.assertRaises(android.ET.ParseError):
                        android.window_nodes(device, directory)
                self.assertEqual(calls[0][:3], ('shell', 'uiautomator', 'dump'))
                self.assertEqual(calls[1][0], 'pull')
                self.assertEqual(len(calls), 2)

    def test_install_has_bounded_package_timeout_without_retry(self):
        error = subprocess.TimeoutExpired(['adb', 'install'], 120)
        with patch.object(android.subprocess, 'check_output', side_effect=error) as output, \
                patch.object(android.subprocess, 'run') as recovery:
            with self.assertRaises(subprocess.TimeoutExpired):
                android.adb_command('adb', 'emulator-5554', ('install', 'A.apk'))
            self.assertEqual(output.call_args.kwargs['timeout'], 120)
            self.assertEqual(output.call_count, 1)
            recovery.assert_not_called()

    def test_recovery_is_bounded_and_timeout_is_not_success(self):
        error = subprocess.CalledProcessError(1, [], output='device offline')
        with patch.object(android.subprocess, 'check_output', side_effect=error) as output, \
                patch.object(android.subprocess, 'run') as recovery:
            with self.assertRaises(subprocess.CalledProcessError):
                android.adb_command('adb', 'emulator-5554', ('logcat', '-c'))
            self.assertEqual(output.call_count, 3)
            self.assertEqual(recovery.call_count, 2)
        with patch.object(android.subprocess, 'check_output', side_effect=subprocess.TimeoutExpired([], 30)):
            with self.assertRaises(subprocess.TimeoutExpired):
                android.adb_command('adb', 'emulator-5554', ('logcat', '-c'))


class QAEventsTest(unittest.TestCase):
    def test_events_survive_buffer_rotation_and_partial_writes(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(android.subprocess, 'Popen') as spawn:
            spawn.return_value.poll.return_value = None
            events = android.QAEvents('adb', 'emulator-5554', pathlib.Path(temporary))
            try:
                events.output.write(b'I/flutter: FFIDO_UPDATE_QA {"stage":"A"}\n')
                events.output.flush()
                self.assertEqual(events.records(), [{'stage':'A'}])
                # Device ring-buffer contents may disappear; captured events remain.
                events.output.write(b'other message\n'*20000)
                events.output.write(b'I/flutter: FFIDO_UPDATE_QA {"result":"rejected"')
                events.output.flush()
                self.assertEqual(len(events.records()), 1)
                events.output.write(b'}\n')
                events.output.flush()
                self.assertEqual(events.records(), [{'stage':'A'}, {'result':'rejected'}])
                events.output.write(b'I/flutter: FFIDO_UPDATE_QA not-json\n')
                events.output.flush()
                with self.assertRaises(json.JSONDecodeError):
                    events.records()
            finally:
                events.close()
            spawn.return_value.terminate.assert_called_once()
            spawn.return_value.wait.assert_called_once_with(timeout=5)
            self.assertTrue(events.output.closed)

    def test_dead_stream_fails_and_shutdown_is_bounded(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(android.subprocess, 'Popen') as spawn:
            process = spawn.return_value
            process.poll.return_value = 1
            events = android.QAEvents('adb', 'emulator-5554', pathlib.Path(temporary))
            with self.assertRaisesRegex(RuntimeError, 'stream stopped'):
                events.records()
            process.poll.return_value = None
            process.wait.side_effect = [subprocess.TimeoutExpired([], 5), 0]
            events.close()
            process.kill.assert_called_once()
            self.assertEqual(process.wait.call_count, 2)
            spawn.assert_called_once()
            self.assertTrue(events.output.closed)
