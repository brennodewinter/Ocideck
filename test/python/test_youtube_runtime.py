import importlib.util
import os
import pathlib
import sys
import tempfile
import time
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[2] / 'testbed/youtube-source'
for name in ['egress_proxy', 'register_decoder', 'source_runtime']:
    spec = importlib.util.spec_from_file_location(name, ROOT / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
runtime = sys.modules['source_runtime']


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.backend = runtime.YoutubeRuntime.__new__(runtime.YoutubeRuntime)
        self.backend.node = pathlib.Path('/not-executed-node')
        self.backend.decoder = None

    def test_invalid_options_do_not_start_a_proxy_or_process(self):
        for action, fields in [
            ('metadata', {'video_id': '--exec=bad'}),
            ('metadata', {'video_id': 'M7lc1UVf-VE', 'url': 'http://localhost'}),
            ('captions', {'video_id': 'M7lc1UVf-VE', 'track': '--exec'}),
            ('audio', {'video_id': 'M7lc1UVf-VE', 'start_ms': False, 'end_ms': 0}),
            ('audio', {'video_id': 'M7lc1UVf-VE', 'start_ms': 10, 'end_ms': 20}),
        ]:
            with mock.patch.object(runtime, 'YoutubeEgressProxy') as proxy:
                with self.assertRaises(runtime.SourceFailure):
                    self.backend.execute(action, fields)
                proxy.assert_not_called()

    def test_live_and_access_restrictions_are_explicit(self):
        base = {'id': 'M7lc1UVf-VE', 'duration': 100, 'live_status': 'not_live'}
        for status in ['is_live', 'is_upcoming', 'post_live']:
            with self.assertRaises(runtime.SourceFailure) as error:
                self.backend._validate_video({**base, 'live_status': status}, base['id'])
            self.assertEqual(error.exception.code, 'live')
        with self.assertRaises(runtime.SourceFailure) as error:
            self.backend._validate_video({**base, 'availability': 'private'}, base['id'])
        self.assertEqual(error.exception.code, 'access')
        self.backend._validate_video({**base, 'live_status': 'was_live'}, base['id'])

    def test_process_group_cancel_reaps_worker_and_its_child(self):
        with tempfile.TemporaryDirectory() as name:
            directory = pathlib.Path(name)
            marker = directory / 'child-pid'
            script = ("import subprocess,sys,time,signal,pathlib\n"
                      "child=subprocess.Popen([sys.executable,'-I','-c','import time;time.sleep(60)'])\n"
                      "def stop(*_):\n child.wait(timeout=1);sys.exit(0)\n"
                      "signal.signal(signal.SIGTERM,stop)\n"
                      f"pathlib.Path({str(marker)!r}).write_text(str(child.pid))\n"
                      "time.sleep(60)\n")
            original = runtime.subprocess.Popen
            started = []

            def start(*args, **kwargs):
                process = original(*args, **kwargs)
                started.append(process)
                return process

            with mock.patch.object(runtime.subprocess, 'Popen', side_effect=start):
                with self.assertRaises(runtime.SourceFailure) as error:
                    self.backend._run([sys.executable, '-I', '-c', script], directory,
                                      time.monotonic() + 5, marker.exists)
            self.assertEqual(error.exception.code, 'cancelled')
            self.assertIsNotNone(started[0].returncode)
            with self.assertRaises(ProcessLookupError):
                os.kill(int(marker.read_text()), 0)

    def test_closed_output_does_not_hide_a_still_running_worker(self):
        with tempfile.TemporaryDirectory() as name:
            script = 'import os,time;os.close(1);os.close(2);time.sleep(60)'
            start = time.monotonic()
            with self.assertRaises(runtime.SourceFailure) as error:
                self.backend._run([sys.executable, '-I', '-c', script], pathlib.Path(name),
                                  start + .2, lambda: False)
            self.assertEqual(error.exception.code, 'network')
            self.assertLess(time.monotonic() - start, 3)

    def test_excessive_worker_output_is_bounded_and_stopped(self):
        with tempfile.TemporaryDirectory() as name:
            script = "import sys,time;sys.stdout.buffer.write(b'x'*(4*1024*1024+1));sys.stdout.flush();time.sleep(60)"
            with self.assertRaises(runtime.SourceFailure) as error:
                self.backend._run([sys.executable, '-I', '-c', script], pathlib.Path(name),
                                  time.monotonic() + 5, lambda: False)
            self.assertEqual(error.exception.code, 'tooLarge')


if __name__ == '__main__':
    unittest.main()
