"""Standalone desktop updater; frozen by PyInstaller on Windows/Linux runners."""
import argparse
import contextlib
import json
import traceback
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
import common


@contextlib.contextmanager
def install_lock(root, timeout=60, *, operation=False):
    # Keep the lock outside the directory being renamed (Windows sharing).
    lock = root.parent/('.'+root.name+('-update.lock' if operation else '-running.lock'))
    if lock.is_symlink(): raise ValueError('Unsafe installation lock')
    with lock.open('a+b') as handle:
        handle.seek(0)
        deadline = time.monotonic()+timeout
        while True:
            try:
                if os.name == 'nt':
                    import msvcrt
                    msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    # Dart File.lock uses POSIX record locks, not flock.
                    fcntl.lockf(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() >= deadline:
                    raise ValueError('Another FFIDO updater is active' if operation else 'Close all FFIDO windows before updating')
                time.sleep(.25)
        yield


def atomic_record(path, value):
    fd, temporary = tempfile.mkstemp(prefix='.ffido-record-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as output:
            json.dump(value, output); output.flush(); os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        pathlib.Path(temporary).unlink(missing_ok=True)


def recover(root):
    journal = root.parent/('.'+root.name+'-update.json')
    if not journal.is_file() or journal.is_symlink(): return
    record = common.strict_json(journal.read_bytes())
    if record.get('phase') not in {'prepared', 'switched'}: return
    backup = root.parent/(root.name+'.previous')
    if record.get('root') != str(root) or record.get('backup') != str(backup):
        raise ValueError('Unsafe desktop recovery journal')
    current = common.strict_json((root/'BUILD.json').read_bytes()) if (root/'BUILD.json').is_file() else {}
    if not backup.exists():
        if record['phase'] == 'prepared' and current.get('tag') == record.get('before_tag'): return
        raise ValueError('Previous bundle is missing; restore the installation manually')
    if backup.is_symlink() or not backup.is_dir(): raise ValueError('Unsafe recovery backup')
    previous = common.strict_json((backup/'BUILD.json').read_bytes())
    if previous.get('component') != 'client' or previous.get('tag') != record.get('before_tag'):
        raise ValueError('Recovery backup identity differs from the journal')
    if root.exists() and (root.is_symlink() or current.get('tag') != record.get('tag')):
        raise ValueError('Recovery would overwrite an unrelated installation')
    with install_lock(root, timeout=0):
        failed = None
        if root.exists():
            failed = pathlib.Path(tempfile.mkdtemp(prefix='.ffido-failed-', dir=root.parent))
            os.rename(root, failed/'bundle')
        try:
            os.rename(backup, root)
        except BaseException:
            if failed is not None: os.rename(failed/'bundle', root)
            raise
        finally:
            if failed is not None: shutil.rmtree(failed)
        atomic_record(journal, {**record, 'phase': 'recovered'})


def validate_parent(root):
    if os.name != 'nt' and (root.parent.stat().st_uid != os.geteuid() or root.parent.stat().st_mode & 0o022):
        raise ValueError('Use a private installation parent owned by the current user')
    if root == root.parent or not os.access(root.parent, os.W_OK): raise ValueError('Installation parent is not writable')
    with tempfile.TemporaryFile(dir=root.parent): pass


def apply(root, archive, keys, executable):
    root = root.resolve(strict=True)
    validate_parent(root)
    if pathlib.Path(executable).name != executable: raise ValueError('Unsafe executable name')
    directory = archive.parent
    manifest = common.verify_manifest((directory/'release-manifest.json').read_bytes(), (directory/'release-manifest.sig').read_bytes(), keys)
    os_name = 'windows' if os.name == 'nt' else 'linux'
    expected = 'client-'+os_name+'-x86_64'
    package = next((row for row in manifest['packages'] if row['id'] == expected), None)
    if package is None or package['file'] != archive.name: raise ValueError('Wrong desktop package')
    common.verify_file(archive, package)
    installed = common.strict_json((root/'data/flutter_assets/assets/updates/identity.json').read_bytes())
    if manifest['update_sequence'] < installed['build_number']: raise ValueError('Stale desktop update manifest')
    if not common.newer(manifest['identity'], installed, 'dev'): raise ValueError('Desktop update cannot downgrade')
    work = pathlib.Path(tempfile.mkdtemp(prefix='.ffido-stage-', dir=root.parent))
    backup = root.parent/(root.name+'.previous')
    journal = root.parent/('.'+root.name+'-update.json')
    try:
        unpacked = common.safe_extract(archive, work/'unpacked')
        bundle = unpacked
        if os_name == 'linux':
            children = list(unpacked.iterdir())
            if len(children) != 1 or not children[0].is_dir() or children[0].is_symlink(): raise ValueError('Invalid full desktop bundle')
            bundle = children[0]
        build = common.strict_json((bundle/'BUILD.json').read_bytes())
        for key in ('tag', 'sha', 'build_number', 'component', 'platform'):
            if build.get(key) != package.get(key): raise ValueError('Desktop BUILD identity mismatch')
        helper = 'ffido-updater.exe' if os_name == 'windows' else 'ffido-updater'
        runtime = 'flutter_windows.dll' if os_name == 'windows' else 'lib/libflutter_linux_gtk.so'
        if not all((bundle/name).is_file() for name in (executable, helper, runtime)) or not (bundle/'data/flutter_assets').is_dir():
            raise ValueError('Incomplete desktop bundle')
        embedded = common.strict_json((bundle/'data/flutter_assets/assets/updates/identity.json').read_bytes())
        if any(embedded.get(key) != manifest['identity'][key] for key in ('version', 'sha', 'tag', 'stable', 'build_number')):
            raise ValueError('Embedded client identity differs from manifest')
        with install_lock(root):
            # A previous interrupted rename is recovered before a second switch.
            if backup.exists():
                if backup.is_symlink(): raise ValueError('Unsafe previous installation')
                record = common.strict_json(journal.read_bytes()) if journal.is_file() else {}
                if record.get('phase') != 'confirmed' or record.get('tag') != installed['tag']:
                    raise ValueError('Existing previous directory is not a confirmed updater backup')
                previous = common.strict_json((backup/'BUILD.json').read_bytes())
                if previous.get('component') != 'client': raise ValueError('Previous directory is not a client bundle')
                shutil.rmtree(backup)
            atomic_record(journal, {'phase': 'prepared', 'root': str(root), 'backup': str(backup), 'before_tag': installed['tag'], 'tag': manifest['identity']['tag']})
            os.rename(root, backup)
            try:
                os.rename(bundle, root)
            except BaseException:
                os.rename(backup, root)
                raise
            atomic_record(journal, {'phase': 'switched', 'root': str(root), 'backup': str(backup), 'before_tag': installed['tag'], 'tag': manifest['identity']['tag']})
    finally:
        shutil.rmtree(work)
    return root/executable


def diagnostic(root, message, *, failure=False):
    # Each append closes its handle; neither renamed bundles nor tests retain it.
    try:
        with (root.parent/('.'+root.name+'-update.log')).open('a', encoding='utf-8') as output:
            output.write(f'{time.monotonic():.3f} {message}\n')
            if failure: output.write(traceback.format_exc())
    except OSError:
        pass  # Diagnostics must not prevent rollback or reporting an error.


def run_install(args):
    root = args.root.resolve()
    executable = root/args.executable
    try:
        # Freeze the trust store into the helper; never trust downloaded keys.
        keys = common.strict_json((pathlib.Path(getattr(sys, '_MEIPASS', pathlib.Path(__file__).parent))/'public_keys.json').read_bytes())
        diagnostic(root, 'Validating and staging desktop update')
        target = apply(root, args.package.resolve(strict=True), keys, args.executable)
        diagnostic(root, 'Bundle switched; starting client')
        nonce = uuid.uuid4().hex
        (root/'.ffido-launch-probe').write_text(nonce)
        child = subprocess.Popen([str(target)], cwd=target.parent, start_new_session=os.name != 'nt')
        diagnostic(root, f'Client started with PID {child.pid}; waiting for readiness')
        ready = root/'.ffido-ready'
        deadline = time.monotonic()+30
        while time.monotonic() < deadline:
            if ready.is_file() and ready.read_text() == nonce:
                ready.unlink(); (root/'.ffido-launch-probe').unlink(missing_ok=True)
                journal = root.parent/('.'+root.name+'-update.json')
                record = common.strict_json(journal.read_bytes())
                atomic_record(journal, {**record, 'phase': 'confirmed'})
                diagnostic(root, 'Client startup confirmed')
                return 0
            if child.poll() is not None: break
            time.sleep(.25)
        child.terminate()
        try: child.wait(timeout=5)
        except subprocess.TimeoutExpired: child.kill(); child.wait()
        raise ValueError('New client did not confirm startup')
    except Exception as error:
        diagnostic(root, 'Desktop installation failed', failure=True)
        # Recovery must take the same process lock as switching: another window
        # may have opened B while startup confirmation was failing.
        try:
            recover(root)
        except (OSError, ValueError) as recovery_error:
            message = 'Обновление не завершено. Закройте все окна FFIDO и повторите установку: '+str(recovery_error)
            if root.is_dir(): (root/'.ffido-update-error').write_text(message)
            print('Update recovery failed: '+str(recovery_error), file=sys.stderr)
            return 1
        if root.is_dir():
            (root/'.ffido-update-error').write_text('Не удалось установить обновление: '+str(error))
            if executable.is_file(): subprocess.Popen([str(executable)], cwd=root, start_new_session=os.name != 'nt')
        return 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=pathlib.Path, required=True)
    parser.add_argument('--package', type=pathlib.Path, required=True)
    parser.add_argument('--executable', required=True)
    parser.add_argument('--preflight', action='store_true', help='Validate installation permissions without changing the bundle')
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        validate_parent(root)
        # Windowed frozen executables have no stderr and show a blocking dialog
        # for unhandled exceptions. Keep diagnostics outside the switched bundle.
        diagnostic(root, f'Updater started; preflight={args.preflight}')
        # This lock spans startup confirmation. The running lock is released
        # before launching Flutter, so its own shared lease can be acquired.
        with install_lock(root, timeout=0, operation=True):
            if args.preflight: return 0
            recover(root)
            return run_install(args)
    except Exception as error:
        diagnostic(root, 'Desktop updater failed', failure=True)
        print('Update failed: '+str(error), file=sys.stderr)
        return 1


if __name__ == '__main__': raise SystemExit(main())
