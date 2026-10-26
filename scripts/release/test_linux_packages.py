import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT/'scripts/release/linux_packages.sh'


class LinuxPackagesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.log = self.root/'calls.jsonl'
        sudo = self.root/'sudo'
        sudo.write_text('''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys
args = sys.argv[1:]
with open(os.environ['FFIDO_TEST_APT_LOG'], 'a') as out:
    out.write(json.dumps(args)+'\\n')
if args[0] == 'sed' and pathlib.Path(args[-1]).is_relative_to(os.environ['FFIDO_TEST_APT_ROOT']):
    if sys.platform == 'darwin':
        args[0] = '/usr/bin/sed'
        args.insert(args.index('-i')+1, '')
    subprocess.run(args, check=True)
if args[0] == 'apt-get' and args[-1] == 'update' and os.environ.get('FFIDO_TEST_APT_FAIL'):
    sys.exit(7)
''')
        sudo.chmod(0o755)
        self.env = {**os.environ, 'PATH': str(self.root)+os.pathsep+os.environ['PATH'],
                    'FFIDO_TEST_APT_LOG': str(self.log), 'FFIDO_TEST_APT_ROOT': str(self.root)}

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_mirror_rewrite_preserves_other_repositories(self):
        source = self.root/'apt sources.txt'
        source.write_text('http://azure.archive.ubuntu.com/ubuntu noble\nhttps://azure.archive.ubuntu.com/ubuntu noble-updates\nhttps://packages.microsoft.com/ubuntu stable\n')
        subprocess.run(['bash', '-c', 'source "$1"; use_ubuntu_archive "$2"', 'test', str(SCRIPT), str(source)], env=self.env, check=True)
        self.assertEqual(source.read_text(), 'https://archive.ubuntu.com/ubuntu noble\nhttps://archive.ubuntu.com/ubuntu noble-updates\nhttps://packages.microsoft.com/ubuntu stable\n')

    def test_update_and_install_keep_packages_and_bound_network_wait(self):
        subprocess.run(['bash', str(SCRIPT), 'clang-format-19', 'ninja-build'], env=self.env, check=True)
        calls = [row for row in self.calls() if row[0]=='apt-get']
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0][-1], 'update')
        self.assertEqual(calls[1][-4:], ['install', '-y', 'clang-format-19', 'ninja-build'])
        for call in calls:
            for option in ('Acquire::Retries=3','Acquire::http::Timeout=30','Acquire::https::Timeout=30'):
                self.assertIn(option, call)

    def test_update_failure_stops_before_install_and_no_packages_is_error(self):
        failed = subprocess.run(['bash', str(SCRIPT), 'clang-format-19'], env={**self.env, 'FFIDO_TEST_APT_FAIL':'1'})
        self.assertEqual(failed.returncode, 7)
        self.assertFalse(any('install' in row for row in self.calls()))
        empty = subprocess.run(['bash', str(SCRIPT)], env=self.env, capture_output=True)
        self.assertEqual(empty.returncode, 2)
