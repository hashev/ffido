import unittest
from unittest.mock import patch
import test_android_flow as flow


class AndroidLaunchTest(unittest.TestCase):
    def test_reopens_after_package_replacement_stops_first_launch(self):
        clock = [100.0]
        calls = []
        def device(*args): calls.append(args)
        with patch.object(flow.time, 'monotonic', side_effect=lambda: clock[0]), patch.object(flow.time, 'sleep', side_effect=lambda delay: clock.__setitem__(0, clock[0]+delay)):
            self.assertTrue(flow.launch_updated(device, lambda: len(calls) == 2, timeout=10))
        self.assertEqual(len(calls), 2)
        self.assertGreaterEqual(clock[0], 103)
        self.assertTrue(all('-W' not in call for call in calls))

    def test_unready_client_times_out_instead_of_reporting_success(self):
        clock = [100.0]
        with patch.object(flow.time, 'monotonic', side_effect=lambda: clock[0]), patch.object(flow.time, 'sleep', side_effect=lambda delay: clock.__setitem__(0, clock[0]+delay)):
            with self.assertRaisesRegex(RuntimeError, 'timed out'):
                flow.launch_updated(lambda *args: None, lambda: False, timeout=2)
