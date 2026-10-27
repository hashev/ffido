from pathlib import Path
import json
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import analysis_cache


class AnalysisCacheTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.record = self.root/'result/success.json'

    def test_only_successful_exact_record_is_reused(self):
        with patch.object(analysis_cache.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
            self.assertEqual(analysis_cache.execute(self.record, 'a', ['tidy']), 0)
            self.assertEqual(analysis_cache.execute(self.record, 'a', ['tidy']), 0)
            self.assertEqual(run.call_count, 1)
            analysis_cache.execute(self.record, 'b', ['tidy'])
            analysis_cache.execute(self.record, 'b', ['tidy'], force=True)
            self.assertEqual(run.call_count, 3)

    def test_failures_partial_or_invalid_proof_never_reused(self):
        for value in ('{}', '{', '{"result":"success"}'):
            self.record.parent.mkdir(parents=True, exist_ok=True)
            self.record.write_text(value)
            with patch.object(analysis_cache.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1)) as run:
                self.assertEqual(analysis_cache.execute(self.record, 'a', ['tidy']), 1)
                run.assert_called_once()
                self.assertFalse(self.record.exists())

    def test_header_config_toolchain_dependencies_invalidate_and_checkout_relocates(self):
        def prepare(root):
            root.mkdir()
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            (root/'apps/backend').mkdir(parents=True)
            (root/'apps/backend/common.h').write_text('header')
            (root/'.clang-tidy').write_text('checks')
            build = root/'build'
            build.mkdir()
            (build/'contracts/generated').mkdir(parents=True)
            (build/'contracts/generated/generated.h').write_text('generated')
            (build/'_deps/dependency-src/include').mkdir(parents=True)
            (build/'_deps/dependency-src/include/library.h').write_text('dependency')
            (build/'compile_commands.json').write_text(json.dumps([{'file': str(root/'apps/backend/main.cpp'),
                          'directory': str(root), 'command': 'c++ -I'+str(root)+'/apps/backend -DVALUE=1'}]))
            return build
        a, b = self.root/'a', self.root/'b'
        build_a, build_b = prepare(a), prepare(b)
        before = analysis_cache.inputs(a, build_a, {'abi': 'a'}, 'tidy1')
        self.assertEqual(before, analysis_cache.inputs(b, build_b, {'abi': 'a'}, 'tidy1'))
        for name in ('apps/backend/common.h', '.clang-tidy', 'build/contracts/generated/generated.h',
                     'build/_deps/dependency-src/include/library.h'):
            path = a/name
            old = path.read_text()
            path.write_text('changed')
            self.assertNotEqual(before, analysis_cache.inputs(a, build_a, {'abi': 'a'}, 'tidy1'))
            path.write_text(old)
        self.assertNotEqual(before, analysis_cache.inputs(a, build_a, {'abi': 'b'}, 'tidy1'))
        self.assertNotEqual(before, analysis_cache.inputs(a, build_a, {'abi': 'a'}, 'tidy2'))
