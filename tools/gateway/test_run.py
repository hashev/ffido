"""Configuration contract tests, without starting a public listener."""
import pathlib
import tempfile
import unittest
from types import SimpleNamespace

from run import config


class GatewayConfigTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = pathlib.Path(self.directory.name)
        for name in ('fullchain.pem', 'privkey.pem', 'ca.pem'):
            (root / name).write_text('test material')
        self.args = SimpleNamespace(origin='https://hashev.github.io', certificate=str(root / 'fullchain.pem'),
            private_key=str(root / 'privkey.pem'), backend_ca=str(root / 'ca.pem'), backend_host='backend.example.org',
            port=8443, backend_port=8080)

    def test_loopback_default_and_explicit_public_listener_preserve_tls(self):
        local = config(self.args)
        public = config(self.args, '0.0.0.0')
        listener = public['static_resources']['listeners'][0]
        self.assertEqual(local['static_resources']['listeners'][0]['address']['socket_address']['address'], '127.0.0.1')
        self.assertEqual(listener['address']['socket_address']['address'], '0.0.0.0')
        tls = listener['filter_chains'][0]['transport_socket']['typed_config']['common_tls_context']
        self.assertTrue(tls['tls_certificates'][0]['certificate_chain']['filename'].endswith('fullchain.pem'))
        upstream = public['static_resources']['clusters'][0]['transport_socket']['typed_config']
        self.assertEqual(upstream['sni'], 'backend.example.org')
        validation = upstream['common_tls_context']['validation_context']
        self.assertEqual(validation['match_typed_subject_alt_names'][0]['matcher']['exact'], 'backend.example.org')
        manager = listener['filter_chains'][0]['filters'][0]['typed_config']
        cors = manager['route_config']['virtual_hosts'][0]['typed_per_filter_config']['envoy.filters.http.cors']
        self.assertEqual(cors['allow_origin_string_match'], [{'exact': 'https://hashev.github.io'}])
        self.assertIn('authorization', cors['allow_headers'])
        self.assertNotIn('access_log', manager)

    def test_invalid_origin_listener_and_missing_material_fail_closed(self):
        for address in ('', 'node.example.org', '0.0.0.0\n', '999.0.0.1'):
            with self.subTest(address=address), self.assertRaises(ValueError):
                config(self.args, address)
        for origin in ('http://hashev.github.io', 'https://hashev.github.io/ffido/', 'https://user:pass@hashev.github.io'):
            self.args.origin = origin
            with self.subTest(origin=origin), self.assertRaises(ValueError):
                config(self.args)
        self.args.origin = 'https://hashev.github.io'
        self.args.certificate = str(pathlib.Path(self.directory.name) / 'missing.pem')
        with self.assertRaises(FileNotFoundError):
            config(self.args)


if __name__ == '__main__':
    unittest.main()
