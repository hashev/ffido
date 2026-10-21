#!/usr/bin/env python3
"""Verify checksums and start extracted CI packages on their native runner."""
import argparse
import hashlib
import json
import os
import pathlib
import plistlib
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import time
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]


def run(*command, **kwargs):
    command = list(map(str, command))
    command[0] = shutil.which(command[0]) or command[0]
    return subprocess.run(command, check=True, **kwargs)


def launch(command, directory):
    with (directory/'launch.log').open('w+') as log:
        process = subprocess.Popen(command, cwd=directory, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=os.name != 'nt')
        try:
            time.sleep(8)
            if process.poll() is not None:
                log.seek(0)
                raise RuntimeError('Packaged client exited during startup: '+log.read())
        finally:
            if process.poll() is None:
                if os.name == 'nt':
                    process.terminate()
                else:
                    os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)


def smoke(row, packages):
    package = packages/row['file']
    if hashlib.sha256(package.read_bytes()).hexdigest() != row['sha256']:
        raise ValueError('Package checksum mismatch')
    component, target, _ = row['id'].split('-')
    with tempfile.TemporaryDirectory(prefix='ffido-package-smoke-') as temporary:
        directory = pathlib.Path(temporary)
        if target == 'android':
            with zipfile.ZipFile(package) as apk:
                assert apk.read('assets/flutter_assets/assets/legal/LICENSE') == (ROOT/'LICENSE').read_bytes()
            print('PASS: APK checksum and embedded license; device installation requires a separate emulator/device check')
            return
        if package.suffix == '.dmg':
            mounted = subprocess.check_output(['hdiutil', 'attach', '-readonly', '-nobrowse', '-plist', str(package)])
            volume = next(pathlib.Path(e['mount-point']) for e in plistlib.loads(mounted)['system-entities'] if 'mount-point' in e)
            try:
                shutil.copytree(volume/'fido.app', directory/'fido.app', symlinks=True)
            finally:
                run('hdiutil', 'detach', volume)
            bundle = directory/'fido.app'
            info = plistlib.loads((bundle/'Contents/Info.plist').read_bytes())
            assert info['CFBundleVersion'] == str(row['build_number'])
            assert info['SURequireSignedFeed'] and info['SUVerifyUpdateBeforeExtraction']
            assert info['SUEnableInstallerLauncherService']
            assert not info['SUEnableAutomaticChecks']
            assert (bundle/'Contents/Frameworks/Sparkle.framework').is_dir()
            embedded = json.loads((bundle/'Contents/Frameworks/App.framework/Resources/flutter_assets/assets/updates/identity.json').read_text())
            assert all(embedded[key] == row[key] for key in ('tag', 'sha', 'build_number'))
            trusted = json.loads((ROOT/'scripts/update/public_keys.json').read_text())
            settings = json.loads((ROOT/'scripts/release/settings.json').read_text())
            key_id = settings.get('update_key_id') or (next(iter(trusted)) if len(trusted) == 1 else '')
            assert info.get('SUPublicEDKey', '') == trusted.get(key_id, '')
            entitlements = plistlib.loads(subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(bundle)], stderr=subprocess.DEVNULL))
            assert entitlements['com.apple.security.app-sandbox']
            lookup = entitlements['com.apple.security.temporary-exception.mach-lookup.global-name']
            assert all(info['CFBundleIdentifier']+suffix in lookup for suffix in ('-spks', '-spki'))
            run('codesign', '--verify', '--deep', '--strict', bundle)
            launch([str(directory/'fido.app/Contents/MacOS/fido'), '--profile', 'package-smoke-'+str(os.getpid())], directory)
        else:
            if package.suffix == '.zip':
                with zipfile.ZipFile(package) as archive:
                    archive.extractall(directory)
                stage = directory
            else:
                with tarfile.open(package) as archive:
                    archive.extractall(directory, filter='data')
                stage = next(directory.iterdir())
            if component == 'server':
                binary = stage/'bin/fidoback'
                if target == 'linux':
                    output = subprocess.check_output(['ldd', str(binary)], text=True)
                    assert 'not found' not in output
                    print(output)
                else:
                    run('otool', '-L', binary)
                relink = stage/'share/ffido/relink'
                run('sh', relink/'relink.sh')
                run(relink/'bin/ffido-admin', '--help', timeout=30)
                run(stage/'bin/ffido-admin', '--help', timeout=30)
                run(sys.executable, ROOT/'scripts/test_admin.py', stage/'bin/ffido-admin')
                run(sys.executable, ROOT/'scripts/test_hpt_wrapper.py', stage/'bin/ffido-run-hpt')
                run(sys.executable, ROOT/'scripts/update/test_server_flow.py', '--bundle', stage, '--directory', directory/'managed-server-qa')
                run('flutter', 'pub', 'get', '--enforce-lockfile', cwd=ROOT/'apps/frontend')
                run(sys.executable, ROOT/'scripts/check_acceptance.py', '--native-only', '--server', binary)
            elif target == 'windows':
                run(stage/'ffido-updater.exe', '--help', timeout=30)
                launch([str(stage/'fido.exe')], directory)
            else:
                run(stage/'ffido-updater', '--help', timeout=30)
                binary = stage/'fido'
                output = subprocess.check_output(['ldd', str(binary)], text=True)
                assert 'not found' not in output
                print(output)
                launch(['xvfb-run', '-a', str(binary)], directory)
        print('PASS: extracted package startup and checksum:', row['id'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package_id')
    parser.add_argument('--packages', type=pathlib.Path, default=ROOT/'build/packages')
    args = parser.parse_args()
    rows = [json.loads(path.read_text()) for path in args.packages.glob('*.package.json')]
    selected = [row for row in rows if row['id'] == args.package_id]
    if len(selected) != 1:
        raise SystemExit('Expected exactly one package manifest for '+args.package_id)
    smoke(selected[0], args.packages)
