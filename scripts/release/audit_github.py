#!/usr/bin/env python3
"""Read-only verification of repository access and master protection."""
import json
import subprocess


def check(repo, rules, workflow):
    errors = []
    if repo.get('private') or repo.get('pull_request_creation_policy') != 'collaborators_only':
        errors.append('Public repository with collaborators-only PRs required')
    if repo.get('default_branch') != 'master':
        errors.append('Default branch must become master after bootstrap')
    if workflow.get('default_workflow_permissions') != 'read' or workflow.get('can_approve_pull_request_reviews'):
        errors.append('Actions default permissions must be read-only without PR approval')
    applicable = [r for r in rules if r.get('enforcement') == 'active' and not r.get('bypass_actors')
                  and 'refs/heads/master' in r.get('conditions', {}).get('ref_name', {}).get('include', [])]
    protected = False
    for rule in applicable:
        types = {r['type']: r.get('parameters', {}) for r in rule['rules']}
        pr, checks = types.get('pull_request', {}), types.get('required_status_checks', {})
        protected |= (all(t in types for t in ['pull_request', 'required_status_checks', 'deletion', 'non_fast_forward'])
                      and pr.get('required_approving_review_count') == 0
                      and not pr.get('require_code_owner_review') and not pr.get('require_last_push_approval')
                      and pr.get('required_review_thread_resolution') is True
                      and checks.get('strict_required_status_checks_policy') is True
                      and any(c.get('context') == 'ci-required' and c.get('integration_id') == 15368
                              for c in checks.get('required_status_checks', [])))
    if not protected:
        errors.append('Active master PR/CI ruleset without bypass is missing or invalid')
    return errors


def api(path):
    return json.loads(subprocess.check_output(['gh', 'api', path], text=True))


if __name__ == '__main__':
    repo = 'hashev/ffido'
    rules = [api(f'repos/{repo}/rulesets/{r["id"]}') for r in api(f'repos/{repo}/rulesets')]
    errors = check(api(f'repos/{repo}'), rules, api(f'repos/{repo}/actions/permissions/workflow'))
    for error in errors:
        print(error)
    raise SystemExit(bool(errors))
