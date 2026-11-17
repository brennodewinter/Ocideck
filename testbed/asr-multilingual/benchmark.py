"""Measure the real reference backend; completion is not quality acceptance.

One process per model is recommended. Peak RSS is cumulative for that process.
WER/CER use independent corpus references and ASR word-midpoint assignment.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import resource
import time
import unicodedata

os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'
os.environ['DO_NOT_TRACK'] = '1'
from whisper_backend import WhisperBackend


def tokens(text):
    return re.findall(r'\w+', unicodedata.normalize('NFKC', text).casefold())


def error(reference, hypothesis):
    if not reference:
        return None
    previous = list(range(len(hypothesis) + 1))
    for i, expected in enumerate(reference, 1):
        row = [i]
        for j, actual in enumerate(hypothesis, 1):
            row.append(min(row[-1] + 1, previous[j] + 1,
                           previous[j - 1] + (expected != actual)))
        previous = row
    return previous[-1] / len(reference)


def score(case, segments):
    output = {}
    for language in sorted({r['language'] for r in case['reference']}):
        intervals = [r for r in case['reference'] if r['language'] == language]
        reference = ' '.join(r['text'] for r in intervals)
        hypothesis = ' '.join(w['text'] for s in segments for w in s['words']
                              if any(r['start'] <= (w['start'] + w['end']) / 2 < r['end']
                                     for r in intervals))
        expected, actual = tokens(reference), tokens(hypothesis)
        output[language] = {'wer': error(expected, actual),
                            'cer': error(list(' '.join(expected)), list(' '.join(actual))),
                            'reference': reference, 'hypothesis': hypothesis}
    return output


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('fixtures', type=Path)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('model_directory', type=Path)
    parser.add_argument('model', choices=['base', 'small', 'large-v3-turbo'])
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    report = {'model': args.model, 'platform': platform.platform(),
              'device': 'cpu', 'compute_type': 'int8', 'threads': 4,
              'peak_rss_scope': 'cumulative process maximum; not isolated per case',
              'quality_accepted': False, 'cases': []}
    start = time.monotonic()
    backend = WhisperBackend(args.model_directory, args.model)
    report['model_load_seconds'] = time.monotonic() - start
    report['model_manifest'] = backend.manifest
    for case in json.loads(args.manifest.read_text())['cases']:
        audio = (args.fixtures / case['file']).read_bytes()
        if hashlib.sha256(audio).hexdigest() != case['sha256']:
            raise ValueError('Fixture hash mismatch')
        for mixed in [False, True]:
            start = time.monotonic()
            result = backend.transcribe(audio, None, False,
                                        language_switching=mixed, include_words=True)
            segments = result['segments']
            report['cases'].append({'file': case['file'], 'sha256': case['sha256'],
                'mode': 'speech-regions' if mixed else 'one-pass',
                'seconds': time.monotonic() - start,
                'peak_rss_bytes': resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
                'scores': score(case, segments),
                'non_speech_hallucination': bool(segments) if not case['reference'] else None,
                'timestamp_order_valid': all(s['start'] >= 0 and s['end'] >= s['start']
                    and (i == 0 or s['start'] >= segments[i-1]['start'])
                    for i, s in enumerate(segments)), 'segments': segments})
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
            print(args.model, case['file'], mixed,
                  round(report['cases'][-1]['seconds'], 2), flush=True)


if __name__ == '__main__':
    main()
