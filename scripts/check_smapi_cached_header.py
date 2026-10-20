#!/usr/bin/env python3
"""Reproduce cached SMAPI close overwriting a later append on a synthetic JAM."""
import argparse
import json
import fcntl
import pathlib
import struct
import subprocess
import sys
import tempfile


def append(base):
    header = bytearray(base.with_suffix('.jhr').read_bytes())
    index = base.with_suffix('.jdx').read_bytes()
    text = base.with_suffix('.jdt').read_bytes()
    first = struct.unpack_from('<I', header, 20)[0]
    number = first + len(index) // 8
    message = struct.pack('<IHH17I', 0x004d414a, 1, 0, 0, 0, 0xffffffff, 0xffffffff,
                          0, 0, 0, 123, 123, 0, number, 1, 0, len(text), 5, 0xffffffff, 0)
    slots = index + struct.pack('<II', 0xffffffff, len(header))
    struct.pack_into('<I', header, 8, struct.unpack_from('<I', header, 8)[0] + 1)
    struct.pack_into('<I', header, 12, len(slots) // 8)
    base.with_suffix('.jdt').write_bytes(text + b'hello')
    base.with_suffix('.jdx').write_bytes(slots)
    base.with_suffix('.jhr').write_bytes(header + message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('probe')
    parser.add_argument('--protected', action='store_true')
    args = parser.parse_args()
    probe = args.probe
    with tempfile.TemporaryDirectory(prefix='ffido-smapi-cache-') as directory:
        base = pathlib.Path(directory) / 'messages'
        subprocess.run([probe, 'create', str(base)], check=True, capture_output=True, timeout=10)
        append(base)
        command = [probe, 'cached-close', str(base)]
        lock_path = pathlib.Path(directory) / 'hpt.lock'
        if args.protected:
            config = pathlib.Path(directory) / 'config.json'
            config.write_text(json.dumps({'ftn': {'coordination_lock': str(lock_path)}}))
            command = [sys.executable, str(pathlib.Path(__file__).with_name('run_hpt.py')), '--config', str(config), '--'] + command
        child = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            assert child.stdout.readline().strip() == 'OPENED 1'
            if args.protected:
                with lock_path.open('r+b') as coordination:
                    try:
                        fcntl.flock(coordination, fcntl.LOCK_SH | fcntl.LOCK_NB)
                        raise AssertionError('Backend could overlap SMAPI open/close lifecycle')
                    except BlockingIOError:
                        pass
                    child.communicate('\n', timeout=10)
                    assert child.returncode == 0
                    fcntl.flock(coordination, fcntl.LOCK_SH | fcntl.LOCK_NB)
                    with base.with_suffix('.jhr').open('r+b') as file:
                        fcntl.lockf(file, fcntl.LOCK_EX, 1, 0)
                        append(base)
                active = struct.unpack_from('<I', base.with_suffix('.jhr').read_bytes(), 12)[0]
                slots = base.with_suffix('.jdx').stat().st_size // 8
                assert active == 2 and slots == 2
                print('Protected SMAPI lifecycle: ActiveMsgs=2; physical slots=2; no overlapping append before cached close')
                return
            append(base)
            before = struct.unpack_from('<I', base.with_suffix('.jhr').read_bytes(), 12)[0]
            with base.with_suffix('.jhr').open('r+b') as file:
                fcntl.lockf(file, fcntl.LOCK_EX, 1, 0)
                output, diagnostics = child.communicate('\n', timeout=10)
                assert child.returncode == 0
                after = struct.unpack_from('<I', base.with_suffix('.jhr').read_bytes(), 12)[0]
            slots = base.with_suffix('.jdx').stat().st_size // 8
            print(f'ActiveMsgs before cached close={before}; after={after}; physical slots={slots}; close ignored competing first-byte lock={after != before}')
            assert before == 2 and after == 1 and slots == 2, 'Expected stale cached-header overwrite was not reproduced'
        finally:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=10)
            for stream in (child.stdin, child.stdout, child.stderr):
                if stream:
                    stream.close()


if __name__ == '__main__':
    main()
