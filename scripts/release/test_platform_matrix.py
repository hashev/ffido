"""The active matrix may shrink without invalidating historical signed packages."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import publish
import version
from update_metadata import COMPATIBILITY, package_platform

ROOT = Path(__file__).resolve().parents[2]
EXPECTED = {'client-macos-arm64', 'client-windows-x86_64', 'client-linux-x86_64',
            'client-android-universal', 'server-macos-arm64', 'server-linux-x86_64'}

class PlatformMatrixTest(unittest.TestCase):
    def test_workflows_and_inventory_keep_all_remaining_targets(self):
        settings = json.loads((ROOT/'scripts/release/settings.json').read_text())
        self.assertEqual(set(settings['expected_packages']), EXPECTED)
        build = (ROOT/'.github/workflows/build.yml').read_text()
        warm = (ROOT/'.github/workflows/native-dependencies.yml').read_text()
        self.assertNotIn('macos-15-intel', build + warm)
        self.assertEqual(build.count('runner: macos-15, os: macos, arch: arm64'), 2)
        for value in ('windows-2022', 'ubuntu-24.04', 'android-qa', 'build-required', 'container', 'Test including HPT'):
            self.assertIn(value, build)
        self.assertIn('name: Resolve client dependencies', build)
        self.assertIn('name: Test client', build)

    def test_each_of_six_packages_is_required(self):
        identity = version.identity('1.0.0', 'a'*40, 1001, 'refs/heads/master', 'push', True)
        baselines = {'macos': 'macOS 15', 'windows': 'Windows 10 x86_64', 'linux': 'Ubuntu 24.04 x86_64', 'android': 'API 24 (Android 7)'}
        with tempfile.TemporaryDirectory() as directory, patch.object(publish, 'validate_report'):
            root = Path(directory)
            for package in EXPECTED:
                component, os_name, arch = package.split('-')
                file = root/(package+'.bin'); file.write_bytes(package.encode())
                row = dict(identity, id=package, file=file.name, size=file.stat().st_size, sha256=publish.digest(file),
                           baseline=baselines[os_name], signing='release', compatibility=COMPATIBILITY,
                           **package_platform(component, os_name, arch, baselines[os_name]))
                (root/(package+'.package.json')).write_text(json.dumps(row))
            self.assertEqual(len(publish.inventory(root, identity, EXPECTED)), 6)
            for package in EXPECTED:
                path = root/(package+'.package.json'); content = path.read_bytes(); path.unlink()
                with self.subTest(package=package), self.assertRaises(ValueError):
                    publish.inventory(root, identity, EXPECTED)
                path.write_bytes(content)

    def test_historical_intel_metadata_is_still_supported(self):
        for component in ('client', 'server'):
            self.assertEqual(package_platform(component, 'macos', 'x86_64', 'macOS 15')['platform']['architecture'], 'x86_64')
