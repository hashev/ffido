"""Structured update metadata shared by package staging and publication."""
import re
import base64

SCHEMA_VERSION = 1
# Supported formats, not permission to migrate a running installation.
# ReleaseSchemaCompatibility checks these bounds against a real SQLiteStore.
COMPATIBILITY = {
    'protocol_major': 1,
    'client_protocol_min': 1, 'client_protocol_max': 1,
    'server_protocol_min': 1, 'server_protocol_max': 1,
    'state_schema_min': 9, 'state_schema_max': 10,
    'config_format': 1, 'jam_format': 'JAM-1',
}


def release_metadata(identity):
    version, sha, tag = (identity.get(key) for key in ('version', 'sha', 'tag'))
    number, stable = identity.get('build_number'), identity.get('stable')
    if (not isinstance(version, str) or not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', version)
            or not isinstance(sha, str) or not re.fullmatch(r'[0-9a-f]{40}', sha)
            or type(number) is not int or not 0 < number < 2_000_000_000
            or type(stable) is not bool):
        raise ValueError('Invalid update identity')
    expected = 'v'+version
    if stable:
        valid = tag == expected
    else:
        valid = tag == f'{expected}-dev.{number}.{sha[:12]}'
    if not valid:
        raise ValueError('Update tag differs from release identity')
    return {'schema_version': SCHEMA_VERSION, 'update_sequence': number,
            'channel': 'stable' if stable else 'dev', 'compatibility': dict(COMPATIBILITY)}


def package_platform(component, os_name, architecture, baseline):
    supported = {
        ('client', 'macos'): {'arm64', 'x86_64'},
        ('server', 'macos'): {'arm64', 'x86_64'},
        ('client', 'linux'): {'x86_64'}, ('server', 'linux'): {'x86_64'},
        ('client', 'windows'): {'x86_64'}, ('client', 'android'): {'universal'},
    }
    if architecture not in supported.get((component, os_name), set()):
        raise ValueError('Unsupported update platform')
    platform = {'os': os_name, 'architecture': architecture}
    if os_name == 'macos':
        found = re.fullmatch(r'macOS (\d+(?:\.\d+)*)', baseline)
        if not found:
            raise ValueError('Invalid macOS baseline')
        minimum = {'version': found[1]}
    elif os_name == 'android':
        if baseline != 'API 24 (Android 7)':
            raise ValueError('Invalid Android baseline')
        minimum = {'api': 24}
    elif os_name == 'linux':
        if baseline != 'Ubuntu 24.04 x86_64':
            raise ValueError('Invalid Linux baseline')
        minimum = {'distribution': 'ubuntu', 'version': '24.04'}
    else:
        if baseline != 'Windows 10 x86_64':
            raise ValueError('Invalid Windows baseline')
        minimum = {'version': '10.0', 'build': 10240}
    return {'component': component, 'platform': platform, 'min_os': minimum}


def validate_package(row, identity):
    """Reject mixed sidecars before signing the release inventory."""
    for key in ('version', 'sha', 'tag', 'build_number', 'stable'):
        if row.get(key) != identity[key] or type(row.get(key)) is not type(identity[key]):
            raise ValueError('Package belongs to a different release identity')
    parts = row.get('id', '').split('-')
    if len(parts) != 3:
        raise ValueError('Invalid package id')
    expected = package_platform(*parts, row.get('baseline'))
    for key, value in expected.items():
        if row.get(key) != value:
            raise ValueError('Package update platform differs from package id/baseline')
    if row.get('compatibility') != COMPATIBILITY:
        raise ValueError('Package compatibility differs from release')
    if type(row.get('size')) is not int or row['size'] <= 0:
        raise ValueError('Invalid package size')
    if not isinstance(row.get('sha256'), str) or not re.fullmatch(r'[0-9a-f]{64}', row['sha256']):
        raise ValueError('Invalid package digest')


def validate_container(container, identity):
    if (container.get('sha') != identity['sha'] or container.get('release_tag') != identity['tag']
            or container.get('version') != identity['version']
            or container.get('tag') != identity['tag'].removeprefix('v')
            or container.get('image') != 'docker.io/hashev/ffido'
            or not isinstance(container.get('digest'), str)
            or not re.fullmatch(r'sha256:[0-9a-f]{64}', container['digest'])):
        raise ValueError('Container belongs to a different release or has an invalid digest')


def select_update_key(keys, settings):
    """Validate the entire shipped trust store and select Sparkle's pinned key."""
    if not isinstance(keys, dict) or not isinstance(settings, dict):
        raise ValueError('Invalid update key configuration')
    for key_id, public in keys.items():
        if not isinstance(key_id, str) or not re.fullmatch(r'[A-Za-z0-9._-]{1,64}', key_id):
            raise ValueError('Invalid update public key ID')
        try:
            raw = base64.b64decode(public, validate=True) if isinstance(public, str) else b''
        except ValueError:
            raise ValueError('Invalid update public key encoding') from None
        if len(raw) != 32 or base64.b64encode(raw).decode() != public:
            raise ValueError('Update public key must be canonical base64 of 32 bytes')
    selected = settings.get('update_key_id')
    if selected is None:
        if len(keys) > 1: raise ValueError('Select update_key_id when multiple update keys are trusted')
        selected = next(iter(keys), '')
    if not isinstance(selected, str) or (selected and selected not in keys):
        raise ValueError('Selected update_key_id is not a trusted key')
    if keys and not selected: raise ValueError('Select a nonempty update_key_id')
    return selected, keys.get(selected, '')
