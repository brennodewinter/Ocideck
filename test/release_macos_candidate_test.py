"""macOS signing boundaries without building or contacting Apple."""
import sys
from pathlib import Path
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
