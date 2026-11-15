#!/usr/bin/env python3
"""A disposable service repeatedly runs the real HPT through its installed wrapper."""
import argparse
import pathlib
import signal
import subprocess
import threading


def run(args):
    stopping = threading.Event()
    signal.signal(signal.SIGTERM, lambda signum, frame: stopping.set())
    signal.signal(signal.SIGINT, lambda signum, frame: stopping.set())
    count = int(args.counter.read_text()) if args.counter.exists() else 0
    while not stopping.is_set():
        with args.log.open('a') as output:
            result = subprocess.run([str(args.wrapper), '--config', str(args.config), '--timeout', '10', '--',
                                     str(args.hpt), '-c', str(args.hpt_config), 'scan', '-w', '-a', 'RU.TEST'],
                                    stdout=output, stderr=subprocess.STDOUT, timeout=15)
        if result.returncode and not stopping.is_set():
            raise RuntimeError('HPT scan failed; see private hpt-driver.log')
        if not result.returncode:
            count += 1
            args.counter.write_text(str(count))
        stopping.wait(.2)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('wrapper', 'config', 'hpt', 'hpt-config', 'counter', 'log'):
        parser.add_argument('--'+name, type=pathlib.Path, required=True)
    run(parser.parse_args())
