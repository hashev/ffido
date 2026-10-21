#!/usr/bin/env python3
"""Create an Ed25519 update key outside the checkout, without replacing keys."""
import argparse
import base64
import json
import os
import pathlib
import re
import stat

ROOT = pathlib.Path(__file__).resolve().parents[2]
PRIVATE_FILE = 'update-private-seed.b64'
PUBLIC_FILE = 'update-public.json'


def private_permissions(path):
    info = path.lstat()
    if info.st_uid != os.geteuid() or info.st_mode & 0o077:
        raise ValueError('Key directory/private seed must be owned by you and inaccessible to other users')
    return info


def prepare(directory, key_id, check_only=False):
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat, PrivateFormat, NoEncryption
    if not re.fullmatch(r'[A-Za-z0-9._-]{1,64}', key_id):
        raise ValueError('Invalid key ID: use 1–64 letters, digits, dots, underscores or hyphens')
    directory = pathlib.Path(directory).resolve()
    if directory.is_relative_to(ROOT):
        raise ValueError('Choose a key directory outside the repository')
    if not directory.exists():
        if check_only: raise ValueError('Key directory does not exist')
        # Do not change the permissions of an existing directory or its contents.
        previous_mask = os.umask(0o077)
        try: directory.mkdir(mode=0o700, parents=True)
        finally: os.umask(previous_mask)
    if not stat.S_ISDIR(private_permissions(directory).st_mode):
        raise ValueError('Expected a private key directory')
    private, public = directory/PRIVATE_FILE, directory/PUBLIC_FILE
    existing = [path.exists() or path.is_symlink() for path in [private, public]]
    if any(existing):
        if not all(existing):
            raise ValueError('Incomplete key pair exists; restore it from backup rather than generating over it')
        if not stat.S_ISREG(private_permissions(private).st_mode) or public.is_symlink() or not public.is_file():
            raise ValueError('Key files must be regular files, not symlinks')
        if private.stat().st_size > 256 or public.stat().st_size > 4096:
            raise ValueError('Unexpected key file size')
        try:
            seed = base64.b64decode(private.read_bytes(), validate=True)
            key = Ed25519PrivateKey.from_private_bytes(seed)
            expected = base64.b64encode(key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()
            trusted = json.loads(public.read_bytes())
        except (ValueError, TypeError):
            raise ValueError('Invalid existing key files; nothing was replaced') from None
        if trusted != {key_id: expected}:
            raise ValueError('Existing public key/key ID does not match the private seed; nothing was replaced')
        return 'Existing matching key pair verified', private, public
    if check_only: raise ValueError('Update key pair is missing')
    key = Ed25519PrivateKey.generate()
    seed = base64.b64encode(key.private_bytes(Encoding.Raw, PrivateFormat.Raw, NoEncryption()))
    trusted = {key_id: base64.b64encode(key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()}
    created = []
    try:
        for path, data in [(private, seed), (public, (json.dumps(trusted, indent=2)+'\n').encode())]:
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            created.append(path)
            with os.fdopen(fd, 'wb') as output:
                output.write(data); output.flush(); os.fsync(output.fileno())
    except BaseException:
        for path in created: path.unlink(missing_ok=True)
        raise
    return 'New key pair created; make a protected backup before using it', private, public


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=pathlib.Path, required=True)
    parser.add_argument('--key-id', default='ffido-prod-2026-01')
    parser.add_argument('--check-only', action='store_true', help='Verify the existing pair without generating or changing files')
    args = parser.parse_args()
    try:
        message, private, public = prepare(args.directory, args.key_id, args.check_only)
    except ImportError:
        parser.exit(1, 'Install scripts/update/requirements.txt into your Python environment first\n')
    except (OSError, ValueError) as error:
        parser.exit(1, str(error)+'\n')
    print(message)
    print('Private seed (do not share): '+str(private))
    print('Public trust anchor (safe to share): '+str(public))
    print('Repository, Android keys and GitHub settings were not changed')


if __name__ == '__main__': main()
