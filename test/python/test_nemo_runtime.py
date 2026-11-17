"""Native runtime boundaries tested without any model or native dependency."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

source = Path(__file__).resolve().parents[2] / 'testbed/asr-diarization/nemo_runtime.py'
spec = importlib.util.spec_from_file_location('nemo_runtime_contract', source)
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimeBoundaryTest(unittest.TestCase):
    def prepare(self, root):
        files = []
        for index, relative in enumerate(sorted(runtime.LIBRARY_FILES)):
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            data = ('fixture library ' + str(index)).encode()
            path.write_bytes(data)
            files.append({'file': relative, 'bytes': len(data),
                          'sha256': hashlib.sha256(data).hexdigest()})
        notice = root / 'share/LICENSE'
        notice.parent.mkdir(parents=True)
        notice.write_text('fixture notice')
        manifest = {'schema': 1, 'revision': runtime.RUNTIME_REVISION, 'platform': 'macos-arm64',
                    'library': 'lib/libnemo_speech_asr_c.2.dylib', 'files': files,
                    'notice_sha256': {'share/LICENSE': hashlib.sha256(notice.read_bytes()).hexdigest()}}
        (root / 'ocideck-runtime.json').write_text(json.dumps(manifest))
        return manifest

    def test_tampered_library_refused_before_native_loading(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.prepare(root)
            self.assertTrue(runtime.verify_runtime(root).is_file())
            (root / 'lib/libnemo_speech_asr.dylib').write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'checksum'):
                runtime.verify_runtime(root)

    def test_missing_or_changed_notice_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.prepare(root)
            (root / 'share/LICENSE').write_text('different')
            with self.assertRaisesRegex(ValueError, 'notice'):
                runtime.verify_runtime(root)

    def test_notice_path_cannot_escape_installation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = self.prepare(root)
            manifest['notice_sha256'] = {'../outside': 'not-used'}
            (root / 'ocideck-runtime.json').write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, 'escapes'):
                runtime.verify_runtime(root)

    def test_bad_model_does_not_start_native_worker(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.prepare(root)
            model = root / 'bad-model.gguf'
            model.write_bytes(b'invalid model')
            with (mock.patch.object(runtime.platform, 'system', return_value='Darwin'),
                  mock.patch.object(runtime.platform, 'machine', return_value='arm64'),
                  mock.patch.object(runtime, 'run_worker') as worker):
                with self.assertRaisesRegex(ValueError, 'model checksum'):
                    runtime.NativeDiarization(root, model)
                worker.assert_not_called()

    def run_process(self, script, check):
        created, original = [], subprocess.Popen
        def capture(*args, **kwargs):
            process = original(*args, **kwargs)
            created.append(process)
            return process
        with tempfile.TemporaryDirectory() as temporary:
            with mock.patch.object(runtime.subprocess, 'Popen', side_effect=capture):
                try:
                    return runtime.run_worker([sys.executable, '-c', script], Path(temporary), 5, check)
                finally:
                    self.assertTrue(all(process.poll() is not None for process in created))

    def test_cancel_reaps_its_child(self):
        started = time.monotonic()
        with self.assertRaises(ConnectionAbortedError):
            self.run_process('import time; time.sleep(30)', lambda: time.monotonic() - started > .15)

    def test_oversized_worker_output_is_bounded_and_child_reaped(self):
        with self.assertRaises(ValueError):
            self.run_process("import sys,time; sys.stdout.write('x'*100000); sys.stdout.flush(); time.sleep(30)", lambda: False)

    def test_worker_does_not_inherit_server_secret_or_pythonpath(self):
        script = ("import os,json; print(json.dumps({'server_secret': 'OCIDECK_ASR_TOKEN' in os.environ,"
                  "'python_path': 'PYTHONPATH' in os.environ}))")
        with mock.patch.dict(os.environ, {'OCIDECK_ASR_TOKEN': 'not-a-secret', 'PYTHONPATH': '/unused'}):
            self.assertEqual(self.run_process(script, lambda: False),
                             {'server_secret': False, 'python_path': False})


if __name__ == '__main__':
    unittest.main()
