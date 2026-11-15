#!/usr/bin/env python3
"""Exercise stop/apply/start/readiness and a stopped HPT backup on a private installation."""
import argparse
import fcntl
import hashlib
import json
import os
import pathlib
import plistlib
import pwd
import re
import secrets
import shutil
import socket
import sqlite3
import struct
import subprocess
import sys
import time
import test_server_flow


class Service:
    def __init__(self, manager, label, command, work, environment, invoke, user=None, hpt=False):
        self.manager, self.label, self.invoke = manager, label, invoke
        if manager == 'systemd':
            if os.geteuid() != 0:
                raise RuntimeError('Use root only in a disposable systemd QA machine')
            self.path = pathlib.Path('/run/systemd/system')/(label+'.service')
            if self.path.exists():
                raise RuntimeError('QA service already exists')
            def quote(value):
                return '"'+str(value).replace('\\', '\\\\').replace('"', '\\"').replace('%', '%%')+'"'
            text = '[Unit]\nDescription=Disposable FFIDO update QA\n[Service]\nType=simple\n'
            text += 'User='+user+'\nWorkingDirectory='+str(work).replace('%', '%%')+'\n'
            text += 'Environment='+quote('PATH='+environment['PATH'])+'\n'
            text += 'ExecStart='+' '.join(quote(part) for part in command)+'\n'
            text += 'Restart=no\nKillMode=mixed\nTimeoutStopSec=20\nNoNewPrivileges=yes\n'
            text += 'StandardOutput=journal\nStandardError=journal\n'
            self.path.write_text(text)
            try:
                self.invoke('systemd-analyze', 'verify', self.path)
                self.invoke('systemctl', 'daemon-reload')
            except (OSError, RuntimeError, subprocess.SubprocessError):
                self.path.unlink(missing_ok=True)
                raise
        else:
            self.domain = 'gui/'+str(os.getuid())
            self.path = work/(label+'.plist')
            self.path.write_bytes(plistlib.dumps({'Label': label, 'ProgramArguments': list(map(str, command)),
                'RunAtLoad': True, 'KeepAlive': False, 'ExitTimeOut': 20, 'WorkingDirectory': str(work),
                'EnvironmentVariables': {'PATH': environment['PATH']},
                'StandardOutPath': str(work/('hpt-service.log' if hpt else 'daemon.log')),
                'StandardErrorPath': str(work/('hpt-service.log' if hpt else 'daemon.log'))}))

    def start(self):
        if self.manager == 'systemd': self.invoke('systemctl', 'start', self.label+'.service')
        else: self.invoke('launchctl', 'bootstrap', self.domain, self.path)

    def stop(self):
        if self.manager == 'systemd': self.invoke('systemctl', 'stop', self.label+'.service')
        else: self.invoke('launchctl', 'bootout', self.domain, self.path)

    def active(self):
        if self.manager == 'systemd':
            return self.invoke('systemctl', 'is-active', '--quiet', self.label+'.service', success=False).returncode == 0
        return self.invoke('launchctl', 'print', self.domain+'/'+self.label, success=False, record_output=False).returncode == 0

    def identity(self):
        if self.manager == 'systemd':
            return self.invoke('systemctl', 'show', self.label+'.service', '--property=MainPID,ActiveState,SubState,User,ExecMainStatus').stdout
        output = self.invoke('launchctl', 'print', self.domain+'/'+self.label, record_output=False).stdout
        return dict(re.findall(r'^\s*(pid|state|program|last exit code) = (.*)$', output, re.M))

    def close(self):
        if self.manager == 'systemd': self.invoke('systemctl', 'stop', self.label+'.service')
        elif self.active(): self.stop()
        if self.manager == 'systemd':
            self.invoke('journalctl', '-u', self.label+'.service', '--no-pager', '-n', '100', success=False)
            self.invoke('systemctl', 'reset-failed', self.label+'.service', success=False)
            self.path.unlink()
            self.invoke('systemctl', 'daemon-reload')


class HptTimer:
    def __init__(self, service, invoke):
        self.label = service.label+'.timer'
        self.invoke = invoke
        self.path = pathlib.Path('/run/systemd/system')/self.label
        with self.path.open('x') as output:
            output.write('[Unit]\nDescription=Disposable HPT update QA timer\n[Timer]\nOnActiveSec=1s\nOnUnitInactiveSec=60s\nAccuracySec=100ms\nUnit='+service.label+'.service\n')
        try:
            invoke('systemd-analyze', 'verify', self.path)
            invoke('systemctl', 'daemon-reload')
        except (OSError, RuntimeError, subprocess.SubprocessError):
            self.path.unlink(missing_ok=True)
            raise

    def start(self): self.invoke('systemctl', 'start', self.label)
    def stop(self): self.invoke('systemctl', 'stop', self.label)
    def active(self):
        return self.invoke('systemctl', 'is-active', '--quiet', self.label, success=False).returncode == 0
    def close(self):
        self.invoke('systemctl', 'stop', self.label)
        self.path.unlink()
        self.invoke('systemctl', 'daemon-reload')


