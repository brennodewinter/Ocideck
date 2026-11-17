"""Explicit offline fixture preparation. No dataset download or hidden ASR.

Requires pyarrow==23.0.0 and FFmpeg on PATH. Pass an existing corpus cache
containing nl-test.parquet, polish-test.parquet, en-test-clean.tar.gz,
bianca-en-introduction.mp3 and dutch-twins.txt (see README).
"""
import argparse
import array
import hashlib
import json
import math
from pathlib import Path
import subprocess
import tarfile
import wave
import pyarrow.parquet as pq


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_wave(path):
    with wave.open(str(path)) as source:
        return source.readframes(source.getnframes())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('corpus', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    cases = []

    def clip(source, name, text, language):
        wav = args.output / (name + '.wav')
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(source),
                        '-ac', '1', '-ar', '16000', '-c:a', 'pcm_s16le', str(wav)], check=True)
        return {'id': name, 'text': text, 'language': language,
                'source_sha256': sha(source), 'raw': read_wave(wav)}

    def write(name, raw, references, layout):
        path = args.output / (name + '.wav')
        with wave.open(str(path), 'wb') as target:
            target.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
            target.writeframes(raw)
        cases.append({'file': path.name, 'sha256': sha(path),
                      'duration': len(raw) / 32000, 'reference': references, 'layout': layout})

    def join(name, sequence, pause, layout):
        raw, references = bytearray(), []
        for part in sequence:
            start = len(raw) / 32000
            raw.extend(part['raw'])
            references.append({k: v for k, v in part.items() if k != 'raw'} |
                              {'start': start, 'end': len(raw) / 32000})
            raw.extend(bytes(pause))
        write(name, raw, references, layout)

    member = 'LibriSpeech/test-clean/5639/40744/5639-40744-0032.flac'
    with tarfile.open(args.corpus / 'en-test-clean.tar.gz') as archive:
        source = args.output / 'en-5639.flac'
        source.write_bytes(archive.extractfile(member).read())
        lines = archive.extractfile('LibriSpeech/test-clean/5639/40744/5639-40744.trans.txt').read().decode().splitlines()
        text = next(line.split(' ', 1)[1] for line in lines if line.startswith('5639-40744-0032 '))
    english = clip(source, 'en-5639', text, 'en')
    dutch = None
    for language, filename in [('nl', 'nl-test.parquet'), ('pl', 'polish-test.parquet')]:
        rows = pq.read_table(args.corpus / filename).to_pylist()
        reader = rows[0]['speaker_id']
        chosen = [r for r in rows if r['speaker_id'] == reader][:4]
        parts = []
        for row in chosen:
            source = args.output / (row['id'] + '.opus')
            source.write_bytes(row['audio']['bytes'])
            parts.append(clip(source, row['id'], row['transcript'], language))
        join(language + '-en' + ('-nl' if language == 'nl' else ''),
             parts[:3] + [english] + (parts[3:] if language == 'nl' else []), 32000,
             'synthetic concatenation, different readers, one second added silence')
        if language == 'nl':
            row = next(r for r in rows if r['id'] == '3798_2211_000000')
            source = args.output / 'bianca-nl.opus'
            source.write_bytes(row['audio']['bytes'])
            dutch = clip(source, 'bianca-nl', row['transcript'], 'nl')
    english = clip(args.corpus / 'bianca-en-introduction.mp3', 'bianca-en', '', 'en')
    book = (args.corpus / 'dutch-twins.txt').read_text()
    start = book.index('This is a picture of Kit and Kat.')
    end = book.index('I will tell', start)
    text = ' '.join((book[start:end] + 'I will tell you about some of them.').split())
    for name, lower, upper, reference, pause in [
        ('same-reader-nl-en-nl', 26.4, 88.9, text, 32000),
        ('same-reader-short-quote', 41.0, 44.3, 'Their real names are Christopher and Katrina.', 0)]:
        part = english | {'raw': english['raw'][int(lower * 32000) // 2 * 2:int(upper * 32000) // 2 * 2],
                          'text': reference}
        join(name, [dutch, part, dutch], pause,
             'synthetic splice, documented reader Bianca Kramer (3798) in both languages; not spontaneous speech')
    write('silence', bytes(32000 * 12), [], 'digital silence')
    chord = array.array('h', (int(1200 * sum(math.sin(2 * math.pi * f * i / 16000)
                             for f in [220, 277.18, 329.63])) for i in range(16000 * 12)))
    write('instrumental-tone-control', chord.tobytes(), [],
          'synthetic sustained chord, not representative music')
    (args.output / 'fixture-manifest.json').write_text(
        json.dumps({'cases': cases}, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
