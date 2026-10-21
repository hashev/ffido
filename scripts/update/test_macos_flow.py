#!/usr/bin/env python3
"""Build isolated real Flutter A/B bundles and test coordinated Sparkle update."""
import argparse
import base64
import functools
import http.server
import json
import os
import pathlib
import plistlib
import shutil
import signal
import subprocess
import tempfile
import threading
import time
import uuid
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
ROOT = pathlib.Path(__file__).resolve().parents[2]


def wait(predicate, timeout=90):
    deadline = time.monotonic()+timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value: return value
        time.sleep(.1)
    raise RuntimeError('QA condition timed out')


def prepare_output(directory, production_keys=None):
    directory = directory.resolve()
    if production_keys is not None:
        keys = production_keys.resolve(strict=True)
        if directory.is_relative_to(keys) or keys.is_relative_to(directory):
            raise ValueError('QA output must not overlap the production key directory')
    # A failed rerun must never leave an old successful result looking current.
    directory.mkdir(mode=0o700, parents=True, exist_ok=False)
    return directory


def terminate_bundle(binary):
    # A relaunched B can fail before writing a status record. Its executable
    # path still identifies our isolated bundle without trusting stale A PIDs.
    binary = str(binary)
    listing = subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True)
    for line in listing.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) != 2: continue
        pid, command = fields
        if command != binary and not command.startswith(binary+' '): continue
        try: os.kill(int(pid), signal.SIGTERM)
        except ProcessLookupError: pass


