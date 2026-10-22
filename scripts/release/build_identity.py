#!/usr/bin/env python3
"""Materialize a caller-supplied release identity or a non-publishable CI one."""
import json
import os
import pathlib
import re
import subprocess
from update_metadata import select_update_key
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
keys = json.loads((root/'scripts/update/public_keys.json').read_text())
settings = json.loads((root/'scripts/release/settings.json').read_text())
try:
    selected_key, public_key = select_update_key(keys, settings)
except ValueError as error:
    raise SystemExit(str(error)) from None
(root/'build').mkdir(exist_ok=True)
(root/'build/identity.json').write_text(json.dumps(data))
assets = root/'apps/frontend/assets/updates'
assets.mkdir(parents=True, exist_ok=True)
(assets/'identity.json').write_text(json.dumps(data)+'\n')
(assets/'public_keys.json').write_bytes((root/'scripts/update/public_keys.json').read_bytes())
with open(os.environ['GITHUB_ENV'], 'a') as out:
    out.write(f"FFIDO_BUILD_NAME={data['version']}\nFFIDO_BUILD_NUMBER={data['build_number']}\n")

(root/'apps/frontend/macos/Runner/Configs/Updates.xcconfig').write_text('// Generated from scripts/update/public_keys.json by build_identity.py.\nFFIDO_UPDATE_SLASH = /\nFFIDO_UPDATE_PUBLIC_KEY = '+public_key.replace('/', '$(FFIDO_UPDATE_SLASH)')+'\n')
