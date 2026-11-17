"""Actual HTTP composition on the documented same-reader NL/EN/NL fixture."""
import argparse
import hashlib
import http.client
import json
from pathlib import Path


def request(audio, diarize):
    boundary = 'ocideck-combined-reference'
    body = bytearray()
    for name, value in [('diarize', b'true' if diarize else b'false'),
                        ('language_mode', b'mixed'), ('file', audio)]:
        body.extend(('--' + boundary + '\r\nContent-Disposition: form-data; name="' + name + '"' +
                     ('; filename="audio.wav"' if name == 'file' else '') + '\r\n\r\n').encode())
        body.extend(value)
        body.extend(b'\r\n')
    body.extend(('--' + boundary + '--\r\n').encode())
    connection = http.client.HTTPConnection('127.0.0.1', 8093, timeout=300)
    try:
        connection.request('POST', '/ocideck-asr/v1/transcribe', body,
                           {'Content-Type': 'multipart/form-data; boundary=' + boundary})
        response = connection.getresponse()
        if response.status != 200:
            raise ValueError('Reference server refused the composition probe')
        return json.loads(response.read())
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('fixture', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    audio = args.fixture.read_bytes()
    plain, result = request(audio, False), request(audio, True)
    report = {'scope': 'real language-switch/diarization composition on the same documented reader; synthetic splice, no general quality claim',
              'fixture_sha256': hashlib.sha256(audio).hexdigest(),
              'language_mode_applied': result['language_switching_applied'],
              'diarization_applied': result['diarization_applied'],
              'languages': sorted({s.get('language') for s in result['segments'] if s.get('language')}),
              'asr_text_preserved': ''.join(s['text'] for s in plain['segments']) ==
                                    ''.join(s['text'] for s in result['segments']),
              'speaker_ids': sorted({i for s in result['segments'] for i in s['speaker_ids']}),
              'segments': result['segments']}
    report['probe_pass'] = (report['language_mode_applied'] and report['diarization_applied']
                            and report['asr_text_preserved'] and set(report['languages']) == {'nl', 'en'}
                            and len(report['speaker_ids']) == 1)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    if not report['probe_pass']:
        raise SystemExit('Same-reader composition probe failed; inspect result')


if __name__ == '__main__':
    main()
