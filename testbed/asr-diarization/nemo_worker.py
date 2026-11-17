"""Bounded native-model worker. Invoked explicitly by the loopback backend.

Runs in a separate process; no model downloads, identities or result logging.
The parent verifies the runtime/model manifests before invoking this worker.
"""
import argparse
import ctypes as c
import json
import math
from pathlib import Path
import resource
import sys
import wave

import numpy as np


class Config(c.Structure):
    _fields_ = [('size', c.c_size_t), ('model_path', c.c_char_p),
                ('gpu', c.c_int32), ('preset', c.c_char_p)] + [
        (name, c.c_int32) for name in ['chunk', 'right', 'left', 'fifo', 'cache', 'period']]


def bind(library):
    library.nemo_speech_diar_create.argtypes = [c.POINTER(Config), c.POINTER(c.c_void_p)]
    library.nemo_speech_diar_offline_f32.argtypes = [c.c_void_p, c.POINTER(c.c_float),
                                                  c.c_size_t, c.c_int32, c.POINTER(c.c_void_p)]
    library.nemo_speech_diar_stream_open.argtypes = [c.c_void_p, c.POINTER(c.c_void_p)]
    library.nemo_speech_diar_stream_push_f32.argtypes = [c.c_void_p, c.POINTER(c.c_float),
                                                      c.c_size_t, c.c_int32]
    library.nemo_speech_diar_stream_finish.argtypes = [c.c_void_p]
    library.nemo_speech_diar_frame_count.argtypes = [c.c_void_p]
    library.nemo_speech_diar_frame_count.restype = c.c_int64
    library.nemo_speech_diar_frame_probs_start.argtypes = [c.c_void_p]
    library.nemo_speech_diar_frame_probs_start.restype = c.c_int64
    library.nemo_speech_diar_num_speakers.argtypes = [c.c_void_p]
    library.nemo_speech_diar_num_speakers.restype = c.c_int32
    library.nemo_speech_diar_seconds_per_frame.argtypes = [c.c_void_p]
    library.nemo_speech_diar_seconds_per_frame.restype = c.c_double
    library.nemo_speech_diar_frame_probs.argtypes = [c.c_void_p, c.POINTER(c.c_float), c.c_size_t]
    library.nemo_speech_diar_stream_close.argtypes = [c.c_void_p]
    library.nemo_speech_diar_destroy.argtypes = [c.c_void_p]


def checked(status):
    if status != 0:
        raise ValueError('Native diarization failed')


def run(args):
    library = c.CDLL(str(args.library.resolve()))
    bind(library)
    model, job = c.c_void_p(), c.c_void_p()
    config = Config(c.sizeof(Config), str(args.model.resolve()).encode(),
                    0 if args.backend == 'metal' else -1, b'v3-offline', 0, 0, -1, 0, 0, 0)
    try:
        checked(library.nemo_speech_diar_create(c.byref(config), c.byref(model)))
        slots = library.nemo_speech_diar_num_speakers(model)
        cadence = library.nemo_speech_diar_seconds_per_frame(model)
        if slots != 8 or not math.isfinite(cadence) or abs(cadence - .01) > .000001:
            raise ValueError('Unexpected pinned-model geometry')
        # The API returns a float32 approximation of the native 10 ms cadence.
        # Canonicalize it to avoid adding a frame at exact ASR word boundaries.
        cadence = round(cadence, 6)
        if args.probe:
            return {'native_ready': True, 'speakers': slots, 'frame_seconds': cadence}
        with wave.open(str(args.audio)) as source:
            if (source.getnchannels(), source.getsampwidth(), source.getframerate(),
                    source.getcomptype()) != (1, 2, 16000, 'NONE'):
                raise ValueError('Expected mono 16 kHz PCM16 WAV')
            count = source.getnframes()
            if not 0 < count <= 16000 * 1200:
                raise ValueError('Audio duration outside reference-server limit')
            raw = source.readframes(count)
        if len(raw) != count * 2:
            raise ValueError('Truncated audio')
        samples = np.frombuffer(raw, dtype='<i2').astype(np.float32) / 32768
        mode = 'full-attention' if count <= 16000 * 360 else 'streaming-v3-offline'
        if mode == 'full-attention':
            checked(library.nemo_speech_diar_offline_f32(
                model, samples.ctypes.data_as(c.POINTER(c.c_float)), count, 16000, c.byref(job)))
        else:
            checked(library.nemo_speech_diar_stream_open(model, c.byref(job)))
            # Bounded pushes preserve one stateful speaker cache across the file.
            for start in range(0, count, 16000 * 10):
                block = samples[start:start + 16000 * 10]
                checked(library.nemo_speech_diar_stream_push_f32(
                    job, block.ctypes.data_as(c.POINTER(c.c_float)), len(block), 16000))
            checked(library.nemo_speech_diar_stream_finish(job))
        frames = library.nemo_speech_diar_frame_count(job)
        first = library.nemo_speech_diar_frame_probs_start(job)
        if first != 0 or not 0 <= frames <= math.ceil(count / 160) + 100:
            raise ValueError('Unexpected native frame extent')
        data = np.empty((frames, slots), dtype=np.float32)
        checked(library.nemo_speech_diar_frame_probs(
            job, data.ctypes.data_as(c.POINTER(c.c_float)), data.size))
        if not np.isfinite(data).all() or (data < 0).any() or (data > 1).any():
            raise ValueError('Invalid native activity values')
        np.save(args.output, data, allow_pickle=False)
        return {'frames': frames, 'speakers': slots, 'frame_seconds': cadence, 'mode': mode,
                'worker_peak_rss_bytes': resource.getrusage(resource.RUSAGE_SELF).ru_maxrss *
                                         (1 if sys.platform == 'darwin' else 1024)}
    finally:
        if job:
            library.nemo_speech_diar_stream_close(job)
        if model:
            library.nemo_speech_diar_destroy(model)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--library', type=Path, required=True)
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--backend', choices=['cpu', 'metal'], default='cpu')
    parser.add_argument('--probe', action='store_true')
    parser.add_argument('--audio', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if not args.probe and (args.audio is None or args.output is None):
        parser.error('Audio and private output paths are required')
    try:
        print(json.dumps(run(args)))
    except (OSError, ValueError, wave.Error):
        # Do not expose paths, audio, native exception text or model contents.
        print('Native reference worker failed', file=sys.stderr)
        sys.exit(1)
