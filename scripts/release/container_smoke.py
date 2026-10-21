#!/usr/bin/env python3
"""Check the built image without registry credentials or production data."""
import argparse
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def smoke(image, upgrade=None):
    info = json.loads(subprocess.check_output(['docker', 'image', 'inspect', image], text=True))[0]
    assert info['Architecture'] == 'amd64' and info['Os'] == 'linux'
    assert info['Config']['User'] == '10001:10001'
    base = ['docker', 'run', '--rm', '--platform', 'linux/amd64']
    for command in ('ffido-admin', 'ffido-hpt-auth', 'ffido-run-hpt'):
        result = subprocess.run([*base, '--entrypoint', '/opt/ffido/bin/'+command, image, '--help'],
                                capture_output=True, text=True, timeout=30)
        # The auth helper takes JSON on stdin, so --help can reject usage, but it must load.
        assert result.returncode in (0, 1, 2), command
        assert 'error while loading shared libraries' not in result.stderr
    run(*base, '--entrypoint', '/bin/sh', image, '-ec',
        'test -f /opt/ffido/share/ffido/ffido-source.tar.gz; '
        'test -f /opt/ffido/share/ffido/relink/relink.sh; '
        'test ! -e /src; test ! -e /etc/ffido/config.json; '
        '! command -v clang; ! command -v flutter; '
        'ldd /opt/ffido/bin/fidoback')
    result = subprocess.run([*base, image], capture_output=True, text=True, timeout=30)
    assert result.returncode != 0 and result.stderr+result.stdout, 'Missing configuration accepted'
    run(sys.executable, str(ROOT/'scripts/check_acceptance.py'), '--native-only', '--container', image, *(['--container-upgrade', upgrade] if upgrade else []))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image')
    parser.add_argument('--upgrade')
    args = parser.parse_args()
    smoke(args.image, args.upgrade)
