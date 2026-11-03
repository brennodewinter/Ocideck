"""Bounded channel continuation through Forgejo 16 dispatch; no external writes."""
import io
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from urllib.parse import unquote
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tool'))
import release_channel_controller as control


class AttemptForge:
    def __init__(self, args):
        self.args = args
        self.values = [self.make_run(42, 'main', {}, 'success')]
        self.proofs = {42: self.make_proof(42, 'pending')}
        self.posts = []
        self.branch = dict(name=control.claim_name(control.identity(args)), commit={'id': args.controller_sha})

    def make_run(self, run_id, ref, extra, status):
        inputs = dict(tag=self.args.tag, source_sha=self.args.sha, frozen_ref=control.identity(self.args)['frozen_ref'],
                      operation_id=self.args.operation_id, channel=self.args.channel, **extra)
        return dict(id=run_id, status=status, workflow_id=control.WORKFLOW, commit_sha=self.args.controller_sha,
                    prettyref=ref, trigger_event='workflow_dispatch', event_payload={'ref': ref, 'inputs': inputs})

    def make_proof(self, run_id, outcome):
        value = dict(schema=1, tag=self.args.tag, sha=self.args.sha,
                     ref=control.identity(self.args)['frozen_ref'], operation_id=self.args.operation_id,
                     forge_run_id=run_id, controller_sha=self.args.controller_sha, outcome=outcome)
        if self.args.channel == 'windows':
            value.update(closed=outcome != 'pending', dispatch_intents=['release.yml', 'windows-test-check.yml'],
                         selected_runs={'release.yml': 100, 'windows-test-check.yml': 101})
        else:
            value.update(submission_id='same-submission', notary_sha256='d' * 64)
        return value

    def get(self, path):
        if path == '':
            return {'permissions': {'push': True}}
        if path.startswith('/git/refs/heads/'):
            return {'object': {'sha': self.args.sha}}
        if path.startswith('/branches/'):
            assert unquote(path.split('/branches/', 1)[1]) == self.branch['name']
            return self.branch
        if path.startswith('/actions/runs?'):
            return {'workflow_runs': self.values}
        if path.endswith('/jobs'):
            return [{'name': 'candidate', 'status': 'success'}]
        if path.endswith('/artifacts'):
            run_id = int(path.split('/')[3])
            return [dict(id=run_id, name=self.args.channel + '-operation-' + self.args.operation_id, expired=False)] if run_id in self.proofs else []
        if path.startswith('/actions/runs/'):
            return next(run for run in self.values if str(run['id']) == path.rsplit('/', 1)[1])
        raise AssertionError('unexpected GET ' + path)

    def artifact(self, artifact_id):
        output = io.BytesIO()
        with zipfile.ZipFile(output, 'w') as archive:
            archive.writestr(self.args.channel + '-operation.json', json.dumps(self.proofs[artifact_id]))
        return output.getvalue()

    def post(self, path, payload):
        self.posts.append((path, payload))
        assert path.endswith('/dispatches')
        previous = int(payload['inputs']['previous_run_id'])
        saved = json.loads(control.attempt_path(self.args, previous).read_text())
        assert saved['attempt_id'] == payload['inputs']['attempt_id']
        extra = {key: payload['inputs'][key] for key in ('attempt_id', 'previous_run_id')}
        self.values.append(self.make_run(previous + 1, payload['ref'], extra, 'running'))


class ContinuationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.args = SimpleNamespace(state_dir=Path(self.temporary.name), tag='v1.2.3', sha='a' * 40,
            controller_sha='b' * 40, channel='windows', operation_id='same-operation', run_id=42)

    def prepare(self, channel='windows'):
        self.args.channel = channel
        api = AttemptForge(self.args)
        wanted = control.reserve(self.args)
        receipt = dict(wanted, branch=control.claim_name(wanted))
        control.release_channel.immutable_write(control.claim_path(self.args, 'owned'), control.release_channel.encoded(receipt))
        return api

    def windows_status(self):
        return patch.object(control.subprocess, 'run', return_value=SimpleNamespace(returncode=0,
            stdout=json.dumps(dict(terminal=False, unknown=False, selected_verified=False,
                                  selected_runs={'release.yml': 100, 'windows-test-check.yml': 101}, runs=[]))))

    def test_pending_windows_dispatches_one_collect_attempt_on_original_controller_ref(self):
        api = self.prepare()
        with self.windows_status():
            initial = control.status(self.args, api)
            self.assertEqual('unproven', initial['build_metadata'])
            resumed = control.hervat(self.args, api)
        self.assertEqual('found', resumed['continuation'])
        self.assertEqual('unproven', resumed['build_metadata'])
        self.assertEqual([42, 43], [run['id'] for run in resumed['runs']])
        self.assertEqual(1, len(api.posts))
        self.assertEqual(api.branch['name'], api.posts[0][1]['ref'])
        self.assertEqual('42', api.posts[0][1]['inputs']['previous_run_id'])
        self.assertEqual(self.args.controller_sha, api.values[-1]['commit_sha'])
        self.assertFalse(control.claim_path(self.args, 'release-intent').exists())
        with self.windows_status():
            control.hervat(self.args, api)
        self.assertEqual(1, len(api.posts))

    def test_pending_green_poll_cannot_publish(self):
        api = self.prepare()
        with self.windows_status():
            with self.assertRaisesRegex(ValueError, 'not terminal green'):
                control.publish(self.args, api)
        self.assertFalse(api.posts)

    def test_mac_continuation_chain_accepts_completed_consumer_upload_evidence(self):
        api = self.prepare('macos')
        result = control.hervat(self.args, api)
        self.assertEqual('found', result['continuation'])
        api.values[-1]['status'] = 'success'
        api.proofs[43] = api.make_proof(43, 'completed')
        result = control.status(self.args, api)
        self.assertEqual('success', result['build_metadata'])
        self.assertEqual('completed', result['runs'][-1]['outcome'])
        self.assertEqual(43, result['runs'][-1]['id'])
        content = control.continuation_state(api, control.identity(self.args), 42, 43,
            api.values[-1]['event_payload']['inputs']['attempt_id'])
        self.assertEqual('same-submission', json.loads(content)['submission_id'])

    def test_lost_continuation_response_is_never_redispatched(self):
        api = self.prepare('macos')
        def lost(path, payload):
            api.posts.append((path, payload))
            self.assertTrue(control.attempt_path(self.args, 42).is_file())
            raise ValueError('lost dispatch response')
        api.post = lost
        with self.assertRaisesRegex(ValueError, 'lost dispatch response'):
            control.hervat(self.args, api)
        with self.assertRaisesRegex(ValueError, 'outcome unknown; never repeat POST'):
            control.hervat(self.args, api)
        self.assertEqual(1, len(api.posts))

    def test_unowned_attempt_and_wrong_predecessor_nonce_or_controller_refused(self):
        for field, replacement in [('attempt_id', 'someone-else'), ('previous_run_id', '999'), ('controller', 'c' * 40)]:
            with self.subTest(field=field), tempfile.TemporaryDirectory() as directory:
                self.args.state_dir = Path(directory)
                api = self.prepare('macos')
                control.hervat(self.args, api)
                if field == 'controller':
                    api.values[-1]['commit_sha'] = replacement
                else:
                    api.values[-1]['event_payload']['inputs'][field] = replacement
                with self.assertRaisesRegex(ValueError, 'identity|predecessor'):
                    control.status(self.args, api)
                self.assertEqual(1, len(api.posts))

    def test_worker_rejects_changed_current_or_previous_identity_before_restore(self):
        api = self.prepare('macos')
        control.hervat(self.args, api)
        attempt = api.values[-1]['event_payload']['inputs']['attempt_id']
        for key, value in [('sha', 'c' * 40), ('controller_sha', 'c' * 40), ('operation_id', 'other-operation')]:
            original = api.proofs[42][key]
            api.proofs[42][key] = value
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'provenance differs'):
                control.continuation_state(api, control.identity(self.args), 42, 43, attempt)
            api.proofs[42][key] = original
        with self.assertRaisesRegex(ValueError, 'current continuation run identity differs'):
            control.continuation_state(api, control.identity(self.args), 42, 43, 'wrong-nonce')

    def test_second_pending_attempt_can_continue_without_releasing_owner_claim(self):
        api = self.prepare('macos')
        control.hervat(self.args, api)
        api.values[-1]['status'] = 'success'
        api.proofs[43] = api.make_proof(43, 'pending')
        result = control.hervat(self.args, api)
        self.assertEqual([42, 43, 44], [run['id'] for run in result['runs']])
        self.assertEqual('unproven', result['build_metadata'])
        self.assertEqual(2, len(api.posts))
        self.assertTrue(control.attempt_path(self.args, 42).is_file())
        self.assertTrue(control.attempt_path(self.args, 43).is_file())
        self.assertFalse(control.claim_path(self.args, 'release-intent').exists())

    def test_upload_failure_continues_completed_bytes_and_records_final_green(self):
        api = self.prepare('macos')
        api.values[0]['status'] = 'failure'
        api.proofs[42] = api.make_proof(42, 'completed')
        control.hervat(self.args, api)
        api.values[-1]['status'] = 'success'
        api.proofs[43] = api.make_proof(43, 'completed')
        result = control.status(self.args, api)
        control.save_observation(self.args, result)
        self.assertEqual('success', result['build_metadata'])
        events = control.release_journal.read(self.args.state_dir / self.args.tag / 'macos.json')['events']
        self.assertEqual(['started', 'failed', 'started', 'completed'],
            [event['state'] for event in events if event['phase'] == 'build'])

    def test_unknown_mac_receipt_neither_continues_nor_releases_claim(self):
        api = self.prepare('macos')
        api.proofs.clear()
        api.values[0]['status'] = 'failure'
        result = control.hervat(self.args, api)
        self.assertEqual('unknown', result['runs'][0]['outcome'])
        self.assertFalse(api.posts)
        self.assertFalse(control.claim_path(self.args, 'release-intent').exists())

    def test_explicitly_released_claim_blocks_resume_after_cancel_and_publication(self):
        api = self.prepare('macos')
        control.hervat(self.args, api)
        api.values[-1]['status'] = 'cancelled'
        api.proofs[43] = api.make_proof(43, 'pending')
        wanted = control.identity(self.args)
        receipt = control.release_channel.encoded(dict(wanted, branch=control.claim_name(wanted)))
        for suffix in ('release-intent', 'release-completed'):
            control.release_channel.immutable_write(control.claim_path(self.args, suffix), receipt)
        result = control.status(self.args, api)
        self.assertEqual('blocked_missing_continuation_controller_claim', result['publication'])
        with self.assertRaisesRegex(ValueError, 'original owned build claim'):
            control.hervat(self.args, api)
        self.assertEqual(1, len(api.posts))

    def test_success_without_worker_receipt_never_records_build_completion(self):
        api = self.prepare('macos')
        api.proofs.clear()
        result = control.hervat(self.args, api)
        self.assertEqual('unproven', result['build_metadata'])
        events = control.release_journal.read(self.args.state_dir / self.args.tag / 'macos.json')['events']
        self.assertEqual(['started'], [event['state'] for event in events if event['phase'] == 'build'])


if __name__ == '__main__':
    unittest.main()
