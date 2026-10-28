#!/usr/bin/env python3
"""Audit the final APK; this is a release gate, not a Play Protect verdict."""
import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import zipfile

PACKAGE = 'io.github.hashev.ffido'
PERMISSIONS = sorted(['android.permission.INTERNET', 'android.permission.REQUEST_INSTALL_PACKAGES',
                      PACKAGE+'.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'])
# Baseline inspected in the official v1.0.4 APK. DUMP protects the AndroidX receiver.
COMPONENTS = sorted([
    {'kind': 'activity', 'name': PACKAGE+'.MainActivity', 'exported': True, 'permission': None},
    {'kind': 'receiver', 'name': PACKAGE+'.UpdateStatusReceiver', 'exported': False, 'permission': None},
    {'kind': 'provider', 'name': 'androidx.startup.InitializationProvider', 'exported': False, 'permission': None},
    {'kind': 'receiver', 'name': 'androidx.profileinstaller.ProfileInstallReceiver', 'exported': True,
     'permission': 'android.permission.DUMP'},
], key=lambda row: row['name'])
DECLARED_PERMISSIONS = [{'name': PACKAGE+'.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION', 'protection_level': 2}]
IDENTITY_ASSET = 'assets/flutter_assets/assets/updates/identity.json'
QA_MARKERS = (b'FFIDO_UPDATE_QA', b'ffido_update_qa_sentinel', b'update-qa.invalid')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def manifest_tree(text):
    """Parse aapt's binary-XML dump, retaining nesting and typed attributes."""
    root, stack = None, []
    for line in text.splitlines():
        element = re.match(r'(\s*)E: (\S+)', line)
        if element:
            level = len(element[1])
            node = {'tag': element[2], 'attrs': {}, 'children': []}
            while stack and stack[-1][0] >= level:
                stack.pop()
            if stack:
                stack[-1][1]['children'].append(node)
            elif root is None:
                root = node
            else:
                raise ValueError('Multiple manifest roots')
            stack.append((level, node))
        else:
            attr = re.match(r'\s*A: ([\w:]+)(?:\(0x[0-9a-f]+\))?=(.*)', line)
            if attr and stack:
                value = attr[2]
                if value.startswith('"'):
                    value = json.JSONDecoder().raw_decode(value)[0]
                elif re.fullmatch(r'\(type 0x[0-9a-f]+\)0x[0-9a-f]+', value):
                    value = int(value.split(')')[1], 16)
                else:
                    # Resource references remain explicit; security fields must be literal.
                    value = value.strip()
                stack[-1][1]['attrs'][attr[1]] = value
    if not root or root['tag'] != 'manifest':
        raise ValueError('Cannot read binary Android manifest')
    return root


def manifest_record(text):
    root = manifest_tree(text)
    def single(tag):
        values = [node for node in root['children'] if node['tag'] == tag]
        if len(values) != 1:
            raise ValueError('Expected one '+tag)
        return values[0]
    app = single('application')
    attrs, sdk = root['attrs'], single('uses-sdk')['attrs']
    components = []
    for node in app['children']:
        if node['tag'] not in ('activity', 'activity-alias', 'receiver', 'service', 'provider'):
            continue
        fields = node['attrs']
        name = fields.get('android:name', '')
        if name.startswith('.'):
            name = attrs['package']+name
        elif '.' not in name:
            name = attrs['package']+'.'+name
        exported = fields.get('android:exported')
        if exported not in (0, 0xffffffff):
            raise ValueError('Component export must be explicit: '+name)
        components.append({'kind': node['tag'], 'name': name, 'exported': exported != 0,
                           'permission': fields.get('android:permission', app['attrs'].get('android:permission'))})
    return {'application_id': attrs.get('package'), 'version_name': attrs.get('android:versionName'),
            'version_code': attrs.get('android:versionCode'),
            'min_sdk': sdk.get('android:minSdkVersion'), 'target_sdk': sdk.get('android:targetSdkVersion'),
            'debuggable': app['attrs'].get('android:debuggable', 0),
            'test_only': app['attrs'].get('android:testOnly', 0),
            'permissions': sorted(node['attrs'].get('android:name', '') for node in root['children']
                                  if node['tag'].startswith('uses-permission')),
            'declared_permissions': sorted([{'name': node['attrs'].get('android:name'),
                 'protection_level': node['attrs'].get('android:protectionLevel', 0)}
                 for node in root['children'] if node['tag'] == 'permission'], key=lambda row: row['name']),
            'components': sorted(components, key=lambda row: row['name'])}


