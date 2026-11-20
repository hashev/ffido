"""Explicit local-pair transition; production trust is always distribution-owned."""
import pathlib
import json
import hashlib

import common
import discovery
from server import atomic_bytes, atomic_json, locked


def signed_floor(plan, state, keys):
    evidence = plan['signed_floor']
    previous = common.verify_manifest(pathlib.Path(evidence['manifest']).read_bytes(),
                                      pathlib.Path(evidence['signature']).read_bytes(), keys)
    floor = previous['update_sequence']
    # Legacy signed state may carry a newer accepted sequence. Never reset it.
    for name in ('sequence.json', 'signed-sequence.json'):
        path = state/name
        if path.exists():
            floor = max(floor, common.integer(common.strict_json(path.read_bytes())['value']))
    return floor


def commit_floor(state, sequence):
    floor = common.integer(sequence, 1)
    for name in ('signed-sequence.json', 'sequence.json'):
        path = state/name
        if path.exists():
            floor = max(floor, common.integer(common.strict_json(path.read_bytes())['value']))
    for name in ('signed-sequence.json', 'sequence.json'):
        atomic_json(state/name, {'value': floor})


def target(args, plan, state, keys):
    raw = args.target_manifest.read_bytes()
    signature = args.target_signature.read_bytes()
    manifest = discovery.selected(raw, signature, keys, args.target_tag,
                                  args.channel or 'stable', signed_floor(plan, state, keys))
    return manifest, raw, signature


def save_signed(state, raw, signature):
    digest = hashlib.sha256(raw).hexdigest()
    paths = {'manifest': state/('manifest-'+digest+'.json'),
             'signature': state/('manifest-'+digest+'.sig')}
    for role, content in [('manifest', raw), ('signature', signature)]:
        atomic_bytes(paths[role], content)
    return {**{k: str(v) for k, v in paths.items()}, 'sha256': digest}


def accepted_source(plan, state, keys, actual, managed_files):
    """Adopt only the exact previously accepted pair backed by signed evidence."""
    path = state/'pair-provenance.json'
    if not path.exists():
        common.verify_local_pair(plan, actual)
        return plan, None
    provenance = common.strict_json(path.read_bytes())
    evidence = provenance['signed']
    raw = pathlib.Path(evidence['manifest']).read_bytes()
    if hashlib.sha256(raw).hexdigest() != evidence['sha256']:
        raise ValueError('Accepted signed provenance changed')
    manifest = common.verify_manifest(raw, pathlib.Path(evidence['signature']).read_bytes(), keys)
    if actual != provenance['source'] or any(x['build'] != provenance['build'] for x in actual.values()):
        raise ValueError('Running pair differs from accepted provenance')
    if any(provenance['build'].get(k) != v for k, v in manifest['identity'].items()):
        raise ValueError('Accepted provenance differs from signed identity')
    adopted = {**plan, 'source': actual, 'files': {k: v for k, v in plan['files'].items() if k not in managed_files}}
    common.verify_local_pair(adopted, actual)
    return adopted, manifest['identity']


def automatic_allowed(plan, installed):
    if installed is None:
        raise ValueError('The first local-to-signed transition must be manual')
    guards = plan.get('automatic_guards')
    if not isinstance(guards, dict) or not guards.get('pause_files'):
        raise ValueError('Automatic mode requires explicit pause guards')
    for name in guards['pause_files']:
        marker = common.strict_json(pathlib.Path(name).read_bytes())
        if marker.get('automatic_apply_paused') is not False:
            raise ValueError('Automatic pair update remains paused')
    if any(pathlib.Path(x).exists() for x in guards.get('block_if_exists', [])):
        raise ValueError('A separate maintenance guard blocks automatic apply')


def main(args, compose, keys, write_images):
    if not args.pair_plan_sha256:
        raise ValueError('Pair mode requires an external trusted plan digest')
    plan = common.local_pair(args.pair_plan.read_bytes(), args.pair_plan_sha256)
    with locked(compose.state/'operation.lock'):
        from pair_host import Host
        from node_maintenance import Transition
        host = Host(compose, plan, write_images)
        operation = Transition(host, compose.state)
        if args.action == 'status':
            record = operation.read()
            print(json.dumps({'phase': record['phase'], 'admitted': record['admitted'],
                              'automatic_state_unchanged': True}))
            return 0
        installed = None
        if args.action in {'check', 'apply'}:
            adopted, installed = accepted_source(plan, compose.state, keys, host.actual_source(),
                                                 {str(compose.override), plan['identity_file']})
            host.plan = adopted
        if args.automatic:
            automatic_allowed(plan, installed)
        if all((args.target_manifest, args.target_signature, args.target_tag)):
            selected, raw, signature = target(args, plan, compose.state, keys)
        elif installed is not None:
            choices = discovery.releases(installed, keys, args.channel or 'stable',
                                          signed_floor(plan, compose.state, keys))
            chosen = next((x for x in choices if x[0].get('container')), None)
            if chosen is None:
                print(json.dumps({'current_origin': 'accepted-signed-pair', 'available': None,
                                  'automatic_state_unchanged': True}))
                return 0
            selected, raw, signature = chosen
        else:
            raise ValueError('Select an explicit signed target manifest, signature and tag')
        if args.action == 'check':
            print(json.dumps({'current_origin': 'accepted-signed-pair' if installed else 'registered-local-pair',
                              'available': selected['identity']['tag'],
                              'automatic_state_unchanged': True}))
            return 0
        if args.action in {'resume', 'rollback'}:
            recorded = operation.read()
            digest = hashlib.sha256(json.dumps(selected, sort_keys=True).encode()).hexdigest()
            if recorded['manifest_sha256'] != digest:
                raise ValueError('Selected release differs from interrupted transaction')
            host.assert_known_state(recorded)
            immutable = {k: v for k, v in plan['files'].items()
                         if k not in {str(compose.override), plan['identity_file']}}
            common.verify_local_pair({'source': recorded['baseline']['source'], 'files': immutable},
                                     recorded['baseline']['source'])
            host.plan = {**host.plan, 'source': recorded['baseline']['source']}
        host.signed_evidence = save_signed(compose.state, raw, signature)
        maintenance = host.root/plan['backup']['maintenance_lock']
        with locked(maintenance, create=False) as lease:
            host.maintenance_fd = lease
            if args.action == 'apply':
                operation.apply(args.pair_plan_sha256, selected)
            elif args.action == 'resume':
                operation.resume(args.pair_plan_sha256)
            else:
                operation.rollback(args.pair_plan_sha256)
        print(json.dumps({'phase': operation.read()['phase'], 'automatic_state_unchanged': True}))
        return 0
