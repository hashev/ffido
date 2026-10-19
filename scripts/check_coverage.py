#!/usr/bin/env python3
"""Enforce the agreed coverage gates; never substitute exclusions for missing tests."""
import argparse
import json
import pathlib
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--backend', type=pathlib.Path, required=True)
parser.add_argument('--frontend', type=pathlib.Path, required=True)
args = parser.parse_args()
backend = json.loads(args.backend.read_text())['data'][0]
frontend = json.loads(args.frontend.read_text())
failures = []
def check(label, covered, total, minimum):
    percent = 100*covered/total if total else 0
    print(f'{label}: {covered}/{total} ({percent:.2f}%), required {minimum}%')
    if percent < minimum:
        failures.append(label)
for metric, minimum in [('lines', 90), ('branches', 85)]:
    summary = backend['totals'][metric]
    check('Backend '+metric, summary['covered'], summary['count'], minimum)
critical = [f for f in backend['files'] if any(part in f['filename'] for part in ('JamMessageBase.h', '/jam_', '/auth_service.', '/crypto.', '/sqlite_store.'))]
for metric, minimum in [('lines', 95), ('branches', 90)]:
    check('JAM/auth/idempotency/recovery '+metric, sum(f['summary'][metric]['covered'] for f in critical), sum(f['summary'][metric]['count'] for f in critical), minimum)
check('Flutter lines', frontend['covered'], frontend['lines'], 90)
# Platform-specific source coverage is combined by the platform acceptance runs.
if failures:
    raise SystemExit('Coverage gates failed: '+', '.join(failures))