def validate_record(record, identity, certificate):
    fingerprint = certificate.replace(':', '').lower()
    if not re.fullmatch('[0-9a-f]{64}', fingerprint):
        raise ValueError('Expected permanent Android certificate SHA-256')
    expected = {'schema_version': 1, 'identity': identity, 'certificate_sha256': fingerprint,
                'application_id': PACKAGE, 'version_name': identity['version'],
                'version_code': identity['build_number'], 'min_sdk': 24, 'target_sdk': 36,
                'debuggable': 0, 'test_only': 0, 'permissions': PERMISSIONS, 'components': COMPONENTS,
                'declared_permissions': DECLARED_PERMISSIONS,
                'qa_markers_found': False, 'play_protect': 'not_checked'}
    for field, value in expected.items():
        if record.get(field) != value:
            raise ValueError('Android audit mismatch: '+field)


def contains_qa(archive):
    for name in archive.namelist():
        if any(marker in name.lower() for marker in ('fixture', 'integration_test', 'update_driver')):
            return True
        if name.endswith(('/libapp.so', '.dex', '.dill', '.snapshot')):
            data = archive.read(name)
            if any(marker in data for marker in QA_MARKERS):
                return True
    return False


def verify_certificate(output, certificate):
    """Read numbered and SDK-scoped signers; source stamps are not APK signers."""
    fingerprints = []
    scope = r'\(minSdkVersion=\d+(?: \(dev release=true\))?, maxSdkVersion=\d+\)'
    label = (r'(?:Signer(?: #\d+| '+scope+r')|V(?:1|2|3\.[01]) Signer(?: #\d+)?:|'
             r'V3\.[01] Signer: '+scope+r')')
    for line in output.splitlines():
        if ' certificate SHA-256 digest:' not in line or line.startswith('Source Stamp Signer'):
            continue
        match = re.fullmatch(label+r' certificate SHA-256 digest: ([0-9a-fA-F]{64})', line)
        if not match:
            raise ValueError('Unrecognized APK signer certificate output')
        fingerprints.append(match[1].lower())
    if not fingerprints:
        raise ValueError('No APK signer certificate SHA-256 digest')
    fingerprint = certificate.replace(':', '').lower()
    if set(fingerprints) != {fingerprint}:
        raise ValueError('APK certificate does not match the permanent key: '+', '.join(fingerprints))
    if 'android debug' in output.lower():
        raise ValueError('Debug APK cannot be published')
    return fingerprint


def audit(apk, identity, certificate, sdk=None):
    apk = pathlib.Path(apk)
    sdk = pathlib.Path(sdk or os.environ['ANDROID_HOME'])
    # Use the latest stable installed build-tools, never silently skip missing tools.
    versions = [p for p in (sdk/'build-tools').iterdir() if re.fullmatch(r'\d+\.\d+\.\d+', p.name)]
    tools = max(versions, key=lambda p: tuple(map(int, p.name.split('.'))))
    def run(*args):
        return subprocess.check_output(list(map(str, args)), text=True)
    cert = run(tools/'apksigner', 'verify', '--print-certs', apk)
    fingerprint = verify_certificate(cert, certificate)
    record = manifest_record(run(tools/'aapt', 'dump', 'xmltree', apk, 'AndroidManifest.xml'))
    with zipfile.ZipFile(apk) as archive:
        if apk.read_bytes()[:4] != b'PK\x03\x04' or archive.testzip() is not None:
            raise ValueError('Invalid APK ZIP structure')
        if len(archive.namelist()) != len(set(archive.namelist())):
            raise ValueError('Duplicated APK entries')
        if json.loads(archive.read(IDENTITY_ASSET)) != identity:
            raise ValueError('APK embedded identity differs from release')
        abis = {name.split('/')[1] for name in archive.namelist() if name.endswith('/libapp.so')}
        if abis != {'arm64-v8a', 'armeabi-v7a', 'x86_64'}:
            raise ValueError('Universal APK must include the three supported ABIs')
        qa = contains_qa(archive)
    record.update(schema_version=1, identity=identity, certificate_sha256=fingerprint,
                  sha256=digest(apk), size=apk.stat().st_size, file=apk.name,
                  qa_markers_found=qa, play_protect='not_checked')
    validate_record(record, identity, fingerprint)
    return record


def validate_report(apk, identity, certificate):
    report = json.loads(pathlib.Path(str(apk)+'.audit.json').read_text())
    validate_record(report, identity, certificate)
    if (report.get('file') != apk.name or report.get('sha256') != digest(apk)
            or report.get('size') != apk.stat().st_size):
        raise ValueError('Android audit APK checksum mismatch')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=pathlib.Path, required=True)
    parser.add_argument('--identity', type=pathlib.Path, required=True)
    parser.add_argument('--certificate', default=os.environ.get('ANDROID_CERT_SHA256', ''))
    parser.add_argument('--sdk', type=pathlib.Path)
    args = parser.parse_args()
    report = audit(args.apk, json.loads(args.identity.read_text()), args.certificate, args.sdk)
    pathlib.Path(str(args.apk)+'.audit.json').write_text(json.dumps(report, indent=2)+'\n')
    print('PASS: final APK audit (Play Protect: not_checked)')
