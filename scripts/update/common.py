"""Trust and resource limits for FFIDO update consumers.

Public keys are provided by the installed distribution, never by the release
being checked. No session or FTN credentials belong in this module.
"""
import base64
import hashlib
import json
import os
import pathlib
import re
import shutil
import stat
import tarfile
import tempfile
import urllib.parse
import urllib.request
import zipfile

MAX_METADATA = 2 * 1024 * 1024
MAX_SIGNATURE = 4096
MAX_PACKAGE = 2 * 1024**3
MAX_UNPACKED = 8 * 1024**3
MAX_MEMBERS = 100000
REPOSITORY = 'hashev/ffido'


def strict_json(raw, limit=MAX_METADATA):
    if len(raw) > limit:
        raise ValueError('Update metadata exceeds size limit')

    def pairs(items):
        value = {}
        for key, item in items:
            if key in value:
                raise ValueError('Duplicate update metadata key')
            value[key] = item
        return value

    def invalid(_):
        raise ValueError('Non-finite JSON number')

    try:
        value = json.loads(raw.decode('utf-8'), object_pairs_hook=pairs, parse_constant=invalid)
    except (UnicodeError, json.JSONDecodeError, RecursionError) as error:
        raise ValueError('Invalid update metadata JSON') from error
    if not isinstance(value, dict):
        raise ValueError('Update metadata must be an object')
    return value


def integer(value, minimum=0, maximum=2**53-1):
    if type(value) is not int or not minimum <= value <= maximum:
        raise ValueError('Invalid update integer')
    return value


def version_key(identity):
    version = identity.get('version')
    if not isinstance(version, str) or not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', version):
        raise ValueError('Unsupported update version')
    sha, stable = identity.get('sha'), identity.get('stable')
    if not isinstance(sha, str) or not re.fullmatch(r'[0-9a-f]{40}', sha) or type(stable) is not bool:
        raise ValueError('Invalid update identity')
    number = integer(identity.get('build_number'), 1, 1_999_999_999)
    tag = 'v'+version+('' if stable else f'-dev.{number}.{sha[:12]}')
    if identity.get('tag') != tag:
        raise ValueError('Update identity/tag mismatch')
    return (*map(int, version.split('.')), int(stable), 0 if stable else number)


def newer(candidate, installed, channel, android=False):
    if channel not in {'stable', 'dev'}:
        raise ValueError('Invalid update channel')
    # Non-public CI/local builds have no update provenance.
    if '-check.' in installed.get('tag', ''):
        return False
    candidate_key, installed_key = version_key(candidate), version_key(installed)
    return ((channel == 'dev' or candidate['stable']) and candidate_key > installed_key
            and (not android or candidate['build_number'] > installed['build_number']))


def asset_url(tag, name):
    if (not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,199}', name)
            or name in {'.', '..'}):
        raise ValueError('Invalid release asset name')
    if not re.fullmatch(r'v\d+\.\d+\.\d+(?:-dev\.\d+\.[0-9a-f]{12})?', tag):
        raise ValueError('Invalid release tag')
    return f'https://github.com/{REPOSITORY}/releases/download/{tag}/{name}'


def validate_https(url):
    parsed = urllib.parse.urlsplit(url)
    host = parsed.hostname or ''
    if (parsed.scheme != 'https' or parsed.username or parsed.password
            or parsed.port not in {None, 443} or parsed.fragment
            or host not in {'github.com', 'api.github.com', 'release-assets.githubusercontent.com',
                            'objects.githubusercontent.com'}):
        raise ValueError('Untrusted update URL')
    if host == 'github.com' and not parsed.path.startswith('/'+REPOSITORY+'/releases/'):
        raise ValueError('Update URL refers to another repository')
    if host == 'api.github.com' and not parsed.path.startswith('/repos/'+REPOSITORY+'/releases'):
        raise ValueError('Update API URL refers to another repository')
    return url


class UpdateRedirect(urllib.request.HTTPRedirectHandler):
    max_redirections = 5
    max_repeats = 2

    def redirect_request(self, request, response, code, message, headers, url):
        validate_https(url)
        redirected = super().redirect_request(request, response, code, message, headers, url)
        if redirected:
            # Only the public Accept/User-Agent headers are needed by asset CDN.
            redirected.remove_header('Authorization')
            redirected.remove_header('Cookie')
        return redirected


