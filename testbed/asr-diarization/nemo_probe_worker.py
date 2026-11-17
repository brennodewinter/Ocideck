"""Separate native-component peak-memory measurements on verified fixtures.

This is not a combined ASR-server/worker memory peak or a quality verdict.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import tempfile
import time

from nemo_runtime import NativeDiarization, run_worker


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('fixtures', type=Path)
    parser.add_argument('runtime', type=Path)
    parser.add_argument('model', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    native = NativeDiarization(args.runtime, args.model)
    manifest = json.loads((args.fixtures / 'manifest.json').read_text())
    report = {'platform': platform.platform(), 'backend': 'native CPU',
              'scope': 'separate worker process peaks; not combined server memory', 'cases': []}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.unlink(missing_ok=True)
    for case in manifest['cases']:
        path = args.fixtures / case['file']
        if hashlib.sha256(path.read_bytes()).hexdigest() != case['sha256']:
            raise ValueError('Fixture hash mismatch')
        with tempfile.TemporaryDirectory(prefix='ocideck-diar-measure-') as temporary:
            directory = Path(temporary)
            start = time.monotonic()
            result = run_worker(native.arguments() + ['--audio', str(path), '--output',
                                str(directory / 'activity.npy')], directory,
                                90 + case['duration_s'] * 2, lambda: False)
            report['cases'].append({'file': case['file'], 'elapsed_seconds': time.monotonic() - start,
                                    'native_result': result})
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    report['complete'] = True
    args.output.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
