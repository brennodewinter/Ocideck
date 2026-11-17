"""Experimental, recording-local Vosk clustering. No identity recognition.

Vosk's utterance vectors do not detect overlapping speakers or guarantee
turn boundaries. Every assigned cluster is therefore marked uncertain.
The v1 client also supports better backends that supply word-aligned turns.
"""
import json
import math
import wave
from io import BytesIO

from vosk import KaldiRecognizer, Model, SetLogLevel, SpkModel


def _unit(vector):
    length = math.sqrt(sum(value * value for value in vector))
    return [value / length for value in vector] if length else None


class VoskBackend:
    def __init__(self, models, speaker_model=None):
        SetLogLevel(-1)
        self.models = {language: Model(path) for language, path in models.items()}
        self.speaker_model = SpkModel(speaker_model) if speaker_model else None

    def capabilities(self):
        return {
            'protocol': 'ocideck-asr', 'version': 1,
            'languages': sorted(self.models),
            'features': {'timestamps': True, 'language_detection': False,
                         'diarization': self.speaker_model is not None},
        }

    def transcribe(self, audio, language, diarize, *, cancelled=None):
        if language not in self.models:
            raise ValueError('Choose an installed language explicitly')
        if diarize and self.speaker_model is None:
            raise ValueError('Speaker model not installed')
        with wave.open(BytesIO(audio)) as source:
            if (source.getnchannels(), source.getsampwidth(),
                    source.getframerate(), source.getcomptype()) != (1, 2, 16000, 'NONE'):
                raise ValueError('Expected mono 16 kHz PCM16 WAV')
            if source.getnframes() > 16000 * 1200:
                raise ValueError('Reference server limit: 20 minutes')
            recognizer = KaldiRecognizer(self.models[language], 16000)
            recognizer.SetWords(True)
            if diarize:
                recognizer.SetSpkModel(self.speaker_model)
            results = []
            while True:
                if cancelled and cancelled():
                    raise ConnectionAbortedError('Request cancelled')
                chunk = source.readframes(4000)
                if not chunk:
                    break
                if recognizer.AcceptWaveform(chunk):
                    results.append(json.loads(recognizer.Result()))
            results.append(json.loads(recognizer.FinalResult()))
        centroids = []
        segments = []
        for result in results:
            words = result.get('result', [])
            if not words:
                continue
            ids = self._cluster(result, centroids) if diarize else []
            segments.append({
                'text': result['text'], 'start': words[0]['start'],
                'end': words[-1]['end'], 'speaker_ids': ids,
                'speaker_uncertain': diarize,
            })
        return {'protocol': 'ocideck-asr', 'version': 1,
                'diarization_applied': diarize, 'segments': segments}

    @staticmethod
    def _cluster(result, centroids):
        if result.get('spk_frames', 0) < 100 or 'spk' not in result:
            return []
        vector = _unit(result['spk'])
        if vector is None:
            return []
        distances = [1 - sum(a * b for a, b in zip(vector, centroid))
                     for centroid in centroids]
        best = min(distances) if distances else 1
        if best < 0.3:
            index = distances.index(best)
        else:
            index = len(centroids)
            centroids.append(vector)
        return [f'cluster-{index + 1}']
