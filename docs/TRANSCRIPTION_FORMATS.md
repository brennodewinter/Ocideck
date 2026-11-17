# Audio and video import: tested formats

A container name does not identify its audio codec. OciDeck reads the file
contents and normalizes decoded audio to 16 kHz, mono, signed 16-bit PCM WAV.
Only a WAV already meeting those requirements bypasses decoding. Source files
are retained; decoding takes place in a separate staging directory.

## macOS decoder distribution

The ordinary route remains Apple's `afconvert`. WebM, Matroska and AVI use a
separate, bundled FFmpeg executable, without looking on the user's PATH or
installing software at import time. Its build enables only the explicitly
listed audio codecs and demuxers; it has no network protocols or video decoder.
See [the source/build/replacement instructions](../native/media_decoder/README.md)
and [the pinned configuration](../native/media_decoder/manifest.json).
WMA/ASF is outside the initially offered picker set, even though the helper's
limited codec set includes WMAv2.

The synthetic fixture corpus is in
[`integration_test/fixtures/audio_formats`](../integration_test/fixtures/audio_formats).
It covers PCM16/PCM24/float32/IMA ADPCM/µ-law WAV, MP3, Ogg Vorbis and Opus,
FLAC, AAC ADTS, M4A AAC and ALAC, MP4/AAC, MOV/AAC and PCM16, 3GP/AAC,
AIFF/PCM, CAF/PCM, WebM/Opus, MKV/Opus and AVI/PCM. Video fixtures contain
an actual video track. The tones prove decoding and duration, not ASR accuracy.

An explicit installed-decoder probe runs the real `IoFileCaptureSource`,
checks fixture hashes, nonempty PCM samples, duration, output format and source
preservation, and records the executable hash. Missing configuration fails:

```sh
OCIDECK_CODEC_MATRIX_DECODER=/absolute/OciDeck.app/Contents/Helpers/ffmpeg \
OCIDECK_CODEC_MATRIX_OUTPUT=/absolute/results.json \
scripts/gate_lock.sh flutter test test/transcription/real_format_matrix_test.dart
```

## Other platforms and limits

Windows retains Media Foundation; Linux retains GStreamer. Availability of a
helper alone does not prove a particular codec. Windows N/KN can require the
Media Feature Pack. Linux needs the codec plugins included by the distributor;
in particular AAC coverage depends on the applicable plugin inventory. Browser
imports use the local browser's `decodeAudioData`; no fallback silently uploads
media to a server.

Earlier decoder-only probes for issue #2942 observed:

| Platform and probe | Ogg Vorbis/Opus | MOV AAC/PCM | Explicit limitations |
| --- | --- | --- | --- |
| Debian 12 amd64, GStreamer 1.22 base/good/libav, emulated | Both decoded | Both decoded | CAF, WMA and IMA ADPCM WAV failed in the helper |
| Chromium 156 on macOS, production browser bridge | Both decoded | Both decoded | IMA ADPCM WAV, M4A/ALAC, AVI, AIFF, CAF, WMA failed |
| Playwright WebKit 27.2 on macOS, production browser bridge | Both decoded | Both failed | MOV, MKV and WMA failed |
| Windows release helper | Not yet established by this matrix | Not yet established | Requires a real Windows release-artifact probe |
| Firefox | Not established | Not established | The research browser failed to start; no product result |

These historical probes do not certify the current release artifacts or every
OS/browser combination. The release/UI and speech-recognition evidence lives
in [TRANSCRIPTION_RELEASE_MATRIX.md](TRANSCRIPTION_RELEASE_MATRIX.md) (#2947). If an import reports an unavailable codec, convert the source
to 16 kHz mono PCM16 WAV using a trusted local tool and import that copy. A
missing codec, a missing audio track, corrupt input and empty audio are separate
outcomes; a generic decoder failure is not evidence that a video has no audio.

## Current synthetic decoder matrix — 17 November 2026

The macOS column is the separately installed helper, tested through the real file source. The Windows/Linux columns test the exact production helper sources. Browser columns test the production bridge. **Decoded** means nonempty normalized PCM and duration within tolerance; it does not mean a full UI/ASR/release pass. **Limited** means this concrete environment rejected the fixture; use a local PCM-WAV copy.

| Fixture (container/codec) | macOS bundled helper | Windows MF | Linux GST | Chromium | WebKit |
| --- | --- | --- | --- | --- | --- |
| 3gp-aac.3gp | Decoded | Decoded | Decoded | Decoded | Decoded |
| aac-adts.aac | Decoded | Decoded | Decoded | Decoded | Decoded |
| aiff.aiff | Decoded | Limited | Decoded | Limited | Decoded |
| avi-pcm.avi | Decoded | Decoded | Decoded | Limited | Decoded |
| caf.caf | Decoded | Limited | Limited | Limited | Decoded |
| flac.flac | Decoded | Decoded | Decoded | Decoded | Decoded |
| m4a-aac.m4a | Decoded | Decoded | Decoded | Decoded | Decoded |
| m4a-alac.m4a | Decoded | Decoded | Decoded | Limited | Decoded |
| mkv-opus.mkv | Decoded | Decoded | Decoded | Decoded | Limited |
| mov-aac.mov | Decoded | Decoded | Decoded | Decoded | Limited |
| mov-pcm.mov | Decoded | Decoded | Decoded | Decoded | Limited |
| mp3.mp3 | Decoded | Decoded | Decoded | Decoded | Decoded |
| mp4-aac.mp4 | Decoded | Decoded | Decoded | Decoded | Decoded |
| ogg-opus.ogg | Decoded | Limited | Decoded | Decoded | Decoded |
| ogg-vorbis.ogg | Decoded | Limited | Decoded | Decoded | Decoded |
| opus.opus | Decoded | Limited | Decoded | Decoded | Decoded |
| wav-adpcm.wav | Decoded | Limited | Limited | Limited | Decoded |
| wav-float32.wav | Decoded | Decoded | Decoded | Decoded | Decoded |
| wav-pcm16.wav | Decoded | Decoded | Decoded | Decoded | Decoded |
| wav-pcm24.wav | Decoded | Decoded | Decoded | Decoded | Decoded |
| wav-ulaw.wav | Decoded | Limited | Decoded | Decoded | Decoded |
| webm-opus.webm | Decoded | Decoded | Decoded | Decoded | Decoded |
| wma.wma | Decoded | Decoded | Limited | Limited | Limited |

Raw results and provenance: [`integration_test/results/codec-matrix`](../integration_test/results/codec-matrix). Windows and Linux additionally exercise no-audio, truncated and empty inputs. The MS-ADPCM negative fixture deliberately targets the limited macOS build; a system decoder may legitimately support it (Linux does).

The current macOS system-decoder comparison passes all 19 ordinary-format
combinations through the real file source and `/usr/bin/afconvert`. The four
extended helper-only combinations are explicitly excluded from that comparison,
not counted as system-decoder successes. The separately installed helper passes
all 23 combinations and four negative cases; 44 targeted regressions pass against the freshly built release app copied to a clean installation path; its deep signature and bundled source-archive hash are verified.

A limited real-speech pass additionally decodes WAV, Vorbis/Opus Ogg, MOV/AAC,
WebM/Opus, MKV/Opus and AVI/PCM through the file source and then runs the
production local Whisper engine with the catalog-hash-verified `base` model.
All seven produce the expected English speech and timestamped segments. The
source sample and hashes are retained under `fixtures/codec_speech`. This is
not a multilingual accuracy benchmark or full UI/release certification.