def run(flutter, directory, architecture, archive_format, read_only, invalid_signature, production_keys=None):
    directory = prepare_output(directory, production_keys)
    key_id = None
    if production_keys:
        key = Ed25519PrivateKey.from_private_bytes(base64.b64decode((production_keys/'update-private-seed.b64').read_bytes(), validate=True))
        anchors = json.loads((production_keys/'update-public.json').read_bytes())
        key_id = json.loads((ROOT/'scripts/release/settings.json').read_bytes())['update_key_id']
        assert anchors == json.loads((ROOT/'scripts/update/public_keys.json').read_bytes())
        assert anchors[key_id] == base64.b64encode(key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()
    else:
        key = Ed25519PrivateKey.generate()
    public = base64.b64encode(key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()
    bundle_id = 'io.github.hashev.ffido.updateqa'+uuid.uuid4().hex[:8]
    override = directory/'qa.xcconfig'
    override.write_text('PRODUCT_BUNDLE_IDENTIFIER = '+bundle_id+'\nFFIDO_UPDATE_SLASH = /\nFFIDO_UPDATE_PUBLIC_KEY = '+public.replace('/', '$(FFIDO_UPDATE_SLASH)')+'\nOTHER_SWIFT_FLAGS = $(inherited) -DFFIDO_UPDATER_TESTING\n')
    with override.open('a') as output:
        output.write('ARCHS = '+architecture+'\nONLY_ACTIVE_ARCH = NO\n')
    archive_name = 'update.'+archive_format
    support = pathlib.Path.home()/'Library/Containers'/bundle_id/'Data/Library/Application Support/FFIDO/UpdaterQA'
    web = directory/'www'; web.mkdir()
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(web))
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    origin = f'http://127.0.0.1:{server.server_port}'
    environment = {**os.environ, 'XCODE_XCCONFIG_FILE': str(override)}
    installed = directory/'installed/fido.app'
    children = []
    mounted = None
    try:
        for name, number in [('B', 2), ('A', 1)]:
            args = [str(flutter), 'build', 'macos', '--release', '--target', 'integration_test/managed_update_driver.dart', '--build-number', str(number), '--dart-define', 'FFIDO_QA_BUILD='+name]
            if name == 'A': args += ['--dart-define', 'FFIDO_QA_FEED='+origin+'/appcast.xml', '--dart-define', 'FFIDO_QA_PACKAGE='+origin+'/'+archive_name, '--dart-define', 'FFIDO_QA_KEY='+public]
            with (directory/('build-'+name+'.log')).open('w') as log:
                subprocess.run(args, cwd=ROOT/'apps/frontend', env=environment, stdout=log, stderr=subprocess.STDOUT, check=True)
            bundle = directory/name/'fido.app'
            bundle.parent.mkdir()
            shutil.copytree(ROOT/'apps/frontend/build/macos/Build/Products/Release/fido.app', bundle, symlinks=True)
            path = bundle/'Contents/Info.plist'
            info = plistlib.loads(path.read_bytes())
            assert info['CFBundleIdentifier'] == bundle_id and info['SUPublicEDKey'] == public, 'QA build settings were not applied'
            info['NSAppTransportSecurity'] = {'NSAllowsArbitraryLoads': True}
            path.write_bytes(plistlib.dumps(info))
            subprocess.run(['codesign', '--force', '--deep', '--preserve-metadata=entitlements', '--sign', '-', str(bundle)], check=True)
            if name == 'B':
                if archive_format == 'zip':
                    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(bundle), str(web/archive_name)], check=True)
                else:
                    subprocess.run(['hdiutil', 'create', '-quiet', '-format', 'UDZO', '-srcfolder', str(bundle.parent), str(web/archive_name)], check=True)
                archive = (web/archive_name).read_bytes()
                signature = base64.b64encode((Ed25519PrivateKey.generate() if invalid_signature else key).sign(archive)).decode()
                content = (f'<?xml version="1.0"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>FFIDO QA</title><item><title>Version 2</title><sparkle:version>2</sparkle:version><enclosure url="{origin}/{archive_name}" length="{len(archive)}" type="application/octet-stream" sparkle:edSignature="{signature}" /></item></channel></rss>\n').encode()
                block = f'<!-- sparkle-signatures:\nedSignature: {base64.b64encode(key.sign(content)).decode()}\nlength: {len(content)}\n-->\n'.encode()
                (web/'appcast.xml').write_bytes(content+block)
            else:
                installed.parent.mkdir()
                shutil.copytree(bundle, installed, symlinks=True)
        if read_only:
            image = directory/'read-only-A.dmg'
            subprocess.run(['hdiutil', 'create', '-quiet', '-format', 'UDZO', '-srcfolder', str(directory/'A'), str(image)], check=True)
            value = plistlib.loads(subprocess.check_output(['hdiutil', 'attach', '-readonly', '-nobrowse', '-plist', str(image)]))
            mounted = next(pathlib.Path(item['mount-point']) for item in value['system-entities'] if 'mount-point' in item)
            installed = mounted/'fido.app'
        binary = installed/'Contents/MacOS/fido'
        def record(profile):
            try: return json.loads((support/(profile+'.json')).read_text())
            except (FileNotFoundError, json.JSONDecodeError): return {}
        for profile in (['default'] if read_only or invalid_signature else ['p2', 'default']):
            log = (directory/(profile+'.log')).open('w')
            child = subprocess.Popen([str(binary), '--profile', profile], stdout=log, stderr=subprocess.STDOUT)
            children.append((child, log))
            wait(lambda: record(profile).get('version') == '1')
        wait(lambda: record('default').get('status') == 'blocked')
        if read_only or invalid_signature:
            error = record('default').get('error', '')
            code = record('default').get('errorCode')
            assert (code == 1003 and '\n' in error) if read_only else (code in [3001, 3002] or (code == 4005 and 'signed' in error.lower())), error
            assert record('default')['version'] == '1' and record('default')['prefsOK']
            result = {'architecture': architecture, 'read_only_rejected': read_only, 'invalid_signature_rejected': invalid_signature, 'move_instruction': read_only, 'version_preserved': '1', 'error': error}
            (directory/'result.json').write_text(json.dumps(result, indent=2)+'\n')
            print(json.dumps(result)); return
        assert all(record(profile).get('secureSession') for profile in ['p2', 'default']), 'A sessions were not readable from Keychain'
        assert all(record(profile).get('version') == '1'  for profile in ['p2', 'default']), 'Busy peer did not block installation'
        assert all(child.poll() is None for child, _ in children), 'A profile exited despite refusing update'
        (support/'allow').write_text('allow test update')
        def complete():
            # Reap directly launched profiles: Sparkle waits for their PIDs to
            # disappear, including zombies retained by this test harness.
            for child, _ in children: child.poll()
            if record('default').get('status') == 'failed': raise RuntimeError(record('default').get('error'))
            return all(record(profile).get('version') == '2' for profile in ['p2', 'default'])
        wait(complete)
        assert all(record(profile).get('sessionWrittenAndReadByA') is False for profile in ['p2', 'default']), 'B must not rewrite A sessions'
        assert all(record(profile).get('prefsOK') for profile in ['p2', 'default']), 'Profile preferences did not survive update'
        sessions = {profile: {'preserved': record(profile).get('secureSession'), 'keychain_status': record(profile).get('keychainStatus')} for profile in ['default', 'p2']}
        assert all(row['preserved'] or row['keychain_status'] in [-25293, -25308] for row in sessions.values()), sessions
        result = {'production_update_key': bool(production_keys), 'update_key_id': key_id, 'sessions': sessions, 'session_storage': 'real SecureSessionStore / login Keychain; B requests a noninteractive Keychain read', 'a_sessions_written_and_read': True, 'architecture': subprocess.check_output(['lipo', '-archs', str(binary)], text=True).strip(), 'from': 1, 'to': 2, 'profiles': ['default', 'p2'], 'busy_peer_blocks': True, 'preferences_preserved': True}
        (directory/'result.json').write_text(json.dumps(result, indent=2)+'\n')
        print(json.dumps(result))
    finally:
        terminate_bundle(installed/'Contents/MacOS/fido')
        for child, log in children:
            if child.poll() is None: child.terminate()
            try: child.wait(timeout=10)
            except subprocess.TimeoutExpired: child.kill(); child.wait()
            log.close()
        server.shutdown(); server.server_close()
        # Only the two synthetic accounts created by this uniquely named QA bundle.
        endpoint = 'https://'+bundle_id+'.update-qa.invalid:8080'
        for profile in ['default', 'p2']:
            account = 'ffido_session_v1:'+endpoint if profile == 'default' else 'ffido_profile_session_v1:'+profile+':'+endpoint
            subprocess.run(['security', 'delete-generic-password', '-s', 'flutter_secure_storage_service', '-a', account], capture_output=True, timeout=10)
        if mounted is not None: subprocess.run(['hdiutil', 'detach', str(mounted)], check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--flutter', type=pathlib.Path, required=True)
    parser.add_argument('--directory', type=pathlib.Path, required=True)
    parser.add_argument('--architecture', choices=['arm64', 'x86_64'], default='arm64')
    parser.add_argument('--archive-format', choices=['zip', 'dmg'], default='dmg')
    parser.add_argument('--read-only', action='store_true')
    parser.add_argument('--invalid-signature', action='store_true')
    parser.add_argument('--production-keys', type=pathlib.Path, help='Read signing material in place; never copy it into QA output')
    args = parser.parse_args()
    run(args.flutter.resolve(), args.directory.resolve(), args.architecture, args.archive_format, args.read_only, args.invalid_signature, args.production_keys.resolve() if args.production_keys else None)
