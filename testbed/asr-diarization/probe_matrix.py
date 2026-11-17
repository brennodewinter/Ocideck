"""Measure an explicitly started reference server with prepared public fixtures.

Reports transport success separately from clustering quality. Source spans are
not word/VAD annotations, so this deliberately does not invent a DER score.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
import urllib.request


def memory(container):
    if not container:
        return None
    result = subprocess.run(['docker', 'stats', '--no-stream', '--format', '{{.MemUsage}}', container],
                            check=True, capture_output=True, text=True)
    return result.stdout.strip()


def infer(path, language):
    boundary = 'ocideck-diarization-matrix'
    body = bytearray()
    for name, value in [('language', language.encode()), ('diarize', b'true'),
                        ('response_format', b'verbose_json'), ('file', path.read_bytes())]:
        body.extend(('--' + boundary + '\r\nContent-Disposition: form-data; name="' + name +
                     '"' + ('; filename="audio.wav"' if name == 'file' else '') + '\r\n\r\n').encode())
        body.extend(value); body.extend(b'\r\n')
    body.extend(('--' + boundary + '--\r\n').encode())
    request = urllib.request.Request('http://127.0.0.1:8093/ocideck-asr/v1/transcribe',
                                     data=body, headers={'Content-Type': 'multipart/form-data; boundary=' + boundary})
    started = time.monotonic()
    with urllib.request.urlopen(request, timeout=300) as response:
        result = json.load(response)
    return result, time.monotonic() - started


def run(fixtures, output, container):
    manifest = json.loads((fixtures / 'manifest.json').read_text())
    report = {
        'scope': 'experimental reference backend, not release UI acceptance',
        'hardware': 'Apple Silicon host; linux/amd64 Vosk image under Colima emulation; container limited to 2 CPUs/1 GiB',
        'algorithm': 'utterance x-vectors, cosine distance 0.3; no overlap detection; all assignments uncertain',
        'der': None,
        'der_unavailable_reason': 'Public clips have speaker IDs but no hand-aligned activity/overlap reference. Synthetic source spans include natural pauses; not a DER denominator.',
        'memory_metric': 'Docker container working set before/after each request, not process peak RSS',
        'backend_sha256': hashlib.sha256((Path(__file__).parent / 'vosk_backend.py').read_bytes()).hexdigest(),
        'fixture_manifest': manifest, 'cases': [],
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.unlink(missing_ok=True)
    for case in manifest['cases']:
        path = fixtures / case['file']
        if hashlib.sha256(path.read_bytes()).hexdigest() != case['sha256']:
            raise ValueError('Fixture hash mismatch')
        before = memory(container)
        result, elapsed = infer(path, case['language'])
        assert result['protocol'] == 'ocideck-asr' and result['version'] == 1
        assert result['diarization_applied'] is True
        segments = result['segments']
        by_source = {}
        for span in case['source_spans']:
            if len(span['source_ids']) != 1:
                continue
            ids = set()
            for segment in segments:
                midpoint = (segment['start'] + segment['end']) / 2
                if span['start'] <= midpoint < span['end']:
                    ids.update(segment['speaker_ids'])
            by_source.setdefault(span['source_ids'][0], []).append(sorted(ids))
        unique = sorted({speaker for segment in segments for speaker in segment['speaker_ids']})
        strict = bool(by_source) and all(
            len(sets[0]) == 1 and all(ids == sets[0] for ids in sets) for sets in by_source.values())
        assigned = [sets[0][0] for sets in by_source.values() if len(sets[0]) == 1]
        strict = strict and len(set(assigned)) == len(by_source)
        measured = {
            'file': case['file'], 'language': case['language'], 'layout': case['layout'],
            'duration_s': case['duration_s'], 'elapsed_s': elapsed,
            'realtime_factor': elapsed / case['duration_s'],
            'memory_before': before, 'memory_after': memory(container),
            'transport_ok': True, 'cluster_count': len(unique),
            'clusters_by_source_occurrence': by_source,
            'strict_known_speaker_layout': strict if by_source else None,
            'overlap_detection_supported': False,
            'segments': [{key: segment[key] for key in
                          ['start', 'end', 'speaker_ids', 'speaker_uncertain']} for segment in segments],
        }
        report['cases'].append(measured)
        output.write_text(json.dumps(report, indent=2) + '\n')
        print(case['file'] + ': clusters=' + str(len(unique)) + ', strict=' + str(measured['strict_known_speaker_layout']), flush=True)
    report['complete'] = True
    report['quality_acceptance'] = all(c['strict_known_speaker_layout'] is True for c in report['cases'])
    output.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('fixtures', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--container')
    args = parser.parse_args()
    run(args.fixtures, args.output, args.container)
