"""Release admission contracts without a build, daemon or SDK installation."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHA = 'a' * 40


class ResourceToolchainTest(unittest.TestCase):
    def test_wrong_live_sdk_stops_before_linux_build(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'bin').mkdir()
            (root / 'pubspec.yaml').write_text('version: 1.2.3+1\n')
            git = root / 'bin/git'
            git.write_text('#!/bin/sh\necho ' + SHA + '\n')
            git.chmod(0o700)
            make = root / 'bin/make'
            make.write_text('''#!/usr/bin/env python3
import json,os,sys
with open(os.environ['CALLS'], 'a') as f:
 f.write(json.dumps([sys.argv[1:], os.environ.get('CMAKE_BUILD_PARALLEL_LEVEL')])+'\\n')
if sys.argv[1]=='check-toolchain': sys.exit(1)
''')
            make.chmod(0o700)
            calls = root / 'calls'
            result = subprocess.run(['bash', str(ROOT / 'scripts/build_release_channel.sh'),
                'v1.2.3', SHA, 'codex/release-candidate-v1.2.3-' + SHA, 'linux-tar'],
                cwd=root, env=dict(os.environ, PATH=str(root / 'bin') + ':' + os.environ['PATH'],
                                   CALLS=str(calls)), capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual([json.loads(row) for row in calls.read_text().splitlines()],
                             [[['check-toolchain'], '2']])
            self.assertFalse((root / 'dist').exists())

    def test_every_docker_job_has_quota_and_linux_channels_share_queue(self):
        text = (ROOT / '.forgejo/workflows/release-channel.yml').read_text()
        self.assertIn("|| 'linux-web-server'", text)
        self.assertIn('cancel-in-progress: false', text)
        containers = text.split('    container:\n')[1:]
        self.assertEqual(len(containers), 8)
        for container in containers:
            self.assertIn('options: --cpus 2 --memory ', container.split('      image:')[0])
        self.assertIn("inputs.channel == 'windows' && '4g' || '8g'", containers[0])

    def test_debian_daemon_build_and_execution_are_bounded(self):
        text = (ROOT / 'scripts/build_debian12_release.sh').read_text()
        self.assertIn('build --platform linux/amd64 --cpu-quota 200000 --cpu-period 100000 --memory 8g', text)
        self.assertIn('create --platform linux/amd64 --cpus 2 --memory 8g', text)
        self.assertIn('--env CMAKE_BUILD_PARALLEL_LEVEL=2', text)
        entry = (ROOT / 'scripts/debian12_builder/container-build.sh').read_text()
        self.assertLess(entry.index('dart run tool/check_toolchain.dart'), entry.index('flutter pub get'))