def fetch(url, limit=MAX_METADATA, timeout=30):
    validate_https(url)
    opener = urllib.request.build_opener(UpdateRedirect())
    request = urllib.request.Request(url, headers={'User-Agent': 'FFIDO-Updater', 'Accept': 'application/vnd.github+json' if urllib.parse.urlsplit(url).hostname == 'api.github.com' else 'application/octet-stream'})
    with opener.open(request, timeout=timeout) as response:
        data = response.read(limit+1)
    if len(data) > limit:
        raise ValueError('Update response exceeds size limit')
    return data


def verify_manifest(raw, signature, trusted_keys, minimum_sequence=0):
    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    if len(raw) > MAX_METADATA:
        raise ValueError('Update metadata exceeds size limit')
    envelope = strict_json(signature, MAX_SIGNATURE)
    if (envelope.get('algorithm') != 'Ed25519' or not isinstance(envelope.get('key_id'), str)
            or envelope['key_id'] not in trusted_keys):
        raise ValueError('Unknown update signing key or algorithm')
    try:
        public_key = base64.b64decode(trusted_keys[envelope['key_id']], validate=True)
        signed = base64.b64decode(envelope['signature'], validate=True)
        Ed25519PublicKey.from_public_bytes(public_key).verify(signed, raw)
    except (InvalidSignature, ValueError, KeyError, TypeError) as error:
        raise ValueError('Invalid update signature') from error
    manifest = strict_json(raw)
    validate_manifest(manifest, minimum_sequence)
    return manifest


