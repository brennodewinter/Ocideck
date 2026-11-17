"""Real subprocess checks for the CI diagnostic boundary; no runner restart."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / 'tool/ci_gate.py'


@unittest.skipUnless(hasattr(os, 'killpg'), 'the host CI wrapper is POSIX-only')
class GateDiagnosticsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ocideck-gate-test-')
        self.directory = Path(self.temp.name)
        self.command = [sys.executable, str(WRAPPER), '--label', 'probe', '--directory',
                        str(self.directory), '--heartbeat-seconds', '0.05', '--terminate-grace', '0.2', '--']

    def tearDown(self):
        self.temp.cleanup()

    def status(self):
        return json.loads((self.directory / 'probe.status.json').read_text())

    def invoke(self, code, **kwargs):
        return subprocess.run(self.command + [sys.executable, '-c', code],
                              capture_output=True, text=True, timeout=10, **kwargs)

    def test_success_keeps_both_streams_and_heartbeat(self):
        result = self.invoke('import sys,time; print("out"); print("err",file=sys.stderr); time.sleep(.16)')
        self.assertEqual(result.returncode, 0, result.stderr)
        status = self.status()
        self.assertEqual(status['state'], 'passed')
        self.assertEqual(status['child_exit_code'], 0)
        self.assertTrue(status['logs_complete'])
        self.assertEqual((self.directory / 'probe.stdout.log').read_text(), 'out\n')
        self.assertEqual((self.directory / 'probe.stderr.log').read_text(), 'err\n')
        self.assertGreaterEqual((self.directory / 'probe.heartbeat.log').read_text().count('running'), 2)

    def test_failure_is_not_retried_or_turned_green(self):
        counter = self.directory / 'calls'
        code = ('from pathlib import Path; import sys; '
                f'p=Path({str(counter)!r}); p.write_text(p.read_text()+"x" if p.exists() else "x"); '
                'print("test_failed", file=sys.stderr); sys.exit(7)')
        result = self.invoke(code)
        self.assertEqual(result.returncode, 7)
        self.assertEqual(self.status()['exit_code'], 7)
        self.assertEqual(self.status()['state'], 'failed')
        self.assertEqual(counter.read_text(), 'x')
        self.assertIn('test_failed', (self.directory / 'probe.stderr.log').read_text())

    def test_secrets_are_redacted_in_logs_console_and_status(self):
        secret = 'ocideck-fixture-secret-827341'
        result = self.invoke('import os,sys; print(os.environ["CI_TEST_SECRET"]); '
                             'print("Authorization: Bearer unlisted-secret",file=sys.stderr)',
                             env=dict(os.environ, CI_TEST_SECRET=secret))
        self.assertEqual(result.returncode, 0)
        self.assertNotIn(secret, result.stdout + result.stderr)
        for path in self.directory.iterdir():
            text = path.read_text()
            self.assertNotIn(secret, text)
            self.assertNotIn('unlisted-secret', text)
        self.assertIn('[REDACTED]', (self.directory / 'probe.stdout.log').read_text())

    def test_signal_records_interruption_and_reaps_child(self):
        process = subprocess.Popen(self.command + [sys.executable, '-c',
            'import time; print("ready",flush=True); time.sleep(30)'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                path = self.directory / 'probe.stdout.log'
                if path.exists() and 'ready' in path.read_text():
                    break
                time.sleep(.01)
            else:
                self.fail('child did not start')
            pid = self.status()['pid']
            process.send_signal(signal.SIGTERM)
            out, err = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 128 + signal.SIGTERM, out + err)
            status = self.status()
            self.assertEqual(status['state'], 'interrupted')
            self.assertEqual(status['signal'], signal.SIGTERM)
            self.assertEqual(status['child_exit_code'], -signal.SIGTERM)
            with self.assertRaises(ProcessLookupError):
                os.kill(pid, 0)
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()

    def test_stubborn_child_is_killed_after_signal_grace(self):
        process = subprocess.Popen(self.command + [sys.executable, '-c',
            'import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); print("ready",flush=True); time.sleep(30)'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                path = self.directory / 'probe.stdout.log'
                if path.exists() and 'ready' in path.read_text():
                    break
                time.sleep(.01)
            else:
                self.fail('child did not start')
            process.send_signal(signal.SIGTERM)
            process.communicate(timeout=5)
            self.assertEqual(process.returncode, 143)
            self.assertEqual(self.status()['child_exit_code'], -signal.SIGKILL)
            self.assertEqual(self.status()['state'], 'interrupted')
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()

    def test_child_signal_is_reported_even_without_signal_to_wrapper(self):
        result = self.invoke('import os,signal; os.kill(os.getpid(), signal.SIGTERM)')
        self.assertEqual(result.returncode, 143)
        self.assertEqual(self.status()['state'], 'interrupted')
        self.assertEqual(self.status()['signal'], signal.SIGTERM)

    def test_missing_executable_is_a_diagnosed_failure(self):
        result = subprocess.run(self.command + [str(self.directory / 'missing')],
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 127)
        self.assertEqual(self.status()['state'], 'failed')
        self.assertIn('error', self.status())

    def test_workflow_always_uploads_diagnostics_and_python_names_cases(self):
        workflow = (ROOT / '.forgejo/workflows/ci.yml').read_text()
        self.assertIn('if: always()', workflow)
        self.assertIn('path: build/ci-diagnostics/', workflow)
        for label in ['dependencies', 'gate', 'python']:
            self.assertIn('tool/ci_gate.py --label ' + label, workflow)
        self.assertIn("unittest discover -s test -p 'release_*_test.py' -v", (ROOT / 'Makefile').read_text())


if __name__ == '__main__':
    unittest.main()
