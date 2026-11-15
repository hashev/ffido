#!/usr/bin/env python3
"""Run isolated CTest measurement matrices; keep raw logs and numeric JSON reports."""
import argparse
import fnmatch
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
TAGS = ('CATALOG_MEASURE', 'UUE_MEASURE', 'UUE_MEMORY', 'UUE_ASSEMBLY_MEMORY',
        'MCP_MEMORY', 'CATALOG_BENCH', 'REGISTRY_BENCH', 'STATISTICS_BENCH',
        'STATISTICS_LOAD', 'THOUSAND_AREAS_MEASURE')


def parse_records(text):
    records = []
    for line in text.splitlines():
        for tag in TAGS:
            marker = tag+' '
            if marker not in line:
                continue
            value = json.loads(line.split(marker, 1)[1])
            if not isinstance(value, dict):
                raise ValueError('Measurement is not an object: '+tag)
            records.append({'kind': tag, **value})
            break
    return records


def percentiles(values):
    ordered = sorted(values)
    if not ordered:
        return {'samples': 0}
    return {'samples': len(ordered), 'p50_ms': ordered[math.ceil(.5*len(ordered))-1],
            'p95_ms': ordered[math.ceil(.95*len(ordered))-1]}


def summarize(records):
    result = {}
    for phase in ('cold', 'warm'):
        selected = [r for r in records if r.get('phase') == phase]
        if not selected:
            continue
        latency = [ms for r in selected for ms in r.get('latency_ms', [])]
        successful = [ms for r in selected for ms in r.get('successful_latency_ms', [])]
        completed = sum(r.get('completed', 0) for r in selected)
        errors = {}
        for record in selected:
            for code, count in record.get('errors', {}).items():
                errors[code] = errors.get(code, 0)+count
        result[phase] = {**percentiles(latency), 'completed': completed, 'errors': errors,
                         'successful_latency': percentiles(successful)}
    return result


def validate_records(name, records, options, samples):
    if name.startswith('catalog-'):
        selected = [r for r in records if r['kind'] == 'CATALOG_MEASURE']
        if any(sum(r.get('phase') == phase for r in selected) != samples for phase in ('cold', 'warm')):
            raise ValueError('Incomplete cold/warm sample set')
    elif name.startswith('uue-'):
        selected = [r for r in records if r['kind'] == 'UUE_MEASURE']
        if sorted(r['sample'] for r in selected) != list(range(samples)):
            raise ValueError('Incomplete UUE sample set')
        if len([r for r in records if r['kind'] == 'UUE_MEMORY']) != 1:
            raise ValueError('Missing retained-memory observation')
    elif name == 'mcp':
        for outcome in ('normal', 'oversized', 'eof', 'closed', 'flood', 'pending-models'):
            if sum(r.get('outcome') == outcome for r in records) != samples:
                raise ValueError('Incomplete MCP lifecycle observations')
        selected = []
    else:
        selected = []
    for record in selected:
        if len(record['latency_ms']) != options['PARALLEL']:
            raise ValueError('Missing request latency')
        if record['completed']+sum(record['errors'].values()) != options['PARALLEL']:
            raise ValueError('Missing request outcome')
        if len(record.get('successful_latency_ms', [])) != record['completed']:
            raise ValueError('Missing successful latency')


def cases(kind):
    if kind in ('all', 'catalog'):
        for areas, messages in ((1, 100), (1, 10000), (100, 100), (1000, 100)):
            for parallel in (1, 16, 64):
                for light in (0, 1):
                    yield (f'catalog-{areas}-{messages}-q{parallel}-light{light}',
                           '^CatalogMeasurementGrpcTest.CatalogMeasurementFixture$',
                           {'AREAS': areas, 'MESSAGES': messages, 'PARALLEL': parallel, 'LIGHT': light}, True)
    if kind in ('all', 'uue'):
        # A 16 MiB file cannot fit in one JAM body (10 MiB read limit); test the
        # one/many-source axis at 1 MiB and the upper file limit with many sources.
        for size, single in ((1048576, 1), (1048576, 0), (16777216, 0)):
            for chunk in (16384, 65536):
                for parallel in (1, 4, 16):
                    yield (f'uue-{size}-single{single}-c{chunk}-q{parallel}',
                           '^ServicesTest.UueChunkMeasurementFixture$',
                           {'FILE_BYTES': size, 'SINGLE_SOURCE': single, 'CHUNK_BYTES': chunk,
                            'PARALLEL': parallel}, False)
    if kind in ('all', 'resources'):
        for size in (1048576, 16777216):
            for parallel in (1, 4, 16):
                yield (f'assembly-{size}-q{parallel}', '^ServicesTest.UueAssemblyMemoryFixture$',
                       {'FILE_BYTES': size, 'PARALLEL': parallel}, False)
    if kind in ('all', 'mcp'):
        yield ('mcp', 'NearLimitOutputMemoryIsReleasedOnSuccessFailureAndEof|CompletedModelsKeepAdmissionUntilTheyEnterTheOutputQueue', {}, True)
    if kind in ('all', 'registry'):
        yield ('registry', 'CatalogStatisticsAndRegistryPerformanceFixture|CatalogPerformanceFixture|'
               'ServerListsAllPagesWithUnchangedLowNofile', {}, False)


