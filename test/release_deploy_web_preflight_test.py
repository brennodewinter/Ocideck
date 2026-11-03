"""A read-only deploy prerequisite check never packs or uploads bytes."""
import os
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DeployPreflightTest(unittest.TestCase):
    def test_config_readback_rejects_conflicting_modes_and_unbound_local_config_before_ssh(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tools, bundle, log = root / 'bin', root / 'bundle', root / 'calls'
            tools.mkdir(); bundle.mkdir()
            (bundle / '.htaccess').write_bytes(b'private config')
            (bundle / 'SHA256SUMS').write_text('0' * 64 + '  .htaccess\n')
            ssh = tools / 'ssh'
            ssh.write_text('#!/bin/sh\nprintf "BAD_SSH\\n" >> "$PROBE_LOG"\nexit 0\n')
            ssh.chmod(0o700)
            for flags in (['--dry-run'], ['--preflight-only'], []):
                with self.subTest(flags=flags):
                    result = subprocess.run(['bash', str(ROOT / 'scripts/deploy_web.sh'),
                        '--verify-server-config-only', '--bundle-dir', str(bundle), *flags],
                        env=dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'],
                                 PROBE_LOG=str(log)), capture_output=True, text=True, timeout=20)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(log.exists())

    def test_config_readback_is_read_only_strict_and_bound_to_manifest(self):
        for problem in ('none', 'config', 'manifest', 'missing', 'symlink', 'root-symlink', 'ssh'):
            with self.subTest(problem=problem), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                tools, bundle, remote, log = root / 'bin', root / 'bundle', root / "remote root's files", root / 'calls'
                tools.mkdir(); bundle.mkdir(); remote.mkdir()
                content = b'Header always set X-Content-Type-Options nosniff\n'
                manifest = hashlib.sha256(content).hexdigest() + '  .htaccess\n'
                for target in (bundle, remote):
                    (target / '.htaccess').write_bytes(content)
                    (target / 'SHA256SUMS').write_text(manifest)
                if problem == 'config':
                    (remote / '.htaccess').write_bytes(b'tampered config')
                elif problem == 'manifest':
                    (remote / 'SHA256SUMS').write_text(manifest + 'unexpected\n')
                elif problem == 'missing':
                    (remote / '.htaccess').unlink()
                elif problem == 'symlink':
                    (remote / '.htaccess').unlink()
                    (remote / '.htaccess').symlink_to(bundle / '.htaccess')
                elif problem == 'root-symlink':
                    alias = root / 'remote-alias'
                    alias.symlink_to(remote, target_is_directory=True)
                    remote = alias
                ssh = tools / 'ssh'
                ssh.write_text('''#!/usr/bin/env python3
import json,os,shlex,subprocess,sys
from pathlib import Path
Path(os.environ['PROBE_LOG']).write_text(json.dumps(sys.argv[1:]))
if os.environ['SSH_RESULT'] != '0': sys.exit(1)
sys.exit(subprocess.run(shlex.split(sys.argv[-1]),input=sys.stdin.buffer.read()).returncode)
''')
                ssh.chmod(0o700)
                for name in ('scp', 'tar', 'curl', 'git', 'dart'):
                    path = tools / name
                    path.write_text('#!/bin/sh\nprintf "BAD_MUTATION\\n" >> "$PROBE_LOG"\nexit 99\n')
                    path.chmod(0o700)
                before = {path: path.read_bytes() for target in (bundle, remote) for path in target.iterdir()}
                result = subprocess.run(['bash', str(ROOT / 'scripts/deploy_web.sh'),
                    '--verify-server-config-only', '--bundle-dir', str(bundle)], env=dict(os.environ,
                    PATH=str(tools) + os.pathsep + os.environ['PATH'], PROBE_LOG=str(log),
                    SSH_RESULT='1' if problem == 'ssh' else '0', OCIDECK_DEPLOY_ROOT=str(remote),
                    OCIDECK_DEPLOY_HOST='fixture@example.test'), capture_output=True, text=True, timeout=20)
                self.assertEqual(result.returncode == 0, problem == 'none', result.stderr)
                calls = json.loads(log.read_text())
                self.assertIn('StrictHostKeyChecking=yes', calls)
                self.assertIn('BatchMode=yes', calls)
                self.assertEqual(calls[-2], 'fixture@example.test')
                self.assertEqual(before, {path: path.read_bytes() for path in before})
                self.assertFalse(list(root.glob('*.bak-*')))

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
