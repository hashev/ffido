#!/usr/bin/env python3
"""Format handwritten Dart only, preserving authoritative protoc output."""
import argparse
import pathlib
import subprocess
ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
frontend = ROOT/'apps/frontend'
paths = sorted(str(p) for d in ('lib', 'test', 'tool', 'integration_test', 'test_driver') for p in (frontend/d).rglob('*.dart') if 'generated' not in p.parts)
subprocess.run(['dart', 'format', *(['--output=none', '--set-exit-if-changed'] if args.check else []), *paths], cwd=frontend, check=True)
