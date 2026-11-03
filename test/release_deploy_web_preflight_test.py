"""A read-only deploy prerequisite check never packs or uploads bytes."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DeployPreflightTest(unittest.TestCase):
    def test_preflight_success_and_failure_never_pack_or_upload(self):
        for failure in (False, True):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                tools, bundle, log = root / 'bin', root / 'bundle', root / 'calls'
                tools.mkdir()
                bundle.mkdir()
                (bundle / 'index.html').write_text('checked elsewhere')
                (bundle / 'SHA256SUMS').write_text('checked elsewhere')
                scripts = {'dart': '#!/bin/sh\nexit 0\n',
                           'ssh': '#!/bin/sh\nprintf "ssh\\n" >> "$PROBE_LOG"\nexit "$SSH_RESULT"\n',
                           'scp': '#!/bin/sh\nprintf "BAD_SCP\\n" >> "$PROBE_LOG"\nexit 99\n',
                           'tar': '#!/bin/sh\nprintf "BAD_TAR\\n" >> "$PROBE_LOG"\nexit 99\n'}
                for name, content in scripts.items():
                    target = tools / name
                    target.write_text(content)
                    target.chmod(0o700)
                result = subprocess.run(['bash', str(ROOT / 'scripts/deploy_web.sh'),
                    '--preflight-only', '--bundle-dir', str(bundle)], env=dict(os.environ,
                    PATH=str(tools) + os.pathsep + os.environ['PATH'], PROBE_LOG=str(log),
                    SSH_RESULT='1' if failure else '0'), capture_output=True, text=True, timeout=20)
                self.assertEqual(result.returncode, 1 if failure else 0, result.stderr)
                self.assertEqual(log.read_text().splitlines(), ['ssh'])


if __name__ == '__main__':
    unittest.main()
