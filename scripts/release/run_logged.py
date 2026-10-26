#!/usr/bin/env python3
"""Run a long build with bounded console progress and a complete compressed log."""
import gzip
import os
import signal
from pathlib import Path
import shutil
import subprocess
import sys
import time


def run(log, command, interval=30):
    log.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    try:
        with log.open('wb') as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, start_new_session=(os.name != 'nt'))
            try:
                while True:
                    try:
                        code = process.wait(timeout=interval)
                        break
                    except subprocess.TimeoutExpired:
                        with log.open('rb') as current:
                            current.seek(max(0, log.stat().st_size-2000))
                            lines = current.read().decode(errors='replace').splitlines()
                        print(f'Build progress ({time.monotonic()-started:.0f}s): '+(lines[-1] if lines else 'starting'), flush=True)
            finally:
                if process.poll() is None:
                    if os.name == 'nt':
                        process.terminate()
                    else:
                        os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        if os.name == 'nt':
                            process.kill()
                        else:
                            os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
        with log.open('rb') as current:
            current.seek(max(0, log.stat().st_size-12000))
            print(current.read().decode(errors='replace'), end='')
        return code
    finally:
        if log.exists():
            with log.open('rb') as source, gzip.open(str(log)+'.gz', 'wb') as destination:
                shutil.copyfileobj(source, destination)
            log.unlink()
        print(f'Build execution: {time.monotonic()-started:.1f}s', flush=True)


if __name__ == '__main__':
    def interrupted(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    raise SystemExit(run(Path(sys.argv[1]), sys.argv[2:]))
