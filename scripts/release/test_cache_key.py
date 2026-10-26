import copy
import os
import unittest
from unittest.mock import patch

import cache_key
from dependency_lock import load


class CacheKeyTest(unittest.TestCase):
    def setUp(self):
        self.lock = load()
        self.values = {'system': 'Linux', 'cxx': 'Ubuntu clang version 19.1.7',
                       'abi': '_GLIBCXX_USE_CXX11_ABI 1', 'sdk': '', 'flags': {},
                       'arch': 'x86_64'}

    def test_runner_labels_and_kernel_are_not_inputs(self):
        with patch.dict(os.environ, {'ImageVersion': 'old'}):
            before = cache_key.fingerprint(self.values, self.lock, {})
        with patch.dict(os.environ, {'ImageVersion': 'new'}):
            self.assertEqual(before, cache_key.fingerprint(self.values, self.lock, {}))
        with patch.object(cache_key.platform, 'platform', side_effect=AssertionError('kernel')):
            self.assertEqual(before, cache_key.fingerprint(self.values, self.lock, {}))

    def test_significant_inputs_invalidate(self):
        before = cache_key.fingerprint(self.values, self.lock, {'build': 'a'})
        for key in self.values:
            values = {**self.values, key: 'different'}
            self.assertNotEqual(before, cache_key.fingerprint(values, self.lock, {'build': 'a'}), key)
        self.assertNotEqual(before, cache_key.fingerprint(self.values, self.lock, {'build': 'b'}))

    def test_unrelated_source_does_not_invalidate_toolchain(self):
        lock = copy.deepcopy(self.lock)
        lock['native']['hpt']['revision'] = 'a'*40
        self.assertEqual(cache_key.fingerprint(self.values, self.lock, {}),
                         cache_key.fingerprint(self.values, lock, {}))

    def test_component_revision_invalidation_follows_dag(self):
        before = cache_key.component_keys('profile', self.lock)
        for changed in ('hpt', 'huskylib', 'abseil'):
            lock = copy.deepcopy(self.lock)
            lock['native'][changed]['revision'] = 'a'*40
            after = cache_key.component_keys('profile', lock)
            self.assertNotEqual(before[changed], after[changed])
            if changed in ('hpt', 'huskylib'):
                for name in ('abseil', 'protobuf', 'grpc'):
                    self.assertEqual(before[name], after[name])
            if changed == 'abseil':
                self.assertNotEqual(before['protobuf'], after['protobuf'])
                self.assertNotEqual(before['grpc'], after['grpc'])

    def test_supported_and_unsupported_profiles(self):
        cache_key.validate_profile(self.values, self.lock)
        for values in ({**self.values, 'cxx': 'clang version 20.0.0'},
                       {'system': 'Windows'},
                       {'system': 'Darwin', 'xcode': 'Xcode 27.0\nBuild version new'}):
            with self.assertRaises(ValueError):
                cache_key.validate_profile(values, self.lock)
        cache_key.validate_profile({'system': 'Darwin', 'xcode': 'Xcode 26.3\nBuild version old'}, self.lock)

    def test_probe_failure_is_not_a_cache_key(self):
        import subprocess
        with patch.object(cache_key.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, ['compiler'])):
            with self.assertRaises(subprocess.CalledProcessError):
                cache_key.probe(['compiler'])

    def test_macos_abi_probe_uses_selected_sdk(self):
        import subprocess
        for explicit_sdk in ('', '/custom/SDK'):
            with self.subTest(sdk=explicit_sdk), patch.dict(os.environ, {'SDKROOT': explicit_sdk}), \
                    patch.object(cache_key.platform, 'system', return_value='Darwin'), \
                    patch.object(cache_key, 'probe', side_effect=lambda cmd: '/selected/SDK' if cmd == ['xcrun', '--show-sdk-path'] else 'tool-version'), \
                    patch.object(cache_key.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, stdout='#define _LIBCPP_VERSION 1')) as run:
                values = cache_key.collect()
                command = run.call_args.args[0]
                self.assertEqual(command[command.index('-isysroot') + 1], explicit_sdk or '/selected/SDK')
                self.assertIn('_LIBCPP_VERSION', values['abi'])

    def test_abi_probe_reports_compiler_diagnostic(self):
        import subprocess
        with patch.object(cache_key.platform, 'system', return_value='Linux'), \
                patch.object(cache_key, 'probe', return_value='tool-version'), \
                patch.object(cache_key.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, [], stderr='header missing')):
            with self.assertRaisesRegex(RuntimeError, 'header missing'):
                cache_key.collect()
