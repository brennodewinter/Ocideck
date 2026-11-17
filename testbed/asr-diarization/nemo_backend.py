"""Optional Whisper ASR plus verified Nemotron activity; all labels uncertain."""
import importlib.util
from pathlib import Path

from nemo_runtime import NativeDiarization
from nemo_word_alignment import align_segments

class NemoWhisperBackend:
    def __init__(self, asr_directory, asr_model, runtime_directory, diarization_model, backend='cpu'):
        self.native = NativeDiarization(runtime_directory, diarization_model, backend)
        source = Path(__file__).parent.parent / 'asr-multilingual/whisper_backend.py'
        spec = importlib.util.spec_from_file_location('ocideck_reference_whisper', source)
        whisper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(whisper)
        self.asr = whisper.WhisperBackend(asr_directory, asr_model)

    def capabilities(self):
        capabilities = self.asr.capabilities()
        capabilities['features']['diarization'] = True
        return capabilities

    def transcribe(self, audio, language, diarize, *, language_switching=False, cancelled=None):
        if not diarize:
            return self.asr.transcribe(audio, language, False,
                                       language_switching=language_switching, cancelled=cancelled)
        check = cancelled or (lambda: False)
        probabilities, cadence = self.native.infer(audio, check)
        if check():
            raise ConnectionAbortedError('Request cancelled')
        result = self.asr.transcribe(audio, language, False, language_switching=language_switching,
                                     cancelled=check, include_words=True)
        if check():
            raise ConnectionAbortedError('Request cancelled')
        result['segments'] = align_segments(result['segments'], probabilities, cadence)
        result['diarization_applied'] = True
        return result