def validate_manifest(manifest, minimum_sequence=0):
    if type(manifest.get('schema_version')) is not int or manifest['schema_version'] != 1:
        raise ValueError('Unsupported update metadata schema')
    identity = manifest.get('identity')
    if not isinstance(identity, dict):
        raise ValueError('Missing release identity')
    version_key(identity)
    sequence = integer(manifest.get('update_sequence'), 1)
    if sequence < integer(minimum_sequence) or sequence != identity['build_number']:
        raise ValueError('Stale or inconsistent update sequence')
    if manifest.get('channel') != ('stable' if identity['stable'] else 'dev'):
        raise ValueError('Inconsistent update channel')
    compatibility = manifest.get('compatibility')
    if not isinstance(compatibility, dict):
        raise ValueError('Missing update compatibility')
    for low, high in [('client_protocol_min', 'client_protocol_max'),
                      ('server_protocol_min', 'server_protocol_max'), ('state_schema_min', 'state_schema_max')]:
        if integer(compatibility.get(low), 1) > integer(compatibility.get(high), 1):
            raise ValueError('Invalid compatibility range')
    integer(compatibility.get('protocol_major'), 1)
    integer(compatibility.get('config_format'), 1)
    if not isinstance(compatibility.get('jam_format'), str) or not compatibility['jam_format']:
        raise ValueError('Invalid JAM compatibility')
    packages = manifest.get('packages')
    if not isinstance(packages, list) or not 1 <= len(packages) <= 32:
        raise ValueError('Invalid update inventory')
    ids, filenames = set(), set()
    for package in packages:
        if not isinstance(package, dict):
            raise ValueError('Invalid update package')
        for key in ('version', 'sha', 'tag', 'stable', 'build_number'):
            if package.get(key) != identity[key] or type(package.get(key)) is not type(identity[key]):
                raise ValueError('Mixed update identities')
        platform = package.get('platform')
        if not isinstance(platform, dict) or package.get('component') not in {'client', 'server'}:
            raise ValueError('Missing update platform')
        os_name, arch = platform.get('os'), platform.get('architecture')
        matrix = {'client': {'macos': {'arm64', 'x86_64'}, 'windows': {'x86_64'},
                             'linux': {'x86_64'}, 'android': {'universal'}},
                  'server': {'macos': {'arm64', 'x86_64'}, 'linux': {'x86_64'}}}
        if not isinstance(os_name, str) or not isinstance(arch, str) or arch not in matrix[package['component']].get(os_name, set()):
            raise ValueError('Unsupported update platform')
        expected_id = f"{package['component']}-{os_name}-{arch}"
        if package.get('id') != expected_id or expected_id in ids:
            raise ValueError('Duplicate or inconsistent package id')
        ids.add(expected_id)
        name = package.get('file')
        asset_url(identity['tag'], name)
        if name in filenames:
            raise ValueError('Duplicate update asset')
        filenames.add(name)
        integer(package.get('size'), 1, MAX_PACKAGE)
        if not isinstance(package.get('sha256'), str) or not re.fullmatch(r'[0-9a-f]{64}', package['sha256']):
            raise ValueError('Invalid update checksum')
        if package.get('compatibility') != compatibility:
            raise ValueError('Mixed compatibility metadata')
        minimum = package.get('min_os')
        if not isinstance(minimum, dict):
            raise ValueError('Missing minimum OS')
        if os_name == 'android':
            integer(minimum.get('api'), 24)
            if package.get('signing') != 'release':
                raise ValueError('Android update must be release signed')
        elif not isinstance(minimum.get('version'), str) or not re.fullmatch(r'\d+(?:\.\d+)*', minimum['version']):
            raise ValueError('Invalid minimum OS version')
        if os_name == 'linux' and minimum.get('distribution') != 'ubuntu':
            raise ValueError('Unsupported Linux distribution baseline')
        if os_name == 'windows':
            integer(minimum.get('build'), 1)
    feeds = manifest.get('macos_appcasts', [])
    if not isinstance(feeds, list):
        raise ValueError('Invalid macOS feeds')
    feed_ids = set()
    mac_ids = {package['id'] for package in packages
               if package['component'] == 'client' and package['platform']['os'] == 'macos'}
    for feed in feeds:
        if not isinstance(feed, dict) or not isinstance(feed.get('package_id'), str):
            raise ValueError('Invalid macOS feed')
        package_id = feed['package_id']
        if package_id not in mac_ids or package_id in feed_ids:
            raise ValueError('Unknown or duplicate macOS feed')
        if feed.get('file') != package_id+'-appcast.xml':
            raise ValueError('macOS feed asset mismatch')
        asset_url(identity['tag'], feed['file'])
        integer(feed.get('size'), 1, MAX_METADATA)
        if not isinstance(feed.get('sha256'), str) or not re.fullmatch(r'[0-9a-f]{64}', feed['sha256']):
            raise ValueError('Invalid macOS feed checksum')
        feed_ids.add(package_id)
    if feed_ids != mac_ids:
        raise ValueError('Missing macOS update feed')
    container = manifest.get('container')
    if container is not None:
        if (not isinstance(container, dict) or container.get('image') != 'docker.io/hashev/ffido'
                or container.get('sha') != identity['sha'] or container.get('release_tag') != identity['tag']
                or container.get('version') != identity['version']
                or container.get('tag') != identity['tag'][1:]
                or not isinstance(container.get('digest'), str)
                or not re.fullmatch(r'sha256:[0-9a-f]{64}', container['digest'])):
            raise ValueError('Invalid update container identity')
    return manifest


def verify_file(path, package):
    path = pathlib.Path(path)
    if path.is_symlink() or path.stat().st_size != integer(package.get('size'), 1, MAX_PACKAGE):
        raise ValueError('Update package size mismatch')
    digest = hashlib.sha256()
    with path.open('rb') as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    if digest.hexdigest() != package.get('sha256'):
        raise ValueError('Update package checksum mismatch')


def download(package, directory):
    """Atomically save a checked asset; incomplete downloads are never reusable."""
    url = asset_url(package['tag'], package['file'])
    directory = pathlib.Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    size = integer(package.get('size'), 1, MAX_PACKAGE)
    descriptor, temporary = tempfile.mkstemp(prefix='.download-', dir=directory)
    temporary = pathlib.Path(temporary)
    try:
        opener = urllib.request.build_opener(UpdateRedirect())
        request = urllib.request.Request(url, headers={'User-Agent': 'FFIDO-Updater'})
        with os.fdopen(descriptor, 'wb') as output, opener.open(request, timeout=30) as source:
            count = 0
            while chunk := source.read(min(1024 * 1024, size-count+1)):
                count += len(chunk)
                if count > size:
                    raise ValueError('Update package exceeds declared size')
                output.write(chunk)
            output.flush()
            os.fsync(output.fileno())
        verify_file(temporary, package)
        destination = directory/package['file']
        os.replace(temporary, destination)
        return destination
    finally:
        temporary.unlink(missing_ok=True)


