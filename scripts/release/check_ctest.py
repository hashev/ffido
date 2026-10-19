#!/usr/bin/env python3
"""Run all registered CTests and reject hidden skips in the integration gate."""
import argparse
import os
import pathlib
import subprocess
import xml.etree.ElementTree as ET
p = argparse.ArgumentParser()
p.add_argument('build', type=pathlib.Path)
a = p.parse_args()
if not pathlib.Path(os.environ.get('FFIDO_TEST_HPT', '')).is_file():
    p.exit(1, 'FFIDO_TEST_HPT must point to the pinned test HPT\n')
report = a.build.resolve()/'ctest-release.xml'
subprocess.run(['ctest', '--test-dir', str(a.build), '--output-on-failure', '--output-junit', str(report)], check=True)
tree = ET.parse(report)
assert list(tree.iter('testcase')), 'No tests discovered'
assert not list(tree.iter('skipped')), 'Required integration test was skipped'
