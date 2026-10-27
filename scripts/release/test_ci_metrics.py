import unittest
import ci_metrics


class CIMetricsTest(unittest.TestCase):
    def test_queues_excluded_and_android_dependency_path_included(self):
        def job(name, start, end):
            return {'name': 'verify / '+name, 'status': 'completed', 'conclusion': 'success',
                    'created_at': '2026-10-26T10:00:00Z',
                    'started_at': f'2026-10-26T10:{start:02}:00Z',
                    'completed_at': f'2026-10-26T10:{end:02}:00Z'}
        result = ci_metrics.report([job('client (macos)', 10, 15), job('android-fixtures', 2, 8),
                                    job('android-qa (24)', 20, 24), job('backend (linux)', 1, 9)])
        self.assertEqual(result['execution_critical_path_seconds'], 600)
        self.assertEqual(result['jobs'][0]['queue_seconds'], 600)
        self.assertEqual(result['runner_minutes'], 23)
        self.assertEqual(result['jobs'][2]['dependency_wait_seconds'], 900)
        self.assertEqual(result['jobs'][2]['queue_seconds'], 300)
        self.assertFalse(result['provisional'])
