#!/usr/bin/env python3
"""Version/dispatch must not load FTN configuration or start gRPC."""
import os
import pathlib
import subprocess
import sys
binary = pathlib.Path(sys.argv[1]).resolve()
environment = {**os.environ, 'FIDOBACK_CONFIG': '/missing/ffido-update-test-config.json'}
result = subprocess.run([binary, '--version'], env=environment, text=True, capture_output=True, timeout=5)
assert result.returncode == 0 and ('FFIDO' in result.stdout or 'version' in result.stdout), result
result = subprocess.run([binary, '--check-ready'], env=environment, text=True, capture_output=True, timeout=10)
assert result.returncode == 2 and 'Usage:' in result.stderr, result
