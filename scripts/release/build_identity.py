#!/usr/bin/env python3
"""Materialize a caller-supplied release identity or a non-publishable CI one."""
import json
import os
import pathlib
import re
import subprocess
root = pathlib.Path(__file__).resolve().parents[2]
sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
value = os.environ.get('IDENTITY_JSON', '')
if value:
    data = json.loads(value)
    if data['sha'] != sha:
        raise SystemExit('Caller identity differs from checked-out SHA')
else:
    version = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+', (root/'apps/frontend/pubspec.yaml').read_text(), re.M)[1]
    data = {'sha': sha, 'version': version, 'build_number': 1, 'tag': f'v{version}-check.{sha[:12]}', 'stable': False}
(root/'build').mkdir(exist_ok=True)
(root/'build/identity.json').write_text(json.dumps(data))
with open(os.environ['GITHUB_ENV'], 'a') as out:
    out.write(f"FFIDO_BUILD_NAME={data['version']}\nFFIDO_BUILD_NUMBER={data['build_number']}\n")