def close_services(services):
    errors = []
    for service in reversed(services):
        try:
            service.close()
        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
            errors.append(error)
    if errors:
        raise RuntimeError('QA service cleanup failed; see service-commands.log') from errors[0]


def wait_for(predicate, label, timeout=30):
    deadline = time.monotonic()+timeout
    while time.monotonic() < deadline:
        if predicate(): return
        time.sleep(.1)
    raise RuntimeError(label+' timed out')


def seed_jam(base, populated=True):
    """One local synthetic message; HPT exports only into the private outbound directory."""
    fields = b''
    for kind, value in [(0, b'2:1/1'), (2, b'QA'), (3, b'All'), (4, b'2:1/1 qa-update'), (6, b'Synthetic update fixture')]:
        fields += struct.pack('<HHI', kind, 0, len(value))+value
    body = b'Synthetic backup fixture\r--- QA\r * Origin: Isolated QA (2:1/1)\r'
    header = struct.pack('<4s6I', b'JAM\0', 123, 0, int(populated), 0xffffffff, 1, 0).ljust(1024, b'\0')
    message = struct.pack('<4sHH17I', b'JAM\0', 1, 0, len(fields), 0, 0, 0, 0, 0, 0,
                          123, 0, 0, 1, 1, 0, 0, len(body), 0xffffffff, 0)
    base.with_suffix('.jhr').write_bytes(header+(message+fields if populated else b''))
    base.with_suffix('.jdt').write_bytes(body if populated else b'')
    base.with_suffix('.jdx').write_bytes(struct.pack('<II', 0xffffffff, 1024) if populated else b'')
    base.with_suffix('.jlr').write_bytes(b'')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args):
    manager = args.manager or ('launchd' if sys.platform == 'darwin' else 'systemd')
    if (manager == 'launchd') != (sys.platform == 'darwin'):
        raise RuntimeError('Choose the native service manager of this QA machine')
    if manager == 'systemd' and (not args.service_user or args.service_user == 'root'):
        raise RuntimeError('Pass an unprivileged --service-user in the disposable systemd machine')
    if manager == 'systemd' and pathlib.Path('/proc/1/comm').read_text().strip() != 'systemd':
        raise RuntimeError('The QA machine must run real systemd as PID 1')
    test_server_flow.run(args)
    work = args.directory.resolve(); root = work/'managed'; state = work/'state'
    state.chmod(0o700)
    label = 'io.github.hashev.ffido.update-qa.'+secrets.token_hex(6)
    binary = root/'current/bin/fidoback'
    environment = {**os.environ, 'PATH': str(pathlib.Path(sys.executable).parent)+os.pathsep+os.environ['PATH']}
    services = []
    with (work/'service-commands.log').open('w') as log:
        def command(*cmd, success=True, record_output=True):
            words = list(map(str, cmd))
            result = subprocess.run(words, env=environment, capture_output=True, text=True, timeout=45)
            log.write(json.dumps(words)+'\n'+(result.stdout+result.stderr if record_output else '')); log.flush()
            if success and result.returncode: raise RuntimeError('Command failed; see '+str(work/'service-commands.log'))
            return result
        tls = work/'tls'; tls.mkdir()
        ext = tls/'openssl.cnf'
        ext.write_text('[req]\nprompt=no\ndistinguished_name=dn\n[dn]\nCN=localhost\n[ca]\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always,issuer\n[server]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always,issuer\n')
        try:
            command('openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', '-subj', '/CN=FFIDO QA CA', '-config', ext, '-extensions', 'ca', '-keyout', tls/'ca-key.pem', '-out', tls/'ca.pem')
            command('openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes', '-subj', '/CN=localhost', '-keyout', tls/'server-key.pem', '-out', tls/'server.csr')
            command('openssl', 'x509', '-req', '-in', tls/'server.csr', '-CA', tls/'ca.pem', '-CAkey', tls/'ca-key.pem', '-CAcreateserial', '-days', '1', '-extfile', ext, '-extensions', 'server', '-out', tls/'server.pem')
            with socket.socket() as sock:
                sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
            areas = state/'areas.cfg'; areas.write_text('EchoArea RU.TEST '+str(state/'file')+' -b JAM\n')
            seed_jam(state/'file')
            for special in ['netmail', 'bad', 'dupe']:
                seed_jam(state/special, populated=False)
            (state/'uploads').mkdir(); (state/'uploads/preserved.bin').write_bytes(b'untouched upload')
            auth = work/'hpt.cfg'
            hpt_text = 'Name Fixture\nSysop Test\nLocation Test\nAddress 2:1/1\n'
            for keyword, directory in [('Inbound', 'inbound'), ('ProtInbound', 'protinbound'), ('Outbound', 'outbound'),
                    ('TempInbound', 'tmpin'), ('TempOutbound', 'tmpout'), ('LogFileDir', 'logs'),
                    ('DupeHistoryDir', 'dupes'), ('NodelistDir', 'nodelist')]:
                (state/directory).mkdir(); hpt_text += keyword+' '+str(state/directory)+'\n'
            hpt_text += 'MsgBaseDir '+str(state)+'\nEchoTossLog '+str(state/'logs/toss.log')+'\n'
            hpt_text += 'ImportLog '+str(state/'logs/import.log')+'\nLink QA\nAKA 2:1/2\nOurAKA 2:1/1\nSessionPwd '+secrets.token_hex(16)+'\nAllowEmptyPktPwd on\nEchoMailFlavour direct\n'
            hpt_text += 'NetmailArea NETMAIL '+str(state/'netmail')+' -b JAM\nBadArea BAD '+str(state/'bad')+' -b JAM\nDupeArea DUPE '+str(state/'dupe')+' -b JAM\n'
            hpt_text += 'EchoArea RU.TEST '+str(state/'file')+' -b JAM -a 2:1/1 2:1/2\n'
            auth.write_text(hpt_text); auth.chmod(0o600)
            config = work/'config.json'
            config.write_text(json.dumps({'auth': {'hpt_config_path': str(auth), 'session_key_path': str(state/'session.key')},
                'server': {'ip': '127.0.0.1', 'port': port, 'thread_num': 2, 'tls_certificate': str(tls/'server.pem'), 'tls_private_key': str(tls/'server-key.pem')},
                'ftn': {'areacfg_path': str(areas), 'jam_base_path': str(state), 'coordination_lock': str(state/'hpt.lock')},
                'database': {'metadata_path': str(state/'metadata.db')}}))
            (state/'metadata.db').unlink()
            if manager == 'systemd':
                user = pwd.getpwnam(args.service_user)
                work.chmod(0o755); root.chmod(0o755); (root/'releases').chmod(0o755)
                (root/'.running.lock').touch(); os.chown(root/'.running.lock', user.pw_uid, user.pw_gid)
                (root/'.running.lock').chmod(0o600)
                for path in [state, *state.rglob('*'), tls/'server-key.pem']:
                    os.chown(path, user.pw_uid, user.pw_gid)
                for path in [auth, config]:
                    os.chown(path, 0, user.pw_gid); path.chmod(0o640)
            server = Service(manager, label, [binary, config], work, environment, command, args.service_user)
            services.append(server)
            def ready():
                return command(binary, '--check-ready', f'127.0.0.1:{port}', tls/'ca.pem', 'localhost', success=False).returncode == 0
            def start():
                server.start(); wait_for(ready, 'TLS gRPC readiness')
                assert server.active()
                identity = server.identity()
                if manager == 'systemd':
                    pid = int(re.search(r'^MainPID=(\d+)$', identity, re.M)[1])
                    assert pathlib.Path('/proc/'+str(pid)+'/exe').resolve() == binary.resolve()
                return identity
            if manager == 'systemd':
                assert command('runuser', '-u', args.service_user, '--', 'test', '-w', root/'releases', success=False).returncode
            first_identity = start()
            blocked = command(binary, 'update', 'apply', '--install-root', root, '--config', config, success=False)
            assert blocked.returncode and 'still running' in blocked.stderr
            assert command(binary, '--check-ready', f'127.0.0.1:{port}', tls/'ca.pem', 'wrong.invalid', success=False).returncode
            hpt_service = None
            hpt_timer = None
            hpt_identity = None
            counter = state/'hpt-scans'
            if args.hpt:
                probe = pathlib.Path(__file__).with_name('service_hpt_probe.py').resolve()
                hpt_service = Service(manager, label+'.hpt', [sys.executable, probe, '--wrapper', root/'current/bin/ffido-run-hpt',
                    '--config', config, '--hpt', args.hpt.resolve(), '--hpt-config', auth, '--counter', counter, '--log', state/'hpt-driver.log'],
                    work, environment, command, args.service_user, hpt=True)
                services.append(hpt_service)
                if manager == 'systemd':
                    hpt_timer = HptTimer(hpt_service, command); services.append(hpt_timer)
                    hpt_timer.start(); assert hpt_timer.active()
                else: hpt_service.start()
                wait_for(lambda: counter.exists() and int(counter.read_text()) > 0, 'real HPT scan')
                assert hpt_service.active()
                hpt_identity = hpt_service.identity()
                if hpt_timer:
                    hpt_timer.stop(); assert not hpt_timer.active()
                hpt_service.stop(); assert not hpt_service.active()
                assert struct.unpack_from('<I', (state/'file.jhr').read_bytes(), 1024+52)[0] & 0x10
                assert any(p.stat().st_size > 0 for p in (state/'outbound').rglob('*.pkt'))
            server.stop(); assert not server.active()
            inodes = {str(path.relative_to(work)): path.stat().st_ino for path in [root/'.running.lock', state/'metadata.db.lock', state/'hpt.lock']}
            with sqlite3.connect(state/'metadata.db') as db:
                db.execute('CREATE TABLE update_qa_sentinel(value TEXT)'); db.execute("INSERT INTO update_qa_sentinel VALUES ('preserved')")
                schema = db.execute('PRAGMA user_version').fetchone()[0]
            backup = work/'backup'; backup.mkdir(mode=0o700)
            with (state/'hpt.lock').open('r+b') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                shutil.copytree(state, backup/'state')
                shutil.copytree(tls, backup/'tls')
                for path in [config, auth]: shutil.copy2(path, backup/path.name)
            jam_hashes = {p.name: digest(p) for p in state.glob('file.j*')}
            external_hashes = {str(p.relative_to(work)): digest(p) for p in [config, auth, tls/'server.pem', tls/'server-key.pem', state/'session.key']}
            def verify():
                for directory in [state, backup/'state']:
                    with sqlite3.connect('file:'+str(directory/'metadata.db')+'?mode=ro', uri=True) as db:
                        assert db.execute('SELECT value FROM update_qa_sentinel').fetchone()[0] == 'preserved'
                        assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
                    assert all(digest(directory/name) == value for name, value in jam_hashes.items())
                    assert (directory/'uploads/preserved.bin').read_bytes() == b'untouched upload'
                assert all(digest(work/name) == value for name, value in external_hashes.items())
                assert all((work/name).stat().st_ino == inode for name, inode in inodes.items())
                assert (state/'uploads/preserved.bin').read_bytes() == b'untouched upload'
            verify()
            command(binary, 'update', 'apply', '--install-root', root, '--config', config)
            assert json.loads(command(binary, '--version').stdout)['tag'] == 'v1.0.1'
            second_identity = start(); server.stop(); verify()
            command(binary, 'update', 'rollback', '--install-root', root, '--config', config)
            assert json.loads(command(binary, '--version').stdout)['tag'] == 'v1.0.0'
            third_identity = start(); server.stop(); verify()
            result = {'manager': manager, 'stop_apply_start_ready': True, 'rollback_ready': True,
                'running_apply_rejected': True, 'wrong_tls_name_rejected': True, 'stopped_sqlite_jam_backup_verified': True,
                'external_config_tls_session_uploads_preserved': True, 'lock_inodes_preserved': True, 'schema': schema,
                'real_hpt_scans': int(counter.read_text()) if args.hpt else 0,
                'systemd_pid1': manager == 'systemd', 'service_user': args.service_user or pwd.getpwuid(os.getuid()).pw_name,
                'hpt_service_stopped_before_backup': bool(args.hpt), 'hpt_timer_stopped_before_backup': bool(hpt_timer),
                'hpt_service_identity': hpt_identity, 'local_hpt_packet_created': bool(args.hpt), 'service_identities': [first_identity, second_identity, third_identity]}
        finally:
            try:
                close_services(services)
            finally:
                for directory in [tls, work/'backup/tls']:
                    if directory.exists():
                        for path in directory.glob('*key*'): path.unlink()
                (work/'hpt.cfg').unlink(missing_ok=True)
                (work/'backup/hpt.cfg').unlink(missing_ok=True)
        result['qa_services_unloaded'] = True
        (work/'service-result.json').write_text(json.dumps(result, indent=2)+'\n'); print(json.dumps(result))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=pathlib.Path, required=True)
    parser.add_argument('--directory', type=pathlib.Path, required=True)
    parser.add_argument('--manager', choices=['systemd', 'launchd'])
    parser.add_argument('--service-user')
    parser.add_argument('--hpt', type=pathlib.Path)
    run(parser.parse_args())
