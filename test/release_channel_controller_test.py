"""Offline fault tests for one release operation; no dispatch reaches a forge."""
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tool'))
import release_channel_controller as control


class FakeForge:
    def __init__(self, run=None):
        self.run = run
        self.posts = []
        self.jobs = [{'name': 'build', 'status': 'success', 'started_at': 'now', 'completed_at': 'later'}]

    def get(self, path):
        if path.startswith('/actions/runs?'):
            return {'workflow_runs': [] if self.run is None else [{'id': self.run['id']}]}
        if path.endswith('/jobs'):
            return self.jobs
        return self.run

    def post(self, path, payload):
        self.posts.append((path, payload))
        if path.endswith('/cancel'):
            self.run['status'] = 'cancelled'
        return None


class ControllerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.args = SimpleNamespace(state_dir=Path(self.temp.name), tag='v0.7.7', sha='a' * 40,
            controller_sha='b' * 40, channel='web', operation_id='ab12cd34')
        self.wanted = control.identity(self.args)

    def run_info(self, status='running', **inputs):
        values = {'operation_id': self.args.operation_id, 'tag': self.args.tag,
            'source_sha': self.args.sha, 'frozen_ref': self.wanted['frozen_ref'],
            'channel': self.args.channel}
        values.update(inputs)
        return {'id': 42, 'workflow_id': control.WORKFLOW,
            'commit_sha': self.args.controller_sha, 'prettyref': 'main',
            'trigger_event': 'workflow_dispatch',
            'event_payload': json.dumps({'inputs': values, 'ref': 'main'}),
            'status': status, 'created_at': '2026-11-03T08:00:00Z',
            'updated_at': '2026-11-03T08:01:00Z'}

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

    def test_exact_reconciliation_and_history(self):
        api = FakeForge(self.run_info('success'))
        control.reserve(self.args)
        result = control.hervat(self.args, api)
        self.assertEqual('success', result['build_metadata'])
        self.assertEqual('unverified', result['artifact_bytes'])
        history = control.release_journal.read(self.args.state_dir / self.args.tag / 'web.json')['events']
        self.assertEqual(['started', 'completed', 'started', 'completed'], [e['state'] for e in history])
        self.assertEqual('build', history[-1]['phase'])

    def test_failed_job_keeps_first_error_and_times_without_claiming_bytes(self):
        api = FakeForge(self.run_info('failure'))
        api.jobs = [
            {'name': 'build', 'status': 'success', 'started_at': 'first', 'completed_at': 'second'},
            {'name': 'evidence', 'status': 'failure', 'started_at': 'third', 'completed_at': 'fourth'},
        ]
        control.reserve(self.args)
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

    def test_conflicting_id_fails_closed_and_does_not_cancel(self):
        api = FakeForge(self.run_info('running', source_sha='c' * 40))
        control.reserve(self.args)
        with self.assertRaisesRegex(ValueError, 'conflicting'):
            control.stop(self.args, api)
        self.assertEqual([], api.posts)

    def test_stop_only_exact_run_and_confirms_terminal(self):
        api = FakeForge(self.run_info())
        control.reserve(self.args)
        result = control.stop(self.args, api)
        self.assertEqual([(control.WORKFLOW and '/actions/runs/42/cancel', {})], api.posts)
        self.assertEqual('cancelled', result['runs'][0]['status'])
        self.assertEqual('cancelled', control.release_journal.read(
            self.args.state_dir / self.args.tag / 'web.json')['events'][-1]['state'])

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


if __name__ == '__main__':
    unittest.main()
