# Explicit YouTube source protocol v1

This optional source contract is separate from `ASR_BATCH_V1.md`. A source
server obtains a public video/captions/audio; an ASR engine transcribes a chosen
audio file. Choosing one destination does not configure or consent to the other.

Base path: `<configured-base>/ocideck-youtube/v1/`. JSON requests use
`Content-Type: application/json`, optional explicit bearer authorization, and
one per-task video/destination consent. No cookies, credentials in URLs,
automatic endpoint, playlist or service fallback. The native client pins the
selected egress tier and rejects redirects; web uses cancellable CORS fetch.
Changing module/online-media consent cancels pending source work and prevents
accepting a late response.

`GET capabilities` contains no video ID. A successful response:

```json
{"protocol":"ocideck-youtube","version":1,"captions":true,"audio":true,"audio_fragments":true,"audio_encoding":"pcm16-wav","max_audio_bytes":8388608}
```

`audio`/`audio_fragments` are false when a validated decoder is unavailable.
An audio capability requires `audio_encoding: "pcm16-wav"`. Other encodings are
not silently decoded in a browser. Missing/unsupported capabilities fail before
the app sends a video ID to a processing endpoint.

Every POST contains a validated 11-character `video_id`; success echoes exactly
that ID and the protocol/version. The app never forwards an input watch URL,
tracking/playlist parameters or arbitrary provider URLs.

| Endpoint | Request fields beyond `video_id` | Success fields |
|---|---|---|
| `metadata` | None | `status: "completed"`, bounded `title`, `duration_ms`, `audio`, `tracks` |
| `captions` | `track`: an offered opaque ID | Same `track`, `format: "vtt"`, bounded `text` |
| `audio` | Integer `start_ms`, `end_ms` (`0` end means source end) | `extension: "wav"`, bounded `base64`, exact `source_offset_ms`, actual `duration_ms` |

Tracks have unique bounded `id`, language tag and `kind` (`manual` or
`automatic`). An automatic/translated provider track is not presented as manual
captions or OciDeck ASR. A caption action never automatically starts audio ASR.
Active/upcoming/post-live unfinished sources are explicitly unsupported.

Audio is canonical mono 16 kHz PCM16 WAV, at most 8 MiB. The client validates the
actual bytes/header before handing them to the file-transcription preview.
`source_offset_ms` must equal the requested start. A source-cut file is not cut
again as though its clock still began at video zero; ASR word/segment times are
shifted back to the original video clock. Provider captions already have source
times. Whole overlapping cues are retained at fragment edges without invented
word-level timing. Original timing/cluster metadata remains inspectable.

Non-2xx replies contain a bounded error code, not raw provider diagnostics:
`configuration`, `consent`, `cancelled`, `network`, `protocol`, `unavailable`,
`live`, `access`, `rateLimited`, `busy`, `captionsMissing`, `audioMissing`,
`tooLarge`, `missingHelper`. The client maps known codes to translated guidance;
unrecognised/HTML/oversized bodies never become product messages. A closed HTTP
peer cancels the provider job and releases capacity. Authentication/origin/body
validation precedes provider work. No retries to another endpoint are implied.

The [operator implementation](../../testbed/youtube-source/README.md) documents
its concrete runtime, full notices, network/process boundaries, stricter source
and output limits and measured-platform scope. Neither this contract nor a
passing component test proves the complete release UI/hardware matrix (#2947).
