# Synthetic codec fixtures

Synthetic 600 ms tones at 48 kHz stereo; video sources contain a real video track. No user audio. Generated for the 2026-11-16 investigation; hashes and actual stream codecs verified with ffprobe. EUPL-1.2 project fixtures.

Codec normalization only, not ASR quality or physical recording. WMA is a helper probe outside the first offered picker set.

Each row in manifest.json records source SHA-256, actual container streams,
expected duration and tolerance. The production file source must return
non-empty 16 kHz mono PCM16; no file extension is used as codec proof.
