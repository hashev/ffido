import gzip
import os
import signal
import subprocess
import time
from pathlib import Path
import sys
import tempfile
import unittest

import run_logged


class LoggedBuildTest(unittest.TestCase):
    def test_failure_code_and_complete_log_are_preserved(self):
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary)/'build.log'
            code = run_logged.run(log, [sys.executable, '-c', 'print("diagnostic"); raise SystemExit(7)'], interval=.1)
            self.assertEqual(code, 7)
            self.assertFalse(log.exists())
            self.assertIn(b'diagnostic', gzip.decompress(Path(str(log)+'.gz').read_bytes()))

    @unittest.skipUnless(os.name == 'posix', 'Native builders use POSIX process groups')
    def test_cancellation_keeps_compressed_diagnostics(self):
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary)/'cancelled.log'
            process = subprocess.Popen([sys.executable, str(Path(run_logged.__file__)), str(log),
                                        sys.executable, '-c', 'import time; print("ready", flush=True); time.sleep(30)'],
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic()+5
                while time.monotonic()<deadline and (not log.exists() or b'ready' not in log.read_bytes()):
                    time.sleep(.02)
                self.assertTrue(log.exists())
                process.send_signal(signal.SIGTERM)
                process.communicate(timeout=5)
                self.assertNotEqual(process.returncode, 0)
                self.assertIn(b'ready', gzip.decompress(Path(str(log)+'.gz').read_bytes()))
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate()
