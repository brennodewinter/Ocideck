"""Local controller tests; publisher subprocess is replaced with receipt outcomes."""
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tool'))
import release_channel_control as control
import release_journal as journal


class ReleaseChannelControlTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.args = SimpleNamespace(state_dir=self.base / 'state', tag='v0.7.7', sha='a' * 40,
                                    controller_sha='b' * 40, channel='web', release_id='12', run_id='34',
                                    dist=self.base / 'dist', evidence=self.base / 'evidence', create_release=False)
        self.state = self.args.state_dir / self.args.tag
        self.journal = self.state / 'web.json'
        self.receipt = self.state / 'web-published.json'

    def publish(self, effect):
        with patch.object(control, 'run_publisher', side_effect=effect) as mocked, redirect_stdout(io.StringIO()):
            result = control.publish(self.args)
        return result, mocked

    def success(self, command, **kwargs):
        self.assertEqual('bash', command[0])
        self.assertEqual(str(self.receipt), command[command.index('--receipt') + 1])
        self.assertEqual(self.args.controller_sha, command[command.index('--controller-sha') + 1])
        self.receipt.write_text(json.dumps({'schema': 1, 'release_id': self.args.release_id,
            'run_id': self.args.run_id, 'tag': self.args.tag, 'source': self.args.sha,
            'controller_sha': self.args.controller_sha, 'channel': self.args.channel,
            'files': {'channel-manifest-web.json': 'c' * 64}}, sort_keys=True) + '\n')
        return SimpleNamespace(returncode=0)

    def test_status_does_not_create_journal_or_publication_lease(self):
        self.args.status = True
        self.args.release_id = 'auto'
        def read_only(command):
            self.assertIn('--verify-only', command)
            self.assertFalse(self.args.state_dir.exists())
            return SimpleNamespace(returncode=0)
        self.assertEqual(self.publish(read_only)[0], 0)
        self.assertFalse(self.args.state_dir.exists())

    def test_first_publication_uses_same_lease_and_journal(self):
        self.args.create_release = True
        self.args.release_id = 'auto'
        def created(command):
            self.assertIn('--create-release', command)
            self.assertEqual(journal.read(self.journal)['events'][-1]['state'], 'started')
            self.receipt.write_text('{"release_id":"12"}')
            return SimpleNamespace(returncode=0)
        self.assertEqual(self.publish(created)[0], 0)
        self.assertEqual(journal.read(self.journal)['events'][-1]['state'], 'completed')

    def test_interrupted_publisher_terminates_process_group_and_waits(self):
        from unittest.mock import Mock
        process = Mock(pid=12345)
        process.wait.side_effect = [KeyboardInterrupt, 0]
        with patch.object(control.subprocess, 'Popen', return_value=process) as spawn, patch.object(control.os, 'killpg') as kill:
            with self.assertRaises(KeyboardInterrupt):
                control.run_publisher(['publisher'])
        spawn.assert_called_once_with(['publisher'], start_new_session=True)
        kill.assert_called_once_with(12345, control.signal.SIGTERM)
        self.assertEqual(process.wait.call_count, 2)

    def test_completed_repeat_rechecks_publisher(self):
        result, mocked = self.publish(self.success)
        self.assertEqual(0, result)
        self.assertEqual(1, mocked.call_count)
        before = journal.read(self.journal)
        self.assertEqual(['started', 'completed'], [e['state'] for e in before['events']])
        result, mocked = self.publish(self.success)
        self.assertEqual(0, result)
        self.assertEqual(1, mocked.call_count)
        self.assertEqual(before, journal.read(self.journal))

    def test_failure_stays_in_history_then_explicit_call_can_retry(self):
        result, _ = self.publish(lambda *a, **k: SimpleNamespace(returncode=7))
        self.assertEqual(7, result)
        self.assertEqual(['started', 'failed'], [e['state'] for e in journal.read(self.journal)['events']])
        result, _ = self.publish(self.success)
        self.assertEqual(0, result)
        self.assertEqual(['started', 'failed', 'started', 'completed'],
                         [e['state'] for e in journal.read(self.journal)['events']])

    def test_interrupted_start_requires_explicit_reconciliation(self):
        with self.assertRaises(ValueError):
            self.publish(lambda *a, **k: SimpleNamespace(returncode=0))
        self.assertEqual('started', journal.read(self.journal)['events'][-1]['state'])
        with patch.object(control.subprocess, 'run') as mocked:
            with self.assertRaisesRegex(ValueError, 'interrupted publication'):
                control.publish(self.args)
            mocked.assert_not_called()

    def test_tag_wide_lease_excludes_other_channels(self):
        self.state.mkdir(parents=True)
        self.args.channel = 'macos'
        with journal.locked(self.state / 'publication'), patch.object(control.subprocess, 'run') as mocked:
            with self.assertRaisesRegex(ValueError, 'locked'):
                control.publish(self.args)
            mocked.assert_not_called()
        self.assertFalse((self.state / 'macos.json').exists())

    def test_wrong_identity_fails_before_any_state_or_publisher(self):
        for name, value in [('sha', '0' * 40), ('controller_sha', 'short'), ('tag', '../v0.7.7'), ('channel', 'unknown')]:
            with self.subTest(field=name):
                old = getattr(self.args, name)
                setattr(self.args, name, value)
                with patch.object(control.subprocess, 'run') as mocked:
                    with self.assertRaises(ValueError):
                        control.publish(self.args)
                    mocked.assert_not_called()
                self.assertFalse(self.args.state_dir.exists())
                setattr(self.args, name, old)

    def test_existing_journal_rejects_other_source_before_publisher(self):
        self.publish(self.success)
        before = self.journal.read_bytes()
        self.args.sha = 'd' * 40
        with patch.object(control.subprocess, 'run') as mocked:
            with self.assertRaisesRegex(ValueError, 'identity mismatch'):
                control.publish(self.args)
            mocked.assert_not_called()
        self.assertEqual(before, self.journal.read_bytes())

    def test_missing_receipt_cannot_complete(self):
        with self.assertRaisesRegex(ValueError, 'without durable readback'):
            self.publish(lambda *a, **k: SimpleNamespace(returncode=0))
        self.assertEqual(['started'], [e['state'] for e in journal.read(self.journal)['events']])

    def test_changed_receipt_blocks_reuse_before_remote_call(self):
        self.publish(self.success)
        self.receipt.write_text('tampered')
        with patch.object(control.subprocess, 'run') as mocked:
            with self.assertRaisesRegex(ValueError, 'evidence changed'):
                control.publish(self.args)
            mocked.assert_not_called()

    def test_interrupt_is_recorded_then_explicit_retry_reconciles(self):
        result, _ = self.publish(KeyboardInterrupt())
        self.assertEqual(130, result)
        self.assertEqual('cancelled', journal.read(self.journal)['events'][-1]['state'])
        result, _ = self.publish(self.success)
        self.assertEqual(0, result)


if __name__ == '__main__':
    unittest.main()
