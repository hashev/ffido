#!/usr/bin/env python3
"""Exercise a frozen updater against two complete native Flutter bundles.

Run on a disposable Windows CI runner or under xvfb-run on Linux. QA trust anchors are built
in an isolated shadow tree, never written to the repository's trust store.
"""
import argparse
import base64
import hashlib
import json
import os
import pathlib
import platform
import secrets
import shutil
import subprocess
import sys
import tarfile
import time
import tempfile
import zipfile
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

ROOT = pathlib.Path(__file__).resolve().parents[2]


def wait(predicate, timeout=45):
    deadline = time.monotonic()+timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value: return value
        time.sleep(.2)
    raise RuntimeError('Desktop update QA condition timed out')


def run(args):
    os_name = {'Linux': 'linux', 'Windows': 'windows'}[platform.system()]
    if os_name == 'windows' and os.environ.get('GITHUB_ACTIONS') != 'true':
        raise ValueError('Use a disposable Windows CI runner; do not modify a personal Windows profile')
    reports = args.directory.resolve()
    reports.mkdir(parents=True, exist_ok=False)
    # Installation ownership checks need a real per-user filesystem, not a
    # Docker/macOS bind mount that remaps every file to the host UID.
    work = pathlib.Path(tempfile.mkdtemp(prefix='ffido-desktop-qa-')).resolve()
    key = Ed25519PrivateKey.generate()
    keys = {'qa': base64.b64encode(key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()}
    shadow = work/'shadow'
    shutil.copytree(ROOT/'scripts/update', shadow/'scripts/update', ignore=shutil.ignore_patterns('__pycache__'))
    (shadow/'scripts/release').mkdir(parents=True)
    shutil.copy2(ROOT/'scripts/release/desktop_updater.py', shadow/'scripts/release/desktop_updater.py')
    (shadow/'scripts/update/public_keys.json').write_text(json.dumps(keys))
    with (work/'freeze.log').open('w') as log:
        frozen = subprocess.run([sys.executable, str(shadow/'scripts/release/desktop_updater.py')], stdout=log, stderr=subprocess.STDOUT)
    if frozen.returncode:
        shutil.copy2(work/'freeze.log', reports/'freeze.log')
        raise RuntimeError('Cannot freeze updater; see freeze.log')
    executable = 'fido.exe' if os_name == 'windows' else 'fido'
    helper_name = 'ffido-updater.exe' if os_name == 'windows' else 'ffido-updater'
    helper = shadow/'build/desktop-updater'/os_name/helper_name
    subprocess.run([str(helper), '--help'], check=True, stdout=subprocess.DEVNULL)
    installed = work/'installed'
    candidate = work/'candidate'
    identity_path = pathlib.Path('data/flutter_assets/assets/updates/identity.json')
    compatibility = {'protocol_major': 1, 'client_protocol_min': 1, 'client_protocol_max': 1, 'server_protocol_min': 1, 'server_protocol_max': 1, 'state_schema_min': 9, 'state_schema_max': 9, 'config_format': 1, 'jam_format': 'JAM-1'}
    def identity(version, number):
        return {'version': version, 'tag': 'v'+version, 'stable': True, 'sha': 'a'*40, 'build_number': number}
    old, new = identity('1.0.0', 41001), identity('1.0.1', 41002)
    for bundle, release in [(installed, old), (candidate, new)]:
        shutil.copytree(args.bundle.resolve(), bundle, symlinks=True)
        shutil.copy2(helper, bundle/helper_name)
        (bundle/identity_path).write_text(json.dumps(release))
        (bundle/'BUILD.json').write_text(json.dumps({**release, 'component': 'client', 'platform': {'os': os_name, 'architecture': 'x86_64'}}))
    # Isolate the actual app's preferences, caches and credential-provider calls.
    profile = work/'profile'; profile.mkdir()
    environment = {**os.environ, 'XDG_CONFIG_HOME': str(profile/'config'), 'XDG_DATA_HOME': str(profile/'data'), 'XDG_CACHE_HOME': str(profile/'cache'), 'APPDATA': str(profile/'roaming'), 'LOCALAPPDATA': str(profile/'local')}
    for name in ['config', 'data', 'cache', 'roaming', 'local']: (profile/name).mkdir()
    children = []
    updater = None
    restore_preferences = {}
    try:
        nonce = secrets.token_hex(16)
        (installed/'.ffido-launch-probe').write_text(nonce)
        log = (work/'A.log').open('w')
        first = subprocess.Popen([str(installed/executable)], cwd=installed, env=environment, stdout=log, stderr=subprocess.STDOUT)
        children.append((first, log))
        def ready():
            if first.poll() is not None: raise RuntimeError('Initial Flutter client failed; see A.log')
            marker = installed/'.ffido-ready'
            return marker.is_file() and marker.read_text() == nonce
        wait(ready)
        (installed/'.ffido-ready').unlink(); (installed/'.ffido-launch-probe').unlink()
        first.terminate(); first.wait(timeout=15)
        # The Flutter preferences writer creates this on first write. Preserve
        # all existing values and insert a sentinel only in files it created.
        preferences = list(profile.rglob('shared_preferences.json'))
        if not preferences and os_name == 'linux':
            supports = [profile/'data/io.github.hashev.ffido', profile/'data/fido']
            support = next((path for path in supports if path.is_dir()), None)
            assert support is not None, 'Flutter application support directory was not created'
            preferences = [support/'shared_preferences.json']
        if not preferences and os_name == 'windows':
            script = '$v=[System.Diagnostics.FileVersionInfo]::GetVersionInfo($env:FFIDO_QA_EXE); Join-Path ([Environment]::GetFolderPath("ApplicationData")) (Join-Path $v.CompanyName $v.ProductName)'
            location = subprocess.check_output(['powershell', '-NoProfile', '-Command', script], env={**environment, 'FFIDO_QA_EXE': str(installed/executable)}, text=True).strip()
            support = pathlib.Path(location)
            assert support.is_dir(), 'Windows application support directory was not created'
            path = support/'shared_preferences.json'
            restore_preferences[path] = path.read_bytes() if path.exists() else None
            preferences = [path]
        assert preferences, 'Preference preservation was not verified'
        snapshots = {}
        for path in preferences:
            values = json.loads(path.read_text()) if path.exists() else {}
            values['flutter.ffido_update_qa'] = 'preserve-me'
            values['flutter.cached_conferences'] = 'clear-this-cache'
            path.write_text(json.dumps(values)); snapshots[str(path)] = 'preserve-me'
        marker = profile/'external-state'; marker.write_bytes(b'profile outside the app bundle')
        downloads = work/'downloads'; downloads.mkdir()
        archive = downloads/('client.zip' if os_name == 'windows' else 'client.tar.gz')
        if os_name == 'windows':
            with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as output:
                for path in candidate.rglob('*'):
                    if path.is_file(): output.write(path, path.relative_to(candidate))
        else:
            with tarfile.open(archive, 'w:gz') as output: output.add(candidate, arcname='ffido')
        package = {**new, 'id': 'client-'+os_name+'-x86_64', 'component': 'client', 'platform': {'os': os_name, 'architecture': 'x86_64'}, 'min_os': {'version': '10.0', 'build': 10240} if os_name == 'windows' else {'version': '24.04', 'distribution': 'ubuntu'}, 'compatibility': compatibility, 'file': archive.name, 'size': archive.stat().st_size, 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest()}
        manifest = {'schema_version': 1, 'identity': new, 'channel': 'stable', 'update_sequence': 41002, 'packages': [package], 'compatibility': compatibility}
        raw = json.dumps(manifest).encode()
        (downloads/'release-manifest.json').write_bytes(raw)
        (downloads/'release-manifest.sig').write_text(json.dumps({'algorithm': 'Ed25519', 'key_id': 'qa', 'signature': base64.b64encode(key.sign(raw)).decode()}))
        # Run the updater outside the installation it must replace on Windows.
        subprocess.run([str(helper), '--root', str(installed), '--package', str(archive), '--executable', executable, '--preflight'], env=environment, check=True)
        with (work/'B.log').open('w') as log:
            process = subprocess.Popen([str(helper), '--root', str(installed), '--package', str(archive), '--executable', executable], env=environment, stdout=log, stderr=subprocess.STDOUT)
            updater = process
            assert process.wait(timeout=120) == 0, 'Frozen updater failed; see B.log'
        if os_name == 'windows':
            # A native Flutter child must not inherit DLLs from PyInstaller's
            # temporary runtime. Also require B to remain alive after helper exit.
            script = r'$p=@(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -eq $env:FFIDO_QA_EXE }); if ($p.Count -ne 1) { throw "Expected one running updated client" }; $modules=@((Get-Process -Id $p[0].ProcessId).Modules | Where-Object { $_.FileName -like "*\_MEI*\*" } | Select-Object -ExpandProperty FileName); ConvertTo-Json -InputObject $modules'
            modules = subprocess.check_output(['powershell', '-NoProfile', '-Command', script], env={**environment, 'FFIDO_QA_EXE': str(installed/executable)}, text=True)
            (reports/'client-frozen-modules.json').write_text(modules)
            assert json.loads(modules) == [], 'Flutter inherited the frozen helper DLL runtime'
        journal = json.loads((work/'.installed-update.json').read_text())
        assert journal['phase'] == 'confirmed' and journal['tag'] == new['tag']
        assert json.loads((installed/identity_path).read_text()) == new
        assert json.loads((work/'installed.previous'/identity_path).read_text()) == old
        assert marker.read_bytes() == b'profile outside the app bundle'
        for name, value in snapshots.items():
            stored = json.loads(pathlib.Path(name).read_text())
            assert stored['flutter.ffido_update_qa'] == value
            assert 'flutter.cached_conferences' not in stored, 'New Flutter did not read and rewrite the seeded preferences'
        result = {'platform': os_name, 'frozen_helper': True, 'complete_flutter_bundle': True, 'from': old['tag'], 'to': new['tag'], 'startup_confirmed': True, 'external_state_preserved': True, 'preferences_files_verified': len(snapshots), 'same_flutter_binary_with_distinct_bundle_metadata': True}
        (reports/'result.json').write_text(json.dumps(result, indent=2)+'\n'); print(json.dumps(result))
    finally:
        for name in ['.installed-update.log', '.installed-update.json']:
            path = work/name
            if path.exists(): shutil.copy2(path, reports/name.removeprefix('.'))
        # The updater intentionally leaves its new Flutter child running. The
        # readiness probe records no PID; terminate only processes under this QA
        # installation, using platform-native inventory with exact path matching.
        if os_name == 'linux':
            for entry in pathlib.Path('/proc').iterdir():
                if not entry.name.isdigit(): continue
                try:
                    if (entry/'exe').resolve() == installed/executable: os.kill(int(entry.name), 15)
                except (OSError, ProcessLookupError): pass
        else:
            # Windows test runners expose PowerShell/CIM; arguments are data.
            script = '$paths=@($env:FFIDO_QA_EXE,$env:FFIDO_QA_HELPER); $p=@(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -in $paths }); $p | Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine | ConvertTo-Json; $p | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }'
            inventory = subprocess.run(['powershell', '-NoProfile', '-Command', script], env={**environment, 'FFIDO_QA_EXE': str(installed/executable), 'FFIDO_QA_HELPER': str(helper)}, text=True, capture_output=True, check=False)
            (reports/'processes.json').write_text(inventory.stdout)
        if updater is not None and updater.poll() is None:
            updater.terminate(); updater.wait(timeout=15)
        for child, log in children:
            if child.poll() is None: child.terminate(); child.wait(timeout=15)
            log.close()
        for name in ['freeze.log', 'A.log', 'B.log']:
            if (work/name).exists():
                shutil.copy2(work/name, reports/name)
                if name == 'B.log': print((work/name).read_text(errors='replace')[-8192:])
        if (reports/'installed-update.log').exists():
            print((reports/'installed-update.log').read_text(errors='replace')[-8192:])
        for path, original in restore_preferences.items():
            if original is None: path.unlink(missing_ok=True)
            else: path.write_bytes(original)
        shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=pathlib.Path, required=True)
    parser.add_argument('--directory', type=pathlib.Path, required=True)
    run(parser.parse_args())
