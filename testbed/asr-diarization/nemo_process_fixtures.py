"""Deterministic repeated public fixtures for process/clock tests, not conversation quality."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import wave


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('fixtures', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    manifest = json.loads((args.fixtures / 'manifest.json').read_text())
    case = next(row for row in manifest['cases'] if row['file'] == 'nl-aba.wav')
    path = args.fixtures / case['file']
    if hashlib.sha256(path.read_bytes()).hexdigest() != case['sha256']:
        raise ValueError('Fixture hash mismatch')
    with wave.open(str(path)) as source:
        params = source.getparams()
        if (params.nchannels, params.sampwidth, params.framerate) != (1, 2, 16000):
            raise ValueError('Expected reference PCM16 WAV')
        if not 360 < params.nframes / 16000 * 12 or params.nframes / 16000 * 23 > 1200:
            raise ValueError('Source does not fit the intended streaming/cancel controls')
        samples = source.readframes(params.nframes)
    args.output.mkdir(parents=True, exist_ok=True)
    report = {'scope': 'repeated public source for native process/clock/cancellation controls only',
              'source_file': case['file'], 'source_sha256': case['sha256'], 'cases': []}
    for repeats in [12, 23]:
        buffer = io.BytesIO()
        with wave.open(buffer, 'wb') as output:
            output.setparams(params)
            output.writeframes(samples * repeats)
        data = buffer.getvalue()
        target = args.output / ('process-control-' + str(repeats) + '.wav')
        if target.exists() and target.read_bytes() != data:
            raise ValueError('Existing process fixture differs; inspect it before retrying')
        if not target.exists():
            target.write_bytes(data)
        report['cases'].append({'file': target.name, 'repeats': repeats,
                                'duration_seconds': params.nframes / 16000 * repeats,
                                'sha256': hashlib.sha256(data).hexdigest()})
    (args.output / 'process-controls.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
