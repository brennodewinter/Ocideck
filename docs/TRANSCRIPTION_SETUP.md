# OciDeck — Transcription and recording: platform setup

> **Status:** setup matrix and step-by-step guide for the released builds · **Status last reviewed:** 2026-10-26 · **Published by:** Stichting LibreKAT

This page answers, per platform: what you must install or allow, how a
recording becomes a transcript, where the files live, and what to do when
something fails. The [User Guide](USER_GUIDE.md#transcription-and-recording)
explains the module itself; this page is the platform matrix the release
notes are tested against. Where a route was not proven on real hardware,
this page says *not tested* rather than letting a shared code path read as
support.

## The three steps, on every platform

1. **Turn the module on.** *Settings → Uitbreidingen (Extensions) →
   Transcription and recording*. It is off by default; the card also shows
   the capability matrix your machine actually reports, so you can inspect
   sources and models without enabling anything.
2. **Choose where text is made.** Local processing is the default and
   needs a model you download once (below). A server route exists only
   after you configure an ASR server profile yourself — there is no
   standing upload, and a task you did not confirm sends nothing.
3. **Record or open audio.** *Import → Record microphone…*, *Record system
   audio…*, *Record microphone and system audio…*, *Record tab audio…*
   (browser-dependent), *Transcribe file…* for an existing file, or
   *Opnemen en transcriberen* in the call rail during a connected call.
   Stopping offers the same three choices everywhere: transcribe now,
   keep for seven days, or discard. The transcript is an ordinary,
   editable Markdown document; the audio travels in the project's
   `media/` folder.

Recording other people — in a room or in a call — can require their
consent, and a meeting deployment may set its own recording policy. The
dialogs remind you; the law and the deployment decide. OciDeck is not a
Teams or Jitsi client and does not claim it can record every protected
audio channel: an operating system that excludes DRM-protected audio is
obeyed, not bypassed.

## Models: what you download, what it costs

The local engine is whisper.cpp v1.9.5 (MIT), run as a subprocess so a
native fault can never take the app down. Models are OpenAI Whisper
weights (MIT) in ggml format, pinned to a fixed revision of the
whisper.cpp model repository and verified by SHA-256 before use — a
mismatch is a refusal, not a warning. Nothing is bundled and nothing
downloads by itself: the model download, started by you, is the local
route's only network traffic.

| Model | Download | Tier | Web |
|---|---|---|---|
| `small` (default) | ~465 MiB | Balanced — the smallest with usable Dutch | Yes |
| `large-v3-turbo` | ~1.5 GiB | Accurate — best quality where memory allows | No (over the 2 GB WASM limit) |
| `base` | ~141 MiB | Light — fast, visibly weaker | Yes |

`tiny` is deliberately not offered: its measured output was not honest
enough to present. Peak memory roughly tracks the download size — the
accurate model asks for ~2 GB free while it runs. Models live in the
app-support folder (IndexedDB on web, which the browser may evict under
storage pressure — that reports as absent, never as corruption, and you
download again). The settings card deletes them again; there is no other
removal path to find.

**Already have the file?** On desktop the settings card also scans a few
well-known locations — `~/Downloads`, a `~/whisper.cpp` checkout, the
huggingface-cli cache of the pinned model repository, and pywhispercpp's
data folder — for `ggml-*.bin` files with a catalog model's exact size.
A match shows as "Found on disk: <path>" with an **Install from disk**
button: the file is SHA-256-verified and copied into the model folder,
and your original stays where it is. A file that fails the hash is
refused, never installed. This is a fresh look every time the card
opens, so a model you drop in later shows up without a restart.

## Platform matrix

| | macOS | Windows | Linux | Web |
|---|---|---|---|---|
| Release artifact | Signed + notarised, universal (arm64 + x86_64) | Unsigned zip and installer (SmartScreen warning is expected) | Unsigned | Static bundle; needs COOP/COEP headers from the host for local inference |
| Existing audio file | WAV/PCM proven; other containers decode or report `DecodeFailed` | same | same | Browser codec coverage decides |
| Microphone | Proven — after the macOS prompt | Offered — OS privacy toggle decides | Offered — hardware presence decides, most setups have no OS prompt | Proven — per-site browser permission |
| System / app audio | Offered — ScreenCaptureKit under *screen recording* consent (macOS 13+); DRM audio is excluded by the OS | Offered — WASAPI loopback records the endpoint mix, not one app | Offered — PipeWire/PulseAudio `.monitor` sources only; bare ALSA has none | Not offered as system audio |
| Tab audio | — | — | — | Chromium only; Firefox and Safari are told honestly instead of given a button |
| Call audio (Jitsi in-app) | Proven in a real two-person call | Not claimed — no proven per-source tap | Not claimed — no proven per-source tap | Proven in a real two-person call (Chromium-tested) |
| Local engine | Proven — measured on Apple Silicon | Built from the same pinned source — real-hardware proof pending | Built from the same pinned source — real-hardware proof pending | Proven — measured on the shipped WASM artifacts in Chrome, Firefox and WebKit |
| Batch server route | Proven | Available — same egress route, hardware proof pending | Available — same egress route, hardware proof pending | Proven — subject to CORS |
| Live server route | Proven against the pinned Vosk testbed | Available — same egress route, hardware proof pending | Available — same egress route, hardware proof pending | Available only without an API key — a browser WebSocket cannot carry the header |

Physical and virtual inputs — built-in, USB, Bluetooth, virtual cables —
are offered as the operating system reports them. Bluetooth headsets work
where the OS presents them as an input; a headset that switches profiles
mid-recording is handled as a source change, not a crash. Where the
platform cannot name a source, the dialog says so instead of guessing.

## Server setup: batch and live

Both server routes go through one **ASR server profile** (*Settings →
Extensions → Transcription and recording*). The profile holds a base
URL, a display name, an optional separate *live endpoint*, and the
opt-ins below. An API key, when the server needs one, lives in the
system keychain — never in the settings blob — and travels only in the
`Authorization` header, and only on `https` endpoints.

Three destination tiers, each with its own visible consent:

- **Loopback** — a server on this machine, e.g. `http://127.0.0.1:8080`.
  The default suggestion; needs no extra confirmation.
- **LAN** — a host on your network. Needs the explicit *trusted internal
  server* confirmation: an address you did not vet is not silently
  trusted.
- **Cloud** — an external endpoint. Needs its own confirmation and is
  `https`-only.

### The batch server — the definitive transcript

The contract is whisper.cpp's **`whisper-server`**: one
`POST /inference` multipart upload of the audio file you confirmed,
answered as `verbose_json`. That is the only protocol claimed — other
ASR servers are not promised to work, and each task asks again rather
than reusing an old consent. A connectivity probe you can run first
sends no audio. Uploads are capped at 400 MiB; a larger file reports a
capacity error instead of a silent truncation. A cancelled upload stays
cancelled; a failed one reports its typed reason — nothing retries or
falls back to a different destination by itself.

**Running one yourself.** The whisper.cpp repository builds
`whisper-server` from the same pinned source the local engine uses.
Exposing it is deliberately not the intended setup: without a TLS,
authentication and (for browsers) CORS layer in front of it, a
`whisper-server` port is an unauthenticated listener. Terminate TLS at
a reverse proxy you control, require the API key OciDeck can send, and
only then put it in the profile. What the server keeps or deletes after
`POST /inference` is that server's policy — OciDeck can show you what it
sent, not what happens next.

### The live server — provisional text while recording

A second endpoint on the same profile speaks **`vosk-ws-1`**: the Vosk
WebSocket protocol, proven against the pinned reference server in
`testbed/vosk-asr` (setup and wire contract in its README; the proof is
`make test-asr-integration`). Compatibility with other streaming ASR
servers is not claimed. The recording dialog offers the opt-in only
after a protocol probe succeeds, and ticking it is consent for that one
session — the host is named in the checkbox. A dropped link loses the
preview only; the recording keeps writing, and nothing reconnects or
re-sends by itself. In a browser this route exists only for an
unauthenticated endpoint: a WebSocket cannot carry the API-key header,
so a key-protected live server is honestly unreachable there rather than
silently unauthenticated. Live sources are the desktop recordings;
web recordings and file transcription do not produce live chunks.

### Browser specifics for server routes

A page cannot reach a LAN address quietly: CORS decides whether the
server answers the app, `http` targets are limited to literal loopback,
and a mixed-content rule blocks `http` from an `https` page. The profile
dialog tests reachability before offering anything, and PRIVACY.md lists
exactly which bytes go where under which consent.

## Storage, retention and wiping

- **Staged recordings** live in the app's staging folder for seven days
  after you choose *keep*, then are swept. On web there is no folder:
  recording and manifest stay in the tab as `mem:` assets and a reload
  loses them — the save flow warns before that happens.
- **Call provenance** rides along as `sources.json` next to the
  recording (as a `mem:` asset on web): which sources fed the mix, how
  much of each arrived, and how much went missing. A transcript names
  that missing audio in an *Ontbrekend* line; it never invents speaker
  labels from the participant list.
- **The transcript** is a Markdown document in your project; its audio
  sits in `media/` next to it, so the pair travels, exports and backs up
  like any deck asset.
- **Wiping.** Kept recordings delete from the staged list; models delete
  from the settings card; the API key deletes with the profile's secret.
  Nothing else is retained — there is no transcript telemetry to purge.

## What was actually proven

Every positive claim above names its evidence; anything absent is *not
tested*, not silently supported.

| Route | Evidence |
|---|---|
| Local engine, macOS | Measured on Apple Silicon, `whisper-cli` v1.9.5 static universal binary, Dutch reference WAV — design doc §4.5 |
| Local engine, web | Measured on the shipped WASM artifacts in Chrome, Firefox and WebKit, same reference audio — §4.6 |
| Live server protocol | Integration test against the pinned Vosk reference server: probe, partials, definitive pass — `make test-asr-integration` |
| Jitsi call end-to-end | Real two-person call on the released macOS build and the released web bundle (join, two-way media, share, leave/rejoin) — #2541, #2544 |
| Call recording → transcript | Real two-person call, macOS and web: mix WAV, `sources.json`, missing-audio line — #2545, #2548 |
| Windows and Linux builds | Shared code paths ship and pass the full test suite; **no real-hardware proof is on file** — treated as not tested until one exists |
| iOS / Android | Not release platforms — no claim at all |

## When something goes wrong

Every failure in this module is a typed, explainable outcome — the
dialog names it rather than pretending success:

- **DecodeFailed** — the container is not one the engine reads. WAV/PCM
  always works; convert anything else first.
- **CapacityExceeded** — the file is over the upload or memory cap. For
  a server route that is the 400 MiB upload ceiling; on web it is the
  2 GB WASM ceiling, which is also why `large-v3-turbo` is not offered.
- **ConsentRequired** — the destination needs a confirmation you have
  not given (LAN trust, cloud confirmation, per-task consent). Give it
  deliberately or pick local.
- **noIsolation** (web only) — the host does not send COOP/COEP headers,
  so the browser refuses `SharedArrayBuffer` and local inference cannot
  run. Serve the bundle per HOSTING.md §3, or use a server route.
- **Live lost** — the live endpoint dropped. The preview is gone; the
  recording and the definitive pass are unaffected, and a retry button
  asks again — nothing reconnects by itself.
- **Source lost / missing audio** — a track or network path went away
  mid-recording. What was written stays written, the manifest records
  the gap, and the transcript names it.
- **No record button in a call** — the platform reports no per-source
  call-audio tap. That is an honest absence, not a hidden switch.

The staged seven-day folder is also the recovery path: a recording that
outlived its dialog can still be transcribed or deleted from the staged
list.
