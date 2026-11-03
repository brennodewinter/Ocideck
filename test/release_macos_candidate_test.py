"""macOS signing boundaries without building or contacting Apple."""
import sys
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
import subprocess
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tool'))
import release_macos_candidate as mac

SHA = 'a' * 40


class FakeAPI:
    def __init__(self):
        self.status = 'success'
        self.jobs = [{'status': 'success'}]
        self.sha = SHA

    def get(self, path):
        if path.endswith('/jobs'):
            return self.jobs
        workflow = path.split('workflow_id=')[1]
        return {'workflow_runs': [{'id': 2, 'commit_sha': self.sha, 'workflow_id': workflow, 'status': self.status}]}


class MacCandidateTest(unittest.TestCase):
    def candidate(self, directory, state=True):
        home = Path(directory)
        cache = home / 'Library/Caches/OciDeck-macos-candidates'
        cache.mkdir(parents=True, mode=0o700)
        root = cache / SHA
        (root / '.git/ocideck-notary').mkdir(parents=True)
        source = root / '.git/ocideck-notary' / (SHA + '.submission.json')
        if state:
            source.write_text(json.dumps({'submission_id': 'same-apple-id', 'status': 'pending'}))
        (cache / (SHA + '.controller.json')).write_text(json.dumps(dict(source_sha=SHA, controller_sha=SHA, tag='v1.2.3')))
        archive = root / 'build/macos/dist/OciDeck-1.2.3-macos.zip'
        archive.parent.mkdir(parents=True)
        archive.write_bytes(b'same candidate archive')
        args = SimpleNamespace(tag='v1.2.3', sha=SHA, controller_sha=SHA, controller=home / 'controller',
            operation_id='operation-1', forge_run_id=20, previous_run_id=None, attempt_id=None,
            result=home / 'result/macos-operation.json', dist=home / 'dist')
        return home, cache, root, source, archive, args

    def source_command(self, arguments, _cwd):
        if arguments[:3] == ['git', 'rev-parse', 'HEAD']:
            return SHA
        if arguments[:2] == ['git', 'show']:
            return 'version: 1.2.3+1\n'
        if arguments[:2] == ['git', 'status']:
            return ''
        raise AssertionError('unexpected source operation: ' + repr(arguments))

    def test_pending_apple_receipt_continues_same_submission_and_finishes_consumer(self):
        with tempfile.TemporaryDirectory() as directory:
            home, _, _, source, archive, args = self.candidate(directory)
            def pending(arguments, **_kwargs):
                self.assertIn('--resume-notary', arguments)
                raise subprocess.CalledProcessError(1, arguments)
            with patch.object(mac.Path, 'home', return_value=home), patch.object(mac, 'Forgejo'), \
                 patch.object(mac, 'source_trusted'), patch.object(mac, 'quality'), \
                 patch.object(mac, 'command', side_effect=self.source_command), patch.object(mac, 'preflight'), \
                 patch.object(mac.subprocess, 'run', side_effect=pending), patch.object(mac, 'consume') as consume:
                result = mac.run(args)
            self.assertEqual('pending', result['outcome'])
            self.assertEqual('same-apple-id', result['submission_id'])
            consume.assert_not_called()
            original = args.result.read_bytes()
            args.forge_run_id, args.previous_run_id, args.attempt_id = 21, 20, 'attempt-1'
            def accepted(arguments, **_kwargs):
                self.assertIn('--resume-notary', arguments)
                self.assertNotIn('--skip-build', arguments)
                source.write_text(json.dumps({'submission_id': 'same-apple-id', 'status': 'stapled'}))
                return SimpleNamespace(returncode=0)
            with patch.object(mac.Path, 'home', return_value=home), patch.object(mac, 'Forgejo'), \
                 patch.object(mac, 'source_trusted'), patch.object(mac, 'quality'), \
                 patch.object(mac, 'command', side_effect=self.source_command), patch.object(mac, 'preflight'), \
                 patch.object(mac, 'continuation_state', return_value=original) as proof, \
                 patch.object(mac.subprocess, 'run', side_effect=accepted), patch.object(mac, 'consume') as consume:
                completed = mac.run(args)
            self.assertEqual('completed', completed['outcome'])
            self.assertEqual('same-apple-id', completed['submission_id'])
            self.assertEqual(21, completed['forge_run_id'])
            self.assertEqual((20, 21, 'attempt-1'), proof.call_args.args[-3:])
            consume.assert_called_once()
            self.assertEqual(archive.read_bytes(), (args.dist / 'ocideck-macos-1.2.3.zip').read_bytes())

    def test_continuation_refuses_missing_or_modified_saved_submission_before_keychain(self):
        for mutate in ('missing', 'changed'):
            with self.subTest(mutate=mutate), tempfile.TemporaryDirectory() as directory:
                home, _, _, source, _, args = self.candidate(directory)
                _, digest = mac.saved_notary(source)
                proof = json.dumps(dict(outcome='pending', submission_id='same-apple-id', notary_sha256=digest)).encode()
                if mutate == 'missing':
                    source.unlink()
                else:
                    source.write_text(json.dumps({'submission_id': 'different-id', 'status': 'pending'}))
                args.previous_run_id, args.attempt_id = 19, 'attempt-1'
                with patch.object(mac.Path, 'home', return_value=home), patch.object(mac, 'Forgejo'), \
                     patch.object(mac, 'source_trusted'), patch.object(mac, 'quality'), \
                     patch.object(mac, 'command', side_effect=self.source_command), \
                     patch.object(mac, 'continuation_state', return_value=proof), patch.object(mac, 'preflight') as preflight:
                    with self.assertRaisesRegex(ValueError, 'saved macOS submission'):
                        mac.run(args)
                preflight.assert_not_called()

    def test_storage_refusal_preserves_pending_proof_and_blocks_build(self):
        with tempfile.TemporaryDirectory() as directory:
            home, _, _, source, archive, args = self.candidate(directory)
            before = (source.read_bytes(), archive.read_bytes())
            args.sha = 'b' * 40
            with patch.object(mac.Path, 'home', return_value=home), patch.object(mac, 'Forgejo'), \
                 patch.object(mac, 'source_trusted'), patch.object(mac, 'quality'), \
                 patch.object(mac, 'command', side_effect=self.source_command) as command, patch.object(mac, 'preflight') as preflight, \
                 patch.object(mac.shutil, 'disk_usage', return_value=SimpleNamespace(free=0)):
                with self.assertRaisesRegex(ValueError, 'cache admission refused'):
                    mac.run(args)
            preflight.assert_not_called()
            self.assertEqual([['git', 'rev-parse', 'HEAD']], [call.args[0] for call in command.call_args_list])
            self.assertEqual(before, (source.read_bytes(), archive.read_bytes()))

    def test_existing_cache_bytes_count_against_admission_budget(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            (cache / 'retained-proof').write_bytes(b'preserve')
            with patch.object(mac, 'CACHE_BUDGET', 8), patch.object(mac, 'CANDIDATE_RESERVE', 2):
                with self.assertRaisesRegex(ValueError, 'cache admission refused'):
                    mac.admission(cache, cache / SHA)
            self.assertEqual(b'preserve', (cache / 'retained-proof').read_bytes())

    def test_cache_wide_admission_limit_and_lease_precede_clone(self):
        with tempfile.TemporaryDirectory() as directory:
            home, cache, _, source, archive, args = self.candidate(directory)
            (cache / ('b' * 40)).mkdir()
            with self.assertRaisesRegex(ValueError, 'maximum two candidates'):
                mac.admission(cache, cache / ('c' * 40))
            with patch.object(mac.Path, 'home', return_value=home), patch.object(mac, 'Forgejo'), \
                 patch.object(mac, 'source_trusted'), patch.object(mac, 'quality'), \
                 patch.object(mac, 'command', side_effect=self.source_command), patch.object(mac, 'preflight') as preflight, \
                 mac.locked(cache / 'admission'):
                with self.assertRaisesRegex(ValueError, 'locked'):
                    mac.run(args)
            preflight.assert_not_called()
            self.assertTrue(source.is_file() and archive.is_file())

    def test_all_exact_source_quality_gates_required(self):
        self.assertEqual(set(mac.quality(FakeAPI(), SHA)), {'static-gate.yml', 'scans.yml', 'macos-gate.yml'})

    def test_pending_failed_cancelled_do_not_reuse_old_success(self):
        for status in ('running', 'failure', 'cancelled', 'skipped'):
            api = FakeAPI()
            api.status = status
            with self.subTest(status=status), self.assertRaises(ValueError):
                mac.quality(api, SHA)

    def test_newer_pending_run_blocks_older_green(self):
        api = FakeAPI()
        original = api.get
        def response(path):
            data = original(path)
            if 'workflow_runs' in data:
                data['workflow_runs'].append(dict(data['workflow_runs'][0], id=3, status='running'))
            return data
        api.get = response
        with self.assertRaises(ValueError):
            mac.quality(api, SHA)

    def test_skipped_job_and_wrong_source_rejected(self):
        api = FakeAPI()
        api.jobs = [{'status': 'skipped'}]
        with self.assertRaises(ValueError):
            mac.quality(api, SHA)
        api.sha = 'b' * 40
        with self.assertRaises(ValueError):
            mac.quality(api, SHA)

    def test_arbitrary_frozen_branch_is_not_trusted(self):
        with patch.object(mac, 'command', side_effect=['', SHA + '\trefs/heads/untrusted']), \
                patch.object(mac.subprocess, 'run', return_value=type('Result', (), {'returncode': 1})()):
            with self.assertRaisesRegex(ValueError, 'protected-main'):
                mac.source_trusted(Path('/unused'), 'v1.2.3', SHA)

    def test_maintenance_requires_normal_merge_identical_tree(self):
        tip = SHA + '\trefs/heads/codex/release-base-v1.2.3'
        for parents, trees in [('one', []), ('one two', ['tree', 'different'])]:
            with patch.object(mac, 'command', side_effect=['', tip, parents, *trees]), \
                    patch.object(mac.subprocess, 'run', return_value=type('Result', (), {'returncode': 1})()):
                with self.assertRaises(ValueError):
                    mac.source_trusted(Path('/unused'), 'v1.2.3', SHA)

    def test_locked_private_key_blocks_before_notary_or_build(self):
        with patch.object(mac.shutil, 'copyfile'), patch.object(mac.subprocess, 'run',
                side_effect=subprocess.CalledProcessError(1, ['codesign'])) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                mac.preflight(Path('/controller'), Path('/source'), {})
            self.assertEqual(run.call_count, 1)
            self.assertEqual(run.call_args.args[0][0], 'codesign')
            self.assertIn('--timestamp=none', run.call_args.args[0])

    def test_signing_probe_then_apple_profile_checked_before_build(self):
        with patch.object(mac.shutil, 'copyfile'), patch.object(mac.subprocess, 'run') as run:
            mac.preflight(Path('/controller'), Path('/source'), {})
            self.assertEqual(run.call_count, 2)
            self.assertIn('--preflight', run.call_args.args[0])
            self.assertEqual(run.call_args.kwargs['cwd'], Path('/source'))

    def test_trusted_notary_script_uses_external_source_and_own_helper(self):
        root = Path(__file__).resolve().parents[1]
        script = (root / 'scripts/notarize_macos.sh').read_text()
        self.assertIn('cd "$SOURCE_ROOT"', script)
        self.assertNotIn('python3 tool/notary_submission.py', script)
        self.assertIn('python3 "$ROOT_DIR/tool/notary_submission.py"', script)


if __name__ == '__main__':
    unittest.main()
