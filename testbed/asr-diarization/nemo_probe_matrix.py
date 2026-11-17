"""Real HTTP/ASR/word-attribution evidence. Completion is not blanket accuracy.

Source clip intervals include internal pauses; no activity-aligned DER is invented.
Unknown output is counted explicitly instead of forcing a speaker assignment.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess

from probe_matrix import infer


def rss(pid):
    if pid is None:
        return None
    output = subprocess.check_output(['ps', '-o', 'rss=', '-p', str(pid)], text=True)
    return int(output.strip()) * 1024


def token_count(text):
    return len(re.findall(r'\w+', text))


def assess(case, segments):
    by_source = {}
    unknown = sum(token_count(s['text']) for s in segments if not s['speaker_ids'])
    for span in case['source_spans']:
        if len(span['source_ids']) != 1:
            continue
        ids = set()
        for segment in segments:
            midpoint = (segment['start'] + segment['end']) / 2
            if span['start'] <= midpoint < span['end']:
                ids.update(segment['speaker_ids'])
        by_source.setdefault(span['source_ids'][0], []).append(sorted(ids))
    known = bool(by_source) and all(len(occurrences[0]) == 1 and
              all(ids == occurrences[0] for ids in occurrences) for occurrences in by_source.values())
    assigned = [occurrences[0][0] for occurrences in by_source.values() if len(occurrences[0]) == 1]
    known = known and len(set(assigned)) == len(by_source)
    all_ids = sorted({speaker for segment in segments for speaker in segment['speaker_ids']})
    multi = [s for s in segments if len(s['speaker_ids']) > 1]
    overlap = bool(multi) and len(all_ids) == 2
    return {'known_source_occurrences': by_source,
            'assigned_ids_consistent': known if by_source else None,
            'distinct_ids': all_ids, 'unknown_output_tokens': unknown,
            'total_output_tokens': sum(token_count(s['text']) for s in segments),
            'multi_id_segments': len(multi),
            'overlap_detected': overlap if case['layout'] in ('overlap', 'stereo-downmix') else None,
            'fixture_layout_pass': known if by_source else overlap}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('fixtures', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--server-pid', type=int)
    args = parser.parse_args()
    manifest = json.loads((args.fixtures / 'manifest.json').read_text())
    report = {'scope': 'real loopback HTTP, actual Whisper small and native Nemotron activity; not full release UI',
              'platform': platform.platform(), 'device': 'ASR CPU/int8/4 threads; diarizer native CPU',
              'source_manifest': manifest,
              'der': None, 'der_unavailable_reason': 'No hand-aligned speech/overlap activity reference; source intervals include natural pauses.',
              'memory_metric': 'server process RSS snapshots, not peak or combined child memory',
              'server_rss_before_bytes': rss(args.server_pid), 'cases': [], 'complete': False}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.unlink(missing_ok=True)
    for case in manifest['cases']:
        path = args.fixtures / case['file']
        if hashlib.sha256(path.read_bytes()).hexdigest() != case['sha256']:
            raise ValueError('Fixture hash mismatch')
        plain, plain_seconds = infer(path, case['language'], diarize=False)
        result, seconds = infer(path, case['language'])
        if result['diarization_applied'] is not True or plain['diarization_applied'] is not False:
            raise ValueError('Requested mode was not applied')
        text = ''.join(s['text'] for s in result['segments'])
        unchanged = text == ''.join(s['text'] for s in plain['segments'])
        measured = assess(case, result['segments'])
        measured.update({'file': case['file'], 'layout': case['layout'],
                         'duration_seconds': case['duration_s'], 'seconds': seconds,
                         'without_diarization_seconds': plain_seconds,
                         'asr_text_unchanged': unchanged,
                         'labels_absent_when_disabled': all(not s.get('speaker_ids') for s in plain['segments']),
                         'segments': result['segments']})
        report['cases'].append(measured)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        print(case['file'], 'assigned_layout', measured['fixture_layout_pass'],
              'unknown_tokens', measured['unknown_output_tokens'], '/', measured['total_output_tokens'],
              'ASR_text_unchanged', unchanged, flush=True)
    report['server_rss_after_bytes'] = rss(args.server_pid)
    report['complete'] = True
    report['fixture_matrix_pass'] = all(c['fixture_layout_pass'] and c['asr_text_unchanged']
                                      and c['labels_absent_when_disabled'] for c in report['cases'])
    report['general_quality_guarantee'] = False
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    if not report['fixture_matrix_pass']:
        raise SystemExit('Fixture matrix did not pass; inspect every failed/unknown result')


if __name__ == '__main__':
    main()
