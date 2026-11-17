"""Explicit real-worker cancellation proof; instrumentation records, never replaces, children."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
from unittest import mock

import nemo_runtime


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('runtime', type=Path)
    parser.add_argument('model', type=Path)
    parser.add_argument('fixture', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    native = nemo_runtime.NativeDiarization(args.runtime, args.model)
    audio = args.fixture.read_bytes()
    children, directories = [], []
    original_process = subprocess.Popen
    original_directory = nemo_runtime.tempfile.TemporaryDirectory

    def process(*arguments, **keywords):
        child = original_process(*arguments, **keywords)
        children.append(child)
        return child

    def directory(*arguments, **keywords):
        temporary = original_directory(*arguments, **keywords)
        directories.append(Path(temporary.name))
        return temporary

    start, cancelled = time.monotonic(), False
    with (mock.patch.object(nemo_runtime.subprocess, 'Popen', side_effect=process),
          mock.patch.object(nemo_runtime.tempfile, 'TemporaryDirectory', side_effect=directory)):
        try:
            native.infer(audio, lambda: time.monotonic() - start >= .4)
        except ConnectionAbortedError:
            cancelled = True
    report = {'scope': 'real native model worker cancellation; no ASR or full release UI assertion',
              'fixture_sha256': hashlib.sha256(audio).hexdigest(),
              'cancelled': cancelled, 'elapsed_seconds': time.monotonic() - start,
              'worker_returncodes': [child.returncode for child in children],
              'all_children_reaped': all(child.poll() is not None for child in children),
              'temporary_audio_and_activity_removed': bool(directories) and
                                                     all(not path.exists() for path in directories)}
    report['pass'] = (cancelled and bool(children) and any(child.returncode < 0 for child in children)
                      and report['all_children_reaped'] and report['temporary_audio_and_activity_removed'])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    if not report['pass']:
        raise SystemExit('No valid active-worker cancellation proof; inspect report')


if __name__ == '__main__':
    main()
