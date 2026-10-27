#!/usr/bin/env python3
"""Report CI queue/execution separately and estimate the build DAG critical path."""
from datetime import datetime
import json
import os
from pathlib import Path
import sys


def seconds(start, finish):
    if not start or not finish:
        return 0
    return max(0, (datetime.fromisoformat(finish.replace('Z', '+00:00'))-
                   datetime.fromisoformat(start.replace('Z', '+00:00'))).total_seconds())


def report(jobs):
    def stage(job):
        return job['name'].split(' / ')[-1].split(' (')[0]
    ends = {}
    for job in jobs:
        if job.get('completed_at'):
            name = stage(job)
            ends[name] = max(ends.get(name, ''), job['completed_at'])
    roots = ['release-tools', 'portable-checks', 'client', 'backend', 'container', 'android-fixtures']
    build_jobs = [*roots, 'android-qa']
    parents = {name: (['identity'] if 'identity' in ends else []) for name in roots}
    parents.update({'android-qa': ['client', 'android-fixtures'], 'metrics': build_jobs,
                    'build-required': [*build_jobs, 'metrics'], 'ci-required': ['build-required'],
                    'android-sign': ['identity'], 'publish': ['build-required', 'android-sign', 'identity']})
    rows, stages = [], {}
    for job in jobs:
        if job['status'] != 'completed':
            continue
        name = stage(job)
        duration = seconds(job['started_at'], job['completed_at'])
        created = job.get('created_at')
        eligible = max([created or '', *[ends.get(parent, '') for parent in parents.get(name, [])]])
        queue = seconds(eligible, job['started_at'])
        stages[name] = max(stages.get(name, 0), duration)
        rows.append({'name': job['name'], 'queue_seconds': queue,
                     'dependency_wait_seconds': seconds(created, eligible),
                     'execution_seconds': duration, 'result': job.get('conclusion'), 'steps': [
                         {'name': step['name'], 'seconds': seconds(step.get('started_at'), step.get('completed_at'))}
                         for step in job.get('steps', [])]})
    android = max(stages.get('client', 0), stages.get('android-fixtures', 0))+stages.get('android-qa', 0)
    build = max([android, *[stages.get(name, 0) for name in roots]])
    gates = stages.get('metrics', 0)+stages.get('build-required', 0)
    if 'identity' in ends:
        critical = stages.get('identity', 0)+max(build+gates, stages.get('android-sign', 0))+stages.get('publish', 0)
    else:
        critical = build+gates+stages.get('ci-required', 0)
    return {'execution_critical_path_seconds': critical, 'build_critical_path_seconds': build,
            'provisional': any(job['status'] != 'completed' for job in jobs),
            'runner_minutes': sum(row['execution_seconds'] for row in rows)/60, 'jobs': rows,
            'method': 'Maximum weighted path of the current CI DAG; runner queue excludes dependency wait. In-flight metrics/gates make this estimate provisional; benchmark using final job data.'}


def main():
    path = Path(sys.argv[1])
    jobs = json.loads(path.read_text())
    value = report(jobs)
    value['sha'] = os.environ.get('GITHUB_SHA') or next((job.get('head_sha') for job in jobs if job.get('head_sha')), None)
    if os.environ.get('GITHUB_RUN_ID'):
        value['run_url'] = f"{os.environ.get('GITHUB_SERVER_URL')}/{os.environ.get('GITHUB_REPOSITORY')}/actions/runs/{os.environ.get('GITHUB_RUN_ID')}"
    else:
        value['run_url'] = next((job['html_url'].split('/job/')[0] for job in jobs if job.get('html_url')), None)
    path.with_name('metrics.json').write_text(json.dumps(value, indent=2)+'\n')
    lines = ['## CI timings', '', value['method'], '',
             f'Execution critical path: {value["execution_critical_path_seconds"]/60:.1f} minutes; provisional: {value["provisional"]}; runner execution: {value["runner_minutes"]:.1f} minutes.',
             '', '| Job | Queue seconds | Execution seconds | Result |', '|---|---:|---:|---|']
    for row in value['jobs']:
        lines.append(f'| {row["name"]} | {row["queue_seconds"]:.0f} | {row["execution_seconds"]:.0f} | {row["result"]} |')
    text = '\n'.join(lines)+'\n'
    print(text)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as out:
            out.write(text)


if __name__ == '__main__':
    main()
