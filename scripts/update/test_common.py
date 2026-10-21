import base64
import copy
import hashlib
import io
import json
import pathlib
import tarfile
import tempfile
import unittest
import zipfile
from unittest.mock import patch

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
from scripts.update import common


def identity(version='1.0.0', number=1001, stable=True):
    return {'version': version, 'build_number': number, 'sha': 'a'*40, 'stable': stable,
            'tag': 'v'+version+('' if stable else f'-dev.{number}.aaaaaaaaaaaa')}


def manifest():
    record = identity()
    compatibility = {'protocol_major': 1, 'client_protocol_min': 1, 'client_protocol_max': 1,
                     'server_protocol_min': 1, 'server_protocol_max': 1,
                     'state_schema_min': 9, 'state_schema_max': 9,
                     'config_format': 1, 'jam_format': 'JAM-1'}
    package = {**record, 'id': 'client-android-universal', 'component': 'client',
               'platform': {'os': 'android', 'architecture': 'universal'},
               'min_os': {'api': 24}, 'signing': 'release', 'compatibility': compatibility,
               'file': 'client.apk', 'size': 3, 'sha256': hashlib.sha256(b'apk').hexdigest()}
    return {'schema_version': 1, 'identity': record, 'channel': 'stable', 'update_sequence': 1001,
            'compatibility': compatibility, 'packages': [package]}


