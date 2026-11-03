"""Native Windows evidence orchestration tests, without dispatching workflows."""
import base64
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tool'))
import release_windows_candidate as windows

SHA = 'a' * 40
TAG = 'v0.7.7'
REF = f'codex/release-candidate-{TAG}-{SHA}'


class FakeGitHub:
    def __init__(self, root):
        self.calls = []
        self.files = {'.github/workflows/' + name: (root / '.github/workflows' / name).read_bytes() for name in windows.WORKFLOWS}
        self.files['pubspec.yaml'] = b'version: 0.7.7+49\n'
        self.files['sbom/ocideck.cdx.json'] = json.dumps({'metadata': {'component': {'version': '0.7.7+49'}}}).encode()
        self.files['sbom/ocideck.spdx.json'] = json.dumps({'packages': [{'name': 'ocideck', 'versionInfo': '0.7.7+49'}]}).encode()
        self.runs = {name: [] for name in windows.WORKFLOWS}
        self.jobs = {}
        self.ref_sha = SHA
        self.artifacts = [{'id': 99, 'name': 'ocideck-windows-cohort', 'expired': False}]
        self.payloads = {'ocideck-windows-x64-0.7.7.zip': b'Windows native ZIP bytes',
                         'ocideck-windows-x64-setup-0.7.7.exe': b'Windows installer bytes'}
        self.payloads['ocideck-windows-cohort-0.7.7.json'] = json.dumps({'tag_commit': SHA, 'run_id': 20,
            'sha256': {'zip': hashlib.sha256(self.payloads['ocideck-windows-x64-0.7.7.zip']).hexdigest(),
                       'installer': hashlib.sha256(self.payloads['ocideck-windows-x64-setup-0.7.7.exe']).hexdigest()}}).encode()
        self.extra = []

    def new_run(self, workflow, operation_id=None):
        run_id = 20 if workflow == 'release.yml' else 10
        run = dict(id=run_id, head_sha=SHA, head_branch=REF, event='workflow_dispatch',
                   path='.github/workflows/' + workflow, display_title='Windows candidate ' + TAG,
                   status='completed', conclusion='success')
        if operation_id:
            run['display_title'] += ' [operation:' + operation_id + ']'
        self.runs[workflow] = [run]
        name = 'Build Windows' if workflow == 'release.yml' else 'Test (windows-2022)'
        self.jobs[run_id] = [{'name': name, 'status': 'completed', 'conclusion': 'success'}]
        if workflow == 'release.yml':
            self.jobs[run_id].append({'name': 'Tag controleren zonder nieuwe build', 'status': 'completed', 'conclusion': 'skipped'})

    def data(self, path, payload=None):
        self.calls.append((path, payload))
        if path.startswith('/git/ref/heads/'):
            return {'ref': 'refs/heads/' + REF, 'object': {'sha': self.ref_sha}}
        if path.startswith('/contents/'):
            name = path[len('/contents/'):].split('?')[0]
            return {'encoding': 'base64', 'content': base64.b64encode(self.files[name]).decode()}
        for workflow in windows.WORKFLOWS:
            prefix = '/actions/workflows/' + workflow
            if path.startswith(prefix + '/dispatches'):
                self.new_run(workflow, payload['inputs'].get('operation_id'))
                return None
            if path.startswith(prefix + '/runs?'):
                return {'workflow_runs': self.runs[workflow]}
        if path.endswith('/cancel'):
            return None
        for run_id, jobs in self.jobs.items():
            if path.startswith(f'/actions/runs/{run_id}/jobs?'):
                return {'jobs': jobs}
        if '/artifacts?' in path:
            return {'artifacts': self.artifacts}
        raise AssertionError('unexpected API call: ' + path)

    def download(self, artifact_id, output):
        assert artifact_id == 99
        with zipfile.ZipFile(output, 'w') as archive:
            for name, payload in self.payloads.items():
                archive.writestr(name, payload)
            for info, payload in self.extra:
                archive.writestr(info, payload)


class WindowsCandidateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.dist = Path(self.temp.name) / 'dist'
        self.api = FakeGitHub(ROOT)

    def fetch(self):
        return windows.fetch(self.api, ROOT, self.dist, TAG, SHA, REF, 'op-test', Path(self.temp.name) / 'operation.json')

    def test_dispatches_only_selected_windows_workflows_and_seals_exact_bytes(self):
        result = self.fetch()
        self.assertEqual({'release.yml': 20, 'windows-test-check.yml': 10}, result)
        posts = [(path, body) for path, body in self.api.calls if body is not None]
        self.assertEqual(2, len(posts))
        self.assertEqual({'ref': REF, 'inputs': {'mode': 'candidate', 'version': TAG, 'commit_sha': SHA, 'operation_id': 'op-test'}}, posts[1][1])
        self.assertFalse(any('linux' in path or 'macos' in path for path, _ in self.api.calls))
        self.assertEqual(5, len(list(self.dist.iterdir())))
        self.assertEqual(self.api.files['sbom/ocideck.cdx.json'], (self.dist / 'ocideck-0.7.7.cdx.json').read_bytes())
        self.assertEqual(result, windows.verify(self.api, ROOT, self.dist, TAG, SHA, REF))

    def test_pending_newer_suite_is_not_replaced_by_old_success(self):
        self.fetch()
        newer = dict(self.api.runs['windows-test-check.yml'][0], id=30, status='in_progress', conclusion=None)
        self.api.runs['windows-test-check.yml'].append(newer)
        with self.assertRaisesRegex(ValueError, 'terminal success'):
            windows.verify(self.api, ROOT, self.dist, TAG, SHA, REF)

    def test_changed_workflow_or_mirror_ref_blocks_before_dispatch(self):
        self.api.files['.github/workflows/release.yml'] = b'jobs: skipped'
        with self.assertRaisesRegex(ValueError, 'changed trusted'):
            self.fetch()
        self.assertFalse(any(body is not None for _, body in self.api.calls))
        self.assertFalse(self.dist.exists())
        self.api = FakeGitHub(ROOT)
        self.api.ref_sha = 'b' * 40
        with self.assertRaisesRegex(ValueError, 'frozen ref differs'):
            self.fetch()

    def test_failed_existing_run_is_not_automatically_redispatched(self):
        self.api.new_run('windows-test-check.yml')
        self.api.runs['windows-test-check.yml'][0]['conclusion'] = 'failure'
        with self.assertRaisesRegex(ValueError, 'existing Windows candidate failed'):
            self.fetch()
        self.assertFalse(any(body is not None for _, body in self.api.calls))

    def test_forged_run_identity_is_refused(self):
        for field, value in [('head_sha', 'b' * 40), ('head_branch', 'main'), ('event', 'push'),
                             ('path', '.github/workflows/other.yml'), ('display_title', 'Windows release v0.7.7')]:
            with self.subTest(field=field):
                self.api = FakeGitHub(ROOT)
                (Path(self.temp.name) / 'operation.json').unlink(missing_ok=True)
                self.api.new_run('release.yml')
                self.api.runs['release.yml'][0][field] = value
                with self.assertRaisesRegex(ValueError, 'identity differs|not a candidate'):
                    self.fetch()

    def test_missing_or_skipped_native_job_is_not_evidence(self):
        self.fetch()
        self.api.jobs[20][0]['conclusion'] = 'skipped'
        with self.assertRaisesRegex(ValueError, 'native/build/suite'):
            windows.verify(self.api, ROOT, self.dist, TAG, SHA, REF)

    def test_cohort_bytes_and_source_sbom_cannot_drift(self):
        self.api.payloads['ocideck-windows-x64-setup-0.7.7.exe'] = b'tampered'
        with self.assertRaisesRegex(ValueError, 'cohort bytes'):
            self.fetch()
        self.assertFalse(self.dist.exists())
        self.api = FakeGitHub(ROOT)
        (Path(self.temp.name) / 'operation.json').unlink(missing_ok=True)
        self.fetch()
        (self.dist / 'ocideck-0.7.7.cdx.json').write_bytes(b'tampered')
        with self.assertRaisesRegex(ValueError, 'SBOM bytes'):
            windows.verify(self.api, ROOT, self.dist, TAG, SHA, REF)

    def test_unsafe_extra_zip_member_is_refused(self):
        self.api.extra = [('../escape.exe', b'evil')]
        with self.assertRaisesRegex(ValueError, 'unsafe Windows artifact'):
            self.fetch()
        self.assertFalse(self.dist.exists())

    def test_expired_artifact_and_wrong_sbom_version_are_refused(self):
        self.api.artifacts[0]['expired'] = True
        with self.assertRaisesRegex(ValueError, 'missing or ambiguous'):
            self.fetch()
        self.api = FakeGitHub(ROOT)
        self.api.files['sbom/ocideck.cdx.json'] = b'{"metadata":{"component":{"version":"old"}}}'
        with self.assertRaisesRegex(ValueError, 'SBOM version'):
            self.fetch()

    def test_interruption_cancels_only_own_nonce_not_foreign_pending_suite(self):
        self.api.new_run('windows-test-check.yml')
        self.api.runs['windows-test-check.yml'][0]['status'] = 'in_progress'
        self.api.runs['windows-test-check.yml'][0]['conclusion'] = None
        original = self.api.data
        def pending(path, payload=None):
            result = original(path, payload)
            if payload is not None and path.endswith('/dispatches'):
                self.api.runs['release.yml'][0]['status'] = 'in_progress'
                self.api.runs['release.yml'][0]['conclusion'] = None
            return result
        with patch.object(self.api, 'data', side_effect=pending), patch.object(windows.time, 'sleep', side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                self.fetch()
        cancellations = [path for path, _ in self.api.calls if path.endswith('/cancel')]
        self.assertEqual(['/actions/runs/20/cancel'], cancellations)

    def test_cancel_wait_confirms_terminal_owned_runs_only(self):
        self.api.new_run('release.yml', 'op-test')
        self.api.new_run('windows-test-check.yml', 'someone-else')
        for runs in self.api.runs.values():
            runs[0]['status'], runs[0]['conclusion'] = 'in_progress', None
        original = self.api.data
        def cancel(path, payload=None):
            result = original(path, payload)
            if path == '/actions/runs/20/cancel':
                self.api.runs['release.yml'][0]['status'] = 'completed'
                self.api.runs['release.yml'][0]['conclusion'] = 'cancelled'
            return result
        state = Path(self.temp.name) / 'closed.json'
        state.write_text(json.dumps(dict(schema=1, operation_id='op-test', tag=TAG, sha=SHA, ref=REF, dispatch_intents=['release.yml'], closed=True, forge_run_id=123, controller_sha=SHA)))
        with patch.object(self.api, 'data', side_effect=cancel):
            result = windows.cancel_owned(self.api, SHA, REF, 'op-test', wait=True, state=state, forge_run_id=123, controller_sha=SHA)
        self.assertTrue(result['terminal'])
        self.assertEqual([20], [run['id'] for run in result['runs']])
        self.assertFalse(any(path == '/actions/runs/10/cancel' for path, _ in self.api.calls))
        self.assertEqual('in_progress', self.api.runs['windows-test-check.yml'][0]['status'])

    def test_dispatch_intent_survives_lost_response_and_prevents_second_post(self):
        original = self.api.data
        posts = []
        def lost(path, payload=None):
            if payload is not None and path.endswith('/dispatches'):
                saved = json.loads((Path(self.temp.name) / 'operation.json').read_text())
                self.assertIn('windows-test-check.yml', saved['dispatch_intents'])
                posts.append(path)
                raise ValueError('lost dispatch response')
            return original(path, payload)
        with patch.object(self.api, 'data', side_effect=lost):
            with self.assertRaisesRegex(ValueError, 'lost dispatch response'):
                self.fetch()
            with self.assertRaisesRegex(ValueError, 'closed'):
                self.fetch()
        self.assertEqual(1, len(posts))

    def test_empty_or_incomplete_registration_never_proves_stop(self):
        self.assertTrue(windows.owned_status(self.api, SHA, REF, 'op-test')['unknown'])
        self.api.new_run('release.yml', 'op-test')
        self.assertFalse(windows.cancel_owned(self.api, SHA, REF, 'op-test')['terminal'])
        state = Path(self.temp.name) / 'closed.json'
        saved = dict(schema=1, operation_id='op-test', tag=TAG, sha=SHA, ref=REF, dispatch_intents=[], closed=False, forge_run_id=123, controller_sha=SHA)
        state.write_text(json.dumps(saved))
        self.assertTrue(windows.owned_status(self.api, SHA, REF, 'op-test', state, 123, SHA)['unknown'])
        saved['closed'] = True
        state.write_text(json.dumps(saved))
        self.assertTrue(windows.owned_status(self.api, SHA, REF, 'op-test', state, 123, SHA)['terminal'])
        saved['sha'] = 'b' * 40
        state.write_text(json.dumps(saved))
        with self.assertRaisesRegex(ValueError, 'identity differs'):
            windows.owned_status(self.api, SHA, REF, 'op-test', state, 123, SHA)

    def test_transport_keeps_credentials_and_signed_urls_out_of_arguments(self):
        secret = 'token-private'
        signed_url = 'https://production.blob.core.windows.net/archive?credential=private'
        seen = []
        def curl(command, **kwargs):
            seen.append((command, kwargs['input']))
            self.assertNotIn(secret, ' '.join(command))
            self.assertNotIn(signed_url, ' '.join(command))
            output = Path(command[command.index('--output') + 1])
            output.write_bytes(b'archive')
            if '--dump-header' in command:
                Path(command[command.index('--dump-header') + 1]).write_text('HTTP/2 302\nLocation: ' + signed_url + '\n')
                return SimpleNamespace(returncode=0, stdout=b'302')
            return SimpleNamespace(returncode=0, stdout=b'200')
        with patch.dict(os.environ, {'GH_DISPATCH_TOKEN': secret}), patch.object(windows.subprocess, 'run', side_effect=curl):
            api = windows.GitHub()
            api.download(99, Path(self.temp.name) / 'artifact.zip')
        self.assertIn(secret.encode(), seen[0][1])
        self.assertNotIn(secret.encode(), seen[1][1])
        self.assertIn(signed_url.encode(), seen[1][1])


if __name__ == '__main__':
    unittest.main()
