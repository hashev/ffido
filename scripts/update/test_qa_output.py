import pathlib
import tempfile
import unittest
from unittest.mock import patch
import test_android_flow as android
import test_macos_flow as macos


class QAOutputTest(unittest.TestCase):
    def test_existing_success_cannot_be_reused_or_overwritten(self):
        for module in [android, macos]:
            with self.subTest(module=module.__name__), tempfile.TemporaryDirectory() as tmp:
                output = pathlib.Path(tmp)/'qa'
                module.prepare_output(output)
                (output/'result.json').write_text('existing successful result')
                with self.assertRaises(FileExistsError): module.prepare_output(output)
                self.assertEqual((output/'result.json').read_text(), 'existing successful result')

    def test_output_and_key_directories_must_not_overlap(self):
        for module in [android, macos]:
            with self.subTest(module=module.__name__), tempfile.TemporaryDirectory() as tmp:
                base = pathlib.Path(tmp); keys = base/'keys'; keys.mkdir(mode=0o700)
                marker = keys/'private-marker'; marker.write_text('do not touch')
                for output in [keys, keys/'qa', base]:
                    with self.assertRaisesRegex(ValueError, 'overlap'):
                        module.prepare_output(output, keys)
                self.assertEqual(marker.read_text(), 'do not touch')
                self.assertFalse((keys/'qa').exists())
                output = module.prepare_output(base/'qa', keys)
                self.assertEqual(output.stat().st_mode & 0o777, 0o700)

    def test_mac_cleanup_finds_relaunched_b_without_a_status_record(self):
        binary = '/tmp/isolated-update-qa/fido.app/Contents/MacOS/fido'
        listing = f'101 {binary} --profile default\n102 {binary}\n103 {binary}2\n104 /Applications/fido.app/Contents/MacOS/fido\n'
        with patch.object(macos.subprocess, 'check_output', return_value=listing), patch.object(macos.os, 'kill') as kill:
            macos.terminate_bundle(pathlib.Path(binary))
        self.assertEqual([call.args[0] for call in kill.call_args_list], [101, 102])
