#!/usr/bin/env python3
"""Run HPT under FFIDO's exclusive lifecycle coordination lock."""
import argparse
import fcntl
import json
import os
import pathlib
import stat
import signal
import subprocess
import sys
import time


class CycleInterrupted(Exception):
    pass


def run_stage(command, fd, timeout):
    process = subprocess.Popen(command, pass_fds=(fd,), start_new_session=True)
    try:
        result = process.wait(timeout=timeout)
        return result if result >= 0 else 128 - result
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()


def cycle(args, config, fd):
    if not args.admin or not args.hpt or not config.get('point_mail', {}).get('enabled', False):
        raise ValueError('Cycle requires enabled point mail, admin and HPT executables')
    root = args.config.absolute().parent
    hpt_config = pathlib.Path(config['auth']['hpt_config_path'])
    if not hpt_config.is_absolute():
        hpt_config = root / hpt_config
    def admin(stage):
        return run_stage([args.admin, 'mail-cycle', str(args.config.absolute()), stage, str(fd)], fd, args.timeout)
    def hpt(*commands):
        return run_stage([args.hpt, '-c', str(hpt_config), *commands], fd, args.timeout)
    def interrupted(signum, frame):
        raise CycleInterrupted()
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    exporting = False
    try:
        for stage in (lambda: admin('recover'), lambda: hpt('toss'), lambda: admin('dispatch')):
            result = stage()
            if result:
                return result
        result = admin('export-begin')
        if result:
            return result
        exporting = True
        result = hpt('pack')
        if not result and args.scan:
            result = hpt('scan', '-w')
        if result:
            admin('export-uncertain')
            return result
        result = admin('export-complete')
        exporting = bool(result)
        return result
    except (subprocess.TimeoutExpired, CycleInterrupted):
        if exporting:
            # If this call is interrupted too, the durable begin state still blocks retry.
            admin('export-uncertain')
        print('Mail cycle interrupted; recovery or export reconciliation is required', file=sys.stderr)
        return 75


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=pathlib.Path, required=True)
    parser.add_argument('--timeout', type=float, default=30)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--cycle', action='store_true')
    mode.add_argument('--status', action='store_true')
    mode.add_argument('--ack-export', action='store_true', help='Acknowledge completed operator reconciliation; never runs HPT or changes JAM')
    parser.add_argument('--admin')
    parser.add_argument('--hpt')
    parser.add_argument('--scan', action='store_true')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    operator = args.cycle or args.status or args.ack_export
    if (not operator and not command) or (operator and command) or not 0 < args.timeout <= 3600:
        parser.error('HPT command and timeout in (0, 3600] are required')
    fd = None
    try:
        with args.config.open(encoding='utf-8') as file:
            config = json.load(file)
        if config.get('point_mail', {}).get('enabled', False) and not operator:
            raise ValueError('Enabled point mail requires the complete operator cycle')
        value = config['ftn']['coordination_lock']
        if not isinstance(value, str) or not value or '\0' in value:
            raise ValueError('Invalid coordination path')
        path = pathlib.Path(value)
        if not path.is_absolute():
            path = args.config.absolute().parent / path
        fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK, 0o600)
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ValueError('Coordination file must be regular')
        deadline = time.monotonic() + args.timeout
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    print('HPT coordination deadline exceeded; HPT was not started', file=sys.stderr)
                    return 75
                time.sleep(min(remaining, 0.01))
        if args.status or args.ack_export:
            if not args.admin or not config.get('point_mail',{}).get('enabled',False):
                raise ValueError('Operator command requires enabled point mail and admin')
            stage='status' if args.status else 'export-reconciled'
            return run_stage([args.admin,'mail-cycle',str(args.config.absolute()),stage,str(fd)],fd,args.timeout)
        if args.cycle:
            return cycle(args, config, fd)
        # exec preserves exit status/signals and the lease until HPT's final exit.
        os.set_inheritable(fd, True)
        os.execvp(command[0], command)
    except KeyboardInterrupt:
        print('HPT coordination wait cancelled; HPT was not started', file=sys.stderr)
        return 130
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError):
        print('HPT wrapper configuration, lock or command failed', file=sys.stderr)
        return 1
    finally:
        if fd is not None:
            os.close(fd)


if __name__ == '__main__':
    raise SystemExit(main())
