"""Explicit speech-region language detection, using locally verified models.

No translation request, audio persistence, speaker identities or model downloads.
Language tags describe the decoder's detected region language, never every word.
"""
import hashlib
from io import BytesIO
import json
import logging
from pathlib import Path
import wave

import ctranslate2
import numpy as np
import onnxruntime
from faster_whisper import WhisperModel
from faster_whisper.vad import VadOptions, get_speech_timestamps


def file_hash(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        while block := source.read(1024 * 1024):
            value.update(block)
    return value.hexdigest()


def verify_model(directory, name):
    catalog = json.loads((Path(__file__).parent / 'models.json').read_text())['models']
    manifest = next((model for model in catalog if model['name'] == name), None)
    if manifest is None:
        raise ValueError('Unknown reference model')
    for entry in manifest['files']:
        path = directory / entry['file']
        if not path.is_file() or path.stat().st_size != entry['bytes']:
            raise ValueError('Missing model file: ' + entry['file'])
        if file_hash(path) != entry['sha256']:
            raise ValueError('Model checksum mismatch: ' + entry['file'])
    return manifest


class WhisperBackend:
    def __init__(self, directory, name, threads=4):
        self.manifest = verify_model(Path(directory), name)
        logging.getLogger('faster_whisper').setLevel(logging.ERROR)
        ctranslate2.set_log_level(logging.ERROR)
        onnxruntime.disable_telemetry_events()
        self.model = WhisperModel(str(directory), device='cpu', compute_type='int8',
                                  cpu_threads=threads, num_workers=1, local_files_only=True)
        self.languages = {language for language in self.model.supported_languages
                          if self.model.hf_tokenizer.token_to_id('<|' + language + '|>') is not None}

    def capabilities(self):
        return {'protocol': 'ocideck-asr', 'version': 1,
                'languages': sorted(self.languages),
                'features': {'timestamps': True, 'diarization': False,
                             'language_detection': True,
                             'language_switching': self.model.model.is_multilingual}}

    def transcribe(self, audio, language, diarize, *, language_switching=False,
                   cancelled=None, include_words=False):
        language = language or None
        if diarize or (language is not None and language not in self.languages):
            raise ValueError('Unsupported transcription option')
        if language_switching and (language is not None or not self.model.model.is_multilingual):
            raise ValueError('Language switching requires multilingual auto detection')
        with wave.open(BytesIO(audio)) as source:
            if (source.getnchannels(), source.getsampwidth(),
                    source.getframerate(), source.getcomptype()) != (1, 2, 16000, 'NONE'):
                raise ValueError('Expected mono 16 kHz PCM16 WAV')
            if source.getnframes() > 16000 * 1200:
                raise ValueError('Reference server limit: 20 minutes')
            samples = np.frombuffer(source.readframes(source.getnframes()), dtype='<i2').astype(np.float32) / 32768
        check = cancelled or (lambda: False)
        if check():
            raise ConnectionAbortedError('Request cancelled')
        if language_switching:
            spans = get_speech_timestamps(samples, VadOptions(
                min_speech_duration_ms=250, min_silence_duration_ms=500, speech_pad_ms=400))
        else:
            spans = [{'start': 0, 'end': len(samples)}]
        result = []
        for span in spans:
            if check():
                raise ConnectionAbortedError('Request cancelled')
            chunk = samples[span['start']:span['end']]
            offset = span['start'] / 16000
            segments, info = self.model.transcribe(chunk, language=language,
                task='transcribe', beam_size=5, temperature=0,
                condition_on_previous_text=False, word_timestamps=True,
                vad_filter=False, multilingual=False)
            for segment in segments:
                if check():
                    raise ConnectionAbortedError('Request cancelled')
                result.append({'text': segment.text, 'start': offset + segment.start,
                               'end': offset + segment.end,
                               **({'words': [{'text': word.word,
                                              'start': offset + word.start,
                                              'end': offset + word.end}
                                             for word in segment.words or []]}
                                  if include_words else {}),
                               **({'language': info.language, 'language_uncertain': True}
                                  if language_switching else {})})
        return {'protocol': 'ocideck-asr', 'version': 1,
                'diarization_applied': False,
                'language_switching_applied': language_switching,
                'segments': result}
