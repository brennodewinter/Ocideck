"""Lightweight local journal fault tests, without runners or network."""
from pathlib import Path
import copy
import json
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tool'))
import release_journal as journal


class ReleaseJournalTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.workflow = self.base / 'workflow.yml'
        self.workflow.write_text('jobs: build')
        self.proof = self.base / 'proof.json'
        self.proof.write_text('{"verified":true}')
        self.args = SimpleNamespace(journal=self.base / 'journal.json', tag='v0.7.7', sha='a' * 40,
                                    channel='web', workflow=self.workflow, phase='build', state='started', evidence=[])

    def test_identity_immutable_and_initialize_idempotent(self):
        first = journal.initialize(self.args)
        self.assertEqual(first, journal.initialize(self.args))
        for name, value in [('sha', 'b' * 40), ('channel', 'macos'), ('tag', 'v0.7.8')]:
            old = getattr(self.args, name)
            setattr(self.args, name, value)
            with self.assertRaises(ValueError):
                journal.initialize(self.args)
            setattr(self.args, name, old)
        self.workflow.write_text('jobs: changed')
        with self.assertRaises(ValueError):
            journal.initialize(self.args)

    def test_start_complete_verify_and_repeat(self):
        journal.initialize(self.args)
        journal.record(self.args)
        self.assertEqual(1, len(journal.record(self.args)['events']))
        self.args.state = 'completed'
        self.args.evidence = [self.proof]
        result = journal.record(self.args)
        self.assertEqual(2, len(result['events']))
        self.assertEqual(result, journal.record(self.args))
        self.assertEqual({'valid': True, 'evidence_checked': 1}, journal.verify(result))
        self.proof.write_text('tampered')
        with self.assertRaises(ValueError):
            journal.verify(result)
        with self.assertRaises(ValueError):
            journal.record(self.args)

    def test_terminal_without_start_or_proof_rejected(self):
        journal.initialize(self.args)
        self.args.state = 'completed'
        with self.assertRaises(ValueError):
            journal.record(self.args)
        self.args.state = 'started'
        journal.record(self.args)
        self.args.state = 'completed'
        with self.assertRaises(ValueError):
            journal.record(self.args)

    def test_explicit_restart_after_failure(self):
        journal.initialize(self.args)
        journal.record(self.args)
        self.args.state = 'failed'
        journal.record(self.args)
        self.assertEqual(2, len(journal.read(self.args.journal)['events']))
        self.args.state = 'started'
        self.assertEqual(3, len(journal.record(self.args)['events']))

    def test_loaded_metadata_is_strict(self):
        journal.initialize(self.args)
        original = journal.record(self.args)
        mutations = [
            lambda d: d.update(schema=True),
            lambda d: d.update(extra='unexpected'),
            lambda d: d.update(tag=7),
            lambda d: d['events'][0].update(phase=[]),
            lambda d: d['events'][0].update(phase='../publish'),
            lambda d: d['events'][0].update(at=123),
            lambda d: d['events'][0].update(at='not a date'),
            lambda d: d['events'][0].update(at='2026-11-03T07:00:00'),
            lambda d: d['events'][0].update(at='2026-11-03T07:00:00+02:00'),
        ]
        for mutate in mutations:
            data = copy.deepcopy(original)
            mutate(data)
            self.args.journal.write_text(json.dumps(data))
            with self.assertRaises(ValueError):
                journal.read(self.args.journal)

    def test_evidence_parent_cannot_be_redirected(self):
        folder = self.base / 'evidence'
        folder.mkdir()
        proof = folder / 'proof.json'
        proof.write_text('verified')
        journal.initialize(self.args)
        journal.record(self.args)
        self.args.state = 'completed'
        self.args.evidence = [proof]
        result = journal.record(self.args)
        folder.rename(self.base / 'moved')
        folder.symlink_to(self.base / 'moved', target_is_directory=True)
        with self.assertRaises(ValueError):
            journal.verify(result)

    def test_lock_rejects_second_writer(self):
        with journal.locked(self.args.journal):
            with self.assertRaises(ValueError):
                journal.initialize(self.args)

    def test_crash_before_replace_preserves_previous_json(self):
        original = journal.initialize(self.args)
        with patch.object(journal.os, 'replace', side_effect=OSError('simulated crash')):
            with self.assertRaises(OSError):
                journal.record(self.args)
        self.assertEqual(original, journal.read(self.args.journal))
        self.assertEqual([], list(self.base.glob('.journal.json*')))

    def test_missing_or_symlink_evidence_rejected(self):
        journal.initialize(self.args)
        journal.record(self.args)
        self.args.state = 'completed'
        self.args.evidence = [self.proof]
        result = journal.record(self.args)
        self.proof.unlink()
        with self.assertRaises(OSError):
            journal.verify(result)
        self.proof.symlink_to(self.workflow)
        with self.assertRaises(ValueError):
            journal.verify(result)


if __name__ == '__main__':
    unittest.main()
