#!/usr/bin/env python3
"""Test documented installed native CLI on an isolated managed installation."""
import argparse
import base64
import hashlib
import json
import os
import pathlib
import shutil
import sqlite3
import subprocess
import sys
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

ROOT = pathlib.Path(__file__).resolve().parents[2]


def run(args):
    work = args.directory.resolve(); work.mkdir(parents=True, exist_ok=False, mode=0o700)
    root = work/'managed'; root.mkdir(mode=0o700); (root/'releases').mkdir(mode=0o700)
    key = Ed25519PrivateKey.generate()
    keys = {'qa': base64.b64encode(key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()}
    platform = {'os': 'macos' if sys.platform == 'darwin' else 'linux', 'architecture': 'arm64' if os.uname().machine == 'arm64' else 'x86_64'}
    compatibility = {'protocol_major': 1, 'client_protocol_min': 1, 'client_protocol_max': 1, 'server_protocol_min': 1, 'server_protocol_max': 1, 'state_schema_min': 9, 'state_schema_max': 9, 'config_format': 1, 'jam_format': 'JAM-1'}
    for version, number in [('1.0.0', 41001), ('1.0.1', 41002)]:
        release = root/'releases'/('v'+version)
        shutil.copytree(args.bundle.resolve(), release, symlinks=True)
        # The container marker is specific to image distribution. These copies
        # model native bundles built from the same runtime, never modify an image.
        (release/'share/ffido/container-distribution').unlink(missing_ok=True)
        module = release/'share/ffido/update'; module.mkdir(parents=True, exist_ok=True)
        for name in ['server.py', 'common.py', 'discovery.py', 'requirements.txt']:
            shutil.copy2(ROOT/'scripts/update'/name, module/name)
        (module/'public_keys.json').write_text(json.dumps(keys))
        shutil.copy2(ROOT/'scripts/update/ffido-update', release/'bin/ffido-update')
        (release/'bin/ffido-update').chmod(0o755)
        identity = {'version': version, 'tag': 'v'+version, 'build_number': number, 'stable': True, 'sha': 'a'*40}
        package = {**identity, 'id': 'server-'+platform['os']+'-'+platform['architecture'], 'component': 'server', 'platform': platform, 'min_os': {'version': '15'} if platform['os'] == 'macos' else {'version': '24.04', 'distribution': 'ubuntu'}, 'compatibility': compatibility, 'file': 'server.tar.gz', 'size': 1, 'sha256': '0'*64}
        manifest = {'schema_version': 1, 'identity': identity, 'channel': 'stable', 'update_sequence': number, 'packages': [package], 'compatibility': compatibility}
        raw = json.dumps(manifest).encode(); (release/'.update').mkdir(exist_ok=True)
        (release/'BUILD.json').write_text(json.dumps(package))
        (release/'.update/manifest.json').write_bytes(raw)
        (release/'.update/manifest.sig').write_text(json.dumps({'key_id': 'qa', 'algorithm': 'Ed25519', 'signature': base64.b64encode(key.sign(raw)).decode()}))
    (root/'current').symlink_to('releases/v1.0.0')
    (root/'.selected-update.json').write_text(json.dumps({'target': 'releases/v1.0.1'}))
    state = work/'state'; state.mkdir(); db_path = state/'metadata.db'
    with sqlite3.connect(db_path) as db: db.execute('PRAGMA user_version=9')
    # A stopped server leaves its existing instance-lock inode behind.
    pathlib.Path(str(db_path)+'.lock').touch()
    jam = state/'messages.jdt'; jam.write_bytes(b'untouched JAM fixture')
    config = work/'config.json'; config.write_text(json.dumps({'database': {'metadata_path': str(db_path)}, 'ftn': {'jam_base_path': str(state)}}))
    before = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [db_path, jam]}
    environment = {**os.environ, 'PATH': str(pathlib.Path(sys.executable).parent)+os.pathsep+os.environ['PATH']}
    binary = root/'current/bin/fidoback'
    def invoke(*arguments, success=True):
        result = subprocess.run([str(binary), *arguments], env=environment, text=True, capture_output=True)
        if success and result.returncode: raise RuntimeError(result.stderr+result.stdout)
        return result
    assert json.loads(invoke('--version').stdout)['tag'] == 'v1.0.0'
    import fcntl
    with (root/'.running.lock').open('a+b') as lock:
        fcntl.flock(lock, fcntl.LOCK_SH | fcntl.LOCK_NB)
        assert invoke('update', 'apply', '--install-root', str(root), '--config', str(config), success=False).returncode != 0
    invoke('update', 'apply', '--install-root', str(root), '--config', str(config))
    assert json.loads(invoke('--version').stdout)['tag'] == 'v1.0.1'
    invoke('update', 'rollback', '--install-root', str(root), '--config', str(config))
    assert json.loads(invoke('--version').stdout)['tag'] == 'v1.0.0'
    assert all(hashlib.sha256(p.read_bytes()).hexdigest() == before[p.name] for p in [db_path, jam])
    result = {'platform': platform, 'installed_dispatcher': True, 'running_lock_rejected': True, 'apply': 'v1.0.1', 'rollback': 'v1.0.0', 'sqlite_jam_unchanged': True}
    (work/'result.json').write_text(json.dumps(result, indent=2)+'\n'); print(json.dumps(result))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=pathlib.Path, required=True)
    parser.add_argument('--directory', type=pathlib.Path, required=True)
    run(parser.parse_args())
