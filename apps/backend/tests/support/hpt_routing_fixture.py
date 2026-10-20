"""Isolated HPT compatibility fixture; no installed config, mailer or network."""
import json
import os
import pathlib
import struct
import subprocess
import sys
import tempfile


def packet(rows, shared_id=False):
    data = bytearray(58)
    for offset, value in {0: 9, 2: 2, 4: 2026, 6: 9, 8: 17, 18: 2, 20: 1,
                          22: 1, 34: 2, 36: 2, 44: 1, 46: 2, 48: 2}.items():
        struct.pack_into('<H', data, offset, value)
    data[40:42] = b'\0\1'
    for tag, node, point in rows:
        serial = '12345678' if shared_id and tag in ('p1', 'p2') else tag
        text = f'\1INTL 2:1/{node} 2:1/9\r\1FMPT 7\r'
        if point:
            text += f'\1TOPT {point}\r'
        text += f'\1MSGID: 2:1/9.7 {serial}\r\1CHRS: CP866 2\rMarker {tag}\r'
        data += struct.pack('<7H', 2, 9, node, 1, 1, 1, 0)
        data += b'17 Oct 26  16:10:00\0Same Name\0Remote\0'
        data += tag.encode() + b'\0' + text.encode() + b'\0'
    return data + b'\0\0'


