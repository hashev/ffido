#!/usr/bin/env python3
"""Verify wrapper leases, signals, timeout and relative config paths without real HPT."""
import fcntl
import json
import pathlib
import os
import signal
import time
import subprocess
import sys
import tempfile


def docker_mount_checks(root, lock, command):
    image = os.environ.get('FFIDO_TEST_DOCKER_IMAGE')
    if not image:
        print('Docker bind-mount checks not run: set FFIDO_TEST_DOCKER_IMAGE')
        return
    docker = ['docker', 'run', '--rm', '-i', '--network', 'none',
              '--user', f'{os.getuid()}:{os.getgid()}',
              '--mount', f'type=bind,source={root},target=/ffido-fixture', image, 'sh', '-c']
    probe = "exec 9<>/ffido-fixture/hpt.lock; flock -E 75 -n -x 9 || exit $?; "
    with lock.open('r+b') as held:
        fcntl.flock(held, fcntl.LOCK_SH)
        result = subprocess.run(docker + [probe], capture_output=True, text=True, timeout=30)
        assert result.returncode == 75, result.stderr
    child = subprocess.Popen(docker + [probe + "printf 'LOCKED\\n'; read marker"],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        assert child.stdout.readline().strip() == 'LOCKED'
        result = subprocess.run(command, capture_output=True, text=True, timeout=5)
        assert result.returncode == 75 and not result.stdout
        child.communicate('\n', timeout=30)
        assert child.returncode == 0
    finally:
        if child.poll() is None:
            child.kill()
            child.wait(timeout=5)
        for stream in (child.stdin, child.stdout, child.stderr):
            if stream:
                stream.close()
    print('Docker bind-mount shared/exclusive lease checks passed')


def main():
    wrapper = str(pathlib.Path(sys.argv[1]).absolute())
    with tempfile.TemporaryDirectory(prefix='ffido-wrapper-') as directory:
        root = pathlib.Path(directory)
        config = root / 'config.json'
        config.write_text(json.dumps({'ftn': {'coordination_lock': 'hpt.lock'}}))
        lock = root / 'hpt.lock'
        command = [sys.executable, wrapper, '--config', str(config), '--timeout', '.03', '--', sys.executable, '-c', 'print("started")']
        with lock.open('w+b') as held:
            fcntl.flock(held, fcntl.LOCK_SH)
            result = subprocess.run(command, cwd='/', capture_output=True, text=True, timeout=5)
            assert result.returncode == 75 and not result.stdout
        assert subprocess.run(command, cwd='/', capture_output=True, text=True, timeout=5).stdout.strip() == 'started'
        hold = command[:-2] + ['-c', 'import sys; print("HPT OPEN",flush=True); sys.stdin.readline(); print("HPT CLOSED",flush=True)']
        child = subprocess.Popen(hold, cwd='/', stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            assert child.stdout.readline().strip() == 'HPT OPEN'
            with lock.open('r+b') as other:
                try:
                    fcntl.flock(other, fcntl.LOCK_SH | fcntl.LOCK_NB)
                    raise AssertionError('Wrapper did not retain exclusive lock across exec')
                except BlockingIOError:
                    pass
                child.communicate('\n', timeout=5)
                assert child.returncode == 0
                fcntl.flock(other, fcntl.LOCK_EX | fcntl.LOCK_NB)
        finally:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=5)
            for stream in (child.stdin, child.stdout, child.stderr):
                if stream:
                    stream.close()
        # Different names of the same physical lock must coordinate too.
        alias = root / 'hpt-alias.lock'
        os.link(lock, alias)
        assert os.stat(lock).st_ino == os.stat(alias).st_ino
        with alias.open('r+b') as held:
            fcntl.flock(held, fcntl.LOCK_SH)
            result = subprocess.run(command, cwd='/', capture_output=True, text=True, timeout=5)
            assert result.returncode == 75 and not result.stdout
        docker_mount_checks(root, lock, command)
        config.write_text(json.dumps({'ftn': {'coordination_lock': 'symlink'}}))
        (root / 'symlink').symlink_to(lock)
        assert subprocess.run(command, capture_output=True, timeout=5).returncode != 0
    with tempfile.TemporaryDirectory(prefix='ffido-cycle-wrapper-') as directory:
        root = pathlib.Path(directory)
        config = root / 'config.json'
        config.write_text(json.dumps({'ftn': {'coordination_lock': 'hpt.lock'},
                                      'auth': {'hpt_config_path': 'hpt.cfg'}, 'point_mail': {'enabled': True}}))
        events = root / 'events'
        state = root / 'state'
        mode = root / 'mode'
        state.write_text('0')
        mode.write_text('normal')
        admin = root / 'admin'
        admin.write_text('#!' + sys.executable + '\nimport sys,os,fcntl,pathlib\nroot=pathlib.Path(' + repr(str(root)) + ')\n'
                         'fd=int(sys.argv[4]); assert os.fstat(fd).st_ino==(root/"hpt.lock").stat().st_ino\n'
                         'fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)\n'
                         'stage=sys.argv[3]\nwith (root/"events").open("a") as f:f.write(stage+"\\n")\n'
                         'state=root/"state"\n'
                         'if stage=="recover" and state.read_text()!="0":raise SystemExit(1)\n'
                         'if stage=="export-begin":state.write_text("1")\n'
                         'if stage=="export-complete":state.write_text("0")\n'
                         'if stage=="export-uncertain":state.write_text("2")\n')
        hpt = root / 'hpt'
        hpt.write_text('#!' + sys.executable + '\nimport pathlib,sys,time,os,signal,fcntl\nroot=pathlib.Path(' + repr(str(root)) + ')\n'
                       'with (root/"hpt.lock").open("rb") as lock:\n'
                       ' try:fcntl.flock(lock,fcntl.LOCK_SH|fcntl.LOCK_NB);raise AssertionError("lost lifecycle lock")\n'
                       ' except BlockingIOError:pass\n'
                       'stage=sys.argv[3]\nwith (root/"events").open("a") as f:f.write(stage+"\\n")\n'
                       'if stage=="pack":\n'
                       ' print("PACK_START",flush=True)\n'
                       ' if (root/"mode").read_text()=="sleep":time.sleep(10)\n'
                       ' if (root/"mode").read_text()=="signal":os.kill(os.getpid(),signal.SIGTERM)\n')
        admin.chmod(0o700)
        hpt.chmod(0o700)
        command = [sys.executable, wrapper, '--config', str(config), '--cycle', '--admin', str(admin), '--hpt', str(hpt)]
        result = subprocess.run(command + ['--scan'], capture_output=True, timeout=10)
        assert result.returncode == 0, result.stderr
        assert events.read_text().splitlines() == ['recover', 'toss', 'dispatch', 'export-begin', 'pack', 'scan', 'export-complete']
        for scenario in ('timeout', 'cancel', 'signal'):
            state.write_text('0')
            mode.write_text('signal' if scenario == 'signal' else 'sleep')
            if scenario == 'cancel':
                process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                assert process.stdout.readline().strip() == 'PACK_START'
                process.terminate()
                process.communicate(timeout=5)
                result_code = process.returncode
            else:
                result_code = subprocess.run(command + ['--timeout', '.3'], capture_output=True, timeout=5).returncode
            assert result_code == (143 if scenario == 'signal' else 75), (scenario, result_code)
            assert state.read_text() == '2'
            with (root / 'hpt.lock').open('r+b') as lease:
                fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
        # An unknown prior export outcome never starts another toss.
        events.write_text('')
        assert subprocess.run(command, capture_output=True, timeout=5).returncode != 0
        assert events.read_text().splitlines() == ['recover']
    print('HPT lifecycle wrapper checks passed')


if __name__ == '__main__':
    main()
