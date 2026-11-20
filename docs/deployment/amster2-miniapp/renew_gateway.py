#!/usr/bin/env python3
"""Manage only amster2's production gateway certificate; never start a stopped gateway."""
import argparse
import fcntl
import hashlib
import json
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

BASE = Path('/srv/ffido-miniapp-main')
LOCK = Path('/home/yurik/fido/ffido/maintenance.lock')
DOMAIN = 'f120n5015z2.ddns.net'
GATEWAY = 'ffido-miniapp-main-gateway'
ENVOY = 'sha256:8f34a3f1f8c804af3f975bc19a50104120482535401d5c8e954156c20ffd5316'
CERTBOT = 'certbot/certbot@sha256:f70ad0adbb7e117f0fe42a63c553f28ea451edabc0148757b6efcd9735acaa20'
CA = '/home/yurik/fido/ffido/tls/ca.pem'
NAMES = ('fullchain.pem', 'privkey.pem')


def command(args):
    result = subprocess.run(args, capture_output=True, timeout=180)
    if result.returncode:
        # Certbot diagnostics can include account details: retain them only privately.
        diagnostics = BASE / 'logs/last-command.private.log'
        diagnostics.write_bytes(result.stdout + result.stderr)
        diagnostics.chmod(0o600)
        raise RuntimeError('Command failed; see private diagnostics')
    return result.stdout


def validate_pair(directory):
    chain, key = (directory / name for name in NAMES)
    for path in (chain, key):
        if path.is_symlink() or not path.is_file():
            raise RuntimeError('Expected materialized certificate files')
    command(['openssl', 'x509', '-in', str(chain), '-noout', '-checkend', '86400'])
    public = command(['openssl', 'x509', '-in', str(chain), '-pubkey', '-noout'])
    private = command(['openssl', 'pkey', '-in', str(key), '-pubout'])
    if public != private:
        raise RuntimeError('Certificate/private key mismatch')
    command(['openssl', 'verify', '-purpose', 'sslserver', '-verify_hostname', DOMAIN,
             '-CAfile', '/etc/ssl/certs/ca-certificates.crt', '-untrusted', str(chain), str(chain)])
    command(['docker', 'run', '--rm', '--network', 'none', '--read-only',
             '--user', '10001:10001', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true',
             '-v', str(directory) + ':/certs/public:ro',
             '-v', str(BASE / 'config/envoy.json') + ':/etc/envoy/envoy.json:ro',
             '-v', CA + ':/certs/backend/ca.pem:ro', '--entrypoint', '/usr/local/bin/envoy',
             ENVOY, '--mode', 'validate', '-c', '/etc/envoy/envoy.json', '--concurrency', '1'])


def same_pair(left, right):
    return all((left / name).is_file() and (right / name).is_file()
               and (left / name).read_bytes() == (right / name).read_bytes() for name in NAMES)


