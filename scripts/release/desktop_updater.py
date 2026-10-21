#!/usr/bin/env python3
"""Build the native standalone helper with the public trust anchors embedded."""
import pathlib
import platform
import subprocess
import sys
root = pathlib.Path(__file__).resolve().parents[2]
target = {'Windows': 'windows', 'Linux': 'linux'}[platform.system()]
subprocess.run([sys.executable, '-m', 'PyInstaller', '--noconfirm', '--clean', '--onefile',
                *(['--noconsole'] if target == 'windows' else []),
                '--name', 'ffido-updater', '--distpath', str(root/'build/desktop-updater'/target),
                '--workpath', str(root/'build/desktop-updater/work'/target),
                '--specpath', str(root/'build/desktop-updater'),
                '--add-data', str(root/'scripts/update/public_keys.json')+':.',
                str(root/'scripts/update/desktop.py')], check=True)

import importlib.metadata
import shutil
for name in ['pyinstaller', 'cryptography', 'cffi', 'pycparser', 'pyinstaller-hooks-contrib', 'altgraph', 'packaging']:
    distribution = importlib.metadata.distribution(name)
    files = [path for path in distribution.files or [] if '.dist-info' in str(path) and ('license' in path.name.lower() or 'copying' in path.name.lower())]
    if not files: raise ValueError('Missing updater dependency license: '+name)
    for path in files:
        destination = root/'build/desktop-updater/licenses'/name/path.name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(distribution.locate_file(path), destination)
