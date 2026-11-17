"""Verified optional native runtime, isolated behind a cancellable worker."""
import hashlib
from io import BytesIO
import json
import math
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile
import time
import wave

RUNTIME_REVISION = 'e790e463b2913cff9f989a3df224c587f14b4c5c'
LIBRARY_FILES = {'lib/libnemo_speech_asr_c.2.dylib', 'lib/libnemo_speech_asr.dylib'}


def file_hash(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        while block := source.read(1024 * 1024):
            value.update(block)
    return value.hexdigest()


def confined(root, relative):
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError('Manifest path escapes runtime directory')
    return path


def verify_runtime(root):
    manifest = json.loads((root / 'ocideck-runtime.json').read_text())
    if (manifest.get('schema') != 1 or manifest.get('revision') != RUNTIME_REVISION or
            manifest.get('platform') != 'macos-arm64' or
            manifest.get('library') != 'lib/libnemo_speech_asr_c.2.dylib' or
            {entry['file'] for entry in manifest.get('files', [])} != LIBRARY_FILES):
        raise ValueError('Unsupported reference runtime manifest')
    for entry in manifest['files']:
        path = confined(root, entry['file'])
        if path.stat().st_size != entry['bytes'] or file_hash(path) != entry['sha256']:
            raise ValueError('Runtime checksum mismatch')
    notices = manifest.get('notice_sha256')
    if not isinstance(notices, dict) or not notices:
        raise ValueError('Runtime notices missing')
    for relative, checksum in notices.items():
        if file_hash(confined(root, relative)) != checksum:
            raise ValueError('Runtime notice checksum mismatch')
    return confined(root, manifest['library'])


def verify_model(path):
    source = Path(__file__).parent
    model = json.loads((source / 'nemo_model.json').read_text())
    if path.stat().st_size != model['bytes'] or file_hash(path) != model['sha256']:
        raise ValueError('Diarization model checksum mismatch')
    for notice in model['notices']:
        target = path.parent / 'notices' / notice['file']
        if target.stat().st_size != notice['bytes'] or file_hash(target) != notice['sha256']:
            raise ValueError('Original model notices missing or changed')
    if file_hash(path.parent / 'notices/OpenMDW-1.1.txt') != model['license_sha256']:
        raise ValueError('Model license notice missing or changed')


def run_worker(arguments, directory, timeout, cancelled):
    """No shell, secrets, unbounded pipe capture or surviving child on cancel."""
    environment = {key: os.environ[key] for key in ['PATH', 'HOME', 'LANG', 'TMPDIR']
                   if key in os.environ}
    environment.update({'PYTHONNOUSERSITE': '1', 'PYTHONDONTWRITEBYTECODE': '1',
                        'HF_HUB_OFFLINE': '1', 'TRANSFORMERS_OFFLINE': '1', 'DO_NOT_TRACK': '1'})
    stdout = directory / 'worker-result.json'
    deadline = time.monotonic() + timeout
    if cancelled():
        raise ConnectionAbortedError('Request cancelled')
    with stdout.open('wb') as target:
        process = subprocess.Popen(arguments, stdout=target, stderr=subprocess.DEVNULL,
                                   stdin=subprocess.DEVNULL, env=environment)
        try:
            while process.poll() is None:
                if cancelled():
                    raise ConnectionAbortedError('Request cancelled')
                if time.monotonic() >= deadline:
                    raise TimeoutError('Native reference worker timed out')
                if stdout.stat().st_size > 64 * 1024:
                    raise ValueError('Unexpected native worker output')
                try:
                    process.wait(timeout=.1)
                except subprocess.TimeoutExpired:
                    pass
            if cancelled():
                raise ConnectionAbortedError('Request cancelled')
            if process.returncode != 0 or stdout.stat().st_size > 64 * 1024:
                raise ValueError('Native reference worker failed')
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
    result = json.loads(stdout.read_text())
    if not isinstance(result, dict):
        raise ValueError('Invalid native worker result')
    return result


class NativeDiarization:
    def __init__(self, runtime_directory, model_path, backend='cpu'):
        if platform.system() != 'Darwin' or platform.machine() != 'arm64':
            raise ValueError('This reference runtime is verified only on native macOS arm64')
        if backend not in ('cpu', 'metal'):
            raise ValueError('Unsupported native backend')
        self.library = verify_runtime(Path(runtime_directory))
        self.model = Path(model_path).resolve()
        verify_model(self.model)
        self.backend = backend
        with tempfile.TemporaryDirectory(prefix='ocideck-diar-probe-') as temporary:
            result = run_worker(self.arguments() + ['--probe'], Path(temporary), 60, lambda: False)
        if result != {'native_ready': True, 'speakers': 8, 'frame_seconds': .01}:
            raise ValueError('Native reference worker is unavailable')

    def arguments(self):
        return [sys.executable, str(Path(__file__).parent / 'nemo_worker.py'),
                '--library', str(self.library), '--model', str(self.model), '--backend', self.backend]

    def infer(self, audio, cancelled=None):
        check = cancelled or (lambda: False)
        if len(audio) > 64 * 1024 * 1024:
            raise ValueError('Reference upload limit exceeded')
        with wave.open(BytesIO(audio)) as source:
            if (source.getnchannels(), source.getsampwidth(), source.getframerate(),
                    source.getcomptype()) != (1, 2, 16000, 'NONE'):
                raise ValueError('Expected normalized WAV')
            count = source.getnframes()
            if not 0 < count <= 16000 * 1200:
                raise ValueError('Reference duration limit exceeded')
        if check():
            raise ConnectionAbortedError('Request cancelled')
        with tempfile.TemporaryDirectory(prefix='ocideck-diar-') as temporary:
            directory = Path(temporary)
            source, output = directory / 'audio.wav', directory / 'activity.npy'
            source.write_bytes(audio)
            result = run_worker(self.arguments() + ['--audio', str(source), '--output', str(output)],
                                directory, 90 + count / 8000, check)
            frames = result.get('frames')
            if (type(frames) is not int or not 0 <= frames <= math.ceil(count / 160) + 100 or
                    result.get('speakers') != 8 or result.get('frame_seconds') != .01 or
                    output.stat().st_size > (frames * 8 * 4) + 1024):
                raise ValueError('Invalid native activity extent')
            import numpy as np
            probabilities = np.load(output, allow_pickle=False)
            if (probabilities.shape != (frames, 8) or probabilities.dtype != np.dtype('float32') or
                    not np.isfinite(probabilities).all() or (probabilities < 0).any() or
                    (probabilities > 1).any()):
                raise ValueError('Invalid native activity data')
            if check():
                raise ConnectionAbortedError('Request cancelled')
            return probabilities, result['frame_seconds']