def install_pair(source, destination):
    destination.mkdir(mode=0o750, parents=True, exist_ok=True)
    os.chown(destination, 0, 10001)
    destination.chmod(0o750)  # mkdir mode is otherwise reduced by the private process umask.
    for name in NAMES:
        target = destination / (name + '.new')
        with target.open('wb') as output:
            output.write((source / name).read_bytes())
            output.flush()
            os.fsync(output.fileno())
        os.chown(target, 0, 10001)
        target.chmod(0o640 if name == 'privkey.pem' else 0o644)
        target.replace(destination / name)
    fd = os.open(destination, os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def gateway_running():
    result = subprocess.run(['docker', 'inspect', GATEWAY], capture_output=True, timeout=30)
    if result.returncode:
        # Distinguish an absent container from a broken Docker daemon.
        names = command(['docker', 'ps', '-a', '--format', '{{.Names}}']).decode().splitlines()
        if GATEWAY in names:
            raise RuntimeError('Cannot inspect gateway')
        return False
    info = json.loads(result.stdout)[0]
    if info['Image'] != ENVOY:
        raise RuntimeError('Gateway image differs from pinned image')
    return info['State']['Running']


def probe(directory):
    # Origin is required by the gateway RBAC; OPTIONS does not invoke an RPC.
    command(['curl', '--fail', '--silent', '--show-error', '--max-time', '15',
             '--resolve', DOMAIN + ':9443:127.0.0.1', '-X', 'OPTIONS',
             '-H', 'Origin: https://hashev.github.io',
             '-H', 'Access-Control-Request-Method: POST',
             'https://' + DOMAIN + ':9443/ffido.v1.Ffido/GetServerCapabilities'])
    response = subprocess.run(['openssl', 's_client', '-connect', '127.0.0.1:9443',
                              '-servername', DOMAIN, '-showcerts'], input=b'',
                             capture_output=True, timeout=20)
    if response.returncode:
        raise RuntimeError('Gateway TLS probe failed')
    actual = subprocess.run(['openssl', 'x509', '-outform', 'DER'], input=response.stdout,
                            capture_output=True, timeout=10, check=True).stdout
    expected = command(['openssl', 'x509', '-in', str(directory / 'fullchain.pem'), '-outform', 'DER'])
    if hashlib.sha256(actual).digest() != hashlib.sha256(expected).digest():
        raise RuntimeError('Gateway did not serve installed certificate')


def deploy(source):
    public = BASE / 'certs/public'
    validate_pair(source)
    if same_pair(source, public):
        logging.info('Certificate unchanged; no gateway action')
        return
    running = gateway_running()
    previous = BASE / 'certs/previous'
    previous.mkdir(mode=0o700, exist_ok=True)
    previous_exists = all((public / name).is_file() for name in NAMES)
    if previous_exists:
        for name in NAMES:
            shutil.copyfile(public / name, previous / name)
            (previous / name).chmod(0o600)
    if running and not previous_exists:
        raise RuntimeError('Running gateway has no recoverable certificate pair')
    if running:
        command(['docker', 'stop', '--time', '15', GATEWAY])
    try:
        install_pair(source, public)
        if running:
            command(['docker', 'start', GATEWAY])
            # curl retries only connection refusal, while the listener is starting.
            for attempt in range(10):
                try:
                    probe(public)
                    break
                except (RuntimeError, subprocess.SubprocessError):
                    if attempt == 9:
                        raise
                    time.sleep(1)
    except (OSError, RuntimeError, subprocess.SubprocessError):
        if running:
            command(['docker', 'stop', '--time', '15', GATEWAY])
        if previous_exists:
            install_pair(previous, public)
            if running:
                command(['docker', 'start', GATEWAY])
                probe(public)
        raise
    logging.info('Certificate installed; gateway %s', 'reloaded and verified' if running else 'left stopped/absent')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['issue', 'renew', 'dry-run', 'deploy'])
    action = parser.parse_args().action
    os.umask(0o077)
    if os.geteuid() != 0:
        raise RuntimeError('Run as root')
    if not logging.getLogger().handlers:
        logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s',
                            handlers=[RotatingFileHandler(BASE / 'logs/renew.log',
                                                         maxBytes=1048576, backupCount=3),
                                      logging.StreamHandler()])
    with LOCK.open('rb') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            logging.warning('Maintenance busy; next scheduled attempt will retry')
            return 75
        if action != 'deploy':
            args = ['docker', 'run', '--rm', '--publish', '80:8081',
                    '-v', str(BASE / 'acme') + ':/acme', CERTBOT]
            common = ['--config-dir', '/acme/config', '--work-dir', '/acme/work',
                      '--logs-dir', '/acme/logs', '--non-interactive']
            if action == 'issue':
                args += ['certonly', '--standalone', '--http-01-port', '8081',
                         '--agree-tos', '--register-unsafely-without-email',
                         '--cert-name', DOMAIN, '-d', DOMAIN]
            else:
                args += ['renew', '--cert-name', DOMAIN, '--no-random-sleep-on-renew',
                         '--standalone', '--http-01-port', '8081']
                if action == 'dry-run':
                    args += ['--dry-run']
            command(args + common)
        if action == 'dry-run':
            logging.info('ACME dry-run passed; public certificate and gateway untouched')
            return 0
        live = BASE / 'acme/config/live' / DOMAIN
        archive = (BASE / 'acme/config/archive' / DOMAIN).resolve()
        with tempfile.TemporaryDirectory(prefix='candidate-', dir=BASE / 'certs') as stage:
            stage = Path(stage)
            os.chown(stage, 0, 10001)
            stage.chmod(0o750)
            for name in NAMES:
                path = (live / name).resolve(strict=True)
                if path.parent != archive:
                    raise RuntimeError('ACME link escapes production lineage')
                shutil.copyfile(path, stage / name)
                os.chown(stage / name, 0, 10001)
                (stage / name).chmod(0o640 if name == 'privkey.pem' else 0o644)
            deploy(stage)
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError, ValueError, KeyError):
        logging.exception('Gateway certificate operation failed')
        raise SystemExit(1)
