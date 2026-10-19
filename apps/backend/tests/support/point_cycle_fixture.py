"""Actual HPT toss/pack plus FFIDO dispatch, only synthetic temporary mail."""
import fcntl
import json
import os
import pathlib
import sqlite3
import struct
import subprocess
import sys
import tempfile
from hpt_routing_fixture import RoutingFixture, packet, records


def empty_jam(base):
    header = bytearray(1024)
    header[:4] = b'JAM\0'
    struct.pack_into('<I', header, 4, 123)
    struct.pack_into('<I', header, 16, 0xffffffff)
    struct.pack_into('<I', header, 20, 1)
    base.with_suffix('.jhr').write_bytes(header)
    for extension in ('.jdt', '.jdx'):
        base.with_suffix(extension).write_bytes(b'')


def main():
    hpt = os.environ.get('FFIDO_TEST_HPT')
    if not hpt:
        return 77
    admin, wrapper = sys.argv[1:3]
    mapped = "--mapped" in sys.argv[3:]
    with tempfile.TemporaryDirectory(prefix='ffido-point-cycle-') as directory:
        fixture = RoutingFixture(pathlib.Path(directory) / 'fixture', 'nopack', hpt, wrapper)
        root = fixture.root
        config = (root / 'hpt.cfg').read_text().replace('-dupeCheck del', '-dupeCheck off')
        config += f'PackNetMailOnScan off\nNetmailArea OUT {root}/out -b JAM -dupeCheck off\n'
        config += 'Link Ordinary\nAKA 2:1/2.3\nOurAKA 2:1/2\nPassword fixture3\nAllowEmptyPktPwd on\n'
        if mapped:
            config += f'Include {root}/areas.cfg\n'
        (root / 'hpt.cfg').write_text(config)
        (root / 'areas.cfg').write_text('')
        for name in ('ingress', 'out', 'bad', 'dupe'):
            empty_jam(root / name)
        document = {'auth': {'hpt_config_path': str(root / 'hpt.cfg'), 'session_key_path': str(root / 'unused.key')},
                    'ftn': {'areacfg_path': str(root / 'areas.cfg'), 'jam_base_path': str(root),
                            'coordination_lock': str(root / 'hpt.lock')},
                    'database': {'metadata_path': str(root / 'metadata.db')},
                    'point_mail': {'enabled': True, 'ingress_areas': ['INGRESS'], 'egress_area': 'OUT',
                                   'points': [{'address': f'2:1/2.{p}', 'jam_base': f'points/p{p}'} for p in (1, 2)]}}
        if mapped:
            document['ftn']['path_mappings'] = [{'from': str(root), 'to': str(root)}]
        path = root / 'config.json'
        path.write_text(json.dumps(document))
        result = subprocess.run([admin, 'provision-mailboxes', str(path)], capture_output=True, timeout=15)
        assert result.returncode == 0, result.stderr
        command = [sys.executable, wrapper, '--config', str(path), '--cycle', '--admin', admin, '--hpt', hpt]
        incoming = packet([('p1', 2, 1), ('p2', 2, 2), ('boss', 2, 0), ('ordinary', 2, 3), ('transit', 7, 1)], True)
        (root / 'protinbound/input.pkt').write_bytes(incoming)
        for attempt in range(2):
            if attempt:
                (root / 'protinbound/repeat.pkt').write_bytes(incoming)
            result = subprocess.run(command, capture_output=True, timeout=30)
            assert result.returncode == 0, result.stdout + result.stderr
            for point in (1, 2):
                mailbox = records(root / f'points/p{point}')
                assert len(mailbox) == 1
                assert mailbox[0][1][1] == [f'2:1/2.{point}'.encode()]
                assert mailbox[0][2] == f'Marker p{point}\r'.encode()
            outbound = fixture.outbound()
            assert b'Marker p1' not in outbound and b'Marker p2' not in outbound
            assert outbound.count(b'Marker ordinary') == outbound.count(b'Marker transit') == 1
            assert b'Marker boss' not in outbound
        # Raw HPT commands cannot bypass dispatch, including aliases/default commands.
        for tail in ([hpt, '-c', str(root / 'hpt.cfg'), 'pack'], [hpt], [hpt, 'scan']):
            result = subprocess.run([sys.executable, wrapper, '--config', str(path), '--', *tail], capture_output=True, timeout=5)
            assert result.returncode != 0
        with (root / 'hpt.lock').open('r+b') as held:
            fcntl.flock(held, fcntl.LOCK_SH)
            result = subprocess.run(command + ['--timeout', '.05'], capture_output=True, timeout=5)
            assert result.returncode == 75
        assert subprocess.run([admin, 'mail-cycle', str(path), 'recover', '-1'], capture_output=True, timeout=5).returncode != 0
        # HPT completes pack, but its caller loses the completion acknowledgement.
        shim = root / 'hpt-shim'
        shim.write_text('#!' + sys.executable + '\nimport subprocess,sys\nr=subprocess.run(' + repr([hpt]) + '+sys.argv[1:])\n'
                        'raise SystemExit(42 if "pack" in sys.argv[1:] and r.returncode==0 else r.returncode)\n')
        shim.chmod(0o700)
        result = subprocess.run(command[:-1] + [str(shim)], capture_output=True, timeout=30)
        assert result.returncode == 42, result.stdout + result.stderr
        with sqlite3.connect(root / 'metadata.db') as db:
            assert db.execute('select state from mail_pipeline').fetchone()[0] == 2
        db.close()
        before = {p: p.read_bytes() for p in root.rglob('*') if p.suffix in ('.jhr', '.jdt', '.jdx')}
        result = subprocess.run(command, capture_output=True, timeout=15)
        assert result.returncode != 0
        assert all(p.read_bytes() == data for p, data in before.items())
        ack = [sys.executable, wrapper, '--config', str(path), '--ack-export', '--admin', admin]
        result = subprocess.run(ack, capture_output=True, timeout=10)
        assert result.returncode == 0, result.stderr
        assert all(p.read_bytes() == data for p, data in before.items())
        with sqlite3.connect(root / 'metadata.db') as db:
            assert db.execute('select state from mail_pipeline').fetchone()[0] == 0
            assert db.execute("select count(*) from mail_export_log where phase='reconciled'").fetchone()[0] == 1
        db.close()

    print('Actual HPT personal-mail cycle, address dedup and export uncertainty passed')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
