"""Protect numeric measurement reports and fail-closed CTest orchestration."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('hardening_measurements',
                                             Path(__file__).parents[1]/'hardening_measurements.py')
measure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(measure)


class HardeningMeasurementsTest(unittest.TestCase):
    def test_ctest_prefixes_and_all_numeric_records_are_preserved(self):
        records = measure.parse_records('17: UUE_MEASURE {"phase":"warm","latency_ms":[1,4],'
                                        '"completed":1,"successful_latency_ms":[1],"errors":{"4":1}}\nother output\n')
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]['kind'], 'UUE_MEASURE')
        self.assertEqual(measure.summarize(records)['warm'],
                         {'samples': 2, 'p50_ms': 1, 'p95_ms': 4, 'completed': 1, 'errors': {'4': 1},
                          'successful_latency': {'samples': 1, 'p50_ms': 1, 'p95_ms': 1}})

    def test_bad_or_non_object_record_is_an_error(self):
        for text in ('UUE_MEASURE {broken}', 'UUE_MEASURE []'):
            with self.assertRaises(ValueError):
                measure.parse_records(text)

    def test_percentiles_keep_boundary_samples(self):
        self.assertEqual(measure.percentiles([]), {'samples': 0})
        self.assertEqual(measure.percentiles([7]), {'samples': 1, 'p50_ms': 7, 'p95_ms': 7})
        self.assertEqual(measure.percentiles(list(range(20)))['p95_ms'], 18)

    def test_matrix_keeps_single_source_within_public_jam_read_limit(self):
        cases = list(measure.cases('uue'))
        self.assertEqual(len(cases), 18)
        self.assertTrue(any(c[2]['FILE_BYTES'] == 1048576 and c[2]['SINGLE_SOURCE'] for c in cases))
        self.assertTrue(all(not c[2]['SINGLE_SOURCE'] for c in cases if c[2]['FILE_BYTES'] == 16777216))
        self.assertEqual(len(list(measure.cases('catalog'))), 24)

    def test_successful_exit_cannot_hide_missing_samples_or_outcomes(self):
        with self.assertRaisesRegex(ValueError, 'Incomplete cold/warm'):
            measure.validate_records('catalog-1', [], {'PARALLEL': 1}, 20)
        record = {'kind': 'UUE_MEASURE', 'sample': 0, 'latency_ms': [1], 'completed': 0, 'errors': {}}
        with self.assertRaisesRegex(ValueError, 'Missing request outcome'):
            measure.validate_records('uue-1', [record, {'kind': 'UUE_MEMORY'}], {'PARALLEL': 1}, 1)

    def test_failed_ctest_is_saved_and_never_reported_as_success(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)/'report'
            def failed(command, **kwargs):
                kwargs['stdout'].write('1: UUE_MEASURE {"phase":"cold","latency_ms":[3],'
                                       '"completed":0,"errors":{"4":1}}\n')
                return subprocess.CompletedProcess(command, 1)
            with patch('sys.argv', ['measure', 'uue', '--output', str(output), '--samples', '1']), \
                 patch.object(measure, 'metadata', return_value={}), \
                 patch.object(measure.subprocess, 'run', side_effect=failed):
                with self.assertRaisesRegex(SystemExit, 'Measurement failed'):
                    measure.main()
            report = json.loads((output/'report.json').read_text())
            self.assertFalse(report['complete'])
            self.assertEqual(report['cases'][0]['returncode'], 1)
            self.assertEqual(report['cases'][0]['summary']['cold']['errors'], {'4': 1})


if __name__ == '__main__':
    unittest.main()
