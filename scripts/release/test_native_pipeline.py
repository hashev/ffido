"""Exercise the actual shell build boundary with a Husky-like configure contract."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NativePipelineTest(unittest.TestCase):
    def test_configure_uses_source_cwd_and_verified_hit_never_runs_cmake(self):
        shell = (ROOT/'scripts/release/dependencies.sh').read_text()
        function = shell[shell.index('build_install() {'):shell.index('\nbuild_install abseil ')]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root/'scripts').symlink_to(ROOT/'scripts', target_is_directory=True)
            (root/'build').mkdir()
            (root/'build/native-profile.json').write_text(json.dumps({'components': {'huskylib': 'key'}}))
            tools = root/'tools'
            tools.mkdir()
            cmake = tools/'cmake'
            cmake.write_text('''#!/usr/bin/env python3
import os, pathlib, sys
root = pathlib.Path(os.environ['TEST_ROOT'])
with (root/'calls').open('a') as out: out.write(' '.join(sys.argv[1:])+'\\n')
if (root/'forbid-cmake').exists(): raise SystemExit(97)
if '-S' in sys.argv:
    # Husky runs git relative to the process cwd during configure.
    assert pathlib.Path('.git').is_dir(), 'configure must run inside source'
    prefix = next(a.split('=', 1)[1] for a in sys.argv if a.startswith('-DCMAKE_INSTALL_PREFIX='))
    (root/'install-prefix').write_text(prefix)
if '--install' in sys.argv:
    prefix = pathlib.Path((root/'install-prefix').read_text())
    (prefix/'lib').mkdir(parents=True, exist_ok=True)
    (prefix/'lib/libhusky.a').write_bytes(b'library')
''')
            cmake.chmod(0o755)
            driver = root/'driver.sh'
            driver.write_text('''set -euo pipefail
ROOT="$TEST_ROOT"
WORK="$ROOT/work"
PREFIX="$WORK/prefix"
COMPONENTS="$WORK/components"
JOBS=1
mkdir -p "$PREFIX" "$COMPONENTS"
common=(-DCMAKE_BUILD_TYPE=Release)
clone_locked() { mkdir -p "$WORK/$1/.git"; echo source > "$WORK/$1/source.c"; }
'''+function+'''
build_install huskylib
if [[ -f "$ROOT/forbid-cmake" ]]; then test -f "$PREFIX/lib/libhusky.a"; fi
''')
            environment = {**os.environ, 'TEST_ROOT': str(root), 'PATH': str(tools)+os.pathsep+os.environ['PATH']}
            subprocess.run(['bash', str(driver)], env=environment, check=True, capture_output=True)
            self.assertEqual(len((root/'calls').read_text().splitlines()), 3)
            (root/'forbid-cmake').touch()
            shutil.rmtree(root/'work/prefix')
            subprocess.run(['bash', str(driver)], env=environment, check=True, capture_output=True)
            self.assertEqual(len((root/'calls').read_text().splitlines()), 3)
            self.assertEqual((root/'work/prefix/lib/libhusky.a').read_bytes(), b'library')
            (root/'work/components/huskylib/payload/prefix/lib/libhusky.a').write_bytes(b'corrupt')
            failed = subprocess.run(['bash', str(driver)], env=environment, capture_output=True)
            self.assertEqual(failed.returncode, 97)
