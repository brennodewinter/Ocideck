"""Offline fault tests for one release operation; no dispatch reaches a forge."""
import json
import io
from pathlib import Path
import sys
import tempfile
import threading
from urllib.parse import unquote
from types import SimpleNamespace
import unittest
import zipfile
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tool'))
import release_channel_controller as control


class FakeForge:
    def __init__(self, run=None):
        self.run = run
        self.posts = []
        self.branches = {}
        self.jobs = [{'name': 'build', 'status': 'success', 'started_at': 'now', 'completed_at': 'later'}]

    def get(self, path):
        if path == '/git/refs/heads/main':
            return {'ref': 'refs/heads/main', 'object': {'sha': 'b' * 40}}
        if path.startswith('/branches/'):
            return self.branches[unquote(path.removeprefix('/branches/'))]
        if path.startswith('/actions/runs?'):
            return {'workflow_runs': [] if self.run is None else [{'id': self.run['id']}]}
        if path.endswith('/jobs'):
            return self.jobs
        if path.endswith('/artifacts'):
            return [{'id': 7, 'name': 'windows-operation-ab12cd34', 'expired': False}]
        return self.run

    def artifact(self, _artifact_id):
        state = dict(schema=1, operation_id='ab12cd34', tag='v0.7.7', sha='a' * 40,
                     ref='codex/release-candidate-v0.7.7-' + 'a' * 40,
                     dispatch_intents=[], closed=True, forge_run_id=42,
                     controller_sha='b' * 40, selected_runs={})
        output = io.BytesIO()
        with zipfile.ZipFile(output, 'w') as archive:
            archive.writestr('windows-operation.json', json.dumps(state))
        return output.getvalue()

    def post(self, path, payload):
        self.posts.append((path, payload))
        if path.endswith('/cancel'):
            self.run['status'] = 'cancelled'
        return None

    def branch_mutation(self, path, method, payload=None, expected=201):
        if method == 'POST':
            name = payload['new_branch_name']
            if name in self.branches:
                raise ValueError('Forgejo branch HTTP 409')
            branch = {'name': name, 'commit': {'id': payload['old_ref_name']}}
            self.branches[name] = branch
            return branch
        name = unquote(path.removeprefix('/branches/'))
        del self.branches[name]
        return None


class ControllerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.args = SimpleNamespace(state_dir=Path(self.temp.name), tag='v0.7.7', sha='a' * 40,
            controller_sha='b' * 40, channel='web', operation_id='ab12cd34')
        self.wanted = control.identity(self.args)

    def reserve_claimed(self, api):
        control.reserve(self.args)
        control.claim(self.args, api, self.wanted)

    def run_info(self, status='running', **inputs):
        values = {'operation_id': self.args.operation_id, 'tag': self.args.tag,
            'source_sha': self.args.sha, 'frozen_ref': self.wanted['frozen_ref'],
            'channel': self.args.channel}
        values.update(inputs)
        return {'id': 42, 'workflow_id': control.WORKFLOW,
            'commit_sha': self.args.controller_sha, 'prettyref': 'main',
            'trigger_event': 'workflow_dispatch',
            'event_payload': json.dumps({'inputs': values, 'ref': 'main'}),
            'status': status, 'created': '2026-11-03T08:00:00Z',
            'updated': '2026-11-03T08:01:00Z', 'started': '2026-11-03T08:00:05Z',
            'stopped': '2026-11-03T08:01:00Z', 'duration': 55}

    def test_start_persists_identity_before_one_dispatch(self):
        api = FakeForge()
        original = api.post
        def post(path, payload):
            self.assertEqual(self.wanted, control.read_operation(self.args))
            self.assertEqual('started', control.release_journal.read(
                self.args.state_dir / self.args.tag / 'web.json')['events'][-1]['state'])
            return original(path, payload)
        api.post = post
        control.start(self.args, api)
        self.assertEqual(1, len(api.posts))
        self.assertEqual(self.args.operation_id, api.posts[0][1]['inputs']['operation_id'])
        with self.assertRaisesRegex(ValueError, 'already reserved'):
            control.start(self.args, api)
        self.assertEqual(1, len(api.posts))

    def test_reservation_serializes_same_operation_before_file_exists(self):
        original = control.release_channel.immutable_write
        def overlap(path, content):
            with self.assertRaisesRegex(ValueError, 'locked'):
                control.reserve(self.args)
            return original(path, content)
        with patch.object(control.release_channel, 'immutable_write', side_effect=overlap):
            control.reserve(self.args)
        with self.assertRaisesRegex(ValueError, 'already reserved'):
            control.reserve(self.args)

    def test_lost_post_and_empty_listing_never_redispatch(self):
        api = FakeForge()
        def lost(*_):
            raise ValueError('lost response')
        api.post = lost
        with self.assertRaisesRegex(ValueError, 'lost response'):
            control.start(self.args, api)
        with self.assertRaisesRegex(ValueError, 'unknown'):
            control.hervat(self.args, api)
        with self.assertRaisesRegex(ValueError, 'unknown'):
            control.stop(self.args, api)

    def test_main_moved_before_dispatch_keeps_reservation_without_post(self):
        api = FakeForge()
        original = api.get
        checks = 0
        def moved(path):
            nonlocal checks
            if path == '/git/refs/heads/main':
                checks += 1
                if checks == 2:
                    return {'ref': 'refs/heads/main', 'object': {'sha': 'c' * 40}}
            return original(path)
        api.get = moved
        with self.assertRaisesRegex(ValueError, 'main moved'):
            control.start(self.args, api)
        self.assertEqual([], api.posts)
        self.assertEqual(self.wanted, control.read_operation(self.args))

    def test_two_state_directories_share_one_remote_build_claim(self):
        api = FakeForge()
        control.start(self.args, api)
        second = SimpleNamespace(**vars(self.args))
        second.state_dir = self.args.state_dir / 'other-host'
        second.operation_id = 'other-op'
        with self.assertRaisesRegex(ValueError, '409'):
            control.start(second, api)
        self.assertEqual(1, len(api.posts))
        self.assertFalse(control.claim_path(second, 'owned').exists())

    def test_unknown_create_never_dispatches_or_claims_ownership(self):
        api = FakeForge()
        original = api.branch_mutation
        def lost(path, method, payload=None, expected=201):
            result = original(path, method, payload, expected)
            if method == 'POST':
                raise ValueError('lost 201 response')
            return result
        api.branch_mutation = lost
        with self.assertRaisesRegex(ValueError, 'lost 201'):
            control.start(self.args, api)
        self.assertTrue(control.claim_path(self.args, 'intent').is_file())
        self.assertFalse(control.claim_path(self.args, 'owned').exists())
        self.assertEqual([], api.posts)

    def test_unknown_delete_never_repeats_against_recreated_claim(self):
        api = FakeForge(self.run_info('success'))
        self.reserve_claimed(api)
        original = api.branch_mutation
        def lost(path, method, payload=None, expected=201):
            result = original(path, method, payload, expected)
            if method == 'DELETE':
                raise ValueError('lost 204 response')
            return result
        api.branch_mutation = lost
        with self.assertRaisesRegex(ValueError, 'lost 204'):
            control.hervat(self.args, api)
        branch = control.claim_name(self.wanted)
        api.branches[branch] = {'name': branch, 'commit': {'id': self.args.controller_sha}}
        with self.assertRaisesRegex(ValueError, 'never repeat DELETE'):
            control.hervat(self.args, api)
        self.assertIn(branch, api.branches)

    def test_concurrent_release_claim_cannot_delete_recreated_same_sha(self):
        api = FakeForge()
        self.reserve_claimed(api)
        entered = threading.Event()
        proceed = threading.Event()
        original_get = api.get
        deletions = []
        original_mutation = api.branch_mutation
        def paused_get(path):
            if path.startswith('/branches/'):
                entered.set()
                self.assertTrue(proceed.wait(5))
            return original_get(path)
        def mutation(path, method, payload=None, expected=201):
            if method == 'DELETE':
                deletions.append(path)
            return original_mutation(path, method, payload, expected)
        api.get = paused_get
        api.branch_mutation = mutation
        outcomes = []
        def release():
            try:
                control.release_claim(self.args, api, self.wanted)
                outcomes.append('released')
            except ValueError as error:
                outcomes.append(str(error))
        first = threading.Thread(target=release)
        second = threading.Thread(target=release)
        first.start()
        self.assertTrue(entered.wait(5))
        second.start()
        second.join(5)
        proceed.set()
        first.join(5)
        self.assertFalse(first.is_alive() or second.is_alive())
        self.assertEqual(1, len(deletions))
        self.assertTrue(any('locked' in outcome for outcome in outcomes))
        branch = control.claim_name(self.wanted)
        api.branches[branch] = {'name': branch, 'commit': {'id': self.args.controller_sha}}
        control.release_claim(self.args, api, self.wanted)
        self.assertEqual(1, len(deletions))
        self.assertIn(branch, api.branches)

    def test_exact_reconciliation_and_history(self):
        api = FakeForge(self.run_info('success'))
        self.reserve_claimed(api)
        result = control.hervat(self.args, api)
        self.assertEqual('success', result['build_metadata'])
        self.assertEqual('unverified', result['artifact_bytes'])
        self.assertEqual('2026-11-03T08:00:05Z', result['runs'][0]['started'])
        self.assertEqual(55, result['runs'][0]['duration'])
        history = control.release_journal.read(self.args.state_dir / self.args.tag / 'web.json')['events']
        self.assertEqual(['started', 'completed', 'started', 'completed'], [e['state'] for e in history])
        self.assertEqual('build', history[-1]['phase'])

    def test_failed_job_keeps_first_error_and_times_without_claiming_bytes(self):
        api = FakeForge(self.run_info('failure'))
        api.jobs = [
            {'name': 'build', 'status': 'success', 'started_at': 'first', 'completed_at': 'second'},
            {'name': 'evidence', 'status': 'failure', 'started_at': 'third', 'completed_at': 'fourth'},
        ]
        self.reserve_claimed(api)
        result = control.hervat(self.args, api)
        self.assertEqual({'job': 'evidence', 'status': 'failure',
                          'started_at': 'third', 'completed_at': 'fourth'},
                         result['runs'][0]['first_error'])
        self.assertEqual('unproven', result['build_metadata'])
        self.assertEqual('unverified', result['artifact_bytes'])
        history = control.release_journal.read(self.args.state_dir / self.args.tag / 'web.json')['events']
        self.assertEqual('failed', history[-1]['state'])
        proof = next(iter(history[-1]['evidence']))
        self.assertEqual(result['runs'][0], json.loads(Path(proof).read_text()))

    def test_skipped_other_channels_are_not_first_errors(self):
        api = FakeForge(self.run_info('success'))
        api.jobs = [{'name': 'unused consumer', 'status': 'skipped'},
                    {'name': 'evidence', 'status': 'success'}]
        control.reserve(self.args)
        result = control.status(self.args, api)
        self.assertIsNone(result['runs'][0]['first_error'])

    def test_conflicting_id_fails_closed_and_does_not_cancel(self):
        api = FakeForge(self.run_info('running', source_sha='c' * 40))
        control.reserve(self.args)
        with self.assertRaisesRegex(ValueError, 'conflicting'):
            control.stop(self.args, api)
        self.assertEqual([], api.posts)

    def test_stop_only_exact_run_and_confirms_terminal(self):
        api = FakeForge(self.run_info())
        self.reserve_claimed(api)
        result = control.stop(self.args, api)
        self.assertEqual([(control.WORKFLOW and '/actions/runs/42/cancel', {})], api.posts)
        self.assertEqual('cancelled', result['runs'][0]['status'])
        self.assertEqual('cancelled', control.release_journal.read(
            self.args.state_dir / self.args.tag / 'web.json')['events'][-1]['state'])

    def test_post_race_wrong_controller_can_only_be_stopped_by_exact_nonce(self):
        run = self.run_info()
        run['commit_sha'] = 'c' * 40
        api = FakeForge(run)
        self.reserve_claimed(api)
        with self.assertRaisesRegex(ValueError, 'different run identity'):
            control.status(self.args, api)
        result = control.stop(self.args, api)
        self.assertEqual('cancelled', result['runs'][0]['status'])
        self.assertEqual('c' * 40, result['runs'][0]['controller_sha'])
        self.assertEqual(['/actions/runs/42/cancel'], [path for path, _ in api.posts])

    def test_status_is_read_only_when_unreserved(self):
        with self.assertRaisesRegex(ValueError, 'no saved operation'):
            control.status(self.args, FakeForge())
        self.assertFalse(self.args.state_dir.joinpath(self.args.tag).exists())

    def test_status_does_not_mutate_saved_journal(self):
        control.reserve(self.args)
        api = FakeForge(self.run_info())
        journal = self.args.state_dir / self.args.tag / 'web.json'
        before = journal.read_bytes()
        result = control.status(self.args, api)
        self.assertEqual(before, journal.read_bytes())
        self.assertEqual('found', result['dispatch'])
        self.assertEqual('unverified', result['publication'])

    def test_status_rejects_wrong_or_symlinked_claim_receipt(self):
        api = FakeForge(self.run_info())
        self.reserve_claimed(api)
        owned = control.claim_path(self.args, 'owned')
        self.assertEqual('owned', control.status(self.args, api)['build_claim'])
        owned.write_text('{}')
        self.assertEqual('unknown', control.status(self.args, api)['build_claim'])
        owned.unlink()
        owned.symlink_to(control.claim_path(self.args, 'intent'))
        self.assertEqual('unknown', control.status(self.args, api)['build_claim'])

    def test_windows_status_uses_exact_remote_artifact(self):
        self.args.channel = 'windows'
        self.wanted = control.identity(self.args)
        control.reserve(self.args)
        (self.args.state_dir / self.args.tag / 'downloaded-windows-operation.json').write_text('{}')
        api = FakeForge(self.run_info('success'))
        with patch.object(control.subprocess, 'run', return_value=SimpleNamespace(
                stdout=json.dumps({'terminal': True, 'unknown': False, 'runs': []}), returncode=0)) as called:
            result = control.status(self.args, api)
        command = called.call_args.args[0]
        self.assertIn('--state', command)
        self.assertEqual(command[command.index('--forge-run-id') + 1], '42')
        self.assertEqual(command[command.index('--controller-sha') + 1], self.args.controller_sha)
        self.assertEqual([], result['github']['runs'])

    def test_windows_unknown_child_proof_keeps_remote_build_claim(self):
        self.args.channel = 'windows'
        self.wanted = control.identity(self.args)
        api = FakeForge(self.run_info('success'))
        self.reserve_claimed(api)
        with patch.object(control.subprocess, 'run', return_value=SimpleNamespace(
                stdout=json.dumps({'terminal': False, 'unknown': True, 'runs': []}), returncode=2)):
            control.hervat(self.args, api)
        self.assertIn(control.claim_name(self.wanted), api.branches)
        self.assertFalse(control.claim_path(self.args, 'release-intent').exists())

    def test_windows_reused_green_children_release_remote_build_claim(self):
        self.args.channel = 'windows'
        self.wanted = control.identity(self.args)
        api = FakeForge(self.run_info('success'))
        self.reserve_claimed(api)
        green = {'terminal': True, 'unknown': False, 'selected_verified': True,
                 'selected_runs': {'release.yml': 20, 'windows-test-check.yml': 10}, 'runs': []}
        with patch.object(control.subprocess, 'run', return_value=SimpleNamespace(
                stdout=json.dumps(green), returncode=0)):
            control.hervat(self.args, api)
        self.assertNotIn(control.claim_name(self.wanted), api.branches)
        self.assertTrue(control.claim_path(self.args, 'release-completed').is_file())

    def test_windows_publication_rejects_vacuous_terminal_result(self):
        self.args.channel = 'windows'
        self.args.run_id = 42
        self.wanted = control.identity(self.args)
        control.reserve(self.args)
        api = FakeForge(self.run_info('success'))
        with patch.object(control, 'status', return_value={
                'runs': [{'id': 42, 'status': 'success'}],
                'github': {'terminal': True, 'unknown': False, 'runs': [],
                           'selected_verified': False, 'selected_runs': {}}}):
            with self.assertRaisesRegex(ValueError, 'not proven terminal green'):
                control.publish(self.args, api)

    def test_windows_artifact_provenance_and_zip_are_strict(self):
        api = FakeForge(self.run_info('success'))
        content = control.windows_state(api, self.wanted, 42)
        self.assertEqual(42, json.loads(content)['forge_run_id'])
        with patch.object(api, 'artifact', return_value=b'not a ZIP'):
            with self.assertRaises(zipfile.BadZipFile):
                control.windows_state(api, self.wanted, 42)
        original = api.artifact
        with patch.object(api, 'get', return_value=[{'id': 7, 'name': 'windows-operation-other', 'expired': False}]):
            with self.assertRaisesRegex(ValueError, 'unavailable'):
                control.windows_state(api, self.wanted, 42)

    def test_windows_stop_before_gh_dispatch_uses_closed_remote_journal(self):
        self.args.channel = 'windows'
        self.wanted = control.identity(self.args)
        api = FakeForge(self.run_info())
        self.reserve_claimed(api)
        with patch.object(control.subprocess, 'run', return_value=SimpleNamespace(returncode=0)) as called:
            result = control.stop(self.args, api)
        command = called.call_args.args[0]
        self.assertIn('--state', command)
        self.assertEqual('cancelled', result['runs'][0]['status'])

    def test_publish_reuses_staged_evidence_and_preserves_lower_verdict(self):
        self.args.run_id = 42
        self.args.release_id = 'auto'
        self.args.create_release = True
        self.args.dist = self.args.state_dir / 'lost-dist'
        self.args.evidence = self.args.state_dir / 'lost-evidence'
        stage = self.args.state_dir / self.args.tag / 'web-candidate'
        (stage / 'dist').mkdir(parents=True)
        (stage / 'evidence').mkdir()
        for name in ('channel-manifest-web.json', 'SHA256SUMS.web',
                     'channel-manifest-web.json.minisig', 'SHA256SUMS.web.minisig'):
            (stage / 'evidence' / name).write_text('signed-test-evidence')
        success = {'runs': [{'id': 42, 'status': 'success'}]}
        with patch.object(control, 'status', return_value=success), \
             patch.object(control.subprocess, 'run', return_value=SimpleNamespace(returncode=0)) as lower:
            self.assertEqual(0, control.publish(self.args, FakeForge()))
        command = lower.call_args.args[0]
        self.assertEqual((stage / 'dist').resolve(), Path(command[command.index('--dist') + 1]))
        self.assertEqual((stage / 'evidence').resolve(), Path(command[command.index('--evidence') + 1]))
        (stage / 'evidence' / 'SHA256SUMS.web.minisig').unlink()
        with patch.object(control, 'status', return_value=success), \
             patch.object(control.subprocess, 'run') as lower:
            with self.assertRaisesRegex(ValueError, 'signed evidence missing'):
                control.publish(self.args, FakeForge())
            lower.assert_not_called()
        (stage / 'evidence' / 'SHA256SUMS.web.minisig').write_text('tampered')
        with patch.object(control, 'status', return_value=success), \
             patch.object(control.subprocess, 'run', return_value=SimpleNamespace(returncode=1)):
            self.assertEqual(1, control.publish(self.args, FakeForge()))


if __name__ == '__main__':
    unittest.main()
