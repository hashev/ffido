"""Exercise the installed operator CLI against isolated HPT configurations."""
import hashlib
import json
import pathlib
import sqlite3
import subprocess
import sys
import tempfile


def exercise(admin, mapped):
    with tempfile.TemporaryDirectory(prefix='ffido-point-provision-') as directory:
        root = pathlib.Path(directory)
        config = 'Name FFIDO fixture\nSysop Fixture\nLocation Test\nAddress 2:1/2\n'
        for point in (1, 2, 3):
            config += f'Link Point{point}\nAKA 2:1/2.{point}\nOurAKA 2:1/2\nPassword fixture{point}\n'
        config += 'KeepTrsMail on\nPackNetMailOnScan off\nRoute nopack 2:1/2.1 2:1/2.2\nRoute normal noroute *\n'
        for tag in ('IN', 'OUT'):
            config += f'NetmailArea {tag} {root / tag} -b JAM -dupeCheck off\n'
        hpt = root / 'hpt.cfg'
        if mapped:
            config = config.replace(str(root), '/ffido-provision-container')
            (root / 'areas.cfg').write_text(config)
            hpt.write_text('Include /ffido-provision-container/areas.cfg\n')
        else:
            hpt.write_text(config)
        original = hashlib.sha256(hpt.read_bytes()).hexdigest()
        if not mapped:
            (root / 'areas.cfg').write_text('')
        document = {'auth': {'hpt_config_path': str(hpt), 'session_key_path': str(root / 'unused.key')},
                    'ftn': {'areacfg_path': str(root / 'areas.cfg'), 'jam_base_path': str(root),
                            'coordination_lock': str(root / 'hpt.lock')},
                    'database': {'metadata_path': str(root / 'metadata.db')},
                    'point_mail': {'enabled': True, 'ingress_areas': ['IN'], 'egress_area': 'OUT',
                                   'points': [{'address': f'2:1/2.{p}', 'jam_base': f'points/p{p}'} for p in (1, 2)]}}
        if mapped:
            document['ftn']['path_mappings'] = [{'from': '/ffido-provision-container', 'to': str(root)}]
        path = root / 'config.json'
        path.write_text(json.dumps(document))
        def run():
            return subprocess.run([admin, 'provision-mailboxes', str(path)], capture_output=True, timeout=15)
        result = run()
        assert result.returncode == 0, result.stderr
        files = {p: p.read_bytes() for p in (root / 'points').iterdir()}
        assert len(files) == 6
        assert run().returncode == 0
        assert all(p.read_bytes() == data for p, data in files.items())
        with sqlite3.connect(root / 'metadata.db') as db:
            assert db.execute('select count(*) from mailbox_bindings').fetchone()[0] == 2
        db.close()
        document['point_mail']['points'][1]['jam_base'] = 'IN'
        path.write_text(json.dumps(document))
        assert run().returncode != 0
        assert hashlib.sha256(hpt.read_bytes()).hexdigest() == original
    print('Explicit point mailbox provisioning passed')


if __name__ == '__main__':
    exercise(sys.argv[1], False)
    if '--mapped' in sys.argv[2:]:
        exercise(sys.argv[1], True)
