#!/usr/bin/env python3
"""Exercise the documented macOS launchd sequence on a private installation."""
import argparse
import hashlib
import json
import os
import pathlib
import plistlib
import secrets
import shutil
import sqlite3
import subprocess
import sys
import time
import test_server_flow


def run(args):
    if sys.platform != 'darwin': raise RuntimeError('This QA requires macOS launchd')
    test_server_flow.run(args)
    work = args.directory.resolve(); root = work/'managed'; state = work/'state'
    label = 'io.github.hashev.ffido.update-qa.'+secrets.token_hex(6)
    domain = 'gui/'+str(os.getuid())
    plist = work/'service.plist'; log = (work/'service-commands.log').open('w')
    binary = root/'current/bin/fidoback'
    environment = {**os.environ, 'PATH': str(pathlib.Path(sys.executable).parent)+os.pathsep+os.environ['PATH']}
    def command(*cmd, success=True):
        result = subprocess.run(list(map(str, cmd)), env=environment, capture_output=True, text=True)
        log.write(json.dumps(list(map(str, cmd)))+'\n'+result.stdout+result.stderr); log.flush()
        if success and result.returncode: raise RuntimeError('Command failed; see '+str(work/'service-commands.log'))
        return result
    # The synthetic FTN fixture has no HPT process. All backup copies happen only
    # after bootout; this does not claim verification of systemd or a live HPT node.
    tls = work/'tls'; tls.mkdir()
    ext = tls/'openssl.cnf'
    ext.write_text('[req]\nprompt=no\ndistinguished_name=dn\n[dn]\nCN=localhost\n[ca]\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always,issuer\n[server]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always,issuer\n')
    try:
        command('openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', '-subj', '/CN=FFIDO QA CA', '-config', ext, '-extensions', 'ca', '-keyout', tls/'ca-key.pem', '-out', tls/'ca.pem')
        command('openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes', '-subj', '/CN=localhost', '-keyout', tls/'server-key.pem', '-out', tls/'server.csr')
        command('openssl', 'x509', '-req', '-in', tls/'server.csr', '-CA', tls/'ca.pem', '-CAkey', tls/'ca-key.pem', '-CAcreateserial', '-days', '1', '-extfile', ext, '-extensions', 'server', '-out', tls/'server.pem')
        import socket
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
        areas = state/'areas.cfg'; areas.write_text('')
        auth = work/'hpt.cfg'
        auth.write_text('Name Fixture\nSysop Test\nLocation Test\nAddress 2:1/1\nLink QA\nAKA 2:1/2\nOurAKA 2:1/1\nSessionPwd '+secrets.token_hex(16)+'\n')
        auth.chmod(0o600)
        config = work/'config.json'
        config.write_text(json.dumps({'auth': {'hpt_config_path': str(auth), 'session_key_path': str(state/'session.key')}, 'server': {'ip': '127.0.0.1', 'port': port, 'thread_num': 2, 'tls_certificate': str(tls/'server.pem'), 'tls_private_key': str(tls/'server-key.pem')}, 'ftn': {'areacfg_path': str(areas), 'jam_base_path': str(state), 'coordination_lock': str(state/'hpt.lock')}, 'database': {'metadata_path': str(state/'metadata.db')}}))
        # Start with the repository's real schema rather than a synthetic empty DB
        # whose user_version merely claims schema 9.
        (state/'metadata.db').unlink()
        plist.write_bytes(plistlib.dumps({'Label': label, 'ProgramArguments': [str(binary), str(config)], 'RunAtLoad': True, 'KeepAlive': False, 'WorkingDirectory': str(work), 'EnvironmentVariables': {'PATH': environment['PATH']}, 'StandardOutPath': str(work/'daemon.log'), 'StandardErrorPath': str(work/'daemon.log')}))
        def start():
            command('launchctl', 'bootstrap', domain, plist)
            for _ in range(30):
                if command(binary, '--check-ready', f'127.0.0.1:{port}', tls/'ca.pem', 'localhost', success=False).returncode == 0: return
                time.sleep(1)
            raise RuntimeError('launchd server readiness timeout; see daemon.log')
        def stop(): command('launchctl', 'bootout', domain, plist)
        start()
        assert command(binary, 'update', 'apply', '--install-root', root, '--config', config, success=False).returncode != 0
        stop()
        with sqlite3.connect(state/'metadata.db') as db:
            db.execute('CREATE TABLE update_qa_sentinel(value TEXT)'); db.execute("INSERT INTO update_qa_sentinel VALUES ('preserved')")
        backup = work/'backup'; shutil.copytree(state, backup)
        jam_hash = hashlib.sha256((state/'messages.jdt').read_bytes()).hexdigest()
        command(binary, 'update', 'apply', '--install-root', root, '--config', config)
        assert json.loads(command(binary, '--version').stdout)['tag'] == 'v1.0.1'
        start(); stop()
        command(binary, 'update', 'rollback', '--install-root', root, '--config', config)
        assert json.loads(command(binary, '--version').stdout)['tag'] == 'v1.0.0'
        start(); stop()
        for directory in [state, backup]:
            with sqlite3.connect(directory/'metadata.db') as db:
                assert db.execute('SELECT value FROM update_qa_sentinel').fetchone()[0] == 'preserved'
                assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
            assert hashlib.sha256((directory/'messages.jdt').read_bytes()).hexdigest() == jam_hash
        result = {'launchd_bootout_apply_bootstrap_ready': True, 'launchd_rollback_ready': True, 'running_apply_rejected': True, 'stopped_sqlite_jam_backup_verified': True, 'systemd': 'not tested', 'hpt': 'no running HPT in synthetic fixture'}
        (work/'service-result.json').write_text(json.dumps(result, indent=2)+'\n'); print(json.dumps(result))
    finally:
        if command('launchctl', 'print', domain+'/'+label, success=False).returncode == 0:
            command('launchctl', 'bootout', domain, plist, success=False)
        for path in tls.glob('*key*'): path.unlink()
        (work/'hpt.cfg').unlink(missing_ok=True)
        log.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=pathlib.Path, required=True)
    parser.add_argument('--directory', type=pathlib.Path, required=True)
    run(parser.parse_args())
