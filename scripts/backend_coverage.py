#!/usr/bin/env python3
"""Run instrumented CTest and produce LLVM reports for FFIDO sources only."""
import argparse
import json
import os
import re
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def llvm_tool(name, compiler):
    sibling = Path(compiler).parent / name
    if sibling.is_file():
        return str(sibling)
    version = run(compiler, '--version', capture_output=True).stdout
    if 'Apple clang' in version and shutil.which('xcrun'):
        return run('xcrun', '--find', name, capture_output=True).stdout.strip()
    tool = shutil.which(name)
    if tool:
        return tool
    if shutil.which('xcrun'):
        return run('xcrun', '--find', name, capture_output=True).stdout.strip()
    raise SystemExit(f'Required tool not found: {name}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir', type=Path, default=ROOT / 'build/backend-coverage')
    args = parser.parse_args()
    build = args.build_dir.resolve()
    cache = (build / 'CMakeCache.txt').read_text()
    if 'FIDOBACK_ENABLE_COVERAGE:BOOL=ON' not in cache:
        raise SystemExit('Configure with -DFIDOBACK_ENABLE_COVERAGE=ON first')
    binary = build / 'apps/backend/fidoback_tests'
    compiler = re.search(r'^CMAKE_CXX_COMPILER:FILEPATH=(.+)$', cache, re.MULTILINE)
    if not compiler:
        raise SystemExit('CMake cache does not identify the compiler')
    profdata = llvm_tool('llvm-profdata', compiler.group(1))
    cov = llvm_tool('llvm-cov', compiler.group(1))
    output = build / 'coverage'
    output.mkdir(exist_ok=True)
    raw = output / 'raw'
    if raw.exists():
        shutil.rmtree(raw)
    raw.mkdir()
    env = dict(os.environ, LLVM_PROFILE_FILE=str(raw / '%p-%m.profraw'))
    run('ctest', '--test-dir', str(build), '--output-on-failure', env=env)
    profiles = sorted(raw.glob('*.profraw'))
    if not profiles:
        raise SystemExit('CTest did not produce coverage profiles')
    merged = output / 'backend.profdata'
    run(profdata, 'merge', '-sparse', *(str(p) for p in profiles), '-o', str(merged))
    ignore = r'/(build|tests|third_party|tmp)/|/usr/|/Applications/|/opt/'
    server = build / 'apps/backend/fidoback'
    admin = build / 'apps/backend/ffido-admin'
    common = [str(binary), '-object', str(server), '-object', str(admin), f'-instr-profile={merged}',
              f'-ignore-filename-regex={ignore}']
    # Explicit source selection also excludes headers outside this repository.
    source_dirs = [ROOT / 'apps/backend/src', ROOT / 'apps/backend/include']
    sources = [str(p) for d in source_dirs for p in sorted(d.rglob('*'))
               if p.suffix in {'.cpp', '.hpp', '.h'}]
    exported = run(cov, 'export', *common, *sources, capture_output=True).stdout
    (output / 'backend.json').write_text(exported)
    report = run(cov, 'report', *common, *sources, capture_output=True).stdout
    (output / 'backend.txt').write_text(report)
    run(cov, 'show', *common, *sources, '-format=html', f'-output-dir={output / "html"}')
    data = json.loads(exported)['data'][0]
    covered = {Path(f['filename']).resolve() for f in data['files']}
    absent = [p for p in sources if Path(p).resolve() not in covered]
    (output / 'unmeasured.txt').write_text('\n'.join(absent) + '\n')
    print(report)
    print(f'Reports: {output}')
    print(f'Sources absent from coverage mapping: {len(absent)} (see unmeasured.txt)')


if __name__ == '__main__':
    main()
