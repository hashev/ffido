from pathlib import Path
import tempfile
import unittest

import native_cache
from cache_report import reason


class NativeCacheTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.component = self.root/'abseil'
        payload = self.component/'payload'
        (payload/'prefix/lib').mkdir(parents=True)
        (payload/'source/.git').mkdir(parents=True)
        (payload/'source/source.c').write_text('source')
        (payload/'prefix/lib/libabsl_base.a').write_bytes(b'library')

    def test_complete_and_changed_inputs(self):
        self.assertFalse(native_cache.verify(self.component, 'a'))
        native_cache.seal(self.component, 'a')
        self.assertTrue(native_cache.verify(self.component, 'a'))
        self.assertFalse(native_cache.verify(self.component, 'b'))
        (self.component/'payload/source/source.c').write_text('modified')
        self.assertFalse(native_cache.verify(self.component, 'a'))

    def test_corrupt_missing_and_extra_files(self):
        native_cache.seal(self.component, 'a')
        path = self.component/'payload/prefix/lib/libabsl_base.a'
        path.write_bytes(b'bad')
        self.assertFalse(native_cache.verify(self.component, 'a'))
        self.assertIn('libabsl_base.a', reason(self.component, 'a'))
        path.unlink()
        self.assertFalse(native_cache.verify(self.component, 'a'))
        path.write_bytes(b'library')
        (self.component/'payload/unexpected').write_text('unexpected')
        self.assertFalse(native_cache.verify(self.component, 'a'))

    def test_relocation_and_collision(self):
        native_cache.seal(self.component, 'a')
        prefix, source = self.root/'other-checkout/prefix', self.root/'other-checkout/source'
        native_cache.assemble(self.component, prefix, source)
        self.assertEqual((prefix/'lib/libabsl_base.a').read_bytes(), b'library')
        self.assertEqual((source/'source.c').read_text(), 'source')
        native_cache.assemble(self.component, prefix, source)
        (prefix/'lib/libabsl_base.a').write_bytes(b'collision')
        with self.assertRaises(ValueError):
            native_cache.assemble(self.component, prefix, source)

    def test_escape_and_executable_mutation(self):
        path = self.component/'payload/prefix/lib/libabsl_base.a'
        native_cache.seal(self.component, 'a')
        path.chmod(0o755)
        self.assertFalse(native_cache.verify(self.component, 'a'))
        (self.component/'payload/leak').symlink_to(self.root)
        with self.assertRaises(ValueError):
            native_cache.seal(self.component, 'a')
