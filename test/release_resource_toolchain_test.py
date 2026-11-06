"""Release admission contracts without a build, daemon or SDK installation."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
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
                    'flutter': '#!/bin/sh\n[ "$1" = pub ] && exit 0\n[ "$1" = config ] && exit 0\nninja -C build install -j99\nexit 17\n',
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

    def test_docker_guards_precede_source_and_candidate_execution(self):
        text = (ROOT / '.forgejo/workflows/release-channel.yml').read_text()
        self.assertIn("|| 'linux-web-server'", text)
        self.assertIn('cancel-in-progress: false', text)
        jobs = dict(re.findall(r'^  ([a-z][a-z0-9-]*):\n(.*?)(?=^  [a-z][a-z0-9-]*:\n|\Z)',
                               text, flags=re.M | re.S))
        containers = {name: job for name, job in jobs.items() if '    container:\n' in job}
        self.assertEqual(set(containers), {'build', 'evidence', 'consumer-deb',
                         'consumer-debian12', 'consumer-rpm', 'consumer-appimage',
                         'consumer-flatpak', 'consumer-tar'})
        for name, job in containers.items():
            with self.subTest(job=name):
                image = re.search(r'^      image: (.+)$', job, re.M).group(1)
                steps = job.split('    steps:\n', 1)[1]
                guard = steps.index('run: node ')
                self.assertIn('enforce_release_cpu.cjs', steps[:guard + 80])
                self.assertIn('EXPECTED_IMAGE: ' + image, steps[:guard])
                self.assertIn('SOURCE_SHA: ${{ inputs.source_sha }}', steps[:guard])
                self.assertIn('FORGEJO_TOKEN: ${{ github.token }}', steps[:guard])
                checkout = steps[:guard]
                self.assertIn('persist-credentials: false', checkout)
                self.assertIn('ref: ${{ github.sha }}', checkout)
                if name == 'build':
                    self.assertLess(guard, steps.index('Vaste bron controleren'))
                    self.assertLess(guard, steps.index('ref: ${{ inputs.source_sha }}'))
                else:
                    self.assertLess(guard, steps.index('actions/download-artifact@'))
        self.assertIn("inputs.channel == 'windows' && '4' || '8'", containers['build'])

    def test_macos_workflow_continuation_argv_under_nounset(self):
        # macOS ships Bash 3.2: an empty array under set -u must add no argument.
        workflow = (ROOT / '.forgejo/workflows/release-channel.yml').read_text()
        lines = workflow.split('\n  build-macos:\n', 1)[1].splitlines()
        start = next(i for i, line in enumerate(lines) if line.strip() == 'continuation=()')
        end = next(i for i in range(start, len(lines))
                   if lines[i].strip().startswith('python3 tool/release_macos_candidate.py '))
        script = 'set -euo pipefail\n' + '\n'.join(line[10:] for line in lines[start:end + 1])
        for attempt, previous, extra in (
                ('', '', []),
                ('attempt-1', '456', ['--previous-run-id', '456', '--attempt-id', 'attempt-1']),
                ('bad attempt', '456', None), ('attempt-1', '', None)):
            with self.subTest(attempt=attempt, previous=previous), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary).resolve()
                (root / 'bin').mkdir()
                stub = root / 'bin/python3'
                stub.write_text('#!' + sys.executable + '\nimport json,os,sys\n'
                                'open(os.environ["CALLS"],"w").write(json.dumps(sys.argv[1:]))\n')
                stub.chmod(0o700)
                calls = root / 'calls.json'
                workspace = root / 'workspace with spaces'
                env = dict(os.environ, PATH=str(root / 'bin') + ':' + os.environ['PATH'],
                           ATTEMPT_ID=attempt, PREVIOUS_RUN_ID=previous, RELEASE_TAG='v0.7.7',
                           SOURCE_SHA=SHA, GITHUB_SHA='b' * 40, GITHUB_WORKSPACE=str(workspace),
                           OPERATION_ID='fixture', GITHUB_RUN_ID='123', CALLS=str(calls))
                result = subprocess.run(['/bin/bash', '-c', script], cwd=root, env=env,
                                        capture_output=True, text=True)
                if extra is None:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(calls.exists(), result.stderr)
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(json.loads(calls.read_text()), [
                        'tool/release_macos_candidate.py', '--tag', 'v0.7.7', '--sha', SHA,
                        '--controller-sha', 'b' * 40, '--controller', str(root),
                        '--dist', str(workspace / 'source/dist'), '--operation-id', 'fixture',
                        '--forge-run-id', '123', '--result', 'build/macos-operation.json'] + extra)

    def test_macos_whisper_cli_is_signed_and_app_resealed_after_install(self):
        # #2800: de helper landt in een al verzegelde .app — zonder eigen
        # handtekening en zonder hersluiten van de bundel is die seal kapot.
        text = (ROOT / 'scripts/bundle_whisper_cli.sh').read_text()
        macos = text.split("PLATFORM in\n  macos)")[1].split('windows)')[0] \
            if 'PLATFORM in\n  macos)' in text else text
        install = macos.index('install -m 0755')
        helper_sign = macos.index('Helpers/whisper-cli"\n    codesign') \
            if 'Helpers/whisper-cli"\n    codesign' in macos \
            else macos.index('codesign --force --options runtime -s -')
        app_seal = macos.index('--preserve-metadata=entitlements')
        self.assertLess(install, helper_sign)
        self.assertLess(helper_sign, app_seal)

    def test_debian_daemon_build_and_execution_are_bounded(self):
        text = (ROOT / 'scripts/build_debian12_release.sh').read_text()
        self.assertIn('build --platform linux/amd64 --cpu-quota 200000 --cpu-period 100000 --memory 8g', text)
        self.assertIn('create --platform linux/amd64 --cpus 2 --memory 8g', text)
        self.assertIn('--env CMAKE_BUILD_PARALLEL_LEVEL=2', text)
        entry = (ROOT / 'scripts/debian12_builder/container-build.sh').read_text()
        # #2799: analytics uit op het runtime-HOME vóór de strikte versieprobe,
        # en de controle standalone — `dart run` zou pub-resolutie/hooks
        # starten vóór de poort die juist vroeg moet zijn.
        self.assertLess(entry.index('flutter config --no-analytics'), entry.index('dart tool/check_toolchain.dart'))
        self.assertLess(entry.index('dart tool/check_toolchain.dart'), entry.index('flutter pub get'))
        self.assertNotIn('dart run tool/check_toolchain.dart', entry)
