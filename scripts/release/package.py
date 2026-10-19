#!/usr/bin/env python3
"""Stage redistributable bundles and record their identity/checksums."""
import argparse
import hashlib
import json
import os
import pathlib
import platform
import re
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import zipfile
from urllib.parse import urlparse
from urllib.request import url2pathname
ROOT = pathlib.Path(__file__).resolve().parents[2]
DEBIAN_DOCS = pathlib.Path('/usr/share/doc')


def run(*args):
    command = list(map(str, args))
    command[0] = shutil.which(command[0]) or command[0]
    return subprocess.check_output(command, text=True)


def licenses(stage, frontend=True):
    legal = stage/'legal'
    legal.mkdir(exist_ok=True)
    for name in ('LICENSE', 'THIRD_PARTY_NOTICES.md'):
        shutil.copy2(ROOT/name, legal/name)
    if not frontend:
        return
    config = ROOT/'apps/frontend/.dart_tool/package_config.json'
    if config.exists():
        for entry in json.loads(config.read_text())['packages']:
            uri = entry['rootUri']
            path = pathlib.Path(url2pathname(urlparse(uri).path)) if uri.startswith('file:') else config.parent/uri
            if not path.is_dir():
                raise ValueError('Dependency license directory unavailable: '+entry['name'])
            for name in ('LICENSE', 'COPYING', 'LICENSE.md', 'LICENSE.txt'):
                if (path/name).is_file():
                    shutil.copy2(path/name, legal/(entry['name']+'-'+name))
    sdk = shutil.which('flutter')
    if sdk:
        sdk_root = pathlib.Path(sdk).resolve().parents[1]
        if (sdk_root/'LICENSE').exists():
            shutil.copy2(sdk_root/'LICENSE', legal/'Flutter-LICENSE')


def bundle_native(stage):
    """Bundle non-system native dependencies; return relocatable runtime paths."""
    library_dir = stage/'lib'
    library_dir.mkdir(exist_ok=True)
    source_digests = {p.name: hashlib.sha256(p.read_bytes()).digest()
                      for p in library_dir.iterdir() if p.is_file()}
    todo = list((stage/'bin').iterdir())
    processed = set()
    darwin = platform.system() == 'Darwin'
    while todo:
        binary = todo.pop()
        if binary in processed or not binary.is_file() or binary.suffix == '.py' or binary.name.endswith('hpt'):
            continue
        processed.add(binary)
        if binary.read_bytes()[:2] == b'#!':
            continue
        if darwin:
            lines = run('otool', '-L', binary).splitlines()[1:]
            deps = [line.strip().split(' (', 1)[0] for line in lines]
            deps = [d for d in deps if d.startswith('/') and not d.startswith(('/usr/lib/', '/System/'))]
        else:
            lines = run('ldd', binary)
            if 'not found' in lines:
                raise ValueError('Unresolved dependency in '+binary.name)
            deps = re.findall(r'=> (/\S+)', lines)
            deps = [d for d in deps if not re.match(r'lib(c|m|stdc\+\+|gcc_s|pthread|rt|dl|util|z)\.', pathlib.Path(d).name)]
        for dependency in deps:
            target = library_dir/pathlib.Path(dependency).name
            notice_dir = stage/'share/ffido/legal' if (stage/'share/ffido/legal').is_dir() else stage/'legal'
            origin = pathlib.Path(dependency).resolve()
            if darwin:
                candidates = [origin.parent.parent/name for name in ('LICENSE', 'LICENSE.txt', 'LICENSE.md', 'COPYING')]
            else:
                owners = run('dpkg-query', '-S', str(origin)).splitlines()
                candidates = [DEBIAN_DOCS/line.split(':', 1)[0]/'copyright' for line in owners]
            notices = [path for path in candidates if path.is_file()]
            if not notices:
                raise ValueError('Missing runtime library license: '+origin.name)
            for index, notice in enumerate(notices):
                shutil.copy2(notice, notice_dir/(origin.name+f'-{index}-LICENSE'))
            if not target.exists():
                source_digests[target.name] = hashlib.sha256(pathlib.Path(dependency).read_bytes()).digest()
                shutil.copy2(dependency, target)
                target.chmod(0o755)
                todo.append(target)
            elif target.resolve() != pathlib.Path(dependency).resolve():
                # Rpath/signature edits change the staged bytes, not the source identity.
                if source_digests[target.name] != hashlib.sha256(pathlib.Path(dependency).read_bytes()).digest():
                    raise ValueError('Conflicting native library name: '+target.name)
            if darwin:
                subprocess.run(['install_name_tool', '-change', dependency, '@rpath/'+target.name, str(binary)], check=True)
        if darwin:
            for old_path in re.findall(r'cmd LC_RPATH\n.*?path (.*?) \(offset', run('otool', '-l', binary), re.S):
                if old_path.startswith('/'):
                    subprocess.run(['install_name_tool', '-delete_rpath', old_path, str(binary)], check=True)
            rpath = '@loader_path' if binary.parent == library_dir else '@executable_path/../lib'
            result = subprocess.run(['install_name_tool', '-add_rpath', rpath, str(binary)], capture_output=True)
            if result.returncode and b'would duplicate path' not in result.stderr:
                raise ValueError('Cannot set portable rpath: '+binary.name)
            if binary.parent == library_dir:
                subprocess.run(['install_name_tool', '-id', '@rpath/'+binary.name, str(binary)], check=True)
            subprocess.run(['codesign', '--force', '--sign', '-', str(binary)], check=True)
        else:
            subprocess.run(['patchelf', '--set-rpath', '$ORIGIN' if binary.parent == library_dir else '$ORIGIN/../lib', str(binary)], check=True)
    return processed


