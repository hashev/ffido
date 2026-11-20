import struct
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import pair_acceptance
import pair_probe


class PairProbeTest(unittest.TestCase):
    def test_acceptance_checks_read_state_without_recording_another_view(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'.ffido-isolated-pair-fixture').write_text('qa')
            state = root/'fixture.json'
            state.write_text(json.dumps({'tokens': ['first', 'second'], 'own': ['own1', 'own2'],
                'crosspost': '0801', 'crossed': '0801', 'commit': '0801',
                'committed': '0801', 'reference': '0a0451412e41120131'}))
            config = {'endpoint': 'https://localhost:9999', 'ca': 'ca.pem', 'origin': 'https://hashev.github.io',
                      'isolated': True, 'root': str(root), 'isolation_id': 'qa', 'state': str(state)}
            for read in (True, False):
                def call(endpoint, ca, origin, method, payload, token, status):
                    if method == 'GetConference':
                        own = pair_acceptance.fields(payload)[1][0].decode()
                        if own != {'first': 'own1', 'second': 'own2'}[token]:
                            raise pair_probe.GrpcError(7)
                    elif method in {'GetTelegramBinding', 'CreateCrosspost', 'CommitUue'}:
                        return b'\x08\x01'
                    elif method == 'ReadArchiveMessage':
                        return pair_acceptance.field(1, pair_acceptance.field(11, int(read)))
                    elif method != 'RestoreSession':
                        self.fail('Unexpected or state-changing probe '+method)
                    return b''
                with patch.object(pair_probe, 'gateway'), patch.object(pair_probe, 'call', side_effect=call), \
                     contextlib.redirect_stdout(io.StringIO()):
                    if read:
                        pair_acceptance.run(config, 'verify-source')
                    else:
                        with self.assertRaisesRegex(ValueError, 'Read state lost'):
                            pair_acceptance.run(config, 'verify-source')

    def invoke(self, data, status='0', origin='https://hashev.github.io'):
        response = Mock(status=200)
        response.getheader.side_effect = lambda name: {'grpc-status': status,
            'access-control-allow-origin': origin}.get(name)
        response.read.return_value = data
        connection = Mock()
        connection.getresponse.return_value = response
        with patch.object(pair_probe.http.client, 'HTTPSConnection', return_value=connection), \
             patch.object(pair_probe.ssl, 'create_default_context'):
            return pair_probe.call('https://localhost:9999', 'ca.pem', 'https://hashev.github.io',
                                   'GetServerCapabilities')

    def test_real_grpc_web_framing_and_trailers(self):
        trailers = b'grpc-status:0\r\n'
        raw = b'\0'+struct.pack('>I', 2)+b'\x08\x01'+b'\x80'+struct.pack('>I', len(trailers))+trailers
        self.assertEqual(self.invoke(raw, status=None), b'\x08\x01')

    def test_malformed_status_frames_and_wildcard_cors_fail_closed(self):
        for data in (b'\0\0', b'\0'+struct.pack('>I', 100), b'\x40'+struct.pack('>I', 0)):
            with self.subTest(data=data), self.assertRaises(ValueError):
                self.invoke(data)
        with self.assertRaises(ValueError): self.invoke(b'', origin='*')
        with self.assertRaisesRegex(ValueError, '^Invalid gRPC status$'):
            self.invoke(b'', status='do-not-print-server-value')
        with self.assertRaises(pair_probe.GrpcError) as error:
            self.invoke(b'', status='7')
        self.assertEqual(error.exception.status, 7)

    def test_fixture_wire_handles_binary_unicode_and_repeated_fields(self):
        raw = pair_acceptance.field(1, 'Проверка')+pair_acceptance.field(2, b'\0\xff')
        raw += pair_acceptance.field(3, 2**40)+pair_acceptance.field(1, 'repeat')
        parsed = pair_acceptance.fields(raw)
        self.assertEqual(parsed[1], ['Проверка'.encode(), b'repeat'])
        self.assertEqual(parsed[2], [b'\0\xff'])
        self.assertEqual(parsed[3], [2**40])
        for invalid in (b'\x80'*11, b'\x0a\x05x', b'\0\0'):
            with self.assertRaises(ValueError): pair_acceptance.fields(invalid)
