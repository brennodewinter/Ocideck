"""Executable failure propagation and immutable mirror matching for #3214."""
import importlib.util
import json
import os
import signal
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def module(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


journey = module('app_journey', 'tool/app_journey.py')
mirror = module('windows_journey', 'scripts/wait_windows_app_journey.py')


def semantics_fixture(directory):
    root = Path(directory)
    sdk = root / 'SDK with spaces'
    (sdk / 'bin/cache').mkdir(parents=True)
    subprocess.run(['git', 'init', '-q', str(sdk)], check=True)
    (sdk / 'seed.txt').write_text('original\n')
    subprocess.run(['git', '-C', str(sdk), 'add', 'seed.txt'], check=True)
    subprocess.run(['git', '-C', str(sdk), '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.test', 'commit', '-qm', 'fixture'], check=True)
    fake = sdk / 'bin/flutter'
    fake.write_text('#!' + sys.executable + '\n' + """import json,sys
from pathlib import Path
sdk=Path(__file__).resolve().parents[1]
if sys.argv[1:]==['--version','--machine']:
 print(json.dumps(dict(frameworkRevision='ab2912035e160d9cad6306df307576da6128ebdb',flutterRoot=str(sdk))))
else:
 assert (sdk/'seed.txt').read_text()=='patched\\n'
 (sdk/'built').write_text('done')
""")
    fake.chmod(0o755)
    project = root / 'project'
    (project / 'scripts').mkdir(parents=True)
    script = project / 'scripts/with_macos_flutter_semantics_fix.sh'
    shutil.copyfile(ROOT / 'scripts/with_macos_flutter_semantics_fix.sh', script)
    patches = project / 'third_party/flutter_patches'
    patches.mkdir(parents=True)
    (patches / '3.50.0-semantics-b304cf1.patch').write_text(
        '--- a/seed.txt\n+++ b/seed.txt\n@@ -1 +1 @@\n-original\n+patched\n')
    lock = sdk / 'bin/cache/ocideck-macos-semantics.lock'
    lock.mkdir()
    environment = dict(os.environ, PATH=str(sdk / 'bin') + os.pathsep + os.environ['PATH'],
                       OCIDECK_MACOS_SEMANTICS_LOCK_TIMEOUT='5')
    return sdk, script, lock, environment


class AppJourneyTest(unittest.TestCase):
    @unittest.skipIf(os.name == 'nt', 'The native startup fix is for POSIX hosts')
    def test_lifecycle_controller_runs_without_native_hook_discovery(self):
        command = journey.scenarios('macos', False)[0][1]
        for device in ['macos', 'linux']:
            self.assertEqual(journey.scenarios(device, False)[0][1][:2],
                             ['dart', '--disable-dart-dev'])
        self.assertEqual(journey.scenarios('windows', False)[0][1][:2], ['dart', 'run'])
        dart = shutil.which('dart')
        if dart is None:
            self.skipTest('Requires the pinned Dart SDK')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ['tool/run_desktop_smoke.dart',
                         'test_driver/desktop_smoke_process.dart',
                         'test_driver/desktop_roundtrip_plan.dart']:
                target = root / name
                target.parent.mkdir(exist_ok=True)
                shutil.copyfile(ROOT / name, target)
            result = subprocess.run([
                dart, command[1], '--packages=' + str(ROOT / '.dart_tool/package_config.json'),
                str(root / command[2]), 'invalid-device'], cwd=root,
                capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Run on the matching macos, linux or windows host', result.stderr)
            self.assertFalse((root / '.dart_tool').exists())
            self.assertNotIn('Building native assets', result.stdout + result.stderr)

    @unittest.skipIf(os.name == 'nt', 'Exercises native POSIX process groups')
    def test_timeout_kills_a_descendant_ignoring_term_and_keeps_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pidfile = root / 'descendant.pid'
            child = root / 'descendant.py'
            child.write_text('import os,signal,time\nfrom pathlib import Path\n'
                             'os.setpgrp()\n'
                             'signal.signal(signal.SIGTERM, signal.SIG_IGN)\n'
                             f'Path({str(pidfile)!r}).write_text(str(os.getpid()))\n'
                             'print("descendant started",flush=True)\ntime.sleep(30)\n')
            parent = [sys.executable, '-u', '-c',
                      'import subprocess,sys,time; '
                      f'subprocess.Popen([sys.executable,{str(child)!r}]); '
                      'print("parent started",flush=True); time.sleep(30)']
            try:
                with self.assertRaises(subprocess.TimeoutExpired):
                    journey.run_command(parent, root / 'run.log', timeout=1)
                self.assertTrue(pidfile.exists())
                pid = int(pidfile.read_text())
                state = subprocess.run(['ps', '-p', str(pid), '-o', 'stat='],
                                       capture_output=True, text=True).stdout.strip()
                self.assertTrue(not state or state.startswith('Z'),
                                'Timed-out native descendant is still running')
                self.assertIn('parent started', (root / 'run.log').read_text())
                self.assertIn('descendant started', (root / 'run.log').read_text())
            finally:
                if pidfile.exists():
                    pid = int(pidfile.read_text())
                    args = subprocess.run(['ps', '-p', str(pid), '-o', 'args='],
                                          capture_output=True, text=True).stdout
                    if str(child) in args:
                        try:
                            os.kill(pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass

    @unittest.skipIf(os.name == 'nt', 'Exercises native POSIX cancellation')
    def test_sigterm_retains_failed_journey_and_reaps_native_descendants(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            subprocess.run(['git', '-C', str(root), '-c', 'user.name=Fixture',
                            '-c', 'user.email=fixture@example.test', 'commit',
                            '--allow-empty', '-qm', 'fixture'], check=True)
            parent_pid = root / 'parent.pid'
            child_pid = root / 'child.pid'
            child = root / 'descendant.py'
            child.write_text('import os,signal,time\nfrom pathlib import Path\n'
                             'os.setpgrp()\n'
                             'signal.signal(signal.SIGTERM, signal.SIG_IGN)\n'
                             f'Path({str(child_pid)!r}).write_text(str(os.getpid()))\n'
                             'print("descendant started",flush=True)\ntime.sleep(30)\n')
            command = [sys.executable, '-u', '-c',
                       'import os,subprocess,sys,time; from pathlib import Path; '
                       f'Path({str(parent_pid)!r}).write_text(str(os.getpid())); '
                       f'subprocess.Popen([sys.executable,{str(child)!r}]); '
                       'print("parent started",flush=True); time.sleep(30)']
            evidence = root / 'evidence'
            bootstrap = ('import importlib.util,sys; from pathlib import Path; '
                         f's=importlib.util.spec_from_file_location("journey",{journey.__file__!r}); '
                         'm=importlib.util.module_from_spec(s); s.loader.exec_module(m); '
                         f'm.ROOT=Path({str(root)!r}); '
                         f'm.scenarios=lambda device,full:[("cancel",{command!r},None)]; '
                         f'sys.argv=["journey","--evidence",{str(evidence)!r}]; m.main()')
            worker = subprocess.Popen([sys.executable, '-u', '-c', bootstrap],
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 10
                while not child_pid.exists() and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertTrue(child_pid.exists(), 'Controlled native child did not start')
                worker.terminate()
                worker.communicate(timeout=10)
                self.assertEqual(worker.returncode, 128 + signal.SIGTERM)
                report = json.loads((evidence / 'journey.json').read_text())
                self.assertFalse(report['success'])
                self.assertFalse(report['scenarios'][0]['success'])
                self.assertIn('descendant started', (evidence / 'cancel/run.log').read_text())
                for file in [parent_pid, child_pid]:
                    state = subprocess.run(['ps', '-p', file.read_text(), '-o', 'stat='],
                                           capture_output=True, text=True).stdout.strip()
                    self.assertTrue(not state or state.startswith('Z'))
            finally:
                if worker.poll() is None:
                    worker.kill()
                    worker.communicate(timeout=5)
                for file in [parent_pid, child_pid]:
                    if file.exists():
                        pid = int(file.read_text())
                        args = subprocess.run(['ps', '-p', str(pid), '-o', 'args='],
                                              capture_output=True, text=True).stdout
                        if str(child) in args:
                            try:
                                os.kill(pid, signal.SIGKILL)
                            except ProcessLookupError:
                                pass

    def test_short_and_full_sets_are_fixed_across_platforms(self):
        for device in ['linux', 'macos', 'windows']:
            self.assertEqual([s[0] for s in journey.scenarios(device, False)], ['lifecycle'])
            expected = ['lifecycle', 'navigation'] + (['video'] if device == 'windows' else [])
            self.assertEqual([s[0] for s in journey.scenarios(device, True)], expected)
            self.assertIn('--roundtrip', journey.scenarios(device, True)[0][1])

    def test_a_real_failed_child_makes_the_journey_fail_and_retains_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory)
            command = [sys.executable, '-c', 'print("scenario failed"); raise SystemExit(7)']
            with patch.object(journey, 'scenarios', return_value=[('broken', command, None)]):
                with self.assertRaises(subprocess.CalledProcessError) as caught:
                    journey.journey('macos', False, evidence)
            self.assertEqual(caught.exception.returncode, 7)
            self.assertIn('scenario failed', (evidence / 'broken/run.log').read_text())
            report = json.loads((evidence / 'journey.json').read_text())
            self.assertFalse(report['success'])
            self.assertFalse(report['scenarios'][0]['success'])
            self.assertEqual(len(report['source_commit']), 40)

    def test_automatic_windows_video_explicitly_uses_local_media(self):
        commands = []
        def finished(command, log, environment=None, timeout=3600):
            commands.append(command)
            Path(environment['VIDEO_RESULT_FILE']).write_text('{"owned_media": true}')
        with tempfile.TemporaryDirectory() as directory, patch.object(journey, 'run_command', side_effect=finished):
            journey.drive('windows', 'windows_video_navigation_test', 'windows_video_driver', Path(directory))
        self.assertIn('--dart-define=OCIDECK_LIVE_VIDEO_PROBE=false', commands[0])

    def test_missing_new_driver_evidence_cannot_reuse_old_success(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory)
            (evidence / 'navigation').mkdir()
            result = evidence / 'navigation/result.json'
            result.write_text('{"old": "success"}')
            with patch.object(journey, 'scenarios', return_value=[('navigation', 'target', 'driver')]), \
                    patch.object(journey, 'run_command'):
                with self.assertRaises(FileNotFoundError):
                    journey.journey('linux', True, evidence)
            self.assertFalse(json.loads((evidence / 'journey.json').read_text())['success'])
            self.assertFalse(result.exists())

    def test_mirror_never_accepts_another_commit_branch_or_trigger(self):
        sha = 'a' * 40
        row = dict(id=123, head_sha=sha, head_branch='codex/work', event='push',
                   path='.github/workflows/windows-app-journey.yml')
        self.assertEqual(mirror.matching_run([row], sha, 'codex/work', 'push'), row)
        for field, value in [('head_sha', 'b' * 40), ('head_branch', 'main'),
                             ('event', 'workflow_dispatch'), ('path', '.github/workflows/ci.yml')]:
            wrong = dict(row, **{field: value})
            self.assertIsNone(mirror.matching_run([wrong], sha, 'codex/work', 'push'))

    def test_red_windows_run_is_red_on_pawprint(self):
        sha = 'a' * 40
        row = dict(id=123, head_sha=sha, head_branch='codex/work', event='push',
                   path='.github/workflows/windows-app-journey.yml',
                   status='completed', conclusion='failure', html_url='https://example.test/run/123')
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(mirror, 'get', return_value={'workflow_runs': [row]}):
            with self.assertRaisesRegex(RuntimeError, 'Windows app journey failed'):
                mirror.wait(sha, 'codex/work', False, Path(directory), timeout=1)
            self.assertEqual(json.loads((Path(directory) / 'windows-run.json').read_text()), row)

    def test_short_manual_windows_run_cannot_satisfy_full_nightly_set(self):
        sha = 'a' * 40
        row = dict(id=123, head_sha=sha, head_branch='main', event='schedule',
                   path='.github/workflows/windows-app-journey.yml', status='completed',
                   conclusion='success', html_url='https://example.test/run/123')
        responses = [{'workflow_runs': [row]}, {'jobs': [dict(name='app-reis Windows (short)', conclusion='success')]}]
        with tempfile.TemporaryDirectory() as directory, patch.object(mirror, 'get', side_effect=responses):
            with self.assertRaisesRegex(RuntimeError, 'Missing or unsuccessful'):
                mirror.wait(sha, 'main', True, Path(directory), timeout=1)


    @unittest.skipIf(os.name == 'nt', 'The macOS SDK copy uses Bash')
    def test_macos_journey_isolates_an_already_patched_and_locked_shared_sdk(self):
        with tempfile.TemporaryDirectory() as directory:
            sdk, wrapper, lock, environment = semantics_fixture(directory)
            prepare = wrapper.parent / 'prepare_macos_app_journey_sdk.sh'
            shutil.copyfile(ROOT / 'scripts/prepare_macos_app_journey_sdk.sh', prepare)
            patch_file = wrapper.parent.parent / 'third_party/flutter_patches/3.50.0-semantics-b304cf1.patch'
            subprocess.run(['git', '-C', str(sdk), 'apply', str(patch_file)], check=True)
            runner_temp = Path(directory) / 'runner-temp'
            runner_temp.mkdir()
            environment.update(RUNNER_TEMP=str(runner_temp),
                               GITHUB_ENV=str(runner_temp / 'env'), GITHUB_PATH=str(runner_temp / 'path'))
            prepared = subprocess.run(['bash', str(prepare)], env=environment,
                                      capture_output=True, text=True, timeout=15)
            self.assertEqual(prepared.returncode, 0, prepared.stdout + prepared.stderr)
            isolated = Path((runner_temp / 'env').read_text().strip().split('=', 1)[1])
            self.assertNotEqual(sdk, isolated)
            self.assertEqual((isolated / 'seed.txt').read_text(), 'original\n')
            self.assertFalse((isolated / 'bin/cache/ocideck-macos-semantics.lock').exists())
            environment['PATH'] = str(isolated / 'bin') + os.pathsep + environment['PATH']
            built = subprocess.run(['bash', str(wrapper), 'build', 'macos'], env=environment,
                                   capture_output=True, text=True, timeout=15)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            self.assertTrue((isolated / 'built').exists())
            self.assertEqual((isolated / 'seed.txt').read_text(), 'original\n')
            self.assertEqual((sdk / 'seed.txt').read_text(), 'patched\n')
            self.assertTrue(lock.is_dir())


if __name__ == '__main__':
    unittest.main()