def metadata(build):
    cache = {}
    for line in (build/'CMakeCache.txt').read_text().splitlines():
        if '=' not in line or ':' not in line.split('=', 1)[0]:
            continue
        name, value = line.split('=', 1)
        key = name.split(':', 1)[0]
        if key in ('CMAKE_BUILD_TYPE', 'CMAKE_CXX_COMPILER', 'CMAKE_OSX_SYSROOT', 'Protobuf_DIR',
                   'gRPC_DIR', 'absl_DIR', 'FIDOBACK_ENABLE_ASAN', 'FIDOBACK_ENABLE_TSAN'):
            cache[key] = value
    digest = hashlib.sha256()
    paths = sorted(p for directory in ('src', 'include', 'tests')
                   for p in (ROOT/'apps/backend'/directory).rglob('*')
                   if p.suffix in ('.cpp', '.h', '.hpp'))
    for path in paths:
        digest.update(str(path.relative_to(ROOT)).encode()+b'\0'+path.read_bytes())
    compiler = subprocess.check_output([cache['CMAKE_CXX_COMPILER'], '--version'], text=True).strip()
    return {'host': platform.platform(), 'python': platform.python_version(), 'cache': cache, 'compiler': compiler,
            'source_sha256': digest.hexdigest(),
            'source_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('kind', choices=('all', 'catalog', 'uue', 'resources', 'mcp', 'registry'))
    parser.add_argument('--build-dir', type=Path, default=ROOT/'build/backend')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--samples', type=int, default=20)
    parser.add_argument('--case', default='*', help='Select case names by glob')
    args = parser.parse_args()
    if args.samples < 1:
        parser.error('--samples must be positive')
    selected = [case for case in cases(args.kind) if fnmatch.fnmatchcase(case[0], args.case)]
    if not selected:
        parser.error('No matching cases')
    args.output.mkdir(parents=True, exist_ok=False)
    build = args.build_dir.resolve()
    report = {'schema': 1, 'environment': metadata(build), 'samples': args.samples,
              'matrix': args.kind, 'case_filter': args.case, 'expected_cases': len(selected),
              'complete': False, 'cases': []}
    for name, pattern, options, repeat in selected:
        print('Measuring '+name, flush=True)
        environment = {k: v for k, v in os.environ.items() if not k.startswith('FFIDO_BENCH_')}
        environment.update({'FFIDO_BENCH_'+key: str(value) for key, value in options.items()})
        environment['FFIDO_BENCH_SAMPLES'] = str(args.samples)
        command = ['ctest', '--test-dir', str(build), '--output-on-failure', '-V', '-R', pattern]
        if repeat:
            command += ['--repeat', 'until-fail:'+str(args.samples)]
        started = time.monotonic()
        log = args.output/(name+'.log')
        with log.open('w') as output:
            completed = subprocess.run(command, cwd=ROOT, env=environment, stdout=output,
                                       stderr=subprocess.STDOUT, timeout=360*args.samples)
        records = parse_records(log.read_text())
        error = None
        if not completed.returncode:
            try:
                validate_records(name, records, options, args.samples)
            except ValueError as failure:
                error = str(failure)
        entry = {'name': name, 'options': options, 'command': command, 'returncode': completed.returncode,
                 'wall_seconds': time.monotonic()-started, 'records': records, 'summary': summarize(records),
                 'validation_error': error}
        report['cases'].append(entry)
        (args.output/'report.json').write_text(json.dumps(report, indent=2)+'\n')
        if completed.returncode or not records or error:
            raise SystemExit(f'Measurement failed: {name}; see {log}')
    report['complete'] = True
    (args.output/'report.json').write_text(json.dumps(report, indent=2)+'\n')
    print('Saved '+str(args.output/'report.json'), flush=True)


if __name__ == '__main__':
    main()
