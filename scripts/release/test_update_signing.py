import base64
import hashlib
import json
import os
import pathlib
import re
import copy
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from unittest.mock import patch

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat, PrivateFormat, NoEncryption

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import update_signing
from scripts.update.common import verify_manifest
from update_metadata import COMPATIBILITY, package_platform, release_metadata


class SigningTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        self.key = Ed25519PrivateKey.generate()
        self.public = base64.b64encode(self.key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()
        self.record = {'version': '1.0.0', 'build_number': 1001, 'sha': 'a'*40, 'tag': 'v1.0.0', 'stable': True}

    def row(self):
        package = self.root/'client.dmg'
        package.write_bytes(b'macOS archive fixture')
        return {**self.record, **package_platform('client', 'macos', 'arm64', 'macOS 15'),
                'compatibility': COMPATIBILITY, 'id': 'client-macos-arm64', 'file': package.name,
                'size': package.stat().st_size, 'sha256': hashlib.sha256(package.read_bytes()).hexdigest()}

    def test_signed_feed_and_archive_match_manifest(self):
        row = self.row()
        feeds = update_signing.appcasts(self.root, self.record, [row], self.key)
        raw = (self.root/feeds[0]['file']).read_bytes()
        content, block = raw.split(b'<!-- sparkle-signatures:')
        sig = re.search(rb'edSignature: (\S+)', block)[1]
        length = int(re.search(rb'length: (\d+)', block)[1])
        self.assertEqual(len(content), length)
        self.key.public_key().verify(base64.b64decode(sig), content)
        enclosure = ET.fromstring(content).find('./channel/item/enclosure')
        signature = enclosure.attrib['{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature']
        self.key.public_key().verify(base64.b64decode(signature), (self.root/row['file']).read_bytes())
        data = {**release_metadata(self.record), 'identity': self.record, 'packages': [row], 'macos_appcasts': feeds}
        update_signing.sign_manifest(self.root, data, 'test', self.key)
        for field, value in [('package_id', 'client-macos-x86_64'), ('file', '../feed.xml'), ('sha256', 'bad')]:
            invalid = copy.deepcopy(data)
            invalid['macos_appcasts'][0][field] = value
            with self.assertRaises(ValueError):
                update_signing.sign_manifest(self.root, invalid, 'test', self.key)
        manifest = (self.root/'release-manifest.json').read_bytes()
        signature = (self.root/'release-manifest.sig').read_bytes()
        self.assertEqual(verify_manifest(manifest, signature, {'test': self.public}), data)
        update_signing.sign_manifest(self.root, data, 'test', self.key)
        self.assertEqual((self.root/'release-manifest.sig').read_bytes(), signature)
        (self.root/row['file']).write_bytes(b'substituted')
        with self.assertRaises(ValueError):
            update_signing.appcasts(self.root, self.record, [row], self.key)

    def test_key_must_exist_and_match_installed_trust(self):
        (self.root/'scripts/update').mkdir(parents=True)
        (self.root/'scripts/release').mkdir(parents=True)
        (self.root/'scripts/release/settings.json').write_text('{}')
        path = self.root/'scripts/update/public_keys.json'
        path.write_text(json.dumps({'test': self.public}))
        private = base64.b64encode(self.key.private_bytes(Encoding.Raw, PrivateFormat.Raw, NoEncryption())).decode()
        with patch.object(update_signing, 'ROOT', self.root):
            for environment in [{}, {'FFIDO_UPDATE_KEY_ID': 'test'},
                                {'FFIDO_UPDATE_KEY_ID': 'unknown', 'FFIDO_UPDATE_PRIVATE_KEY': private}]:
                with patch.dict(os.environ, environment, clear=True), self.assertRaises(ValueError):
                    update_signing.load_key()
            with patch.dict(os.environ, {'FFIDO_UPDATE_KEY_ID': 'test', 'FFIDO_UPDATE_PRIVATE_KEY': private}, clear=True):
                self.assertEqual(update_signing.load_key()[0], 'test')
