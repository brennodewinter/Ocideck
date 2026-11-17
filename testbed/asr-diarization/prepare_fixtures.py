"""Build synthetic speaker layouts from explicitly downloaded public corpora.

Inputs: nl-test.parquet (MLS Dutch), en-test-clean.tar.gz (OpenSLR 12).
Requires Python 3.13 + pyarrow 23.0.0 and FFmpeg; does not download anything.
Source IDs describe audiobook readers, not identities inferred by OciDeck.
"""
import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path
import subprocess
import tarfile
import wave


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def select_sources(corpus):
    import pyarrow.parquet as pq
    selected = {'nl': {}, 'en': {}}
    for row in pq.read_table(corpus / 'nl-test.parquet').to_pylist():
        speaker = row['speaker_id']
        if speaker in selected['nl']:
            continue
        source = corpus / ('nl-' + speaker + '.opus')
        source.write_bytes(row['audio']['bytes'])
        selected['nl'][speaker] = {'id': row['id'], 'path': source.name,
                                  'sha256': digest(source)}
        if len(selected['nl']) == 3:
            break
    with tarfile.open(corpus / 'en-test-clean.tar.gz') as bundle:
        for item in bundle:
            if not item.name.endswith('.flac'):
                continue
            speaker = item.name.split('/')[2]
            if speaker in selected['en']:
                continue
            source = corpus / ('en-' + speaker + '.flac')
            source.write_bytes(bundle.extractfile(item).read())
            selected['en'][speaker] = {'member': item.name, 'path': source.name,
                                      'sha256': digest(source)}
            if len(selected['en']) == 3:
                break
    return selected


def write_wave(path, samples, channels=1):
    with wave.open(str(path), 'wb') as target:
        target.setparams((channels, 2, 16000, 0, 'NONE', 'not compressed'))
        target.writeframes(samples.tobytes())


def build(corpus, output):
    output.mkdir(parents=True, exist_ok=True)
    selected = select_sources(corpus)
    cases = []
    for language, sources in selected.items():
        clips = []
        for speaker, source in sources.items():
            target = output / (language + '-' + speaker + '.wav')
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(corpus / source['path']),
                            '-ac', '1', '-ar', '16000', '-c:a', 'pcm_s16le', str(target)], check=True)
            with wave.open(str(target)) as audio:
                clips.append((speaker, array('h', audio.readframes(audio.getnframes()))))
        layouts = {'single': [0], 'aba': [0, 1, 0], 'three': [0, 1, 2]}
        for name, indices in layouts.items():
            samples = array('h'); spans = []
            for index in indices:
                speaker, clip = clips[index]
                start = len(samples) / 16000
                samples.extend(clip)
                spans.append({'start': start, 'end': len(samples) / 16000, 'source_ids': [speaker]})
                samples.extend([0] * 16000)
            path = output / (language + '-' + name + '.wav')
            write_wave(path, samples)
            cases.append({'file': path.name, 'language': language, 'layout': name, 'source_spans': spans})
        a_id, a = clips[0]; b_id, b = clips[1]
        size = min(len(a), len(b))
        mixed = array('h', (int((a[i] + b[i]) / 2) for i in range(size)))
        stereo = array('h', (value for i in range(size) for value in (a[i], b[i])))
        write_wave(output / (language + '-stereo-original.wav'), stereo, 2)
        for name in ['overlap', 'stereo-downmix']:
            path = output / (language + '-' + name + '.wav')
            write_wave(path, mixed)
            cases.append({'file': path.name, 'language': language, 'layout': name,
                          'source_spans': [{'start': 0, 'end': size / 16000, 'source_ids': [a_id, b_id]}]})
        # An original synthetic three-note backing, not a commercial recording.
        notes = [261.6256, 329.6276, 391.9954, 329.6276]
        music = array('h')
        for i, value in enumerate(a):
            frequency = notes[(i // 8000) % len(notes)]
            envelope = min(1, (i % 8000) / 400) * (1 - (i % 8000) / 8000)
            tone = 1400 * math.sin(2 * math.pi * frequency * i / 16000) * envelope
            music.append(max(-32768, min(32767, int(value * 0.8 + tone))))
        path = output / (language + '-music.wav'); write_wave(path, music)
        cases.append({'file': path.name, 'language': language, 'layout': 'music',
                      'source_spans': [{'start': 0, 'end': len(a) / 16000, 'source_ids': [a_id]}]})
    for case in cases:
        path = output / case['file']; case['sha256'] = digest(path)
        with wave.open(str(path)) as audio:
            case['duration_s'] = audio.getnframes() / 16000
    manifest = {
        'license': 'CC-BY-4.0 source corpora; original synthetic backing: CC0',
        'nl_source': 'https://huggingface.co/datasets/facebook/multilingual_librispeech/tree/2e83e61823b4c47dcbcb1980bb88601274127609',
        'en_source': 'https://www.openslr.org/12/',
        'corpus_sha256': {name: digest(corpus / name) for name in ['nl-test.parquet', 'en-test-clean.tar.gz']},
        'selected': selected, 'cases': cases,
        'reference_limit': 'Source-span boundaries include natural pauses. No hand-aligned speech activity; do not report these as DER references.',
    }
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('corpus', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    build(args.corpus, args.output)