def safe_extract(archive, destination, max_size=MAX_UNPACKED, max_members=MAX_MEMBERS):
    """Extract only to a new directory; allow internal tar symlinks for native libs."""
    destination = pathlib.Path(destination)
    if destination.exists() or destination.is_symlink():
        raise ValueError('Extraction requires a new staging directory')
    destination.mkdir(parents=True)
    try:
        is_zip = zipfile.is_zipfile(archive)
        with (zipfile.ZipFile(archive) if is_zip else tarfile.open(archive, 'r:*')) as source:
            members = source.infolist() if is_zip else []
            if not is_zip:
                declared_size = 0
                for member in source:
                    declared_size += member.size
                    if member.size < 0 or declared_size > max_size:
                        raise ValueError('Update archive exceeds unpacked size limit')
                    members.append(member)
                    if len(members) > max_members:
                        raise ValueError('Update archive has too many entries')
            if len(members) > max_members:
                raise ValueError('Update archive has too many entries')
            paths, links, total, entries = set(), set(), 0, []
            for member in members:
                name = member.filename if is_zip else member.name
                path = pathlib.PurePosixPath(name)
                if (not name or '\\' in name or ':' in name or path.is_absolute()
                        or '..' in path.parts or path == pathlib.PurePosixPath('.') or path in paths):
                    raise ValueError('Unsafe or duplicate archive path')
                reserved = {'CON', 'PRN', 'AUX', 'NUL', *('COM'+str(i) for i in range(1, 10)), *('LPT'+str(i) for i in range(1, 10))}
                if any(part.rstrip(' .') != part or part.split('.')[0].upper() in reserved for part in path.parts):
                    raise ValueError('Unsafe cross-platform archive path')
                paths.add(path)
                if is_zip:
                    mode = member.external_attr >> 16
                    if stat.S_ISLNK(mode) or (stat.S_IFMT(mode) not in {0, stat.S_IFREG, stat.S_IFDIR}):
                        raise ValueError('Unsupported ZIP entry')
                    directory = member.is_dir()
                    link = False
                    size = member.file_size
                else:
                    if not (member.isfile() or member.isdir() or member.issym()):
                        raise ValueError('Unsupported tar entry')
                    directory, link, size, mode = member.isdir(), member.issym(), member.size, member.mode
                    if link:
                        target = member.linkname
                        if not target or '\\' in target or ':' in target or pathlib.PurePosixPath(target).is_absolute():
                            raise ValueError('Unsafe archive link')
                        resolved = (destination/path.parent/target).resolve()
                        if not resolved.is_relative_to(destination.resolve()):
                            raise ValueError('Archive link escapes staging')
                        links.add(path)
                total += size
                if size < 0 or total > max_size:
                    raise ValueError('Update archive exceeds unpacked size limit')
                entries.append((member, path, directory, link, mode))
            if any(parent in links for path in paths for parent in path.parents):
                raise ValueError('Archive entry traverses a symlink')
            # Symlinks are created last, so they cannot affect writing regular files.
            for member, path, directory, link, mode in entries:
                if link:
                    continue
                target = destination/path
                target.parent.mkdir(parents=True, exist_ok=True)
                if directory:
                    target.mkdir(exist_ok=True)
                else:
                    with (source.open(member) if is_zip else source.extractfile(member)) as inp, target.open('xb') as out:
                        shutil.copyfileobj(inp, out, 1024 * 1024)
                    target.chmod(0o755 if mode & 0o111 else 0o644)
            for member, path, _, link, _ in entries:
                if link:
                    target = destination/path
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.symlink_to(member.linkname)
            # Resolve the complete graph too: chained links can escape despite
            # each individual target being lexically inside the staging tree.
            for path in links:
                if not (destination/path).resolve().is_relative_to(destination.resolve()):
                    raise ValueError('Archive link chain escapes staging')
    except BaseException:
        shutil.rmtree(destination)
        raise
    return destination
