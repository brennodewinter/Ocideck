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

    def test_both_linux_routes_limit_actual_direct_ninja_invocation(self):
        for nested in (False, True):
            with self.subTest(debian12=nested), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                (root / 'bin').mkdir()
                (root / 'pubspec.yaml').write_text('version: 1.2.3+1\n')
                (root / 'scripts').mkdir()
                import shutil
                shutil.copy(ROOT / 'scripts/run_release_linux_build.sh', root / 'scripts')
                binaries = {
                    'git': '#!/bin/sh\necho ' + SHA + '\n',
                    'dart': '#!/bin/sh\nexit 0\n',
                    'ninja': "#!/usr/bin/env python3\nimport json,os,sys\nopen(os.environ['CALLS'],'a').write(json.dumps(sys.argv[1:])+'\\n')\n",
                    'make': '#!/bin/sh\n[ "$1" = check-toolchain ] && exit 0\nninja -C build install -j99\nexit 17\n',
                    'flutter': '#!/bin/sh\n[ "$1" = pub ] && exit 0\nninja -C build install -j99\nexit 17\n',
                }
                for name, source in binaries.items():
                    executable = root / 'bin' / name
                    executable.write_text(source)
                    executable.chmod(0o700)
                calls = root / 'calls'
                environment = dict(os.environ, PATH=str(root / 'bin') + ':' + os.environ['PATH'],
                                   HOME=str(root), CALLS=str(calls))
                if nested:
                    command = ['bash', str(ROOT / 'scripts/debian12_builder/container-build.sh')]
                else:
                    command = ['bash', str(ROOT / 'scripts/build_release_channel.sh'), 'v1.2.3',
                               SHA, 'codex/release-candidate-v1.2.3-' + SHA, 'linux-tar']
                result = subprocess.run(command, cwd=root, env=environment, capture_output=True)
                self.assertEqual(result.returncode, 17, result.stderr)
                self.assertEqual(json.loads(calls.read_text()),
                                 ['-j2', '-C', 'build', 'install'])
                # De wrapper verandert alleen zijn subprocess, niet het omringende PATH.
                calls.unlink()
                subprocess.run(['ninja', '--version'], env=environment, check=True)
                self.assertEqual(json.loads(calls.read_text()), ['--version'])

    def test_ninja_shim_path_survives_wrapper_exit_for_cmake_cache_reuse(self):
        # #2798: CMake bewaart het absolute ninjapad in CMAKE_MAKE_PROGRAM;
        # een shim die bij exit verdwijnt laat de cache onbruikbaar achter.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'bin').mkdir()
            ninja = root / 'bin' / 'ninja'
            ninja.write_text(
                "#!/usr/bin/env python3\nimport json,os,sys\n"
                "open(os.environ['CALLS'],'a').write(json.dumps(sys.argv[1:])+'\\n')\n")
            ninja.chmod(0o700)
            recorder = root / 'bin' / 'recorder'
            recorder.write_text(
                '#!/bin/sh\ncommand -v ninja > "$OUT"\nninja -C build install -j99\n')
            recorder.chmod(0o700)
            out = root / 'out'
            calls = root / 'calls'
            env = dict(os.environ, PATH=str(root / 'bin') + ':' + os.environ['PATH'],
                       HOME=str(root), CALLS=str(calls), OUT=str(out))
            script = str(ROOT / 'scripts/run_release_linux_build.sh')
            first = subprocess.run(['bash', script, 'recorder'], env=env, capture_output=True)
            self.assertEqual(first.returncode, 0, first.stderr)
            shim = out.read_text().strip()
            # Een tweede, los wrapperproces (of cmake --build op de cache)
            # moet dat pad nog kunnen uitvoeren.
            second = subprocess.run(
                [shim, '-C', 'build', 'install', '-j99'],
                env=dict(os.environ, OCIDECK_RELEASE_NINJA=str(ninja),
                         CALLS=str(calls)), capture_output=True)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(
                [json.loads(row) for row in calls.read_text().splitlines()],
                [['-j2', '-C', 'build', 'install']] * 2)

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
