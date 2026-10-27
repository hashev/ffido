import pathlib
import tempfile
import unittest
import zipfile
import xml.etree.ElementTree as ET
from unittest.mock import patch

import android_sdk


class AndroidSDKTest(unittest.TestCase):
    def test_extract_rejects_traversal(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            archive = root/'bad.zip'
            with zipfile.ZipFile(archive, 'w') as package:
                package.writestr('../escaped', 'bad')
            target = root/'target'
            target.mkdir()
            with self.assertRaises(ValueError):
                android_sdk.extract(archive, target)
            self.assertFalse((root/'escaped').exists())

    def test_revision_and_locked_hit_do_not_download(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            (root/'emulator').mkdir()
            (root/'emulator/source.properties').write_text('Pkg.Revision = 1.2.3\n')
            (root/'emulator/.ffido-archive').write_text('hash')
            with patch.object(android_sdk.urllib.request, 'urlopen', side_effect=AssertionError('network')):
                android_sdk.install(root, 'emulator', {'android': {'emulator': {'revision': '1.2.3', 'sha1': 'hash'}}})
            package = ET.parse(root/'emulator/package.xml').getroot().find('localPackage')
            self.assertEqual(package.get('path'), 'emulator')
            self.assertEqual(package.findtext('revision/major'), '1')

    def test_corrupt_archive_does_not_replace_installed_sdk(self):
        import io
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            (root/'emulator').mkdir()
            (root/'emulator/keep').write_text('existing')
            with patch.object(android_sdk.urllib.request, 'urlopen', return_value=io.BytesIO(b'wrong')):
                with self.assertRaises(ValueError):
                    android_sdk.install(root, 'emulator', {'android': {'emulator': {
                        'revision': '1.2.3', 'sha1': 'wrong-checksum', 'url': 'https://dl.google.com/archive.zip'}}})
            self.assertEqual((root/'emulator/keep').read_text(), 'existing')
