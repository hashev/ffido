#!/usr/bin/env python3
"""Проверка SMAPI/POSIX locks отдельным процессом, только на временной JAM-базе."""
import argparse
import fcntl
import pathlib
import select
import subprocess
import tempfile


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('probe_command', nargs='+', help='SMAPI probe executable / wrapper')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='ffido-smapi-') as directory:
        base = pathlib.Path(directory) / 'messages'

        def run(mode):
            return subprocess.run(
                [*args.probe_command, mode, str(base)], text=True,
                capture_output=True, timeout=15,
            )

        created = run('create')
        print(created.stderr.strip(), flush=True)
        require(created.returncode == 0, f'SMAPI initialization failed: {created.returncode}')
        with open(str(base) + '.jhr', 'r+b') as header:
            for lock in (fcntl.LOCK_EX, fcntl.LOCK_SH):
                fcntl.lockf(header, lock | fcntl.LOCK_NB, 1, 0)
                attempt = run('probe')
                require(attempt.returncode == 10, 'SMAPI accepted a conflicting POSIX lock')
                fcntl.lockf(header, fcntl.LOCK_UN, 1, 0)

            with subprocess.Popen(
                [*args.probe_command, 'hold', str(base)], text=True,
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            ) as holder:
                try:
                    require(select.select([holder.stdout], [], [], 15)[0],
                            'SMAPI lock handshake timeout')
                    require(holder.stdout.readline().strip() == 'LOCKED',
                            'SMAPI did not acquire its lock')
                    for lock in (fcntl.LOCK_EX, fcntl.LOCK_SH):
                        try:
                            fcntl.lockf(header, lock | fcntl.LOCK_NB, 1, 0)
                        except BlockingIOError:
                            pass
                        else:
                            raise RuntimeError('POSIX accepted a conflicting SMAPI lock')
                    fcntl.lockf(header, fcntl.LOCK_EX | fcntl.LOCK_NB, 1, 1)
                    fcntl.lockf(header, fcntl.LOCK_UN, 1, 1)
                    holder.stdin.write('\n')
                    holder.stdin.flush()
                    require(holder.wait(timeout=15) == 0, 'SMAPI unlock failed')
                    fcntl.lockf(header, fcntl.LOCK_EX | fcntl.LOCK_NB, 1, 0)
                    fcntl.lockf(header, fcntl.LOCK_UN, 1, 0)
                finally:
                    if holder.poll() is None:
                        holder.kill()
                        holder.wait()
        print('PASS: SMAPI/POSIX conflicts both directions, read/write, offset 0 length 1, release')


if __name__ == '__main__':
    main()
