import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch
import generate_update_key as generator


class GenerateUpdateKeyTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = pathlib.Path(self.temporary.name)/'keys'

    def test_generate_and_repeat_verify_without_rotation(self):
        _, private, public = generator.prepare(self.directory, 'production-1')
        before = private.read_bytes()
        self.assertEqual(private.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.directory.stat().st_mode & 0o777, 0o700)
        self.assertEqual(list(json.loads(public.read_bytes())), ['production-1'])
        for check_only in [False, True]:
            with patch('cryptography.hazmat.primitives.asymmetric.ed25519.Ed25519PrivateKey.generate') as generate:
                generator.prepare(self.directory, 'production-1', check_only)
                generate.assert_not_called()
            self.assertEqual(private.read_bytes(), before)

    def test_check_missing_does_not_create_directory(self):
        with self.assertRaisesRegex(ValueError, 'does not exist'):
            generator.prepare(self.directory, 'production-1', True)
        self.assertFalse(self.directory.exists())

    def test_incomplete_pair_is_preserved(self):
        self.directory.mkdir(mode=0o700)
        private = self.directory/generator.PRIVATE_FILE
        private.write_bytes(b'keep this backup')
        with self.assertRaisesRegex(ValueError, 'Incomplete'):
            generator.prepare(self.directory, 'production-1')
        self.assertEqual(private.read_bytes(), b'keep this backup')
        self.assertFalse((self.directory/generator.PUBLIC_FILE).exists())

    def test_wrong_key_id_and_corrupt_public_do_not_replace_seed(self):
        _, private, public = generator.prepare(self.directory, 'production-1')
        before = private.read_bytes()
        with self.assertRaisesRegex(ValueError, 'does not match'):
            generator.prepare(self.directory, 'different-id')
        public.write_text('{}')
        with self.assertRaisesRegex(ValueError, 'does not match'):
            generator.prepare(self.directory, 'production-1')
        self.assertEqual(private.read_bytes(), before)

    def test_publicly_accessible_directory_is_rejected(self):
        self.directory.mkdir(mode=0o755)
        with self.assertRaisesRegex(ValueError, 'inaccessible'):
            generator.prepare(self.directory, 'production-1')
        self.assertFalse(list(self.directory.iterdir()))

    def test_repository_and_invalid_id_are_rejected(self):
        for directory, key_id in [(generator.ROOT/'keys', 'production-1'), (self.directory, 'invalid/id')]:
            with self.assertRaises(ValueError): generator.prepare(directory, key_id)
        self.assertFalse(self.directory.exists())

    def test_second_file_write_failure_removes_only_own_new_files(self):
        original = generator.os.open
        def open_file(path, *args):
            if pathlib.Path(path).name == generator.PUBLIC_FILE: raise OSError('disk full')
            return original(path, *args)
        with patch.object(generator.os, 'open', side_effect=open_file):
            with self.assertRaises(OSError): generator.prepare(self.directory, 'production-1')
        self.assertFalse(list(self.directory.iterdir()))

    def test_generated_format_is_accepted_by_release_signer(self):
        import os
        import update_signing
        _, private, public = generator.prepare(self.directory, 'production-1')
        repository = pathlib.Path(self.temporary.name)/'fixture-repository'
        (repository/'scripts/update').mkdir(parents=True)
        (repository/'scripts/release').mkdir(parents=True)
        (repository/'scripts/update/public_keys.json').write_bytes(public.read_bytes())
        (repository/'scripts/release/settings.json').write_text(json.dumps({'update_key_id': 'production-1'}))
        with patch.object(update_signing, 'ROOT', repository), patch.dict(os.environ, {'FFIDO_UPDATE_KEY_ID': 'production-1', 'FFIDO_UPDATE_PRIVATE_KEY': private.read_text()}, clear=True):
            key_id, key = update_signing.load_key()
        self.assertEqual(key_id, 'production-1')
        key.public_key().verify(key.sign(b'consumer format fixture'), b'consumer format fixture')
