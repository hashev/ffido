"""Crash boundaries and admission safety for the durable pair coordinator."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import node_maintenance
from server import locked


class Crash(BaseException):
    pass


class HostFixture:
    def __init__(self):
        self.calls = []
        self.fail = None
        self.compatible = True

    def call(self, name):
        self.calls.append(name)
        if self.fail == name:
            raise ValueError('injected failure')

    def prepare(self, manifest):
        self.call('prepare')
        return {'backend': 'new', 'tosser': 'new-worker'}

    def preflight(self): self.call('preflight')
    def baseline(self): return {'running': {'backend': True, 'tosser': True, 'mailer': False}}
    def quiesce(self): self.call('quiesce')
    def backup(self): self.call('backup'); return {'sha256': 'trusted-backup'}
    def switch(self, prepared): self.call('switch')
    def validate_private(self): self.call('validate-private')
    def open_ingress(self): self.call('open-ingress')
    def validate_public(self): self.call('validate-public')
    def commit(self, sequence): self.call('commit-floor')
    def release_writers(self, baseline): self.call('release-writers')
    def return_original(self, baseline): self.call('return-original')
    def preserve_current(self): self.call('preserve-current')
    def rollback_compatible(self, baseline): self.call('compatible'); return self.compatible
    def restore(self, backup): self.call('restore')
    def restore_pair(self, baseline): self.call('restore-pair')
    def validate_rollback(self): self.call('validate-rollback')
    def validate_rollback_public(self): self.call('validate-rollback-public')
    def open_rollback_ingress(self, baseline): self.call('open-rollback-ingress')


class CoordinatorTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.host = HostFixture()
        self.transaction = node_maintenance.Transition(self.host, Path(self.temp.name))
        self.manifest = {'identity': {'tag': 'v1.0.28'}, 'update_sequence': 1066}

    def apply(self): return self.transaction.apply('trusted-plan', self.manifest)

    def test_concurrent_operation_is_rejected_before_host_actions(self):
        with locked(self.transaction.path.with_suffix('.lock')):
            with self.assertRaises(ValueError):
                with locked(self.transaction.path.with_suffix('.lock')):
                    self.apply()
        self.assertEqual(self.host.calls, [])

    def test_success_orders_backup_validation_and_write_admission(self):
        original = self.host.open_ingress
        def open_ingress():
            self.assertTrue(self.transaction.read()['admitted'])
            self.assertEqual(self.transaction.read()['phase'], 'admitting')
            original()
        self.host.open_ingress = open_ingress
        self.assertEqual(self.apply()['phase'], 'complete')
        self.assertEqual(self.host.calls, ['prepare', 'preflight', 'quiesce', 'backup', 'switch',
                                          'validate-private', 'open-ingress', 'validate-public',
                                          'commit-floor', 'release-writers'])

    def test_worker_preparation_and_budget_fail_before_stop(self):
        for name in ('prepare', 'preflight'):
            with self.subTest(name=name):
                self.host.calls = []; self.host.fail = name
                with self.assertRaises(ValueError): self.apply()
                self.assertNotIn('quiesce', self.host.calls)
                self.assertFalse(self.transaction.path.exists())

    def test_backup_failure_does_not_switch_or_blindly_restart_migrated_state(self):
        self.host.fail = 'backup'
        with self.assertRaises(ValueError): self.apply()
        self.assertEqual(self.transaction.read()['phase'], 'aborted')
        self.assertIn('return-original', self.host.calls)
        self.assertNotIn('switch', self.host.calls)

    def test_crash_between_pair_starts_recovers_by_verified_rollback(self):
        with patch.object(self.host, 'switch', side_effect=Crash):
            with self.assertRaises(Crash): self.apply()
        self.assertEqual(self.transaction.read()['phase'], 'switching')
        value = self.transaction.resume('trusted-plan')
        self.assertEqual(value['phase'], 'rolled-back')
        self.assertFalse(value['update_succeeded'])
        self.assertNotIn('open-ingress', self.host.calls)

    def test_incompatible_state_restores_full_backup_before_original_pair(self):
        self.host.compatible = False
        self.host.fail = 'validate-private'
        with self.assertRaises(ValueError): self.apply()
        self.host.fail = None
        self.transaction.rollback('trusted-plan')
        self.assertLess(self.host.calls.index('restore'), self.host.calls.index('restore-pair'))
        calls = list(self.host.calls)
        self.transaction.rollback('trusted-plan')
        self.assertEqual(self.host.calls, calls)

    def test_gateway_failure_after_admission_preserves_data_and_blocks_snapshot(self):
        self.host.fail = 'validate-public'
        self.host.compatible = False
        with self.assertRaises(ValueError): self.apply()
        self.host.fail = None
        with self.assertRaisesRegex(ValueError, 'reconciliation'):
            self.transaction.rollback('trusted-plan')
        self.assertIn('preserve-current', self.host.calls)
        self.assertNotIn('restore', self.host.calls)
        self.assertNotIn('restore-pair', self.host.calls)
        self.assertNotIn('commit-floor', self.host.calls)

    def test_explicit_compatible_rollback_after_admission_keeps_new_data(self):
        self.apply()
        self.transaction.rollback('trusted-plan')
        self.assertIn('preserve-current', self.host.calls)
        self.assertIn('restore-pair', self.host.calls)
        self.assertNotIn('restore', self.host.calls)
        self.assertFalse(self.transaction.read()['restore_required'])

    def test_crash_before_opening_listener_is_conservatively_admitted(self):
        original = self.transaction.record
        def record(value, phase, **fields):
            result = original(value, phase, **fields)
            if phase == 'admitting': raise Crash()
            return result
        with patch.object(self.transaction, 'record', side_effect=record):
            with self.assertRaises(Crash): self.apply()
        self.assertNotIn('open-ingress', self.host.calls)
        with self.assertRaisesRegex(ValueError, 'reconcile'):
            self.transaction.resume('trusted-plan')
        self.assertNotIn('restore', self.host.calls)

    def test_resume_rejects_another_plan_and_never_restarts_after_migration_error(self):
        self.host.fail = 'validate-private'
        with self.assertRaises(ValueError): self.apply()
        self.assertNotIn('return-original', self.host.calls)
        with self.assertRaises(ValueError): self.transaction.resume('another-plan')

    def test_restore_decision_is_persisted_before_restoring(self):
        self.host.fail = 'validate-private'
        self.host.compatible = False
        with self.assertRaises(ValueError): self.apply()
        self.host.fail = None
        with patch.object(self.host, 'restore', side_effect=Crash):
            with self.assertRaises(Crash): self.transaction.rollback('trusted-plan')
        self.assertTrue(self.transaction.read()['restore_required'])
        self.host.compatible = True  # Half-restored state must not change the decision.
        self.transaction.resume('trusted-plan')
        self.assertIn('restore', self.host.calls)

    def test_abort_journal_is_durable_before_returning_source_writers(self):
        self.host.fail = 'backup'
        original = self.host.return_original
        def returned(baseline):
            self.assertEqual(self.transaction.read()['phase'], 'aborted')
            original(baseline)
        self.host.return_original = returned
        with self.assertRaises(ValueError): self.apply()
        self.assertTrue(self.transaction.read()['source_unchanged'])

    def test_journal_failure_after_backup_never_replays_snapshot_over_source(self):
        original = self.transaction.record
        def record(value, phase, **fields):
            result = original(value, phase, **fields)
            if phase in {'backed-up', 'aborted'}: raise OSError('injected journal fsync failure')
            return result
        with patch.object(self.transaction, 'record', side_effect=record):
            with self.assertRaises(OSError): self.apply()
        self.assertNotIn('return-original', self.host.calls)
        self.transaction.resume('trusted-plan')
        self.assertNotIn('restore', self.host.calls)

    def test_rollback_public_admission_also_blocks_replaying_old_snapshot(self):
        self.host.fail = 'validate-private'; self.host.compatible = False
        with self.assertRaises(ValueError): self.apply()
        self.host.fail = 'validate-rollback-public'
        with self.assertRaises(ValueError): self.transaction.rollback('trusted-plan')
        self.assertTrue(self.transaction.read()['admitted'])
        self.host.fail = None
        calls = list(self.host.calls)
        with self.assertRaises(ValueError): self.transaction.resume('trusted-plan')
        self.assertEqual(self.host.calls.count('restore'), calls.count('restore'))
