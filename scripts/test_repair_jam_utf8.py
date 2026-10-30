#!/usr/bin/env python3
"""Synthetic wire fixtures: never open production mail or require HPT."""
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name('repair_jam_utf8.py')
spec = importlib.util.spec_from_file_location('repair', SCRIPT)
repair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repair)


def corrupt(raw):
    return raw.decode('cp866').encode('koi8-r')


def fixture(root):
    header = bytearray(1024)
    header[:4] = b'JAM\0'
    struct.pack_into('<I', header, 4, 123)
    struct.pack_into('<I', header, 12, 2)
    struct.pack_into('<I', header, 20, 1)
    text, index = bytearray(), bytearray()
    for number in (1, 2):
        fields = b''
        for low, raw in [(2, 'Автор'.encode()), (3, b'All'), (6, 'Тема'.encode()),
                         (4, f'2:1/2 fixture-{number}'.encode()),
                         (5, b'2:1/2 fixture-1'), (2000, b'CHRS: UTF-8 4')]:
            value = corrupt(raw) if number == 1 and low in (2, 6) else raw
            fields += struct.pack('<HHI', low, 0, len(value)) + value
        body = 'Привет UTF-8\r  текст'.encode()
        if number == 1:
            body = corrupt(body)
        message = bytearray(76)
        message[:4] = b'JAM\0'
        struct.pack_into('<H', message, 4, 1)
        for offset, value in [(8, len(fields)), (24, 1 if number == 2 else 0),
                              (36, 456), (48, number), (52, 0x01000000),
                              (60, len(text)), (64, len(body))]:
            struct.pack_into('<I', message, offset, value)
        index.extend(struct.pack('<II', 0xffffffff, len(header)))
        header.extend(message + fields)
        text.extend(body)
    data = {'.jhr': bytes(header), '.jdt': bytes(text), '.jdx': bytes(index), '.jlr': bytes(16)}
    for ext, raw in data.items():
        (root / ('utf-8' + ext)).write_bytes(raw)
    return data


class RepairTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.data = fixture(self.root)
        self.config = self.root / 'config.json'
        self.config.write_text(json.dumps({'ftn': {'jam_base_path': str(self.root),
            'coordination_lock': str(self.root / 'hpt.lock'), 'jam_encoding_overrides': {'utf-8': 'UTF-8'}}}))
        (self.root / 'hpt.lock').touch()
        self.report = self.root / 'report.json'
        self.backup = self.root / 'backup'
        self.marker = self.root / 'maintenance.json'
        self.command = [sys.executable, str(SCRIPT), '--config', str(self.config), '--base', 'utf-8', '--report', str(self.report)]

    def run_cli(self, *args, ok=True):
        result = subprocess.run(self.command + list(args), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0 if ok else 1, result.stderr)
        self.assertNotIn('Привет', result.stdout + result.stderr)
        self.assertNotIn('Автор', result.stdout + result.stderr)
        return result

    def prepare(self):
        self.run_cli()
        expected = json.loads(self.report.read_bytes())
        self.marker.write_bytes(repair.json_bytes({'report_sha256': repair.digest(repair.json_bytes(expected)),
                                                  'stopped': sorted(repair.STOPPED)}))
        return expected

    def write_args(self, mode='--apply'):
        return [mode, '--backup', str(self.backup), '--maintenance-file', str(self.marker)]

    def actual(self):
        return {ext: (self.root / ('utf-8' + ext)).read_bytes() for ext in self.data}

    def test_dry_run_apply_repeat_and_identity(self):
        expected = self.prepare()
        self.assertEqual(len(expected['changes']), 3)
        self.assertEqual(expected['messages'], 2)
        self.assertEqual(self.actual(), self.data)
        identities = [(self.root / ('utf-8' + ext)).stat().st_ino for ext in self.data]
        self.run_cli(*self.write_args())
        actual = self.actual()
        fixed = repair.repaired(self.data, expected['changes'])
        self.assertEqual(actual, fixed)
        self.assertEqual(actual['.jhr'][:1024], self.data['.jhr'][:1024])
        for ext in ('.jdx', '.jlr'):
            self.assertEqual(actual[ext], self.data[ext])
        # Every byte outside planned ranges is identical, including CHRS,
        # MsgID/REPLY, dates, attributes, offsets and the second clean message.
        for ext, raw in self.data.items():
            allowed = set()
            for edit in expected['changes']:
                if edit['file'] == ext:
                    allowed.update(range(edit['offset'], edit['offset'] + edit['length']))
            self.assertTrue(all(a == b for i, (a, b) in enumerate(zip(raw, actual[ext])) if i not in allowed))
        self.assertEqual(identities, [(self.root / ('utf-8' + ext)).stat().st_ino for ext in self.data])
        self.report = self.root / 'second.json'
        self.command[-1] = str(self.report)
        self.run_cli()
        self.assertEqual(json.loads(self.report.read_bytes())['changes'], [])

    def test_no_maintenance_stale_report_and_lock(self):
        self.prepare()
        self.run_cli('--apply', '--backup', str(self.backup), ok=False)
        self.marker.write_text('{}')
        self.run_cli(*self.write_args(), ok=False)
        self.prepare_marker()
        with (self.root / 'hpt.lock').open('rb') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.run_cli(*self.write_args(), ok=False)
        with (self.root / 'utf-8.jdt').open('ab') as out:
            out.write(b'new arrival')
        self.run_cli(*self.write_args(), ok=False)
        self.assertFalse(self.backup.exists())

    def prepare_marker(self):
        self.marker.write_bytes(repair.json_bytes({'report_sha256': repair.digest(self.report.read_bytes()),
                                                  'stopped': sorted(repair.STOPPED)}))

    def test_path_and_structure_rejections(self):
        for base in ('../utf-8', '/tmp/utf-8', 'sub/../utf-8'):
            with self.assertRaises(repair.RepairError):
                with repair.open_base(self.root, base):
                    pass
        (self.root / 'link').symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(OSError):
            with repair.open_base(self.root, 'link/utf-8'):
                pass
        (self.root / 'utf-8.jlr').unlink()
        (self.root / 'utf-8.jlr').symlink_to(self.root / 'utf-8.jdx')
        self.run_cli(ok=False)
        for key, raw in [('.jdx', b'x'), ('.jhr', b'JAM\0'), ('.jdt', b'')]:
            data = dict(self.data)
            data[key] = raw
            with self.assertRaises(repair.RepairError):
                repair.plan(data)
        data = dict(self.data)
        header = bytearray(data['.jhr'])
        struct.pack_into('<I', header, 1024 + 76 + 4, 0xffffffff)
        data['.jhr'] = bytes(header)
        with self.assertRaises(repair.RepairError):
            repair.plan(data)
        with patch.object(repair, 'MAX_FILE', 1):
            with (self.root / 'utf-8.jhr').open('rb') as file:
                with self.assertRaises(repair.RepairError):
                    repair.read_fd(file.fileno())

    def test_unrecoverable_aborts_whole_plan(self):
        data = dict(self.data)
        raw = bytearray(data['.jdt'])
        raw[0] = 0xff
        data['.jdt'] = bytes(raw)
        with self.assertRaises(repair.RepairError):
            repair.plan(data)
        self.assertEqual(self.actual(), self.data)

    def test_io_failure_restores_all_files(self):
        expected = self.prepare()
        with repair.open_base(self.root, 'utf-8', True) as (files, directory, name):
            original_write = repair.write_all
            failed = False
            def fail_once(fd, data):
                nonlocal failed
                if fd == files['.jdt'] and not failed:
                    failed = True
                    os.pwrite(fd, data[:2], 0)
                    raise OSError('fixture injected write failure')
                return original_write(fd, data)
            with patch.object(repair, 'write_all', fail_once):
                with self.assertRaises(OSError):
                    repair.apply_repair(files, directory, name, self.data, expected, self.backup)
        self.assertTrue(failed)
        self.assertEqual(self.actual(), self.data)
        self.assertEqual(json.loads((self.backup / 'manifest.json').read_bytes())['state'], 'rolled-back')

    def test_restore_interrupted_write_and_refuse_new_data(self):
        expected = self.prepare()
        self.run_cli(*self.write_args())
        fixed = self.actual()
        # Simulate an interrupted application: original header + repaired body.
        (self.root / 'utf-8.jhr').write_bytes(self.data['.jhr'])
        self.run_cli(*self.write_args('--restore'))
        self.assertEqual(self.actual(), self.data)
        (self.root / 'utf-8.jdt').write_bytes(fixed['.jdt'] + b'new')
        self.run_cli(*self.write_args('--restore'), ok=False)
        self.assertTrue(self.actual()['.jdt'].endswith(b'new'))

    def test_source_changes_during_backup_are_not_overwritten(self):
        expected = self.prepare()
        with repair.open_base(self.root, 'utf-8', True) as (files, directory, name):
            original_save = repair.save_manifest
            def mutate(folder, value):
                original_save(folder, value)
                os.pwrite(files['.jdt'], b'X', 0)
            with patch.object(repair, 'save_manifest', mutate):
                with self.assertRaises(repair.RepairError):
                    repair.apply_repair(files, directory, name, self.data, expected, self.backup)
        self.assertEqual(self.actual()['.jdt'][0:1], b'X')


if __name__ == '__main__':
    unittest.main()
