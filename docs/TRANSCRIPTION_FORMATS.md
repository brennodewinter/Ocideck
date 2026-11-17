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
OS/browser combination. The release/UI and speech-recognition evidence remains
tracked in #2947. If an import reports an unavailable codec, convert the source
to 16 kHz mono PCM16 WAV using a trusted local tool and import that copy. A
missing codec, a missing audio track, corrupt input and empty audio are separate
outcomes; a generic decoder failure is not evidence that a video has no audio.
