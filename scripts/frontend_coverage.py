#!/usr/bin/env python3
"""Run Flutter tests and summarize coverage of application Dart sources."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FRONTEND = ROOT / 'apps/frontend'


def main():
    subprocess.run(['flutter', 'test', '--no-pub', '--coverage'], cwd=FRONTEND, check=True)
    measured = {}
    name, counts = None, []
    for line in (FRONTEND / 'coverage/lcov.info').read_text().splitlines():
        if line.startswith('SF:'):
            name, counts = line[3:], []
        elif line.startswith('DA:'):
            counts.append(int(line.split(',')[1]))
        elif line == 'end_of_record' and name:
            path = Path(name)
            path = path if path.is_absolute() else FRONTEND / path
            measured[path.resolve()] = counts
    files = []
    for path in sorted((FRONTEND / 'lib').rglob('*.dart')):
        if 'generated' in path.parts or path.name.endswith(('.pb.dart', '.pbenum.dart',
                                                          '.pbgrpc.dart', '.pbjson.dart')):
            continue
        counts = measured.get(path.resolve())
        files.append({'file': str(path.relative_to(FRONTEND)),
                      'lines': len(counts) if counts is not None else None,
                      'covered': sum(n > 0 for n in counts) if counts is not None else 0})
    total = sum(f['lines'] or 0 for f in files)
    covered = sum(f['covered'] for f in files)
    result = {'lines': total, 'covered': covered,
              'percent': 100 * covered / total if total else 0,
              'unmeasured': [f['file'] for f in files if f['lines'] is None], 'files': files}
    output = FRONTEND / 'coverage/summary.json'
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(f'Flutter: {covered}/{total} lines ({result["percent"]:.2f}%)')
    print(f'Sources absent from coverage mapping: {len(result["unmeasured"])}')
    print(f'Report: {output}')


if __name__ == '__main__':
    main()
