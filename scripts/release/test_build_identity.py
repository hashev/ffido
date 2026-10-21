import base64
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from update_metadata import select_update_key

ROOT = pathlib.Path(__file__).resolve().parents[2]
PUBLIC = base64.b64encode(bytes([255])*32).decode()


class KeySelectionTest(unittest.TestCase):
    def test_selection_and_unconfigured_local_build(self):
        self.assertEqual(select_update_key({}, {}), ('', ''))
        self.assertEqual(select_update_key({'prod': PUBLIC}, {}), ('prod', PUBLIC))
        self.assertEqual(select_update_key({'old': PUBLIC, 'prod': PUBLIC}, {'update_key_id': 'prod'}), ('prod', PUBLIC))

    def test_unknown_ambiguous_empty_or_malformed_configuration_is_rejected(self):
        cases = [({'prod': PUBLIC}, {'update_key_id': 'typo'}),
                 ({'old': PUBLIC, 'prod': PUBLIC}, {}),
                 ({'prod': PUBLIC}, {'update_key_id': ''}),
                 ({}, {'update_key_id': 'prod'}),
                 ({'bad/id': PUBLIC}, {}), ({'prod': 'A'*42+'B='}, {'update_key_id': 'prod'}),
                 ({'prod': base64.b64encode(bytes(31)).decode()}, {}),
                 ({'prod': 123}, {}), ([], {}), ({}, [])]
        for keys, settings in cases:
            with self.subTest(keys=keys, settings=settings), self.assertRaises(ValueError):
                select_update_key(keys, settings)


class BuildIdentityTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        for directory in ['scripts/release', 'scripts/update', 'apps/frontend/assets/updates', 'apps/frontend/macos/Runner/Configs', 'build']:
            (self.root/directory).mkdir(parents=True)
        for name in ['build_identity.py', 'update_metadata.py']:
            shutil.copy2(ROOT/'scripts/release'/name, self.root/'scripts/release'/name)
        (self.root/'apps/frontend/pubspec.yaml').write_text('version: 1.0.0+1\n')
        self.outputs = [self.root/p for p in ['apps/frontend/assets/updates/identity.json', 'apps/frontend/assets/updates/public_keys.json', 'apps/frontend/macos/Runner/Configs/Updates.xcconfig', 'build/identity.json', 'github.env']]
        for p in self.outputs: p.write_text('preserve existing output')

    def execute(self, keys, settings):
        (self.root/'scripts/update/public_keys.json').write_text(json.dumps(keys))
        (self.root/'scripts/release/settings.json').write_text(json.dumps(settings))
        return subprocess.run([sys.executable, str(self.root/'scripts/release/build_identity.py')], cwd=ROOT, env={**os.environ, 'GITHUB_ENV': str(self.root/'github.env'), 'IDENTITY_JSON': ''}, capture_output=True, text=True)

    def test_bad_selection_fails_before_writing_any_outputs(self):
        before = {p: p.read_bytes() for p in self.outputs}
        result = self.execute({'prod': PUBLIC}, {'update_key_id': 'missing'})
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(all(p.read_bytes() == content for p, content in before.items()))

    def test_actual_generator_embeds_selected_key_and_escapes_slashes(self):
        result = self.execute({'prod': PUBLIC}, {'update_key_id': 'prod'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.outputs[1].read_bytes()), {'prod': PUBLIC})
        config = self.outputs[2].read_text()
        self.assertIn('FFIDO_UPDATE_PUBLIC_KEY = '+PUBLIC.replace('/', '$(FFIDO_UPDATE_SLASH)'), config)
        self.assertNotIn(PUBLIC, config)