def relink(stage, build, deps):
    destination = stage/'share/ffido/relink'
    destination.mkdir(parents=True)
    prefix = deps/'prefix/share/ffido/legal'
    if not (prefix/'revisions.json').is_file():
        raise ValueError('Missing dependency legal/source bundle; run dependencies.sh')
    shutil.copytree(prefix, stage/'share/ffido/legal', dirs_exist_ok=True)
    scripts = ['#!/bin/sh', 'set -eu', 'cd "$(dirname "$0")"', 'mkdir -p bin']
    if platform.system() == 'Darwin':
        scripts.append('export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"')
    for name in ('fidoback', 'ffido-admin', 'ffido-hpt-auth'):
        link = build/f'apps/backend/CMakeFiles/{name}.dir/link.txt'
        tokens = shlex.split(link.read_text())
        converted = ['${CXX:-c++}']
        cwd = build/'apps/backend'
        dynamic = []
        it = iter(tokens[1:])
        for token in it:
            if token == '-o':
                next(it)
                converted += ['-o', 'bin/'+name]
            elif token == '-isysroot':
                next(it)  # Use the relinking compiler's own SDK.
            elif token.startswith(('-Wl,-rpath,', '-Wl,-syslibroot,',
                                   '-Wl,--dependency-file=', '-Wl,--dependency-file,')):
                continue
            elif not token.startswith('-') and (cwd/token).is_file():
                source = (cwd/token).resolve()
                if source.suffix == '.tbd':
                    converted.append('-l'+source.stem.removeprefix('lib'))
                    continue
                if source.suffix == '.dylib':
                    install_id = run('otool', '-D', source).splitlines()[-1].strip()
                    dynamic.append((install_id, pathlib.Path(install_id).name))
                unique = hashlib.sha256(str(source).encode()).hexdigest()[:12]+'-'+source.name
                if not (destination/unique).exists():
                    shutil.copy2(source, destination/unique)
                converted.append('./'+unique)
            else:
                converted.append(token)
        scripts.append(converted[0]+' '+shlex.join(converted[1:]))
        if platform.system() == 'Darwin':
            for original, library in dynamic:
                scripts.append(shlex.join(['install_name_tool', '-change', original, '@loader_path/../../../../lib/'+library, 'bin/'+name]))
            scripts.append(shlex.join(['codesign', '--force', '--sign', '-', 'bin/'+name]))
        else:
            scripts.append(shlex.join(['patchelf', '--set-rpath', '$ORIGIN/../../../../lib', 'bin/'+name]))
    (destination/'relink.sh').write_text('\n'.join(scripts)+'\n')
    shutil.copy2(ROOT/'scripts/release/RELINK.md', destination/'RELINK.md')
    (destination/'README.txt').write_text('Run sh relink.sh with a compatible C++23 compiler and platform linker tools (patchelf on Linux).\nReplace the copied Husky .a or cfg.c.o with your rebuilt version first.\nSource revisions, original source archives and licenses: ../legal/.\nFFIDO sources and adapter patch accompany this package as ffido-source.tar.gz.\n')
    with tarfile.open(stage/'share/ffido/ffido-source.tar.gz', 'w:gz') as archive:
        # Release checkout only; no runtime data/history.
        import importlib.util
        spec = importlib.util.spec_from_file_location('ffido_export', ROOT/'scripts/release/export.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as temporary:
            target = pathlib.Path(temporary)/'source'
            module.export(ROOT, target)
            archive.add(target, arcname='ffido')
    for dep_name in ('spdlog', 'nlohmann_json', 'sqlite3'):
        source = build/f'_deps/{dep_name}-src'
        if not source.is_dir():
            raise ValueError('Missing source for included dependency: '+dep_name)
        with tarfile.open(stage/f'share/ffido/legal/{dep_name}-source.tar.gz', 'w:gz') as archive:
            archive.add(source, arcname=dep_name, filter=lambda info: None if '/.git' in info.name else info)


def verify_legal(stage, component, os_name):
    if not (stage/'legal/LICENSE').is_file() or not (stage/'legal/THIRD_PARTY_NOTICES.md').is_file():
        raise ValueError('Own license/notices missing')
    if component == 'server':
        legal = stage/'share/ffido/legal'
        revisions = json.loads((legal/'revisions.json').read_text())
        for name in ('huskylib', 'smapi', 'fidoconf', 'grpc', 'protobuf', 'abseil'):
            archive = legal/f'{name}-{revisions[name]}.tar.gz'
            if not archive.is_file() or not archive.stat().st_size:
                raise ValueError('Missing dependency sources: '+name)
        relink_dir = stage/'share/ffido/relink'
        if not list(relink_dir.glob('*.a')) or not list(relink_dir.glob('*cfg.c.o')):
            raise ValueError('Missing relink objects/archives')
        for filename in ('relink.sh', 'RELINK.md'):
            if not (relink_dir/filename).is_file():
                raise ValueError('Missing relink instructions')
        if not (stage/'share/ffido/ffido-source.tar.gz').is_file():
            raise ValueError('Missing FFIDO sources')
    else:
        if not (stage/'legal/Flutter-LICENSE').is_file():
            raise ValueError('Missing Flutter license')
        expected = (stage/'legal/LICENSE').read_bytes()
        if os_name == 'android':
            with zipfile.ZipFile(stage/'ffido.apk') as apk:
                notice = apk.read('assets/flutter_assets/assets/legal/LICENSE')
            if notice != expected:
                raise ValueError('APK lacks the authoritative MIT notice')
        elif not any(p.read_bytes() == expected for p in stage.rglob('LICENSE')
                     if p.as_posix().endswith('assets/legal/LICENSE')):
            raise ValueError('Desktop client lacks its embedded MIT notice')


def package(component, os_name, arch, identity, output, build, deps, public=False):
    settings = json.loads((ROOT/'scripts/release/settings.json').read_text())
    if os_name != 'android' and settings['desktop_signing'] != 'unsigned':
        raise ValueError('Signed desktop mode requires a configured signing implementation; no unsigned fallback')
    host_arch = {'AMD64': 'x86_64', 'aarch64': 'arm64'}.get(platform.machine(), platform.machine())
    if os_name != 'android' and host_arch != arch:
        raise ValueError('Package architecture differs from the native runner')
    output.mkdir(parents=True, exist_ok=True)
    package_id = f'{component}-{os_name}-{arch}'
    basename = f"ffido-{identity['tag']}-{package_id}"
    with tempfile.TemporaryDirectory() as tmp:
        stage = pathlib.Path(tmp)/basename
        stage.mkdir()
        licenses(stage, frontend=component == 'client')
        signing = 'unsigned'
        if component == 'server':
            if os_name != platform.system().lower().replace('darwin', 'macos'):
                raise ValueError('Server packaging must run on target OS')
            subprocess.run(['cmake', '--install', str(build), '--prefix', str(stage), '--component', 'ffido'], check=True)
            relink(stage, build, deps)
            bundle_native(stage)
            signing = 'ad-hoc' if os_name == 'macos' else 'unsigned'
        elif os_name == 'macos':
            source = ROOT/'apps/frontend/build/macos/Build/Products/Release/fido.app'
            shutil.copytree(source, stage/'fido.app', symlinks=True)
            actual = run('lipo', '-archs', stage/'fido.app/Contents/MacOS/fido').split()
            if actual != [arch]:
                raise ValueError('Client architecture differs from package label')
            subprocess.run(['codesign', '--force', '--deep', '--preserve-metadata=entitlements', '--sign', '-', str(stage/'fido.app')], check=True)
            signing = 'ad-hoc'
        elif os_name == 'windows':
            source = ROOT/'apps/frontend/build/windows/x64/runner/Release'
            shutil.copytree(source, stage, dirs_exist_ok=True)
        elif os_name == 'linux':
            source = ROOT/'apps/frontend/build/linux/x64/release/bundle'
            shutil.copytree(source, stage, dirs_exist_ok=True, symlinks=True)
            (stage/'ffido.desktop').write_text('[Desktop Entry]\nName=FFIDO\nType=Application\nExec=fido\nTerminal=false\nCategories=Network;\n')
        elif os_name == 'android':
            source = ROOT/'apps/frontend/build/app/outputs/flutter-apk/app-release.apk'
            with zipfile.ZipFile(source) as apk:
                abis = {name.split('/')[1] for name in apk.namelist() if name.startswith('lib/') and name.endswith('/libapp.so')}
            if abis != {'arm64-v8a', 'armeabi-v7a', 'x86_64'}:
                raise ValueError('Universal APK must include the three supported ABIs')
            if public:
                tool = pathlib.Path(os.environ['ANDROID_HOME'])/'build-tools'
                verifier = sorted(tool.glob('*/apksigner*'))[-1]
                certificate = run(verifier, 'verify', '--print-certs', source)
                fingerprint = os.environ.get('ANDROID_CERT_SHA256', '').replace(':', '').lower()
                if not fingerprint or fingerprint not in certificate.replace(':', '').lower():
                    raise ValueError('APK certificate does not match the permanent key')
                if 'android debug' in certificate.lower():
                    raise ValueError('Debug APK cannot be published')
                signing = 'release'
            shutil.copy2(source, stage/'ffido.apk')
        else:
            raise ValueError('Unsupported package target')
        verify_legal(stage, component, os_name)
        toolchain = {'python': platform.python_version(), 'flutter': settings['flutter']}
        if component == 'server':
            toolchain['cmake'] = run('cmake', '--version').splitlines()[0]
            compiler_file = next(build.glob('CMakeFiles/*/CMakeCXXCompiler.cmake'))
            compiler_data = compiler_file.read_text()
            compiler_id = re.search(r'set\(CMAKE_CXX_COMPILER_ID \"([^\"]+)\"\)', compiler_data)[1]
            compiler_version = re.search(r'set\(CMAKE_CXX_COMPILER_VERSION \"([^\"]+)\"\)', compiler_data)[1]
            toolchain['compiler'] = compiler_id+' '+compiler_version
        else:
            flutter = json.loads(run('flutter', '--version', '--machine'))
            toolchain['flutter'] = flutter['frameworkVersion']
            toolchain['flutter_revision'] = flutter['frameworkRevision']
            toolchain['dart'] = flutter['dartSdkVersion']
        baseline = {'linux': 'Ubuntu 24.04 x86_64', 'macos': 'macOS 15',
                    'windows': 'Windows 10 x86_64', 'android': 'API 24 (Android 7)'}[os_name]
        if os_name == 'macos':
            minimums = [(15, 0)]
            for candidate in stage.rglob('*'):
                if candidate.is_file() and not candidate.is_symlink():
                    with candidate.open('rb') as source:
                        magic = source.read(4)
                    if magic in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'):
                        for version in re.findall(r'minos (\d+(?:\.\d+)*)', run('vtool', '-show-build', candidate)):
                            minimums.append(tuple(map(int, version.split('.'))))
            baseline = 'macOS '+'.'.join(map(str, max(minimums)))
        (stage/'BUILD.json').write_text(json.dumps({**identity, 'component': component, 'os': os_name,
            'toolchain': toolchain,
            'architecture': arch, 'signing': signing, 'notarized': False,
            'baseline': baseline}, indent=2)+'\n')
        if os_name == 'macos' and component == 'client':
            target = output/(basename+'.dmg')
            subprocess.run(['hdiutil', 'create', '-volname', 'FFIDO', '-srcfolder', str(stage), '-ov', '-format', 'UDZO', str(target)], check=True)
        elif os_name == 'android':
            target = output/(basename+'.apk')
            shutil.copy2(stage/'ffido.apk', target)
        elif os_name == 'windows':
            target = output/(basename+'.zip')
            shutil.make_archive(str(target.with_suffix('')), 'zip', stage)
        else:
            target = output/(basename+'.tar.gz')
            with tarfile.open(target, 'w:gz') as archive:
                archive.add(stage, arcname=basename)
        row = {'id': package_id, **identity, 'file': target.name, 'signing': signing,
               'sha256': hashlib.sha256(target.read_bytes()).hexdigest(), 'toolchain': toolchain, 'baseline': baseline}
        (output/(basename+'.package.json')).write_text(json.dumps(row, indent=2)+'\n')
        return target


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('component', choices=['client', 'server'])
    p.add_argument('os', choices=['macos', 'linux', 'windows', 'android'])
    p.add_argument('arch', choices=['arm64', 'x86_64', 'universal'])
    p.add_argument('--identity', type=pathlib.Path, required=True)
    p.add_argument('--output', type=pathlib.Path, default=ROOT/'build/packages')
    p.add_argument('--build', type=pathlib.Path, default=ROOT/'build/backend')
    p.add_argument('--deps', type=pathlib.Path, default=ROOT/'build/release-deps')
    p.add_argument('--public', action='store_true')
    a = p.parse_args()
    print(package(a.component, a.os, a.arch, json.loads(a.identity.read_text()), a.output, a.build, a.deps, a.public))
