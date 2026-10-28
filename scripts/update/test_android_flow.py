#!/usr/bin/env python3
"""Real release APK A→B via FFIDO's bridge and the Android system installer.

Only disposable emulator serials are accepted. All keys and APKs stay in build/.
ADB UIAutomator drives OS dialogs, never a user's phone or desktop UI.
"""
import argparse
import functools
import base64
import hashlib
import http.server
import json
import os
import pathlib
import re
import secrets
import shutil
import subprocess
import struct
import threading
import time
import xml.etree.ElementTree as ET
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
PACKAGE = 'io.github.hashev.ffido'


def wait(predicate, timeout=90):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = predicate()
        if result is not None and result is not False:
            return result
        time.sleep(.4)
    raise RuntimeError('Android update QA condition timed out')


def launch_updated(device, ready, timeout=90):
    # VersionCode becomes visible before API 24/25 finishes replacement
    # broadcasts. A premature launch can be stopped by 'pkg removed'.
    last_start = 0
    def launched():
        nonlocal last_start
        if ready(): return True
        if time.monotonic()-last_start >= 3:
            device('shell', 'am', 'start', '-n', PACKAGE+'/.MainActivity')
            last_start = time.monotonic()
        return False
    return wait(launched, timeout=timeout)


def prepare_output(directory, production_keys=None):
    directory = directory.resolve()
    if production_keys is not None:
        keys = production_keys.resolve(strict=True)
        if directory.is_relative_to(keys) or keys.is_relative_to(directory):
            raise ValueError('QA output must not overlap the production key directory')
    # A failed rerun must never leave an old successful result looking current.
    directory.mkdir(mode=0o700, parents=True, exist_ok=False)
    return directory


def adb_command(adb, serial, command, attempts=3):
    recoverable = (command[:2] in [('shell', 'getprop'), ('shell', 'dumpsys')]
                   or command[0] in ('logcat', 'reverse')
                   or command[:3] == ('shell', 'pm', 'list'))
    for attempt in range(attempts):
        try:
            return subprocess.check_output([str(adb), '-s', serial, *command], text=True,
                                           stderr=subprocess.STDOUT, timeout=120 if command[0] == 'install' else 30)
        except subprocess.CalledProcessError as error:
            transport = any(marker in (error.output or '').lower() for marker in
                            ('device offline', 'device not found', 'no devices/emulators',
                             'transport error', 'protocol fault'))
            if not recoverable or not transport or attempt+1 == attempts:
                print(f'ADB command failed: {command}: {error.output}', flush=True)
                raise
            print(f'ADB transport recovery {attempt+1}/{attempts}: {serial}', flush=True)
            subprocess.run([str(adb), '-s', serial, 'wait-for-device'], check=True, timeout=30,
                           stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)


class QAEvents:
    """Keep app events even when Android rotates its busy main log buffer."""
    def __init__(self, adb, serial, directory):
        self.path = directory/'flutter-stream.log'
        self.output = self.path.open('wb')
        try:
            self.process = subprocess.Popen([str(adb), '-s', serial, 'logcat', '-b', 'main',
                                             '-v', 'brief', '-s', 'flutter:I', '*:S'],
                                            stdout=self.output, stderr=subprocess.STDOUT)
        except OSError:
            self.output.close()
            raise

    def records(self):
        if self.process.poll() is not None:
            raise RuntimeError('ADB app event stream stopped; see flutter-stream.log')
        records = []
        for line in self.path.read_bytes().splitlines(keepends=True):
            if line.endswith(b'\n') and b'FFIDO_UPDATE_QA ' in line:
                records.append(json.loads(line.split(b'FFIDO_UPDATE_QA ', 1)[1]))
        return records

    def close(self):
        try:
            if self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(timeout=5)
        finally:
            self.output.close()


def window_nodes(device, directory):
    device('shell', 'uiautomator', 'dump', '/sdcard/ffido-update-qa.xml')
    # Old Android shell streams can truncate XML and return status 255.
    # File transfer preserves the full dump; malformed XML remains an error.
    path = directory/'window.xml'
    device('pull', '/sdcard/ffido-update-qa.xml', str(path))
    return list(ET.parse(path).iter('node'))


QA_PORT = 8765


