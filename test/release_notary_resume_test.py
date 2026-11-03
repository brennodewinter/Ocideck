"""Notary recovery tests with fake Apple commands; never calls Apple or builds."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tool'))
import notary_submission as notary
from release_journal import locked

ID = '12345678-1234-1234-1234-123456789abc'


class NotaryResumeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        app = self.root / 'OciDeck.app'
        app.mkdir()
        (app / 'executable').write_bytes(b'signed app')
        archive = self.root / 'OciDeck.zip'
        archive.write_bytes(b'immutable original submission')
        self.args = SimpleNamespace(mode='submit', state=self.root / 'state.submission.json', archive=archive,
                                    app=app, profile='profile', keychain='/keychain', identity='Developer ID Application: Test')
        self.calls = []
        self.status = 'Accepted'

    def command(self, args):
        self.calls.append(args)
        if args[0] == 'codesign':
            return SimpleNamespace(returncode=0, stdout='', stderr='Authority=' + self.args.identity + '\n')
        if args[:3] == ['xcrun', 'notarytool', 'submit']:
            saved = notary.read_state(self.args.state)
            self.assertEqual('submitting', saved['status'])
            return SimpleNamespace(returncode=0, stdout=json.dumps({'id': ID}), stderr='')
        if args[:3] == ['xcrun', 'notarytool', 'info']:
            self.assertEqual(ID, notary.read_state(self.args.state)['submission_id'])
            return SimpleNamespace(returncode=0, stdout=json.dumps({'id': ID, 'status': self.status}), stderr='')
        if args[:3] == ['xcrun', 'notarytool', 'wait']:
            return SimpleNamespace(returncode=1, stdout=json.dumps({'id': ID, 'status': 'In Progress'}), stderr='timeout')
        if args[:3] == ['xcrun', 'stapler', 'staple']:
            self.assertEqual(b'signed app', (self.args.app / 'executable').read_bytes())
            (self.args.app / 'executable').write_bytes(b'signed app with stapled ticket')
        if args[0] == 'ditto':
            Path(args[-1]).write_bytes(b'complete stapled distribution archive')
        if args[:3] == ['xcrun', 'notarytool', 'log']:
            return SimpleNamespace(returncode=0, stdout=json.dumps({'issues': [
                {'code': 4000, 'severity': 'error', 'message': 'sensitive account data', 'path': '/private/account'}]}), stderr='')
        return SimpleNamespace(returncode=0, stdout='', stderr='')

    def run_notary(self):
        with patch.object(notary, 'command', side_effect=self.command):
            return notary.run(self.args)

    def test_id_and_hash_saved_before_wait_resume_does_not_submit(self):
        self.status = 'In Progress'
        original = self.args.archive.read_bytes()
        with self.assertRaisesRegex(ValueError, 'pending'):
            self.run_notary()
        saved = notary.read_state(self.args.state)
        self.assertEqual(ID, saved['submission_id'])
        self.assertEqual('pending', saved['status'])
        self.calls.clear()
        self.status, self.args.mode = 'Accepted', 'resume'
        self.assertEqual('stapled', self.run_notary()['status'])
        self.assertFalse(any(c[:3] == ['xcrun', 'notarytool', 'submit'] for c in self.calls))
        self.assertEqual(original, self.args.archive.read_bytes())
        self.calls.clear()
        self.run_notary()
        self.assertFalse(any(c[:3] == ['xcrun', 'stapler', 'staple'] for c in self.calls))

    def test_lost_submit_response_blocks_auto_resubmit(self):
        original = self.command
        def lost(args):
            if args[:3] == ['xcrun', 'notarytool', 'submit']:
                return SimpleNamespace(returncode=1, stdout='', stderr='sensitive account data')
            return original(args)
        with patch.object(notary, 'command', side_effect=lost):
            with self.assertRaisesRegex(ValueError, 'unknown'):
                notary.run(self.args)
        self.assertEqual('unknown', notary.read_state(self.args.state)['status'])
        self.assertNotIn('sensitive', self.args.state.read_text())
        self.args.mode = 'resume'
        with self.assertRaisesRegex(ValueError, 'unknown'):
            self.run_notary()
        self.args.mode = 'submit'
        with self.assertRaisesRegex(ValueError, 'state exists'):
            self.run_notary()

    def test_identity_and_bytes_mismatch_refused(self):
        self.run_notary()
        self.args.mode = 'resume'
        for key, value in [('profile', 'different'), ('keychain', '/other'), ('identity', 'other')]:
            old = getattr(self.args, key)
            setattr(self.args, key, value)
            with self.assertRaisesRegex(ValueError, 'changed'):
                self.run_notary()
            setattr(self.args, key, old)
        self.args.archive.write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'changed'):
            self.run_notary()

    def test_saved_app_tamper_rejected_before_apple(self):
        self.run_notary()
        self.args.mode = 'resume'
        (self.args.app / 'executable').write_bytes(b'tampered')
        self.calls.clear()
        with self.assertRaisesRegex(ValueError, 'changed'):
            self.run_notary()
        self.assertFalse(any(c[0] == 'xcrun' for c in self.calls))

    def test_unrecognized_status_cannot_staple_or_resubmit(self):
        self.status = 'Future State'
        with self.assertRaisesRegex(ValueError, 'unknown Apple status'):
            self.run_notary()
        self.assertEqual('submitted', notary.read_state(self.args.state)['status'])
        self.assertFalse(any(c[:3] == ['xcrun', 'stapler', 'staple'] for c in self.calls))

    def test_rejected_is_typed_durable_without_raw_credentials(self):
        self.status = 'Invalid'
        with self.assertRaisesRegex(ValueError, 'rejected'):
            self.run_notary()
        self.assertEqual('invalid', notary.read_state(self.args.state)['status'])
        summary = json.loads(Path(str(self.args.state) + '.rejection.json').read_text())
        self.assertEqual({'schema': 1, 'submission_id': ID, 'status': 'Invalid',
                          'issues': [{'code': 4000, 'severity': 'error'}]}, summary)
        self.assertFalse(any(c[:3] == ['xcrun', 'stapler', 'staple'] for c in self.calls))

    def test_corruption_and_concurrent_writer_refused(self):
        self.run_notary()
        self.args.mode = 'resume'
        with locked(self.args.state):
            with self.assertRaisesRegex(ValueError, 'locked'):
                self.run_notary()
        data = json.loads(self.args.state.read_text())
        data['schema'] = True
        self.args.state.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'schema'):
            self.run_notary()

    def test_guard_preserves_pending_app_before_new_clean(self):
        self.status = 'In Progress'
        with self.assertRaises(ValueError):
            self.run_notary()
        with self.assertRaisesRegex(ValueError, 'unfinished'):
            notary.guard(self.root)

    def test_mutating_staple_crash_restores_saved_app_without_resubmit(self):
        write = notary.atomic_write
        def crash_after_staple(path, data):
            if data.get('status') == 'stapled':
                raise OSError('crash after staple before state commit')
            return write(path, data)
        with patch.object(notary, 'atomic_write', side_effect=crash_after_staple):
            with self.assertRaisesRegex(OSError, 'crash after staple'):
                self.run_notary()
        self.assertEqual('stapling', notary.read_state(self.args.state)['status'])
        self.assertEqual(b'signed app with stapled ticket', (self.args.app / 'executable').read_bytes())
        self.args.mode = 'resume'
        self.calls.clear()
        self.assertEqual('stapled', self.run_notary()['status'])
        self.assertFalse(any(c[:3] == ['xcrun', 'notarytool', 'submit'] for c in self.calls))
        self.assertEqual(b'immutable original submission', self.args.archive.read_bytes())

    def test_corrupt_pre_staple_backup_never_restored(self):
        original = self.command
        def fail_staple(args):
            if args[:3] == ['xcrun', 'stapler', 'staple']:
                return SimpleNamespace(returncode=1, stdout='', stderr='failed')
            return original(args)
        with patch.object(notary, 'command', side_effect=fail_staple):
            with self.assertRaisesRegex(ValueError, 'stapling failed'):
                notary.run(self.args)
        backup = Path(str(self.args.state) + '.pre-staple.app')
        (backup / 'executable').write_bytes(b'tampered backup')
        self.args.mode = 'resume'
        self.calls.clear()
        with self.assertRaisesRegex(ValueError, 'backup differs'):
            self.run_notary()
        self.assertEqual([], self.calls)
        self.assertEqual(b'signed app', (self.args.app / 'executable').read_bytes())

    def test_package_directory_is_durable_before_receipt(self):
        self.run_notary()
        self.args.mode = 'package'
        self.args.package = self.root / 'dist' / 'release.zip'
        events = []
        original_write = notary.atomic_write
        original_sync = notary.sync_directory
        def sync(path):
            events.append(('sync', Path(path)))
            return original_sync(path)
        def write(path, data):
            if str(path).endswith('.package.json'):
                self.assertIn(('sync', self.args.package.parent), events)
                self.assertTrue(self.args.package.with_name('.release.zip.pending').is_file())
            return original_write(path, data)
        with patch.object(notary, 'sync_directory', side_effect=sync), patch.object(notary, 'atomic_write', side_effect=write):
            self.run_notary()

    def test_package_crash_after_rename_repairs_checksum_without_repacking(self):
        self.run_notary()
        self.args.mode = 'package'
        self.args.package = self.root / 'dist' / 'release.zip'
        replace = notary.os.replace
        def crash_before_checksum(source, target):
            if Path(target).name == 'SHA256SUMS':
                raise OSError('crash before checksum commit')
            return replace(source, target)
        with patch.object(notary.os, 'replace', side_effect=crash_before_checksum):
            with self.assertRaisesRegex(OSError, 'checksum commit'):
                self.run_notary()
        self.assertTrue(self.args.package.is_file())
        self.assertFalse((self.args.package.parent / 'SHA256SUMS').exists())
        self.assertEqual('packaging', notary.read_state(self.args.state)['status'])
        with self.assertRaisesRegex(ValueError, 'unfinished'):
            notary.guard(self.root)
        self.calls.clear()
        self.run_notary()
        self.assertFalse(any(c[0] == 'ditto' for c in self.calls))
        self.assertTrue((self.args.package.parent / 'SHA256SUMS').is_file())

    def test_partial_package_before_receipt_is_retried_from_saved_app(self):
        self.run_notary()
        self.args.mode = 'package'
        self.args.package = self.root / 'dist' / 'release.zip'
        original = self.command
        def partial(args):
            if args[0] == 'ditto':
                Path(args[-1]).write_bytes(b'partial')
                return SimpleNamespace(returncode=1, stdout='', stderr='interrupted')
            return original(args)
        with patch.object(notary, 'command', side_effect=partial):
            with self.assertRaisesRegex(ValueError, 'creation failed'):
                notary.run(self.args)
        self.assertFalse(self.args.package.exists())
        self.run_notary()
        self.assertEqual(b'complete stapled distribution archive', self.args.package.read_bytes())
        self.assertEqual(b'immutable original submission', self.args.archive.read_bytes())

    def test_guard_is_central_even_if_unsupported_state_env_changes(self):
        self.status = 'In Progress'
        with self.assertRaises(ValueError):
            self.run_notary()
        with patch.dict(os.environ, {'OCIDECK_NOTARY_STATE': str(self.root / 'outside.json')}):
            with self.assertRaisesRegex(ValueError, 'unfinished'):
                notary.guard(self.root)
        with self.assertRaisesRegex(ValueError, 'unfinished'):
            notary.guard(self.root)
        self.assertNotIn('OCIDECK_NOTARY_STATE', (ROOT / 'scripts/notarize_macos.sh').read_text())

    def test_shell_resume_skips_build_sign_and_zip(self):
        scripts = self.root / 'scripts'
        scripts.mkdir()
        shutil.copyfile(ROOT / 'scripts/notarize_macos.sh', scripts / 'notarize_macos.sh')
        bindir = self.root / 'bin'
        bindir.mkdir()
        log = self.root / 'commands.log'
        handlers = {
            'uname': 'echo Darwin',
            'git': f'case "$*" in *--git-path*) echo "{self.root}/notary";; *) echo abc123;; esac',
            'security': 'echo "Developer ID Application: Test"',
            'codesign': 'echo forbidden-codesign >&2; exit 91',
            'ditto': 'echo forbidden-zip >&2; exit 92',
            'python3': f'printf "python %s\\n" "$*" >>"{log}"',
            'xcrun': 'exit 93',
            'spctl': 'exit 0',
        }
        for name, body in handlers.items():
            path = bindir / name
            path.write_text('#!/bin/bash\n' + body + '\n')
            path.chmod(0o755)
        env = dict(os.environ, PATH=str(bindir) + ':/usr/bin:/bin', OCIDECK_NOTARY_KEYCHAIN='/keychain',
                   OCIDECK_SIGN_IDENTITY='Developer ID Application: Test', OCIDECK_SKIP_LAUNCH_PROBE='1')
        result = subprocess.run(['bash', str(scripts / 'notarize_macos.sh'), '--resume-notary', '--no-package'],
                                env=env, capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn('notary_submission.py resume', log.read_text())
        self.assertNotIn('forbidden', result.stderr)


if __name__ == '__main__':
    unittest.main()
