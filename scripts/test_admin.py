#!/usr/bin/env python3
"""Exercise session revocation without provisioning a bypass around HPT."""
import hashlib
import json
import struct
import pathlib
import sqlite3
import subprocess
import sys
import tempfile


def main():
    executable = sys.argv[1]
    with tempfile.TemporaryDirectory(prefix='ffido-admin-') as directory:
        database = str(pathlib.Path(directory) / 'metadata.db')
        def run(*args):
            return subprocess.run([executable, *args], capture_output=True, text=True, timeout=10)
        assert run('--help').returncode == 0
        assert run('revoke-user', database, 'A').returncode == 0
        with sqlite3.connect(database) as db:
            db.execute("INSERT INTO users(user_id,name,ftn_address) VALUES('A','Name','2:1/2')")
            db.execute("INSERT INTO users(user_id,name,ftn_address) VALUES('B','Other','2:1/3')")
            db.execute("INSERT INTO tokens(digest,user_id,expires_at) VALUES(zeroblob(32),'A',9999999999)")
            db.execute("INSERT INTO tokens(digest,user_id,expires_at) VALUES(randomblob(32),'B',9999999999)")
        db.close()
        result = run('revoke-user', database, 'A')
        assert result.returncode == 0 and not result.stdout and not result.stderr
        with sqlite3.connect(database) as db:
            assert db.execute("SELECT revoked FROM tokens WHERE user_id='A'").fetchone()[0] == 1
            assert db.execute("SELECT revoked FROM tokens WHERE user_id='B'").fetchone()[0] == 0
        db.close()
        base = pathlib.Path(directory) / 'mail'
        header = bytearray(1024)
        header[:4] = b'JAM\0'
        struct.pack_into('<I', header, 4, 123)
        struct.pack_into('<I', header, 20, 1)
        record = bytearray(76)
        record[:4] = b'JAM\0'
        struct.pack_into('<I', record, 48, 1)
        struct.pack_into('<I', record, 52, 0x01000005)  # historical FFIDO TypeNet
        external = bytearray(record)
        struct.pack_into('<I', external, 48, 2)
        base.with_suffix('.jhr').write_bytes(header + record + external)
        base.with_suffix('.jdx').write_bytes(struct.pack('<4I', 0, 1024, 0, 1100))
        base.with_suffix('.jdt').write_bytes(b'')
        lock = pathlib.Path(directory) / 'hpt.lock'
        lock.touch()
        identity = base.with_suffix('.jhr').stat()
        generation = f'{identity.st_dev}:{identity.st_ino}:123:1'
        with sqlite3.connect(database) as db:
            for operation, number, state in [('own', 1, 1), ('pending', 3, 0), ('quarantine', 4, 3)]:
                db.execute("""INSERT INTO operations VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                           ('A', operation, 'MAIL', generation, operation, bytes(32), number,
                            1024, 0, 0, bytes(header), bytes(header), bytes(record), b'',
                            struct.pack('<2I', 0, 1024), state, ''))
        db.close()
        def snapshot():
            return {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in pathlib.Path(directory).iterdir() if p.is_file()}
        before = snapshot()
        audit = run('audit-jam', database, str(base), str(lock))
        assert audit.returncode == 0, audit.stderr
        report = json.loads(audit.stdout)
        assert report['read_only'] and report['pending_operations'] == report['quarantined_operations'] == 1
        assert report['records'][0]['provenance'] == 'committed_ffido'
        assert report['records'][1]['provenance'] == 'unproven'
        assert all(r['ambiguous_type'] and not r['migration_performed'] for r in report['records'])
        assert snapshot() == before, {k for k in snapshot().keys() | before.keys() if snapshot().get(k) != before.get(k)}
        assert run('audit-jam', database + '.missing', str(base), str(lock)).returncode != 0
        assert snapshot() == before, {k for k in snapshot().keys() | before.keys() if snapshot().get(k) != before.get(k)}
        assert run('provision', database, 'A', 'Name', '2:1/2', '9999999999').returncode != 0
    print('Session administration checks passed')


if __name__ == '__main__':
    main()
