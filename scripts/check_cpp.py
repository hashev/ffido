#!/usr/bin/env python3
"""Scoped formatting and compilation-database analysis of FFIDO C++ sources."""
import argparse
import concurrent.futures
import json
import pathlib
import platform
import shutil
import subprocess
import sys
ROOT = pathlib.Path(__file__).resolve().parents[1]

def tool(name):
    value = shutil.which(name)
    if not value:
        raise SystemExit(f'Required tool not found: {name}')
    return value

def sources():
    # Preserve untouched legacy headers/utilities. These paths contain the migration.
    directories = ['src', 'include/storage', 'include/service', 'include/domain', 'include/ftn',
                   'tests/unit', 'tests/integration', 'tests/support', 'tests/fuzz']
    return sorted({p for directory in directories for p in (ROOT/'apps/backend'/directory).rglob('*')
                   if p.suffix in {'.cpp', '.hpp', '.h'}})

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--format', action='store_true')
    mode.add_argument('--format-check', action='store_true')
    mode.add_argument('--skip-format', action='store_true')
    parser.add_argument('--build-dir', type=pathlib.Path, default=ROOT/'build/backend')
    args = parser.parse_args()
    paths = sources()
    if not args.skip_format:
        formatter = tool('clang-format')
        subprocess.run([formatter, '--style=file', *(['-i'] if args.format else ['--dry-run', '-Werror']), *map(str, paths)], check=True)
    if args.format or args.format_check:
        return
    tidy = tool('clang-tidy')
    build = args.build_dir.resolve()
    database = build/'compile_commands.json'
    if not database.is_file():
        raise SystemExit(f'Required compilation database is missing: {database}; run build.sh build first')
    entries = json.loads(database.read_text())
    translation_units = sorted({str(pathlib.Path(e['file']).resolve()) for e in entries
                               if pathlib.Path(e['file']).resolve() in paths})
    if not translation_units:
        raise SystemExit('Compilation database contains no FFIDO source units')
    extra = []
    if platform.system() == "Darwin":
        sdk = subprocess.run(["xcrun", "--show-sdk-path"], check=True, text=True, capture_output=True).stdout.strip()
        extra = ["--extra-arg=-isysroot"+sdk, "--extra-arg=-isystem"+str(pathlib.Path(sdk)/"usr/include/c++/v1")]
    def check(path):
        return subprocess.run([tidy, '-p', str(build), *extra, path], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        pending = {pool.submit(check, path): path for path in translation_units}
        for future in concurrent.futures.as_completed(pending):
            result = future.result()
            results.append(result)
            print(f'clang-tidy {len(results)}/{len(translation_units)}: {pending[future]}', flush=True)
            if result.stdout:
                print(result.stdout, end='', flush=True)
    if any(r.returncode for r in results):
        raise SystemExit(1)
    label = 'clang-tidy' if args.skip_format else 'Format and clang-tidy'
    print(f'{label} passed: {len(paths)} files / {len(translation_units)} translation units')

if __name__ == '__main__':
    main()
