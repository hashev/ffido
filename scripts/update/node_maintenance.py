"""Durable pair transaction. The host adapter owns Docker, backup and probes."""
import common
import hashlib
import json
import uuid
from server import atomic_json


class Transition:
    def __init__(self, host, state):
        self.host, self.path = host, state/'pair-operation.json'

    def read(self):
        return common.strict_json(self.path.read_bytes())

    def record(self, value, phase, **fields):
        value.update(fields, phase=phase)
        atomic_json(self.path, value)
        return value

    def apply(self, plan_digest, manifest):
        previous = self.read() if self.path.exists() else None
        if previous and previous['phase'] not in {'rolled-back', 'aborted', 'complete'}:
            raise ValueError('Existing pair transaction; use status/resume/rollback')
        # Preparation, schema/space checks and identity recheck precede all stops.
        prepared = self.host.prepare(manifest)
        self.host.preflight()
        value = {'version': 1, 'plan_sha256': plan_digest, 'admitted': False,
                 'source_unchanged': True,
                 'target': manifest['identity'], 'sequence': manifest['update_sequence'],
                 'manifest_sha256': hashlib.sha256(json.dumps(manifest, sort_keys=True).encode()).hexdigest(),
                 'prepared': prepared, 'baseline': self.host.baseline()}
        if previous:
            atomic_json(self.path.with_name('pair-history-'+uuid.uuid4().hex+'.json'), previous)
        self.record(value, 'prepared')
        try:
            self.record(value, 'quiescing')
            self.host.quiesce()
            self.record(value, 'quiesced')
            backup = self.host.backup()
            self.record(value, 'backed-up', backup=backup)
        except Exception:
            # No migration or image change has occurred in these phases.
            self.record(value, 'aborted')
            self.host.return_original(value['baseline'])
            raise
        try:
            self.record(value, 'switching', source_unchanged=False)
            self.host.switch(prepared)
            self.record(value, 'validating')
            self.host.validate_private()
            self.record(value, 'private-ready')
            # Public ingress may accept a write immediately. Persist this first.
            self.record(value, 'admitting', admitted=True)
            self.host.open_ingress()
            self.host.validate_public()
            self.record(value, 'accepted')
            self.host.commit(value['sequence'])
            self.record(value, 'releasing-writers')
            self.host.release_writers(value['baseline'])
            self.record(value, 'complete')
        except Exception:
            self.host.quiesce()
            self.record(value, 'rollback-required')
            raise
        return value

    def resume(self, plan_digest):
        value = self.read()
        if value['plan_sha256'] != plan_digest:
            raise ValueError('Transaction belongs to another trusted plan')
        if value['phase'] in {'complete', 'rolled-back', 'aborted'}:
            return value
        # A crash can leave a partial pair. Close writers before any inspection.
        self.record(value, 'recovery-quiescing')
        self.host.quiesce()
        if value['admitted']:
            self.record(value, 'reconciliation-required')
            self.host.preserve_current()
            raise ValueError('Writes may have been admitted; preserve and reconcile current data')
        if value.get('source_unchanged') or 'backup' not in value:
            self.record(value, 'aborted')
            self.host.return_original(value['baseline'])
            return value
        return self.rollback(plan_digest)

    def rollback(self, plan_digest):
        value = self.read()
        if value['plan_sha256'] != plan_digest:
            raise ValueError('Transaction belongs to another trusted plan')
        if value['phase'] in {'rolled-back', 'aborted'}:
            return value
        self.record(value, 'rollback-quiescing')
        self.host.quiesce()
        if value.get('source_unchanged'):
            self.record(value, 'aborted')
            self.host.return_original(value['baseline'])
            return value
        if value['admitted']:
            self.host.preserve_current()
            if not self.host.rollback_compatible(value['baseline']):
                self.record(value, 'reconciliation-required')
                raise ValueError('Snapshot rollback forbidden after admission; reconciliation required')
            # Explicit compatible image-only rollback retains all subsequent data.
            self.record(value, 'restoring', restore_required=False)
        self.record(value, 'restoring')
        if 'restore_required' not in value:
            self.record(value, 'restoring', restore_required=not self.host.rollback_compatible(value['baseline']))
        if value['restore_required']:
            self.host.restore(value['backup'])
        self.host.restore_pair(value['baseline'])
        self.host.validate_rollback()
        self.record(value, 'rollback-admitting', admitted=True)
        self.host.open_rollback_ingress(value['baseline'])
        self.host.validate_rollback_public()
        self.host.return_original(value['baseline'])
        return self.record(value, 'rolled-back', update_succeeded=False)
