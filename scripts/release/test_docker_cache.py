import pathlib
import tempfile
import unittest

import docker_cache
import native_cache


class DockerCacheTest(unittest.TestCase):
    def test_only_complete_exact_new_components_are_saved(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            component = root/'abseil'
            (component/'payload/source/.git').mkdir(parents=True)
            (component/'payload/prefix/lib').mkdir(parents=True)
            (component/'payload/prefix/lib/libabsl_base.a').write_bytes(b'library')
            native_cache.seal(component, 'key')
            self.assertEqual(docker_cache.ready(root, {'abseil': 'key'}, {}), {'abseil': 'true'})
            self.assertEqual(docker_cache.ready(root, {'abseil': 'other'}, {}), {})
            self.assertEqual(docker_cache.ready(root, {'abseil': 'key'}, {'abseil': True}), {})
            (component/'payload/prefix/lib/libabsl_base.a').write_bytes(b'corrupt')
            self.assertEqual(docker_cache.ready(root, {'abseil': 'key'}, {}), {})