def fixture_manifest(directory):
    web = directory/'www'
    entries = sorted(web.iterdir())
    if any(not path.is_file() or path.is_symlink() for path in entries):
        raise ValueError('Unexpected QA fixture directory or symlink')
    files = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in entries}
    expected = {'A.apk', 'B.apk', 'foreign-key.apk', 'foreign-id.apk', 'lower.apk'}
    if set(files) != expected:
        raise ValueError('Unexpected or incomplete QA APK inventory')
    return {'schema': 1, 'sha': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
            'origin': f'http://127.0.0.1:{QA_PORT}', 'from': 41001, 'to': 41002,
            'files': files, 'production_certificate': False, 'certificate_sha256': None}


def read_fixtures(directory):
    manifest = json.loads((directory/'fixtures.json').read_text())
    if manifest != fixture_manifest(directory):
        raise ValueError('QA fixture identity, origin or checksums mismatch')
    if any(directory.glob('*.jks')) or (directory/'password.txt').exists():
        raise ValueError('Private QA keys must not be distributed')
    return manifest


def prepare_apks(args, directory, port):
    sdk = args.sdk.resolve()
    environment = dict(os.environ)
    if args.java_home:
        environment['JAVA_HOME'] = str(args.java_home.resolve())
    java_bin = pathlib.Path(environment['JAVA_HOME'])/'bin' if environment.get('JAVA_HOME') else None
    keytool = str(java_bin/'keytool') if java_bin else shutil.which('keytool')
    tools = sdk/'build-tools'/args.build_tools
    web = directory/'www'
    web.mkdir(exist_ok=True)
    password = directory/'password.txt'
    password.write_text(secrets.token_urlsafe(32)); password.chmod(0o600)
    for name in (['foreign'] if args.production_keys else ['trusted', 'foreign']):
        key = directory/(name+'.jks')
        if not key.exists():
            subprocess.run([keytool, '-genkeypair', '-keystore', str(key), '-alias', 'qa', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '2', '-dname', 'CN=FFIDO ephemeral update QA', '-storepass:file', str(password), '-keypass:file', str(password)], env=environment, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    production_metadata = None
    production_signer = None
    sign_environment = environment
    if args.production_keys:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
        production_metadata = json.loads((args.production_keys/'android-signing-metadata.json').read_bytes())
        credentials = json.loads((args.production_keys/'android-signing-passwords.json').read_bytes())
        sign_environment = {**environment, 'FFIDO_QA_STORE_PASSWORD': credentials['store_password'], 'FFIDO_QA_KEY_PASSWORD': credentials['key_password']}
        production_signer = Ed25519PrivateKey.from_private_bytes(base64.b64decode((args.production_keys/'update-private-seed.b64').read_bytes(), validate=True))
        key_id = json.loads((ROOT/'scripts/release/settings.json').read_bytes())['update_key_id']
        anchors = json.loads((ROOT/'scripts/update/public_keys.json').read_bytes())
        assert anchors[key_id] == base64.b64encode(production_signer.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()
    def sign(source, destination, key='trusted'):
        if args.production_keys and key == 'trusted':
            arguments = ['--ks', str(args.production_keys/'ffido-release.jks'), '--ks-key-alias', credentials['alias'], '--ks-pass', 'env:FFIDO_QA_STORE_PASSWORD', '--key-pass', 'env:FFIDO_QA_KEY_PASSWORD']
        else:
            arguments = ['--ks', str(directory/(key+'.jks')), '--ks-key-alias', 'qa', '--ks-pass', 'file:'+str(password)]
        subprocess.run([str(tools/'apksigner'), 'sign', '--v4-signing-enabled', 'false', *arguments, '--out', str(destination), str(source)], env=sign_environment if args.production_keys and key == 'trusted' else environment, check=True)
        verified = subprocess.check_output([str(tools/'apksigner'), 'verify', '--print-certs', str(destination)], env=environment, text=True)
        if args.production_keys and key == 'trusted':
            assert production_metadata['certificate_sha256'].replace(':', '').lower() in verified.replace(':', '').lower()
    try:
        for stage, number in [('B', 41002), ('A', 41001)]:
            output = directory/('build-'+stage+'.log')
            if stage == 'B' and args.prebuilt_b:
                source = args.prebuilt_b.resolve()
            else:
                # Flutter must regenerate the release registrant after pub get,
                # which includes dev plugins that Gradle excludes from release.
                command = [str(args.flutter.resolve()), '--no-version-check', 'build', 'apk', '--release', '--target', 'integration_test/android_update_driver.dart', '--build-number', str(number), '--build-name', '1.0.0' if stage == 'A' else '1.0.1', '--dart-define', 'FFIDO_QA_VERIFY_MANIFEST='+str(bool(args.production_keys)).lower(), '--dart-define', 'FFIDO_QA_STAGE='+stage, '--dart-define', f'FFIDO_QA_ORIGIN=http://127.0.0.1:{port}']
                build_environment = environment
                if args.production_keys:
                    build_environment = {**environment, 'FFIDO_PUBLIC_RELEASE': 'true',
                        'FFIDO_ANDROID_KEYSTORE': str(args.production_keys/'ffido-release.jks'),
                        'FFIDO_ANDROID_STORE_PASSWORD': credentials['store_password'],
                        'FFIDO_ANDROID_KEY_PASSWORD': credentials['key_password'],
                        'FFIDO_ANDROID_KEY_ALIAS': credentials['alias']}
                with output.open('w') as log:
                    subprocess.run(command, cwd=ROOT/'apps/frontend', env=build_environment, check=True, stdout=log, stderr=subprocess.STDOUT)
                source = ROOT/'apps/frontend/build/app/outputs/flutter-apk/app-release.apk'
            preserved = directory/(stage+'-source.apk')
            shutil.copy2(source, preserved)
            sign(preserved, web/(stage+'.apk'))
        if production_signer:
            compatibility = {'protocol_major': 1, 'client_protocol_min': 1, 'client_protocol_max': 1, 'server_protocol_min': 1, 'server_protocol_max': 1, 'state_schema_min': 9, 'state_schema_max': 9, 'config_format': 1, 'jam_format': 'JAM-1'}
            identity = {'version': '1.0.1', 'tag': 'v1.0.1', 'sha': '0'*40, 'stable': True, 'build_number': 41002}
            package = {**identity, 'id': 'client-android-universal', 'component': 'client', 'platform': {'os': 'android', 'architecture': 'universal'}, 'min_os': {'api': 24}, 'signing': 'release', 'compatibility': compatibility, 'file': 'B.apk', 'size': (web/'B.apk').stat().st_size, 'sha256': hashlib.sha256((web/'B.apk').read_bytes()).hexdigest()}
            manifest = {'schema_version': 1, 'identity': identity, 'channel': 'stable', 'update_sequence': 41002, 'compatibility': compatibility, 'packages': [package]}
            raw = json.dumps(manifest).encode()
            (web/'release-manifest.json').write_bytes(raw)
            (web/'release-manifest.sig').write_text(json.dumps({'algorithm': 'Ed25519', 'key_id': key_id, 'signature': base64.b64encode(production_signer.sign(raw)).decode()}))
        sign(directory/'B-source.apk', web/'foreign-key.apk', 'foreign')
        foreign = directory/'foreign-id-unsigned.apk'
        with zipfile.ZipFile(directory/'B-source.apk') as source, zipfile.ZipFile(foreign, 'w') as target:
            for entry in source.infolist():
                raw = source.read(entry)
                if entry.filename == 'AndroidManifest.xml':
                    before = raw
                    for encoding in ['utf-8', 'utf-16le']:
                        raw = raw.replace(PACKAGE.encode(encoding), 'io.github.hashev.ffidq'.encode(encoding))
                    assert before != raw, 'Fixture package identity was not changed'
                target.writestr(entry, raw)
        sign(foreign, web/'foreign-id.apk')
        lower = directory/'lower-unsigned.apk'
        with zipfile.ZipFile(directory/'B-source.apk') as source, zipfile.ZipFile(lower, 'w') as target:
            for entry in source.infolist():
                raw = source.read(entry)
                if entry.filename == 'AndroidManifest.xml':
                    raw = bytearray(raw); offset = 8; version_index = None; changed = False
                    while offset < len(raw):
                        kind, header, size = struct.unpack_from('<HHI', raw, offset)
                        assert size >= header >= 8
                        if kind == 0x180:  # Resource map: android.R.attr.versionCode.
                            ids = struct.unpack_from('<'+'I'*((size-header)//4), raw, offset+header)
                            version_index = ids.index(0x0101021b)
                        elif kind == 0x102 and version_index is not None:
                            start, stride, count = struct.unpack_from('<HHH', raw, offset+24)
                            for index in range(count):
                                attribute = offset+16+start+index*stride
                                if struct.unpack_from('<I', raw, attribute+4)[0] == version_index:
                                    assert raw[attribute+15] == 0x10
                                    struct.pack_into('<I', raw, attribute+16, 41000); changed = True
                        offset += size
                    assert changed, 'Fixture versionCode was not changed'
                target.writestr(entry, raw)
        sign(lower, web/'lower.apk')
        return {'production_certificate': bool(args.production_keys),
                'certificate_sha256': production_metadata['certificate_sha256'] if production_metadata else None}
    finally:
        for name in ['password.txt', 'trusted.jks', 'foreign.jks']:
            (directory/name).unlink(missing_ok=True)


def run(args):
    if args.prepare_only and (args.production_keys or args.fixtures):
        raise ValueError('Shared fixtures require disposable QA keys and a fresh build')
    if args.fixtures and args.production_keys:
        raise ValueError('Shared fixtures cannot use production keys')
    if not args.prepare_only and not re.fullmatch(r'emulator-\d+', args.serial or ''):
        raise ValueError('Use an explicitly selected disposable emulator')
    if not args.fixtures and not args.flutter:
        raise ValueError('Flutter is required to prepare QA APKs')
    directory = prepare_output(args.directory, args.production_keys)
    if args.fixtures:
        metadata = read_fixtures(args.fixtures.resolve())
        shutil.copytree(args.fixtures.resolve()/'www', directory/'www')
    else:
        metadata = prepare_apks(args, directory, QA_PORT)
    if args.prepare_only:
        manifest = fixture_manifest(directory)
        (directory/'fixtures.json').write_text(json.dumps(manifest, indent=2)+'\n')
        read_fixtures(directory)
        return
    web = directory/'www'
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(web))
    server = http.server.ThreadingHTTPServer(('127.0.0.1', QA_PORT), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    port = QA_PORT
    adb = args.sdk.resolve()/'platform-tools/adb'
    def device(*command):
        return adb_command(adb, args.serial, command)
    events = None
    try:
        assert device('shell', 'getprop', 'ro.kernel.qemu').strip() == '1'
        wait(lambda: device('shell', 'getprop', 'sys.boot_completed').strip() == '1')
        api = int(device('shell', 'getprop', 'ro.build.version.sdk').strip())
        device('reverse', f'tcp:{port}', f'tcp:{port}')
        # Do not silently replace a real device install: this emulator is explicit.
        device('uninstall', PACKAGE) if PACKAGE in device('shell', 'pm', 'list', 'packages', PACKAGE) else None
        device('install', str(web/'A.apk'))
        # Fresh A must not inherit restored data from another QA run.
        assert device('shell', 'pm', 'clear', PACKAGE).strip() == 'Success'
        device('logcat', '-b', 'main', '-c')
        events = QAEvents(adb, args.serial, directory)
        device('shell', 'am', 'start', '-W', '-n', PACKAGE+'/.MainActivity')
        def records():
            return events.records()
        def ready(stage):
            return next((value for value in records() if value.get('stage') == stage and value.get('preferences') and value.get('secureSession') and value.get('footerPreferences')), None)
        wait(lambda: ready('A'))
        def nodes():
            return window_nodes(device, directory)
        def click(label):
            labels = {value.casefold() for value in (label if isinstance(label, tuple) else (label,))}
            def find():
                return next((node for node in nodes() if (node.get('text', '').casefold() in labels or node.get('content-desc', '').casefold() in labels) and node.get('enabled') == 'true'), None)
            node = wait(find)
            left, top, right, bottom = map(int, re.findall(r'\d+', node.get('bounds')))
            device('shell', 'input', 'tap', str((left+right)//2), str((top+bottom)//2))
        def result_since(count):
            return next((value.get('result') for value in records()[count:] if 'result' in value), None)
        checks = []
        # Permission denial, then permission grant and OS installer cancellation.
        if api >= 26:
            count = len(records()); click('Install B')
            wait(lambda: any(node.get('resource-id') == 'android:id/switch_widget' or 'Allow from this source' in node.get('text', '') for node in nodes()))
            device('shell', 'input', 'keyevent', 'KEYCODE_BACK')
            assert wait(lambda: result_since(count)) == 'cancelled'
            checks.append('permission_denied')
            click('Install B')
            click('Allow from this source')
            device('shell', 'input', 'keyevent', 'KEYCODE_BACK')
        else:
            # API 24/25 uses the global unknown-sources setting, absent per-app UI.
            device('shell', 'settings', 'put', 'global', 'install_non_market_apps', '1')
            device('shell', 'settings', 'put', 'secure', 'install_non_market_apps', '1')
            click('Install B')
        count = len(records()); click('Cancel')
        assert wait(lambda: result_since(count)) == 'cancelled'
        checks.extend(['pending_user_action', 'installer_cancelled'])
        if args.process_restart:
            # am kill deliberately spares processes referenced by a pending installer.
            # Root is used only on an explicitly selected disposable QA emulator;
            # unlike force-stop, SIGKILL preserves delivery to the private receiver.
            click('Install B')
            wait(lambda: any(node.get('text', '').casefold() == 'cancel' for node in nodes()))
            assert 'uid=0' in device('shell', 'su', '0', 'id')
            pid = device('shell', 'pidof', PACKAGE).strip()
            assert re.fullmatch(r'\d+', pid)
            device('shell', 'su', '0', 'kill', '-9', pid)
            wait(lambda: not device('shell', 'pidof '+PACKAGE+' || true').strip())
            click('Cancel')
            count = len(records())
            device('shell', 'am', 'start', '-W', '-n', PACKAGE+'/.MainActivity')
            assert wait(lambda: result_since(count)) == 'cancelled'
            checks.append('cancelled_result_after_process_restart')
        for name, expected in [('foreign-key', 'Подпись APK отличается'), ('foreign-id', 'Другой пакет'), ('A', 'Другой пакет'), ('lower', 'Другой пакет')]:
            count = len(records()); click('Install '+name)
            value = wait(lambda: result_since(count))
            assert expected in value, value
            checks.append('rejected_'+name)
        click('Install B'); click(('Update', 'Install'))
        print('Installer QA only. Play Protect is not checked by this fixture test; a warning or block must be recorded separately. Do not disable protection or upload private QA fixtures.', flush=True)
        wait(lambda: 'versionCode=41002' in device('shell', 'dumpsys', 'package', PACKAGE))
        launch_updated(device, lambda: ready('B'))
        wait(lambda: any(row.get('stage') == 'B' and row.get('recovered') == 'success' for row in records()))
        checks.append('successful_result_after_package_replacement')
        if metadata['production_certificate']: assert any(row.get('manifestVerified') is True for row in records())
        result = {'production_certificate': bool(args.production_keys), 'production_update_manifest_verified': metadata['production_certificate'], 'certificate_sha256': metadata['certificate_sha256'], 'api': api, 'from': 41001, 'to': 41002, 'release_apks': True, 'system_installer': True, 'same_ephemeral_certificate': not bool(args.production_keys), 'same_certificate': True, 'preferences_preserved': True, 'secure_session_preserved': True, 'footer_preferences_preserved': True, 'checks': checks, 'play_protect': {'status': 'not_checked', 'reason': 'isolated installer fixtures; not a certified-device security acceptance', 'apk_sha256': hashlib.sha256((web/'B.apk').read_bytes()).hexdigest()}}
        (directory/'result.json').write_text(json.dumps(result, indent=2)+'\n')
        (directory/'device.log').write_text(device('logcat', '-d', '-s', 'flutter:I', '*:S'))
        print(json.dumps(result))
    finally:
        if events is not None:
            try:
                events.close()
            except (OSError, subprocess.SubprocessError) as error:
                (directory/'stream-cleanup.log').write_text(str(error))
        try:
            (directory/'device-all.log').write_text(device('logcat', '-d'))
        except (subprocess.SubprocessError, OSError) as error:
            (directory/'diagnostics-error.log').write_text(str(error))
        try:
            device('reverse', '--remove', f'tcp:{port}')
        except subprocess.SubprocessError as error:
            print(f'ADB cleanup failed: {error}', flush=True)
        finally:
            server.shutdown(); server.server_close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', type=pathlib.Path)
    parser.add_argument('--sdk', type=pathlib.Path, required=True)
    parser.add_argument('--serial')
    parser.add_argument('--directory', type=pathlib.Path, required=True)
    parser.add_argument('--build-tools', default='36.0.0')
    parser.add_argument('--java-home', type=pathlib.Path)
    parser.add_argument('--prebuilt-b', type=pathlib.Path)
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--fixtures', type=pathlib.Path)
    parser.add_argument('--process-restart', action='store_true', help='Also verify process death on a rootable disposable QA emulator')
    parser.add_argument('--production-keys', type=pathlib.Path, help='Read production keys in place, only on the selected disposable emulator')
    args = parser.parse_args()
    if args.production_keys: args.production_keys = args.production_keys.resolve()
    run(args)
