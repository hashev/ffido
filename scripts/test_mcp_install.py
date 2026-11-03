#!/usr/bin/env python3
"""Check the real server install includes MCP without local runtime artifacts."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

cmake, build = sys.argv[1:]
with tempfile.TemporaryDirectory(prefix='ffido-mcp-install-') as directory:
    stage = Path(directory)
    subprocess.run([cmake, '--install', build, '--component', 'ffido', '--prefix', str(stage)],
                   check=True, capture_output=True)
    binary = stage/'bin/ffido-mcp'
    assert binary.is_file() and os.access(binary, os.X_OK)
    assert (stage/'share/ffido/mcp.md').is_file()
    response = subprocess.run([str(binary)], capture_output=True, timeout=10)
    assert response.returncode == 2 and b'Usage: ffido-mcp' in response.stderr
    for path in stage.rglob('*'):
        if path.is_file():
            assert path.name not in {'config.json', 'session.json', 'metadata.db'}
            assert path.suffix.lower() not in {'.jhr', '.jdt', '.jdx', '.jlr', '.sqlite', '.db'}
            assert not (len(path.stem) == 48 and path.suffix == '.json')
