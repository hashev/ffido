#!/usr/bin/env python3
"""Check the correction loader and read-only CLI against an independent JAM fixture."""

import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest


BINARY = sys.argv.pop(1)
SOURCE = 'a' * 64


class EncodingCheck(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix='ffido-encoding-check-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.manifest = self.root / 'corrections.jsonl'
        self.config = self.root / 'config.json'
        self.lock = self.root / 'hpt.lock'
        self.lock.touch()
        areas = self.root / 'areas.cfg'
        areas.write_text('EchoArea TEST echo -b Jam\n', encoding='ascii')
        self.config.write_text(json.dumps({'ftn': {
            'areacfg_path': str(areas), 'jam_base_path': str(self.root),
            'coordination_lock': str(self.lock), 'jam_message_encoding_corrections_path': self.manifest.name,
        }}), encoding='ascii')
        fields = b''
        for kind, value in ((6, 'Тема'.encode('koi8-r')), (2000, b'CHRS: CP866 2')):
            fields += struct.pack('<HHI', kind, 0, len(value)) + value
        body = 'Тело тестового письма'.encode('koi8-r')
        base = bytearray(1024)
        base[:4] = b'JAM\0'
        struct.pack_into('<I', base, 12, 1)
        struct.pack_into('<I', base, 20, 1)
        header = bytearray(76)
        header[:4] = b'JAM\0'
        struct.pack_into('<H', header, 4, 1)
        for offset, value in ((8, len(fields)), (48, 1), (64, len(body))):
            struct.pack_into('<I', header, offset, value)
        self.files = {
            self.root / 'echo.jhr': base + header + fields,
            self.root / 'echo.jdx': struct.pack('<II', 0, len(base)),
            self.root / 'echo.jdt': body,
        }
        for path, value in self.files.items():
            path.write_bytes(value)
        self.entry = {'base': 'echo', 'number': 1, 'raw_sha256': hashlib.sha256(fields + body).hexdigest(),
                      'expected_encoding': 'CP866', 'encoding': 'KOI8-R'}

    def write(self, *entries: dict, **header: object) -> None:
        envelope = {'kind': 'manifest', 'version': 1, 'count': len(entries), 'source_sha256': SOURCE, **header}
        self.manifest.write_text('\n'.join(json.dumps(row) for row in (envelope, *entries)) + '\n', encoding='ascii')

    def check(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run([BINARY, *args], capture_output=True, text=True, timeout=15, check=False)

    def dry_run(self) -> subprocess.CompletedProcess[str]:
        return self.check('--dry-run', str(self.config), '-', '-')

    def test_matches_original_bytes_without_writing(self) -> None:
        self.write(self.entry)
        result = self.dry_run()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['counts'], {'eligible': 1})
        self.assertEqual({path: path.read_bytes() for path in self.files}, self.files)
        self.assertFalse((self.root / 'echo.jlr').exists())

    def test_stale_missing_and_undecodable_entries(self) -> None:
        for entry, reason in (
            ({**self.entry, 'raw_sha256': '0' * 64}, 'fingerprint_changed'),
            ({**self.entry, 'expected_encoding': 'UTF-8'}, 'decoder_changed'),
            ({**self.entry, 'number': 2}, 'missing_record'),
            ({**self.entry, 'encoding': 'UTF-8'}, 'invalid_target_text'),
        ):
            with self.subTest(reason=reason):
                self.write(entry)
                result = self.dry_run()
                self.assertEqual(result.returncode, 3, result.stderr)
                rejection, summary = [json.loads(line) for line in result.stdout.splitlines()]
                self.assertEqual(rejection['reason'], reason)
                self.assertEqual(summary['counts'], {reason: 1})
        self.assertEqual({path: path.read_bytes() for path in self.files}, self.files)

    def test_codec_aliases_and_duplicate_physical_record(self) -> None:
        self.write({**self.entry, 'expected_encoding': 'LATIN-1'})
        self.assertEqual(self.check('--validate-only', str(self.manifest)).returncode, 0)
        self.write({**self.entry, 'expected_encoding': 'ibm866'})
        self.assertEqual(self.dry_run().returncode, 0)
        for path in self.files:
            (self.root / f'alias{path.suffix}').hardlink_to(path)
        areas = self.root / 'areas.cfg'
        areas.write_text('EchoArea TEST echo -b Jam\nEchoArea ALIAS alias -b Jam\n', encoding='ascii')
        self.write(self.entry, {**self.entry, 'base': 'alias'})
        result = self.dry_run()
        self.assertEqual(result.returncode, 1)
        self.assertIn('Duplicate physical JAM record', result.stderr)

    def test_invalid_manifests_and_catalog(self) -> None:
        for entries, header in (
            ((self.entry, self.entry), {}),
            ((self.entry,), {'count': 2}),
            ((self.entry,), {'version': 2}),
            (({**self.entry, 'base': '../echo'},), {}),
            (({**self.entry, 'number': -1},), {}),
            (({**self.entry, 'encoding': 'UTF-8//IGNORE'},), {}),
        ):
            with self.subTest(entries=entries, header=header):
                self.write(*entries, **header)
                self.assertEqual(self.check('--validate-only', str(self.manifest)).returncode, 1)
        self.write(self.entry)
        self.manifest.write_bytes(self.manifest.read_bytes().replace(b'"version": 1', b'"version": 1, "version": 1'))
        self.assertEqual(self.check('--validate-only', str(self.manifest)).returncode, 1)
        self.write({**self.entry, 'base': 'absent'})
        self.assertEqual(self.dry_run().returncode, 1)
        self.write(self.entry)
        self.lock.unlink()
        self.assertEqual(self.dry_run().returncode, 1)
        self.assertFalse(self.lock.exists())


if __name__ == '__main__':
    unittest.main()
