"""Registration and signed-sequence tests use ephemeral keys and isolated state."""
import base64
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from types import SimpleNamespace

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

import discovery
import pair_update
from test_common import manifest


class PairTrustTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.key = Ed25519PrivateKey.generate()
        self.keys = {'qa': base64.b64encode(self.key.public_key().public_bytes(
            Encoding.Raw, PublicFormat.Raw)).decode()}
        self.previous = self.release(1065)
        (self.root/'previous.json').write_bytes(self.previous)
        (self.root/'previous.sig').write_bytes(self.sign(self.previous))
        self.plan = {'signed_floor': {'manifest': str(self.root/'previous.json'),
                                     'signature': str(self.root/'previous.sig')}}

    def sign(self, raw):
        return json.dumps({'algorithm': 'Ed25519', 'key_id': 'qa',
                           'signature': base64.b64encode(self.key.sign(raw)).decode()}).encode()

    def release(self, sequence):
        value = manifest()
        value['identity']['build_number'] = sequence
        value['packages'][0]['build_number'] = sequence
        value['update_sequence'] = sequence
        identity = value['identity']
        value['container'] = {'image': 'docker.io/hashev/ffido', 'digest': 'sha256:'+'b'*64,
                              'sha': identity['sha'], 'release_tag': identity['tag'],
                              'version': identity['version'], 'tag': identity['tag'][1:]}
        return json.dumps(value).encode()

    def test_floor_is_authenticated_not_local_build_and_never_decreases(self):
        self.plan['source'] = {'backend': {'build': {'build_number': 2026111804}}}
        floor = pair_update.signed_floor(self.plan, self.root, self.keys)
        self.assertEqual(floor, 1065)
        raw = self.release(1066)
        selected = discovery.selected(raw, self.sign(raw), self.keys, 'v1.0.0', 'stable', floor)
        self.assertEqual(selected['update_sequence'], 1066)
        pair_update.commit_floor(self.root, 1066)
        pair_update.commit_floor(self.root, 1065)
        self.assertEqual(pair_update.signed_floor(self.plan, self.root, self.keys), 1066)
        for sequence in (1001, 1065):
            raw = self.release(sequence)
            with self.assertRaises(ValueError):
                discovery.selected(raw, self.sign(raw), self.keys, 'v1.0.0', 'stable', 1066)

    def test_explicit_target_still_requires_signature_identity_channel(self):
        raw = self.release(1066)
        signature = self.sign(raw)
        for data, tag, channel in [(raw+b' ', 'v1.0.0', 'stable'),
                                   (raw, 'v9.0.0', 'stable'), (raw, 'v1.0.0', 'dev')]:
            with self.subTest(tag=tag, channel=channel), self.assertRaises(ValueError):
                discovery.selected(data, signature, self.keys, tag, channel, 1065)
        with self.assertRaises(ValueError):
            pair_update.signed_floor(self.plan, self.root, {})

    def test_legacy_signed_sequence_is_not_reset(self):
        (self.root/'sequence.json').write_text('{"value":1070}')
        self.assertEqual(pair_update.signed_floor(self.plan, self.root, self.keys), 1070)

    def test_recovery_reauthenticates_already_committed_target_without_lowering_floor(self):
        raw = self.release(1066)
        (self.root/'target.json').write_bytes(raw)
        (self.root/'target.sig').write_bytes(self.sign(raw))
        pair_update.commit_floor(self.root, 1066)
        (self.root/'pair-operation.json').write_text('{"sequence":1066}')
        args = SimpleNamespace(target_manifest=self.root/'target.json',
                               target_signature=self.root/'target.sig', target_tag='v1.0.0',
                               channel='stable', action='rollback')
        self.assertEqual(pair_update.target(args, self.plan, self.root, self.keys)[0]['update_sequence'], 1066)
        (self.root/'target.json').write_bytes(self.release(1065))
        (self.root/'target.sig').write_bytes(self.sign(self.release(1065)))
        with self.assertRaises(ValueError):
            pair_update.target(args, self.plan, self.root, self.keys)
        self.assertEqual(pair_update.signed_floor(self.plan, self.root, self.keys), 1066)

    def test_accepted_pair_requires_signed_provenance_and_exact_images(self):
        raw = self.release(1066)
        selected = json.loads(raw)
        build = {**selected['identity'], 'compatibility': selected['compatibility']}
        actual = {role: {'image_id': 'sha256:'+letter*64, 'build': build, 'platform': 'linux/amd64'}
                  for role, letter in [('backend', 'a'), ('tosser', 'b')]}
        evidence = pair_update.save_signed(self.root, raw, self.sign(raw))
        (self.root/'pair-provenance.json').write_text(json.dumps({'signed': evidence, 'source': actual, 'build': build}))
        config = self.root/'operator.json'; config.write_bytes(b'configuration')
        plan = {'source': {'registered-local': {}},
                'files': {str(config): hashlib.sha256(config.read_bytes()).hexdigest()}}
        adopted, identity = pair_update.accepted_source(plan, self.root, self.keys, actual, set())
        self.assertEqual(adopted['source'], actual)
        self.assertEqual(identity, selected['identity'])
        changed = copy.deepcopy(actual); changed['tosser']['image_id'] = 'sha256:'+'c'*64
        with self.assertRaises(ValueError):
            pair_update.accepted_source(plan, self.root, self.keys, changed, set())
        config.write_bytes(b'changed')
        with self.assertRaises(ValueError):
            pair_update.accepted_source(plan, self.root, self.keys, actual, set())

    def test_automatic_mode_requires_promoted_source_and_every_pause_guard(self):
        marker = self.root/'manual-deployment.json'
        marker.write_text('{"automatic_apply_paused":true}')
        plan = {'automatic_guards': {'pause_files': [str(marker)],
                                    'block_if_exists': [str(self.root/'legacy-guard')]}}
        for installed in (None, {'tag': 'v1.0.28'}):
            with self.assertRaises(ValueError):
                pair_update.automatic_allowed(plan, installed)
        marker.write_text('{"automatic_apply_paused":false}')
        pair_update.automatic_allowed(plan, {'tag': 'v1.0.28'})
        (self.root/'legacy-guard').touch()
        with self.assertRaises(ValueError):
            pair_update.automatic_allowed(plan, {'tag': 'v1.0.28'})
