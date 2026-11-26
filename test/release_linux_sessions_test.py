"""Both native Linux sessions must reject fatal startup logs."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    'linux_startup_log', Path(__file__).resolve().parents[1] / 'scripts/linux_startup_log.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class SessionStartupTest(unittest.TestCase):
    def test_first_frame_is_required_and_fatal_errors_win_even_after_it(self):
        with tempfile.TemporaryDirectory() as work:
            log = Path(work) / 'startup.log'
            log.write_text('2026-11-26T00:00:00 INFO opstart: bootstrap\n')
            self.assertFalse(probe.startup_frame(log))
            frame = '2026-11-26T00:00:01 INFO opstart: eerste frame (+100 ms)\n'
            log.write_text(frame)
            self.assertTrue(probe.startup_frame(log))
            for message in ['ERROR Uncaught zone error',
                            'WARN opstart: nog geen eerste frame na 10 s',
                            'WARN opstart: nog geen eerste frame na 10 s (watchdog)']:
                with self.subTest(message=message):
                    log.write_text(frame + '2026-11-26T00:00:02 ' + message + '\n')
                    with self.assertRaisesRegex(RuntimeError, 'startup error'):
                        probe.startup_frame(log)

    def test_user_text_and_unrelated_warnings_are_not_startup_failures(self):
        with tempfile.TemporaryDirectory() as work:
            log = Path(work) / 'startup.log'
            log.write_text('2026-11-26T00:00:00 WARN optional font unavailable\n'
                           '2026-11-26T00:00:01 INFO user text: ERROR example\n'
                           '2026-11-26T00:00:02 INFO opstart: eerste frame (+120 ms)\n')
            self.assertTrue(probe.startup_frame(log))
