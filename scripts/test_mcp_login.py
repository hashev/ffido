#!/usr/bin/env python3
"""Exercise interactive MCP login against the caller's temporary TLS fixture."""
import os
import pty
import selectors
import subprocess
import sys
import time

binary, config = sys.argv[1:]
master, slave = pty.openpty()
process = subprocess.Popen([binary, 'login', config], stdin=slave, stdout=slave, stderr=slave, close_fds=True)
os.close(slave)
selector = selectors.DefaultSelector()
selector.register(master, selectors.EVENT_READ)
transcript = bytearray()
try:
    for prompt, value in [(b'Name: ', b'MCP fixture'), (b'FTN address: ', b'2:5015/1.1'),
                          (b'Password: ', b'mcp-fixture-password')]:
        deadline = time.monotonic() + 10
        while prompt not in transcript:
            if time.monotonic() >= deadline or not selector.select(timeout=0.2):
                if time.monotonic() >= deadline:
                    raise RuntimeError('Login prompt timeout')
                continue
            transcript.extend(os.read(master, 4096))
        os.write(master, value + b'\n')
    deadline = time.monotonic() + 12
    while process.poll() is None:
        if time.monotonic() >= deadline:
            raise RuntimeError('Login did not terminate; transcript withheld')
        if selector.select(timeout=0.1):
            try:
                transcript.extend(os.read(master, 4096))
            except OSError:
                break
    process.wait(timeout=2)
    while selector.select(timeout=0):
        try:
            chunk = os.read(master, 4096)
        except OSError:
            break
        if not chunk:
            break
        transcript.extend(chunk)
    if process.returncode != 0 or b'mcp-fixture-password' in transcript:
        raise RuntimeError('Login failed or echoed password; transcript withheld')
finally:
    if process.poll() is None:
        process.kill()
        process.wait()
    selector.close()
    os.close(master)
