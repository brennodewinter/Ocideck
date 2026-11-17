"""Composition and cancellation contracts, independent of native model installs."""
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest import mock

source = Path(__file__).resolve().parents[2] / 'testbed/asr-diarization/nemo_backend.py'
spec = importlib.util.spec_from_file_location('nemo_backend_contract', source)
backend_module = importlib.util.module_from_spec(spec)
with mock.patch.object(sys, 'path', [str(source.parent), *sys.path]):
    spec.loader.exec_module(backend_module)


class BackendCompositionTest(unittest.TestCase):
    def backend(self):
        backend = backend_module.NemoWhisperBackend.__new__(backend_module.NemoWhisperBackend)
        backend.native = mock.Mock()
        backend.asr = mock.Mock()
        return backend

    def test_disabled_diarization_bypasses_native_worker_and_preserves_response(self):
        backend = self.backend()
        response = {'diarization_applied': False, 'segments': [{'text': 'raw text'}]}
        backend.asr.transcribe.return_value = response
        result = backend.transcribe(b'audio', 'nl', False)
        self.assertIs(result, response)
        backend.native.infer.assert_not_called()
        backend.asr.transcribe.assert_called_once_with(
            b'audio', 'nl', False, language_switching=False, cancelled=None)

    def test_cancellation_after_native_job_prevents_asr(self):
        backend = self.backend()
        backend.native.infer.return_value = ([[.9, .0]], .1)
        with self.assertRaises(ConnectionAbortedError):
            backend.transcribe(b'audio', 'nl', True, cancelled=lambda: True)
        backend.asr.transcribe.assert_not_called()

    def test_completed_attribution_preserves_text_and_language_mode(self):
        backend = self.backend()
        backend.native.infer.return_value = ([[.9, .0], [.0, .9]], .1)
        backend.asr.transcribe.return_value = {
            'diarization_applied': False, 'language_switching_applied': True,
            'segments': [{'text': ' A B', 'start': 0, 'end': .2, 'language': 'nl',
                          'language_uncertain': True,
                          'words': [{'text': ' A', 'start': 0, 'end': .1},
                                    {'text': ' B', 'start': .1, 'end': .2}]}]}
        result = backend.transcribe(b'audio', None, True, language_switching=True)
        self.assertTrue(result['diarization_applied'])
        self.assertTrue(result['language_switching_applied'])
        self.assertEqual(''.join(s['text'] for s in result['segments']), ' A B')
        self.assertEqual([s['speaker_ids'] for s in result['segments']], [['nemo-1'], ['nemo-2']])
        self.assertTrue(backend.asr.transcribe.call_args.kwargs['include_words'])


if __name__ == '__main__':
    unittest.main()
