import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from dependency_lock import load, LOCK

ROOT = LOCK.parents[2]


class DependencyLockTest(unittest.TestCase):
    def test_existing_versions_are_preserved(self):
        lock = load()
        self.assertEqual(lock['tools']['flutter'], '3.47.7')
        self.assertEqual(lock['native']['grpc']['revision'], '3252a89f10d8e92997862167ca7d095ecda85973')
        self.assertEqual(lock['cmake']['protobuf']['version'], '36.2.0')
        for item in lock['native'].values():
            self.assertRegex(item['revision'], r'^[a-f0-9]{40}$')
            self.assertTrue(item['url'].startswith('https://github.com/'))

    def test_consumers_read_lock(self):
        shell = (ROOT/'scripts/release/dependencies.sh').read_text()
        from cache_key import UPSTREAM
        self.assertEqual(set(load()['native']), set(UPSTREAM))
        self.assertIn('clone_locked "$name"', shell)
        for name in ('abseil', 'protobuf', 'grpc'):
            self.assertIn('build_install '+name, shell)
        self.assertIn('for name in huskylib smapi fidoconf areafix hpt;', shell)
        self.assertNotIn('clone grpc https:', shell)
        cmake = (ROOT/'cmake/deps.cmake').read_text()
        self.assertIn('dependencies.lock.json', cmake)
        self.assertNotIn('GIT_TAG v', cmake)
        docker = (ROOT/'Dockerfile').read_text()
        self.assertIn('dependency_lock.py', docker)
        self.assertIn('dependencies.lock.json', docker)
        self.assertNotIn('clang-19', docker)
        for name in ('build.yml', 'release.yml'):
            workflow = (ROOT/'.github/workflows'/name).read_text()
            self.assertNotIn("flutter-version: '3.47.7'", workflow)
            self.assertIn('steps.dependency-lock.outputs.flutter', workflow)
            self.assertIn('--enforce-lockfile', workflow)

    def test_cmake_reads_locked_versions(self):
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory)/'lock.cmake'
            script.write_text('file(READ "'+LOCK.as_posix()+'" lock)\n'
                              'string(JSON version GET "${lock}" cmake protobuf version)\n'
                              'if(NOT version STREQUAL "36.2.0")\nmessage(FATAL_ERROR "Wrong version")\nendif()\n')
            subprocess.run(['cmake', '-P', str(script)], check=True, capture_output=True)

    def test_unknown_schema_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'lock.json'
            path.write_text(json.dumps({'schema': 2}))
            with self.assertRaises(ValueError):
                load(path)
