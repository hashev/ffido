"""Check release schema bounds against an actual backend, including migration.

Set FFIDO_E2E_BACKEND when the binary is outside build/backend. This test never
uses working FTN files or credentials.
"""
import json
import os
from pathlib import Path
import socket
import sqlite3
import struct
import subprocess
import tempfile
import time
import unittest

from update_metadata import COMPATIBILITY

ROOT = Path(__file__).resolve().parents[2]
BINARY = Path(os.environ.get('FFIDO_E2E_BACKEND', ROOT/'build/backend/apps/backend/fidoback'))


@unittest.skipUnless(BINARY.is_file(), 'Build backend or set FFIDO_E2E_BACKEND')
class SchemaCompatibilityTest(unittest.TestCase):
    def test_fresh_migrated_and_unsupported_schema(self):
        with tempfile.TemporaryDirectory(prefix='ffido-schema-') as name:
            root = Path(name)
            subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                            '-days', '1', '-subj', '/CN=localhost', '-keyout', str(root/'key.pem'),
                            '-out', str(root/'cert.pem')], check=True, capture_output=True)
            (root/'areas.cfg').write_text('EchoArea TEST file -b JAM\n')
            (root/'hpt.cfg').write_text('Name Fixture\nSysop Test\nLocation Test\nAddress 2:1/1\n')
            (root/'file.jhr').write_bytes(struct.pack('<7I', 0x004d414a, 123, 0, 0, 0xffffffff, 1, 0)+bytes(996))
            for ext in ['jdt', 'jdx']: (root/('file.'+ext)).touch()
            with socket.socket() as sock:
                sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
            config = {'server': {'ip': '127.0.0.1', 'port': port,
                                'tls_certificate': str(root/'cert.pem'), 'tls_private_key': str(root/'key.pem')},
                      'auth': {'hpt_config_path': str(root/'hpt.cfg'), 'session_key_path': str(root/'session.key')},
                      'ftn': {'areacfg_path': str(root/'areas.cfg'), 'jam_base_path': str(root),
                              'coordination_lock': str(root/'hpt.lock'), 'default_encoding': 'UTF-8'},
                      'database': {'metadata_path': str(root/'metadata.db')}}
            (root/'config.json').write_text(json.dumps(config))

            def boot(expected):
                process = subprocess.Popen([str(BINARY.resolve()), str(root/'config.json')],
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                try:
                    if not expected:
                        self.assertNotEqual(process.wait(timeout=15), 0)
                        return
                    deadline = time.monotonic()+15
                    while time.monotonic() < deadline:
                        self.assertIsNone(process.poll(), 'Backend exited during schema initialization')
                        try:
                            with socket.create_connection(('127.0.0.1', port), timeout=.1): break
                        except OSError: time.sleep(.05)
                    else: self.fail('Backend did not become ready')
                finally:
                    if process.poll() is None:
                        process.terminate(); process.wait(timeout=10)

            boot(True)
            with sqlite3.connect(root/'metadata.db') as db:
                version = db.execute('PRAGMA user_version').fetchone()[0]
                self.assertLessEqual(COMPATIBILITY['state_schema_min'], version)
                self.assertEqual(COMPATIBILITY['state_schema_max'], version,
                                 'Published metadata must cover the schema created by the backend')
                # Reconstruct the supported v9 boundary from this empty fixture.
                db.execute('DROP TABLE crosspost_groups')
                db.execute('PRAGMA user_version=9')
            boot(True)
            with sqlite3.connect(root/'metadata.db') as db:
                self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0], version)
                self.assertIsNotNone(db.execute("SELECT name FROM sqlite_master WHERE name='crosspost_groups'").fetchone())
            boot(True)  # Reopening the latest schema is also supported.
            with sqlite3.connect(root/'metadata.db') as db:
                db.execute(f'PRAGMA user_version={COMPATIBILITY["state_schema_max"]+1}')
            boot(False)
