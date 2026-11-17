#!/usr/bin/env python3
"""Probe the exact production helper; no Flutter/UI/ASR certification."""
import hashlib
import json
import os
from pathlib import Path
import platform
import struct
import subprocess
import sys
import tempfile
import wave

helper = Path(sys.argv[1]).resolve(strict=True)
output = Path(sys.argv[2])
root = Path(__file__).resolve().parents[2]
fixtures = root / 'integration_test/fixtures/audio_formats'
manifest = json.loads((fixtures / 'manifest.json').read_text())
sha = lambda data: hashlib.sha256(data).hexdigest()
report = {'scope': 'Production helper sources; no installed-package/UI/ASR claim',
          'platform': platform.platform(), 'helper_sha256': sha(helper.read_bytes()),
          'results': []}
invalid = False
with tempfile.TemporaryDirectory(prefix='ocideck-codec-') as directory:
    for item in manifest['fixtures'] + manifest['negative_fixtures']:
        original = (fixtures / item['source']).read_bytes()
        if sha(original) != item['source_sha256']:
            raise ValueError('Fixture hash mismatch')
        source = Path(directory) / ('brón ü met spaties ' + item['source'])
        source.write_bytes(original)
        destination = Path(directory) / 'decoded.wav'
        destination.unlink(missing_ok=True)
        environment = {'PATH': ''}
        if os.name == 'nt':
            environment['SystemRoot'] = os.environ['SystemRoot']
        else:
            environment['LD_LIBRARY_PATH'] = str(helper.parent / 'lib')
        run = subprocess.run([str(helper), '--decode', str(source), str(destination)],
                             capture_output=True, timeout=30, env=environment)
        negative = item.get('expected')
        row = {'source': item['source'], 'negative_case': negative, 'source_sha256': item['source_sha256'],
               'exit_code': run.returncode}
        if run.returncode:
            row['error'] = run.stderr.decode('utf-8', errors='replace').replace(str(source), '<source>')[-1000:]
        elif negative and negative != 'unsupported-codec':
            row['unexpected_success'] = True
            invalid = True
        else:
            with wave.open(str(destination), 'rb') as audio:
                row.update(channels=audio.getnchannels(), sample_rate=audio.getframerate(),
                           sample_bytes=audio.getsampwidth(), frames=audio.getnframes())
                samples = audio.readframes(audio.getnframes())
            row['duration_ms'] = row['frames'] * 1000 / row['sample_rate']
            row['has_signal'] = any(value[0] for value in struct.iter_unpack('<h', samples))
            if ((row['channels'], row['sample_rate'], row['sample_bytes']) != (1, 16000, 2)
                    or not row['has_signal']
                    or (not negative and abs(row['duration_ms'] - item['expected_duration_ms']) > item['duration_tolerance_ms'])):
                row['invalid_output'] = True
                invalid = True
        if negative and run.returncode and destination.exists():
            raise ValueError('Failed decode left output behind')
        if negative == 'no-audio' and run.returncode != 3:
            row['incorrect_no_audio_status'] = True
            invalid = True
        if source.read_bytes() != original:
            raise ValueError('Decoder modified source')
        report['results'].append(row)
output.write_text(json.dumps(report, indent=2) + '\n')
if invalid or not any(row['exit_code'] == 0 for row in report['results']):
    raise SystemExit(1)