class SignatureTest(unittest.TestCase):
    def setUp(self):
        # Ephemeral test keys are never installed into production trust stores.
        self.key = Ed25519PrivateKey.generate()
        self.keys = {'test': base64.b64encode(self.key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()}

    def sign(self, raw):
        return json.dumps({'algorithm': 'Ed25519', 'key_id': 'test',
                           'signature': base64.b64encode(self.key.sign(raw)).decode()}).encode()

    def test_exact_bytes_signature_and_replay(self):
        raw = json.dumps(manifest()).encode()
        signature = self.sign(raw)
        self.assertEqual(common.verify_manifest(raw, signature, self.keys), manifest())
        for data, sig, keys, sequence in [(raw+b' ', signature, self.keys, 0),
                                        (raw, signature, {}, 0),
                                        (raw, b'{}', self.keys, 0),
                                        (raw, signature, self.keys, 1002)]:
            with self.subTest(sequence=sequence), self.assertRaises(ValueError):
                common.verify_manifest(data, sig, keys, sequence)

    def test_signed_but_invalid_schema_identity_or_inventory(self):
        for key, value in [('schema_version', 2), ('schema_version', True), ('channel', 'dev'),
                           ('packages', []), ('update_sequence', 1000), ('compatibility', {})]:
            record = manifest()
            record[key] = value
            raw = json.dumps(record).encode()
            with self.subTest(key=key), self.assertRaises(ValueError):
                common.verify_manifest(raw, self.sign(raw), self.keys)
        for update in [{'size': True}, {'file': '../secret'}, {'stable': False},
                       {'platform': {'os': 'android', 'architecture': 'arm64'}},
                       {'signing': 'debug'}, {'min_os': {}}, {'compatibility': {}}, {'sha256': 'bad'}]:
            record = manifest()
            record['packages'][0].update(update)
            with self.subTest(update=update), self.assertRaises(ValueError):
                common.validate_manifest(record)
        record = manifest()
        record['packages'] *= 2
        with self.assertRaises(ValueError):
            common.validate_manifest(record)

    def test_nonfinite_duplicate_and_oversized_json(self):
        for raw in [b'{"a":1,"a":2}', b'{"a":NaN}', b'[]', b'\xff', b' '*(common.MAX_METADATA+1)]:
            with self.subTest(raw=raw[:20]), self.assertRaises(ValueError):
                common.strict_json(raw)


class VersionTest(unittest.TestCase):
    def test_semver_channels_builds_and_android(self):
        self.assertTrue(common.newer(identity('1.10.0'), identity('1.9.0'), 'stable'))
        self.assertFalse(common.newer(identity('1.9.0'), identity('1.10.0'), 'stable'))
        self.assertFalse(common.newer(identity('2.0.0', stable=False), identity(), 'stable'))
        self.assertTrue(common.newer(identity('2.0.0', stable=False), identity(), 'dev'))
        self.assertTrue(common.newer(identity(number=1002, stable=False), identity(stable=False), 'dev'))
        self.assertTrue(common.newer(identity(number=1002), identity(stable=False), 'dev'))
        self.assertFalse(common.newer(identity('2.0.0', number=1000), identity(), 'dev', android=True))
        self.assertFalse(common.newer(identity(), {**identity(), 'tag': 'v1.0.0-check.aaaaaaaaaaaa'}, 'stable'))
        self.assertFalse(common.newer(identity(), identity(), 'stable'))

    def test_invalid_numeric_fields_and_tags(self):
        for change in [{'version': '01.0.0'}, {'build_number': True}, {'stable': 'false'}, {'tag': 'latest'}]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                common.version_key({**identity(), **change})


class TransportTest(unittest.TestCase):
    def test_url_boundaries(self):
        self.assertEqual(common.asset_url('v1.0.0', 'client.apk'),
                         'https://github.com/hashev/ffido/releases/download/v1.0.0/client.apk')
        for url in ['http://github.com/hashev/ffido/releases/x', 'https://github.com/other/repo/releases/x',
                    'https://github.com.evil.test/x', 'https://github.com:444/hashev/ffido/releases/x',
                    'https://user:password@github.com/hashev/ffido/releases/x', 'file:///etc/passwd',
                    'https://api.github.com/repos/other/repo/releases', 'https://example.com/x']:
            with self.subTest(url=url), self.assertRaises(ValueError):
                common.validate_https(url)
        for name in ['../x', '/x', '..', 'x/y', 'x\\y', 'x?token=y']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                common.asset_url('v1.0.0', name)

    def test_redirect_rejects_untrusted_destination(self):
        request = common.urllib.request.Request(common.asset_url('v1.0.0', 'client.apk'))
        with self.assertRaises(ValueError):
            common.UpdateRedirect().redirect_request(request, None, 302, '', {}, 'https://evil.test/apk')

    def test_response_limit_and_network_failure(self):
        opener = unittest.mock.Mock()
        opener.open.return_value = io.BytesIO(b'abcd')
        with patch.object(common.urllib.request, 'build_opener', return_value=opener):
            with self.assertRaises(ValueError):
                common.fetch(common.asset_url('v1.0.0', 'client.apk'), limit=3)
        opener.open.side_effect = TimeoutError('fixture timeout')
        with patch.object(common.urllib.request, 'build_opener', return_value=opener), self.assertRaises(TimeoutError):
            common.fetch(common.asset_url('v1.0.0', 'client.apk'))

    def test_download_is_atomic_and_checks_size_and_digest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            package = manifest()['packages'][0]
            opener = unittest.mock.Mock()
            for raw in [b'apk', b'ap', b'bad', b'apk extra']:
                opener.open.side_effect = lambda *args, **kwargs: io.BytesIO(raw)
                with patch.object(common.urllib.request, 'build_opener', return_value=opener):
                    if raw == b'apk':
                        result = common.download(package, root)
                        self.assertEqual(result.read_bytes(), b'apk')
                    else:
                        with self.assertRaises(ValueError):
                            common.download(package, root)
                        self.assertEqual((root/'client.apk').read_bytes(), b'apk')
                self.assertEqual([p.name for p in root.iterdir()], ['client.apk'])


class DiscoveryTest(unittest.TestCase):
    def test_old_candidates_do_not_block_current_candidate_but_stale_only_fails(self):
        import discovery
        key = Ed25519PrivateKey.generate()
        keys = {'qa': base64.b64encode(key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()}
        rows, contents = [], {}
        for version, number in [('2.0.0', 1002), ('3.0.0', 1003)]:
            data = manifest(); record = identity(version, number)
            data.update(identity=record, update_sequence=number)
            data['packages'][0].update(record)
            raw = json.dumps(data).encode()
            signature = json.dumps({'algorithm': 'Ed25519', 'key_id': 'qa', 'signature': base64.b64encode(key.sign(raw)).decode()}).encode()
            assets = []
            for name, value in [('release-manifest.json', raw), ('release-manifest.sig', signature), ('client.apk', b'apk')]:
                url = common.asset_url(record['tag'], name); contents[url] = value
                assets.append({'name': name, 'browser_download_url': url, 'size': len(value)})
            rows.append({'draft': False, 'prerelease': False, 'tag_name': record['tag'], 'assets': assets})
        def fetch(url, **kwargs):
            return json.dumps(rows).encode() if url.startswith('https://api.github.com/') else contents[url]
        # Old releases signed with a retired key are not fetched at all.
        rows.append({'draft': False, 'prerelease': False, 'tag_name': 'v1.0.0', 'assets': [
            {'name': name, 'browser_download_url': common.asset_url('v1.0.0', name)}
            for name in ['release-manifest.json', 'release-manifest.sig']]})
        for ordered in [rows[:], list(reversed(rows))]:
            rows[:] = ordered
            selected = discovery.releases(identity(), keys, 'stable', 1003, fetch=fetch)
            self.assertEqual([item[0]['identity']['tag'] for item in selected], ['v3.0.0'])
        rows[:] = [row for row in rows if row['tag_name'] == 'v2.0.0']
        with self.assertRaisesRegex(ValueError, 'Stale'):
            discovery.releases(identity(), keys, 'stable', 1003, fetch=fetch)


class ArchiveTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        self.archive = self.root/'package.tar.gz'
        self.target = self.root/'staged'

    def tar(self, files, links=()):
        with tarfile.open(self.archive, 'w:gz') as archive:
            for name, data in files:
                member = tarfile.TarInfo(name)
                member.size = len(data)
                member.mode = 0o4755
                archive.addfile(member, io.BytesIO(data))
            for name, target in links:
                member = tarfile.TarInfo(name)
                member.type, member.linkname = tarfile.SYMTYPE, target
                archive.addfile(member)

    def test_full_bundle_with_safe_native_link(self):
        self.tar([('bundle/bin/server', b'bin'), ('bundle/lib/liba.so.1', b'lib')],
                 [('bundle/lib/liba.so', 'liba.so.1')])
        common.safe_extract(self.archive, self.target)
        self.assertEqual((self.target/'bundle/lib/liba.so').read_bytes(), b'lib')
        self.assertEqual((self.target/'bundle/bin/server').stat().st_mode & 0o7777, 0o755)

    def test_zip_bundle(self):
        with zipfile.ZipFile(self.archive, 'w') as archive:
            archive.writestr('fido.exe', b'executable')
            archive.writestr('data/asset', b'data')
        common.safe_extract(self.archive, self.target)
        self.assertEqual((self.target/'data/asset').read_bytes(), b'data')

    def test_traversal_absolute_duplicates_symlinks_and_limits(self):
        cases = [([('../outside', b'x')], []), ([('/absolute', b'x')], []),
                 ([('C:/windows', b'x')], []), ([('.. /outside', b'x')], []), ([('CON.txt', b'x')], []), ([('a', b'x'), ('a', b'y')], []),
                 ([], [('link', '../outside')]), ([('link/child', b'x')], [('link', 'dir')])]
        for files, links in cases:
            with self.subTest(files=files, links=links):
                self.tar(files, links)
                with self.assertRaises(ValueError):
                    common.safe_extract(self.archive, self.target)
                self.assertFalse(self.target.exists())
        self.tar([('x', b'too big')])
        with self.assertRaises(ValueError):
            common.safe_extract(self.archive, self.target, max_size=2)
        with self.assertRaises(ValueError):
            common.safe_extract(self.archive, self.target, max_members=0)
        self.assertFalse(self.target.exists())
        self.assertFalse((self.root/'outside').exists())

    def test_existing_destination_is_never_removed(self):
        self.tar([('x', b'x')])
        self.target.mkdir()
        (self.target/'private').write_text('keep')
        with self.assertRaises(ValueError):
            common.safe_extract(self.archive, self.target)
        self.assertEqual((self.target/'private').read_text(), 'keep')


if __name__ == '__main__':
    unittest.main()
