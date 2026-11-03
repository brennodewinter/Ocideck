"""Reject an incompatible shell checker before the expensive full gate."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ShellcheckPinTest(unittest.TestCase):
    def test_wrong_version_stops_without_scanning(self):
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / 'shellcheck'
            binary.write_text('#!/bin/sh\nif [ "$1" = --version ]; then echo "version: 0.9.0"; else exit 99; fi\n')
            binary.chmod(0o700)
            result = subprocess.run(['make', 'shellcheck'], cwd=ROOT,
                env=dict(os.environ, PATH=directory + os.pathsep + os.environ['PATH']),
                capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('ShellCheck 0.11.0 required', result.stdout)
            self.assertNotIn('Error 99', result.stderr)
        rule = next(line for line in (ROOT / 'Makefile').read_text().splitlines()
                    if line.startswith('check-full-locked:'))
        self.assertTrue(rule.startswith('check-full-locked: shellcheck check-locked '))


if __name__ == '__main__':
    unittest.main()
