"""Phase-scoped readiness and bounded factual progress, without network mutations."""
import sys
from pathlib import Path
from unittest import TestCase, main
from unittest.mock import patch
from types import SimpleNamespace
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tool'))
import release_channel_capabilities as subject


class CapabilitiesTest(TestCase):
    def api(self, channel='linux-rpm', secrets=()):
        wanted = {'channel': channel, 'source': 'a' * 40, 'frozen_ref': 'frozen'}
        responses = {'': {'permissions': {'push': True}},
                     '/actions/runners?visible=true&limit=100&page=1': [{'status': 'active', 'labels': ['docker:docker://pinned']}],
                     '/actions/secrets?page=1&limit=100': [{'name': name} for name in secrets],
                     '/git/refs/heads/frozen': {'object': {'sha': 'a' * 40}}}
        return SimpleNamespace(get=lambda path: responses[path]), wanted

    def test_linux_needs_no_windows_or_mac_credentials(self):
        api, wanted = self.api()
        self.assertTrue(subject.inspect(api, wanted)['ready'])

    def test_windows_missing_secret_blocks(self):
        api, wanted = self.api('windows')
        self.assertEqual(subject.inspect(api, wanted)['blockers'], ['missing repository secret GH_DISPATCH_TOKEN'])

    def test_unknown_metadata_blocks(self):
        api, wanted = self.api()
        api.get = lambda _: (_ for _ in ()).throw(OSError('unreachable'))
        self.assertFalse(subject.inspect(api, wanted)['ready'])

    def test_asset_publish_needs_no_build_runner_or_github_secret(self):
        api, wanted = self.api('windows')
        original = api.get
        api.get = lambda path: self.fail('irrelevant prerequisite queried') if '/actions/' in path else original(path)
        self.assertTrue(subject.inspect(api, wanted, 'assets')['ready'])

    def test_website_requires_only_selected_deploy_credentials(self):
        api, wanted = self.api()
        result = subject.inspect(api, wanted, 'website')
        self.assertEqual(result['required_secret_names'], ['WEBSITE_REPO_KEY_V1', 'WEBSITE_REPO_KNOWN_HOSTS_V1'])
        self.assertFalse(result['ready'])

    def test_first_error_is_found_before_long_successful_tail(self):
        self.assertEqual(subject.first_failure('before\n::error::first\n' + 'ok\n' * 10000)['line'], 2)
        self.assertEqual(subject.first_failure('2026-11-03T17:29:35Z Traceback (most recent call last):\n' + 'cleanup\n' * 10000)['line'], 1)

    def test_missing_times_are_unknown_not_zero(self):
        self.assertIsNone(subject.timing({})['queue_seconds'])
        self.assertEqual(subject.timing({'created': '2026-11-03T10:00:00Z', 'started': '2026-11-03T10:00:02Z'})['queue_seconds'], 2)

    def test_phase_wall_time_preserves_original_start_and_unknown_wait(self):
        events = [{'phase': 'build', 'state': 'started', 'at': '2026-11-03T10:00:00+00:00'},
                  {'phase': 'build', 'state': 'failed', 'at': '2026-11-03T10:02:00+00:00'},
                  {'phase': 'build', 'state': 'started', 'at': '2026-11-03T11:00:00+00:00'}]
        value = subject.history_timing(events)
        self.assertEqual(value['original_start'], events[0]['at'])
        self.assertEqual(value['phases'][0]['wall_seconds'], 120)
        self.assertEqual(value['phases'][0]['state'], 'failed')
        self.assertIsNone(value['phases'][1]['wall_seconds'])
        self.assertIsNone(value['manual_wait_seconds'])
        self.assertIsNone(value['active_machine_seconds'])

    def test_space_and_symlink_rejected_before_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = str(Path(directory).resolve())
            path = Path(directory) / 'not-created'
            with patch.object(subject.shutil, 'disk_usage', return_value=SimpleNamespace(free=1)):
                with self.assertRaisesRegex(ValueError, 'insufficient'):
                    subject.require_space(path, 100)
            self.assertFalse(path.exists())
            link = Path(directory) / 'link'
            link.symlink_to(directory)
            with self.assertRaisesRegex(ValueError, 'symlink'):
                subject.require_space(link / 'child', 1)


if __name__ == '__main__':
    main()
