"""Deterministic Ed25519 signatures and Sparkle feeds for trusted releases."""
import base64
import hashlib
import json
import os
import pathlib
import re
import sys
import xml.etree.ElementTree as ET
from update_metadata import select_update_key

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.update.common import asset_url, validate_manifest


def load_key():
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
    key_id = os.environ.get('FFIDO_UPDATE_KEY_ID', '')
    if not re.fullmatch(r'[A-Za-z0-9._-]{1,64}', key_id):
        raise ValueError('Missing or invalid FFIDO_UPDATE_KEY_ID')
    try:
        key = Ed25519PrivateKey.from_private_bytes(base64.b64decode(
            os.environ.get('FFIDO_UPDATE_PRIVATE_KEY', ''), validate=True))
    except (ValueError, TypeError) as error:
        raise ValueError('FFIDO_UPDATE_PRIVATE_KEY must contain a base64 Ed25519 seed') from error
    keys = json.loads((ROOT/'scripts/update/public_keys.json').read_text())
    settings = json.loads((ROOT/'scripts/release/settings.json').read_text())
    selected, _ = select_update_key(keys, settings)
    if selected != key_id:
        raise ValueError('Select update_key_id in release settings to match the macOS embedded key')
    public = base64.b64encode(key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()
    if keys.get(key_id) != public:
        raise ValueError('Release key is not trusted by this source distribution')
    return key_id, key


def signature(raw, key_id, key):
    return {'algorithm': 'Ed25519', 'key_id': key_id,
            'signature': base64.b64encode(key.sign(raw)).decode()}


def appcasts(directory, identity, rows, key):
    """Immutable per-release feeds; no shared mutable feed is published."""
    namespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
    ET.register_namespace('sparkle', namespace)
    records = []
    for row in rows:
        if row['component'] != 'client' or row['platform']['os'] != 'macos':
            continue
        path = directory/row['file']
        if path.stat().st_size != row['size'] or hashlib.sha256(path.read_bytes()).hexdigest() != row['sha256']:
            raise ValueError('macOS archive differs from manifest')
        root = ET.Element('rss', {'version': '2.0'})
        channel = ET.SubElement(root, 'channel')
        ET.SubElement(channel, 'title').text = 'FFIDO'
        item = ET.SubElement(channel, 'item')
        ET.SubElement(item, 'title').text = identity['tag']
        # CFBundleVersion is the monotonically increasing Android-compatible build number.
        ET.SubElement(item, '{'+namespace+'}version').text = str(identity['build_number'])
        ET.SubElement(item, '{'+namespace+'}shortVersionString').text = identity['version']
        ET.SubElement(item, '{'+namespace+'}minimumSystemVersion').text = row['min_os']['version']
        ET.SubElement(item, 'enclosure', {
            'url': asset_url(identity['tag'], row['file']), 'length': str(row['size']),
            'type': 'application/octet-stream', '{'+namespace+'}edSignature':
                base64.b64encode(key.sign(path.read_bytes())).decode()})
        content = ET.tostring(root, encoding='utf-8', xml_declaration=True)+b'\n'
        # Sparkle 2.10 signing-block format (common_cli/Signing.swift).
        block = ('<!-- sparkle-signatures:\nedSignature: '+base64.b64encode(key.sign(content)).decode()
                 +'\nlength: '+str(len(content))+'\n-->\n').encode()
        raw = content+block
        name = row['id']+'-appcast.xml'
        (directory/name).write_bytes(raw)
        records.append({'package_id': row['id'], 'file': name, 'size': len(raw),
                        'sha256': hashlib.sha256(raw).hexdigest()})
    return records


def sign_manifest(directory, data, key_id, key):
    validate_manifest(data)
    raw = (json.dumps(data, indent=2, ensure_ascii=False)+'\n').encode('utf-8')
    (directory/'release-manifest.json').write_bytes(raw)
    (directory/'release-manifest.sig').write_text(json.dumps(signature(raw, key_id, key), indent=2)+'\n')
