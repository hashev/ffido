"""Keep installed-MCP loader failures visible instead of hiding them behind usage checks."""
import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('mcp_install', Path(__file__).parents[1]/'test_mcp_install.py')
install = importlib.util.module_from_spec(spec)
spec.loader.exec_module(install)


class McpInstallDiagnosticsTest(unittest.TestCase):
    def test_loader_error_reports_exit_and_bounded_stderr(self):
        response = subprocess.CompletedProcess([], -6, b'', b'Library not loaded: libgrpc++\n'+b'x'*5000)
        with patch.object(install.subprocess, 'run', return_value=response):
            with self.assertRaisesRegex(AssertionError, 'exit=-6; stderr=Library not loaded') as failure:
                install.check_startup(Path('/synthetic/ffido-mcp'))
        self.assertLess(len(str(failure.exception)), 4200)

    def test_only_real_usage_exit_is_accepted(self):
        for code in (0, 2):
            response = subprocess.CompletedProcess([], code, b'', b'Usage: ffido-mcp CONFIG')
            with patch.object(install.subprocess, 'run', return_value=response):
                if code == 2:
                    install.check_startup(Path('/synthetic/ffido-mcp'))
                else:
                    with self.assertRaises(AssertionError):
                        install.check_startup(Path('/synthetic/ffido-mcp'))
