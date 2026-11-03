"""Lightweight website dispatch/input contracts; no website build or network."""
import json
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class WebsiteWorkflowTest(unittest.TestCase):
    def test_workflow_is_linux_trusted_main_and_uses_scoped_credentials(self):
        text = (ROOT / '.forgejo/workflows/website-downloads.yml').read_text()
        for expected in ("github.ref == 'refs/heads/main'", 'runs-on: docker',
                         'WEBSITE_REPO_KEY_V1', 'WEBSITE_REPO_KNOWN_HOSTS_V1',
                         'StrictHostKeyChecking yes', 'Port 2222', 'chmod 700',
                         'git clone --depth 1 --single-branch --branch main',
                         'trap ', 'scripts/bump-ocideck.sh "$VERSION" "$CHANNEL"',
                         'python3 scripts/improve_public_output.py',
                         'python3 scripts/check_i18n_parity.py',
                         'test_bump_ocideck_channel.py', 'git push origin HEAD:refs/heads/main'):
            self.assertIn(expected, text)
        self.assertNotIn('runs-on: macos', text)
        self.assertNotIn('DEPLOY_KEY', text)
        self.assertNotIn('push --force', text)
        self.assertLess(text.index('test_bump_ocideck_channel.py'), text.index('git commit'))
        self.assertLess(text.index('git fetch origin main'), text.index('git commit'))

    def test_untrusted_inputs_are_rejected_without_execution(self):
        text = (ROOT / '.forgejo/workflows/website-downloads.yml').read_text()
        body = text.split('run: |', 1)[1].split('      - name:', 1)[0]
        body = '\n'.join(line[10:] for line in body.splitlines())
        for tag, channel, success in [('v0.7.7', 'windows', True), ('v1.2.3', 'all', True),
                                      ('v01.2.3', 'web', False), ('v1.2.3; touch /tmp/no', 'all', False),
                                      ('v1.2.3', 'windows; true', False), ('v1.2.3-rc1', 'all', False)]:
            with self.subTest(tag=tag, channel=channel):
                result = subprocess.run(['bash', '-c', body], env={'RELEASE_TAG': tag, 'CHANNEL': channel,
                    'OPERATION_ID': '', 'OCIDECK_EXPECTED_CURRENT_TAG': ''})
                self.assertEqual(result.returncode == 0, success)

    def test_rollback_requires_canonical_current_tag_and_operation(self):
        text = (ROOT / '.forgejo/workflows/website-downloads.yml').read_text()
        body = text.split('run: |', 1)[1].split('      - name:', 1)[0]
        body = '\n'.join(line[10:] for line in body.splitlines())
        for current, operation, success in [('v1.2.4', 'restore-1', True),
                ('v1.2.4', '', False), ('v01.2.4', 'restore-1', False),
                ('v1.2.4', 'x; true', False)]:
            result = subprocess.run(['bash', '-c', body], env={
                'RELEASE_TAG': 'v1.2.3', 'CHANNEL': 'macos',
                'OPERATION_ID': operation, 'OCIDECK_EXPECTED_CURRENT_TAG': current})
            self.assertEqual(result.returncode == 0, success)

    def test_main_runs_are_selected_by_exact_tag_and_legacy_all_channel(self):
        text = (ROOT / 'scripts/release_auto.sh').read_text()
        body = re.search(r'latest_website_download_run\(\) \{\n.*?\n\}', text, re.S)[0]
        runs = [{'id': 4, 'workflow_id': 'website-downloads.yml', 'prettyref': 'main'},
                {'id': 3, 'workflow_id': 'website-downloads.yml', 'prettyref': 'main'}]
        details = {4: dict(runs[0], status='running', event_payload={'inputs': {'tag': 'v9.9.9', 'channel': 'windows'}}),
                   3: dict(runs[1], status='success', event_payload={'inputs': {'tag': 'v9.9.9', 'channel': 'all'}})}
        api = 'api() { case "$2" in\n'
        api += "'/actions/runs?limit=50&page=1&workflow_id=website-downloads.yml') cat <<'JSON'\n" + json.dumps({'workflow_runs': runs}) + '\nJSON\n;;\n'
        for run_id, detail in details.items():
            api += f"/actions/runs/{run_id}) cat <<'JSON'\n" + json.dumps(detail) + '\nJSON\n;;\n'
        api += '*) return 1;; esac; }\n'
        result = subprocess.run(['bash', '-c', api + body + '\nTAG=v9.9.9\nlatest_website_download_run'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), '3|success')
        self.assertEqual(text.count('\\"channel\\":\\"all\\"'), 2)


if __name__ == '__main__':
    unittest.main()