def records(base):
    """Decode actual wire bytes independently of FFIDO and SMAPI enums."""
    index_path = base.with_suffix('.jdx')
    if not index_path.exists():
        return []
    index = index_path.read_bytes()
    headers = base.with_suffix('.jhr').read_bytes()
    text = base.with_suffix('.jdt').read_bytes()
    result = []
    for slot in range(len(index) // 8):
        offset = struct.unpack_from('<I', index, slot * 8 + 4)[0]
        if offset == 0xffffffff:
            continue
        flags = struct.unpack_from('<I', headers, offset + 52)[0]
        if flags & 0x80000000:
            continue
        fields = {}
        position = offset + 76
        end = position + struct.unpack_from('<I', headers, offset + 8)[0]
        while position < end:
            low, high, length = struct.unpack_from('<HHI', headers, position)
            position += 8
            assert high == 0 and position + length <= end
            fields.setdefault(low, []).append(headers[position:position + length])
            position += length
        start, length = struct.unpack_from('<II', headers, offset + 60)
        result.append((flags, fields, text[start:start + length]))
    return result


class RoutingFixture:
    def __init__(self, root, mode, hpt, wrapper):
        self.root, self.hpt, self.wrapper = root, hpt, wrapper
        root.mkdir()
        directories = [('Inbound', 'inbound'), ('ProtInbound', 'protinbound'),
                       ('Outbound', 'outbound'), ('TempInbound', 'tmpin'),
                       ('TempOutbound', 'tmpout'), ('LogFileDir', 'logs'),
                       ('DupeHistoryDir', 'dupes'), ('NodelistDir', 'nodelist')]
        config = 'Name FFIDO isolated routing\nSysop Test\nLocation Test\nAddress 2:1/2\n'
        for key, directory in directories:
            (root / directory).mkdir()
            config += f'{key} {root / directory}\n'
        config += f'MsgBaseDir {root}\nEchoTossLog {root}/logs/toss.log\n'
        for name, address in [('Remote', '2:1/9'), ('P1', '2:1/2.1'), ('P2', '2:1/2.2')]:
            config += (f'Link {name}\nAKA {address}\nOurAKA 2:1/2\n'
                       'AllowEmptyPktPwd on\nPassword fixture\n')
        dupe = 'off' if mode == 'dedup-off' else 'del'
        config += f'NetmailArea INGRESS {root}/ingress -b JAM -dupeCheck {dupe} -dupeHistory 7\n'
        config += f'BadArea BAD {root}/bad -b JAM\nDupeArea DUPE {root}/dupe -b JAM\n'
        if mode == 'foreign-aka':
            config += f'NetmailArea P1 {root}/p1 -b JAM -a 2:1/2.1\n'
        if mode in ('keep', 'nopack', 'nopack-priority', 'locked'):
            config += 'KeepTrsMail on\n'
        if mode in ('nopack', 'nopack-priority', 'locked'):
            config += 'Route nopack 2:1/2.1 2:1/2.2\n'
        config += 'Route normal noroute *\n'
        (root / 'hpt.cfg').write_text(config)
        (root / 'wrapper.json').write_text(json.dumps({'ftn': {'coordination_lock': str(root / 'hpt.lock')}}))

    def run(self, *arguments):
        process = subprocess.run([sys.executable, self.wrapper, '--config', str(self.root / 'wrapper.json'),
                                  '--timeout', '10', '--', self.hpt, '-c', str(self.root / 'hpt.cfg'),
                                  *arguments], capture_output=True, timeout=20)
        assert process.returncode == 0, process.stdout + process.stderr

    def outbound(self):
        return b''.join(p.read_bytes() for p in sorted((self.root / 'outbound').rglob('*')) if p.is_file())


def main():
    hpt = os.environ.get('FFIDO_TEST_HPT')
    if not hpt:
        print('Set FFIDO_TEST_HPT to enable isolated routing fixtures')
        return 77
    wrapper = sys.argv[1]
    expectations = {'normal': (5, 1, 1), 'keep': (5, 5, 1), 'nopack': (5, 5, 0),
                    'nopack-priority': (5, 5, 1), 'locked': (5, 5, 0),
                    'dedup-del': (4, 1, 1), 'dedup-off': (5, 1, 1)}
    with tempfile.TemporaryDirectory(prefix='ffido-hpt-routing-test-') as directory:
        root = pathlib.Path(directory)
        for mode in [*expectations, 'foreign-aka']:
            fixture = RoutingFixture(root / mode, mode, hpt, wrapper)
            incoming = packet([('p1', 2, 1), ('p2', 2, 2), ('boss', 2, 0),
                               ('unknown', 2, 9), ('transit', 7, 1)], mode.startswith('dedup'))
            (fixture.root / 'protinbound' / 'input.pkt').write_bytes(incoming)
            if mode == 'foreign-aka':
                result = subprocess.run([hpt, '-c', str(fixture.root / 'hpt.cfg'), 'toss'],
                                        capture_output=True, timeout=20)
                assert result.returncode == 78
                assert not records(fixture.root / 'ingress')
                assert not fixture.outbound()
                continue
            fixture.run('toss')
            before = records(fixture.root / 'ingress')
            assert len(before) == expectations[mode][0], mode
            assert before[0][1][0] == [b'2:1/9.7']
            assert before[0][1][1] == [b'2:1/2.1']
            if mode != 'dedup-del':
                assert before[1][1][1] == [b'2:1/2.2']
                assert before[0][1][3] == before[1][1][3] == [b'Same Name']
            if mode in ('nopack-priority', 'locked'):
                path = fixture.root / 'ingress.jhr'
                headers = bytearray(path.read_bytes())
                index = (fixture.root / 'ingress.jdx').read_bytes()
                for slot in (0, 1):
                    offset = struct.unpack_from('<I', index, slot * 8 + 4)[0] + 52
                    flags = struct.unpack_from('<I', headers, offset)[0] | 0x100
                    if mode == 'locked':
                        flags |= 0x40000000
                    struct.pack_into('<I', headers, offset, flags)
                path.write_bytes(headers)
            fixture.run('pack')
            assert len(records(fixture.root / 'ingress')) == expectations[mode][1], mode
            packed = fixture.outbound()
            assert packed.count(b'Marker p1') == expectations[mode][2], mode
            assert packed.count(b'Marker p2') == (0 if mode == 'dedup-del' else expectations[mode][2]), mode
            assert b'Marker boss' not in packed
            assert packed.count(b'Marker unknown') == packed.count(b'Marker transit') == 1
            fixture.run('pack')
            assert fixture.outbound() == packed, mode
            if mode == 'nopack':
                (fixture.root / 'protinbound' / 'repeat.pkt').write_bytes(incoming)
                fixture.run('toss')
                assert len(records(fixture.root / 'ingress')) == 5
                (fixture.root / 'body.txt').write_text('Outgoing marker\n')
                fixture.run('post', '-nf', 'Same Name', '-nt', 'Remote', '-af', '2:1/2.1',
                            '-at', '2:1/9.7', '-s', 'outgoing', '-f', 'pvt loc', str(fixture.root / 'body.txt'))
                fixture.run('pack')
                outgoing = records(fixture.root / 'ingress')[-1]
                assert outgoing[1][0] == [b'2:1/2.1'] and outgoing[1][1] == [b'2:1/9.7']
                assert outgoing[0] & 0x10
                packed = fixture.outbound()
                fixture.run('pack')
                assert fixture.outbound() == packed and packed.count(b'Outgoing marker') == 1
            print(mode, 'passed')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
