"""Executable failure propagation and immutable mirror matching for #3214."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
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


class AppJourneyTest(unittest.TestCase):
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


if __name__ == '__main__':
    unittest.main()
