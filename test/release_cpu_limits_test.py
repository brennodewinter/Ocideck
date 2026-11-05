"""Exercise the Node-only resource guard through the normal release test gate."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ReleaseCpuLimitsTest(unittest.TestCase):
    def test_node_guard_behaviour(self):
        result = subprocess.run(
            ['node', '--test', str(ROOT / 'test/release_cpu_limits_test.cjs')],
            cwd=ROOT, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
