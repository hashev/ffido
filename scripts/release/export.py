#!/usr/bin/env python3
"""Export the current monorepo without Git history or local runtime data."""
import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOP = {'apps', 'contracts', 'tools', 'scripts', 'cmake', 'docs', 'openspec', '.github'}
FILES = {'README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'CONTRIBUTING.md',
         'AGENTS.md', '.gitignore', '.clang-format', '.clang-tidy', 'CMakeLists.txt', 'build.sh'}
SKIP = {'.git', 'build', '.cache', '.dart_tool', '.pub-cache', '.pub', 'coverage',
        '__pycache__', '.idea', '.vscode', '.gradle', 'ephemeral', 'Pods', '.symlinks',
        'uploads', 'data', 'tmp', '.cxx', '.swiftpm', 'DerivedData', 'node_modules'}
SUFFIXES = {'.db', '.sqlite', '.sqlite3', '.jhr', '.jdt', '.jdx', '.jlr', '.key',
            '.p12', '.pfx', '.jks', '.keystore', '.log', '.pyc', '.iml', '.lockfile'}
SECRET = re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----|'
                    r'\bgh[pousr]_[A-Za-z0-9]{30,}\b|\bgithub_pat_[A-Za-z0-9_]{50,}\b|'
                    r'\bAKIA[0-9A-Z]{16}\b')
MACHINE = re.compile(r'/Users/[^/\s]+/|/home/[^/\s]+/')


def excluded(path):
    return (bool(set(path.parts) & SKIP) or path.suffix.lower() in SUFFIXES
            or path.name in {'config.json', 'local.properties', 'key.properties',
                             '.DS_Store', '.flutter-plugins-dependencies', 'compile_commands.json',
                             '.env', 'GoogleService-Info.plist', 'google-services.json', 'Generated.xcconfig',
                             'flutter_export_environment.sh', '.last_build_id', 'GeneratedPluginRegistrant.java',
                             'gradlew', 'gradlew.bat', 'gradle-wrapper.jar'}
            or path.name.endswith(('-wal', '-shm')))


def scan(content, path=None):
    text = content.decode('utf-8', errors='replace')
    found = bool(SECRET.search(text))
    if path is not None and path.suffix in {'.json', '.yaml', '.yml', '.toml', '.cfg', '.conf', '.ini', '.properties'}:
        fixture = 'tests' in path.parts or 'test' in path.parts or 'example' in path.name
        if not fixture:
            pattern = r"(?i)\b(?:password|token|access_token|api_key|client_secret)[\"']?\s*[:=]\s*[\"']?([^\s\"',}]+)"
            values = re.findall(pattern, text)
            if path.suffix == '.cfg':
                values += re.findall(r'(?im)^\s*Password\s+(\S+)', text)
            found |= any(value.lower() not in {'null', 'none', 'false'} and not value.startswith('$') for value in values)
    return found, bool(MACHINE.search(text))


def export(source, destination):
    source, destination = source.resolve(), destination.absolute()
    if destination.is_symlink() or destination.resolve().is_relative_to(source):
        raise ValueError('Export must be outside the source tree and not a symlink')
    if destination.exists():
        raise ValueError('Destination already exists; use a new directory')
    selected, warnings = [], []
    candidates = []
    for directory, folders, files in os.walk(source, followlinks=False):
        base = pathlib.Path(directory)
        folders[:] = sorted(f for f in folders if not excluded((base/f).relative_to(source))
                            and ((base/f).relative_to(source).parts[0] in TOP))
        for folder in folders:
            if (base/folder).is_symlink():
                raise ValueError('Symlink directory requires review: '+str((base/folder).relative_to(source)))
        candidates.extend(base/f for f in files)
    for path in sorted(candidates):
        relative = path.relative_to(source)
        if relative.parts[0] not in TOP and str(relative) not in FILES:
            continue
        if excluded(relative):
            continue
        if path.is_symlink():
            raise ValueError(f'Symlink requires review: {relative}')
        if not path.is_file():
            continue
        content = path.read_bytes()
        secret, machine = scan(content, relative)
        if secret:
            raise ValueError(f'Possible secret in {relative}; contents withheld')
        if len(content) > 10 * 1024 * 1024:
            raise ValueError(f'Large file requires review: {relative}')
        if machine:
            warnings.append(str(relative))
        selected.append((path, relative, hashlib.sha256(content).hexdigest()))
    if not (source/'LICENSE').is_file():
        raise ValueError('LICENSE is required')
    destination.mkdir(parents=True)
    for path, relative, _ in selected:
        target = destination/relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    report = {'history': 'new; no .git exported', 'license': 'MIT',
              'files': {str(rel): digest for _, rel, digest in selected},
              'machine_reference_review': warnings, 'secret_findings': 0}
    (destination/'PUBLICATION-MANIFEST.json').write_text(json.dumps(report, indent=2)+'\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=pathlib.Path)
    parser.add_argument('--source', type=pathlib.Path, default=ROOT)
    args = parser.parse_args()
    try:
        report = export(args.source, args.destination)
    except ValueError as error:
        parser.exit(1, str(error)+'\n')
    print(f"Exported {len(report['files'])} files; review {len(report['machine_reference_review'])} documentation references")
