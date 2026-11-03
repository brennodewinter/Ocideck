"""Consumer-image contract tests; Docker is replaced, never contacted."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROFILES = ('deb', 'rpm', 'tar', 'debian12', 'appimage', 'flatpak')


class ConsumerImagesTest(unittest.TestCase):
    def test_pinned_bases_and_captured_tool_versions(self):
        for profile in PROFILES:
            with self.subTest(profile=profile):
                text = (ROOT / 'scripts/release_consumers' / (profile + '.Dockerfile')).read_text()
                self.assertRegex(text, r'FROM [^\n]+@sha256:[0-9a-f]{64}\n')
                self.assertIn('packages.txt', text)
                self.assertIn('SOURCE_REVISION', text)
                self.assertNotIn('--no-gpg-verify', text)
        for profile in ('deb', 'rpm'):
            text = (ROOT / 'scripts/release_consumers' / (profile + '.Dockerfile')).read_text()
            for library in ('libgtk', 'libsecret', 'libayatana', 'libpulse'):
                self.assertNotIn(library, text)
        flatpak = (ROOT / 'scripts/release_consumers/flatpak.Dockerfile').read_text()
        self.assertIn('org.gnome.Platform/x86_64/50', flatpak)
        self.assertIn('--show-commit', flatpak)

    def test_image_probe_rejects_corrupt_bytes_before_docker_and_preserves_checks(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            artifact = directory / 'archive'
            artifact.write_bytes(b'existing verified fixture')
            docker = directory / 'docker'
            calls = directory / 'calls'
            docker.write_text('#!/bin/sh\ncat > "$DOCKER_CALLS"\n')
            docker.chmod(0o700)
            env = dict(os.environ, PATH=str(directory) + os.pathsep + os.environ['PATH'], DOCKER_CALLS=str(calls))
            command = ['bash', str(ROOT / 'scripts/probe_release_consumer_image.sh'), 'deb',
                       'registry.invalid/consumer@sha256:' + 'a' * 64, '9.9.9', str(artifact), '0' * 64]
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(calls.exists())
            import hashlib
            command[-1] = hashlib.sha256(artifact.read_bytes()).hexdigest()
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            probe = calls.read_text()
            self.assertLess(probe.index('ldconfig -p'), probe.index('apt-get install'))
            self.assertIn("grep 'not found'", probe)
            self.assertIn('timeout 20 xvfb-run', probe)
            self.assertIn('--no-deps --no-related --bundle', probe)
            self.assertIn('FILES.sha256', probe)

    def test_debian12_uses_existing_builder_without_other_format_builds(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / 'scripts').mkdir()
            (directory / 'bin').mkdir()
            (directory / 'pubspec.yaml').write_text('version: 9.9.9+1\n')
            sha = 'b' * 40
            builder = directory / 'scripts/build_debian12_release.sh'
            builder.write_text('#!/bin/sh\nset -eu\nmkdir dist\nprintf "%s" "$1" > dist/debian12-called\n')
            builder.chmod(0o700)
            git = directory / 'bin/git'
            git.write_text('#!/bin/sh\ncase "$1" in rev-parse) echo ' + sha + ';; ls-remote) echo "' + sha + ' ref";; *) exit 2;; esac\n')
            git.chmod(0o700)
            env = dict(os.environ, PATH=str(directory / 'bin') + os.pathsep + os.environ['PATH'])
            command = ['bash', str(ROOT / 'scripts/build_release_channel.sh'), 'v9.9.9', sha,
                       'codex/release-candidate-v9.9.9-' + sha, 'linux-debian12']
            result = subprocess.run(command, cwd=directory, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((directory / 'dist/debian12-called').read_text(), '9.9.9')
            repeated = subprocess.run(command, cwd=directory, env=env, capture_output=True, text=True)
            self.assertNotEqual(repeated.returncode, 0)
            self.assertIn('dist moet afwezig', repeated.stderr)

    def test_build_receipt_contains_registry_readback_digests(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            docker = directory / 'docker'
            docker.write_text('''#!/usr/bin/env python3
import json,os,sys
with open(os.environ['DOCKER_CALLS'],'a') as f:f.write(json.dumps(sys.argv[1:])+'\\n')
if sys.argv[1:3]==['image','inspect']:
 print(json.dumps([sys.argv[3].rsplit(':',1)[0]+'@sha256:'+'a'*64]))
''')
            docker.chmod(0o700)
            calls = directory / 'calls'
            output = directory / 'images.json'
            env = dict(os.environ, PATH=str(directory) + os.pathsep + os.environ['PATH'], DOCKER_CALLS=str(calls))
            command = ['bash', str(ROOT / 'scripts/build_release_consumer_images.sh'), 'registry.invalid/test', 'b' * 40, str(output)]
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            receipt = json.loads(output.read_text())
            self.assertEqual(set(receipt['images']), set(PROFILES))
            self.assertTrue(all(re.fullmatch(r'registry.invalid/test/ocideck-consumer-[a-z0-9]+@sha256:a{64}', image) for image in receipt['images'].values()))
            recorded = [json.loads(line) for line in calls.read_text().splitlines()]
            self.assertEqual(sum(call[0] == 'push' for call in recorded), 6)
            for call in recorded:
                if call[0] == 'build':
                    self.assertIn('--cpu-quota', call)
                    self.assertEqual(call[call.index('--cpu-quota') + 1], '200000')
                    self.assertEqual(call[call.index('--memory') + 1], '4g')
            before = calls.read_bytes()
            self.assertNotEqual(subprocess.run(command, env=env, capture_output=True).returncode, 0)
            self.assertEqual(calls.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
