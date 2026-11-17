# Transcription release matrix — executable user-flow proof (#2947)

> **Status:** living verification record · **Last executed:** 2026-11-17 on
> macOS 27.0.1 (Apple Silicon); local probes ran on source `9d54b381e`, the
> media-URL row cites `e607f8798` evidence, app 0.7.7+49
>
> This matrix is the *executable* half of #2947: for every offered
> transcription route it names the current evidence, the reproduction
> command, or the explicit reason a cell is not (yet) proven. A cell that
> says *not tested* is an honest absence, never a silent pass. A green cell
> without a dated run, artefact and engine/model/server name is not green.
>
> Cell states: **werkt** (dated proof below), **niet beschikbaar**
> (deliberate — reason named), **defect** (linked issue), **niet getest**
> (explicit; reproduction command included).

## Platforms and what they mean here

| Platform | What counts as proven |
| --- | --- |
| macOS arm64 | Real run on this machine, dated 2026-11-17 |
| macOS x64 | Universal build shares the arm64 code path; a separate x64 run is *not yet tested* |
| Windows x64 | Installed release artefact on real Windows, not the CI stub |
| Linux x64 | Installed artefact on a real desktop session (Flatpak and native package each count separately) |
| Chromium/Edge | The shipped `web/` bundle in a real Chromium-family browser |
| Firefox | The shipped bundle in real Firefox — the 2026-11-16 research browser failed to start on a local profile issue, so no product result exists yet |
| Safari/WebKit | The shipped bundle in WebKit (Playwright WebKit counts) |
| Android / iOS | **Bewust niet beschikbaar** — not release platforms by design (`docs/design/TRANSCRIPTION.md` §1.2/§5) |
| Windows/Linux ARM64 | **Bewust niet beschikbaar** — outside the desktop Whisper ABI set |

## Route matrix

### 1. File → decode → local ASR → editable document → save → reopen

| Platform | Status | Evidence / reproduction |
| --- | --- | --- |
| macOS arm64 | **werkt** | `real_codec_speech_test.dart` 2026-11-17: all 7 `codec_speech` containers decoded through the production file source and transcribed by installed `whisper-cli` (sha256 `b106266a…6a0830`) with catalog-pinned `ggml-base.bin` (sha256 `60ed5bc3…ba2efe`) — correct English text + timestamps. Command under *Probes* |
| macOS x64 | niet getest | same universal binary; run the same probe on an Intel Mac |
| Windows x64 | niet getest | build/install/open proven on artefact `951fdc2e9` (candidate run); the file→ASR→document pass still needs a real Windows run — `integration_test/desktop_audio_test.dart` is the decode half |
| Linux x64 | niet getest | helper decode proven in a Debian 12 container (20/23 synthetic fixtures); the full app pass needs a real desktop session + package form |
| Chromium/Edge | niet getest | decoder bridge proven 2026-11-17 (`codec-matrix/browser`); WASM engine measured in `native/whisper_wasm/probe/results/`; full save/reopen flow not yet run in-app |
| Firefox | niet getest | WASM probe results exist (`bridge-firefox-*`); installed research browser did not start — local profile, no product result |
| Safari/WebKit | niet getest | decode matrix limits recorded (`codec-matrix/browser`); WASM probe results exist (`bridge-webkit-*` where present) |

Codec coverage per format lives in
[TRANSCRIPTION_FORMATS.md](TRANSCRIPTION_FORMATS.md) — 23-fixture matrix per
platform/browser, dated 2026-11-17, results under
`integration_test/results/codec-matrix/`.

### 2. Model download → hash → install

| Platform | Status | Evidence / reproduction |
| --- | --- | --- |
| All desktop + web | **werkt** (route) | `ggml-base.bin` fetched 2026-11-17 from the catalog-pinned revision `5359861c…` and SHA-256 verified against `whisperModelCatalog` — a mismatch refuses the model by design. Download/verify logic covered by `model_download_test.dart`, `model_download_web_test.dart`, `model_store*_test.dart` in the VM suite |

### 3. Live server ASR (WebSocket)

| Platform | Status | Evidence / reproduction |
| --- | --- | --- |
| macOS arm64 | **werkt** | `make test-asr-integration` 2026-11-17 against the pinned `alphacep/kaldi-vosk-server` container (`sha256:3810243…`) + pinned `vosk-model-small-en-us-0.15`: capability probe, live partial hypotheses ("zero one eight…"), definitive transcript over the same WAV, clean eof |
| Other platforms | niet getest | same test runs wherever Docker and the fixture exist; the route is platform-independent Dart — UI/host differences unproven |

### 4. Batch server ASR (whisper.cpp `whisper-server`)

| Platform | Status | Evidence / reproduction |
| --- | --- | --- |
| macOS arm64 | **werkt** | `asr_batch_whisper_testbed_test.dart` 2026-11-17 against `whisper-server` (sha256 `1dbd367d…94225`) built from the pinned v1.9.5 source (`native/whisper_cli/manifest.json`) on loopback with the catalog `base` model; server log shows real inference of three hostile-path uploads |
| Other platforms | niet getest | start a loopback `whisper-server`, set `OCIDECK_BATCH_ASR_URL`, run the same test |

### 5. Media-URL source → captions or ASR clip → document

| Platform | Status | Evidence / reproduction |
| --- | --- | --- |
| macOS arm64 (native clients + widgets) | **werkt** | `integration_test/results/youtube-source/` 2026-11-17: manual and automatic captions, a 25 s source clip and a full 19 s video through the production HTTP clients and ASR; Markdown saved and reopened byte-for-byte; the no-caption/no-speech refusal and the typed access error are proven paths too — see the directory README for component hashes and limits |
| Chromium + WebKit (compiled bundle) | **werkt** | Same evidence set: real TLS/CORS source and ASR endpoints under production CSP, identical audio digest, identical ASR text digest |
| Windows / Linux | niet getest | the operator-side yt-dlp helper contract is shared code; installed-artefact runs outstanding |
| Firefox | niet getest | research browser failed to start; no product result |

### 6. Recording sources (microphone, system/tab, combination, call audio)

| Route | Status | Evidence / reproduction |
| --- | --- | --- |
| Call audio, macOS + web | **werkt** | Real two-person Jitsi call on released builds: mix WAV, `sources.json`, missing-audio line — #2545/#2548 (reproduction: `testbed/jitsi-meet/PROCEDURE.md`, form `EVIDENCE_FORM.md`) |
| Jitsi join/preflight | **werkt** | `make test-jitsi-integration` against the pinned testbed (Docker required) |
| Microphone, physical | niet getest | VM has no device; needs a real mic on each desktop platform — see `integration_test/` source tests for the contract half |
| System/tab/combination | niet getest | capability labels are tested per binding in the suite; physical capture needs real devices per OS |
| In-app call audio, Windows/Linux | niet getest | no physical-device run on file |

### 7. Web storage, export, tab close/reload, recovery

| Route | Status | Evidence / reproduction |
| --- | --- | --- |
| Browser persistence roundtrip | **werkt** | `flutter test --platform chrome test/browser_storage_web_test.dart` ran 2026-11-17 in real Google Chrome on this machine — localStorage, package/media roundtrip, save/open/delete |
| Web audio ownership | defect → **hersteld** | #2944 (active-audio retention), closed |
| WASM context release | defect → **hersteld** | #2945, closed |
| Last recording blob | defect → **hersteld** | #2946, closed |
| Desktop crash recovery / staging cleanup | niet getest | 7-day staged window is implemented and unit-covered; a real crash proof per platform is outstanding |

### 8. Consent, offline and failure routes

| Route | Status | Evidence / reproduction |
| --- | --- | --- |
| No server consent → no egress | **werkt** (contract) | `asr_server_gate_test.dart`, `transcription_boundary_test.dart`, `network_sink_guard_test.dart` — fail-closed in the suite |
| Offline / engine unavailable | **werkt** (contract) | typed outcomes (`DecodeFailed`, `ConsentRequired`, `noIsolation`) — TRANSCRIPTION_SETUP.md *When something goes wrong* |
| Privacy boundary (nothing leaves the device unasked) | **werkt** (contract) | privacy projection boundary gate in `make check` |

## Probes — reproduction commands

```sh
# A. Live server ASR (Docker required; one-time model fetch):
cd testbed/vosk-asr && ./fetch-model.sh && docker compose up -d && cd ../..
make test-asr-integration

# B. File → decode → local whisper → transcript (installed app helpers):
OCIDECK_CODEC_MATRIX_DECODER=/usr/bin/afconvert \
  # or the bundled ffmpeg helper; afconvert covers the ordinary formats,
  # WebM/MKV/AVI need the bundled helper or ffmpeg
OCIDECK_CODEC_SPEECH_WHISPER=/Applications/OciDeck.app/Contents/Helpers/whisper-cli \
OCIDECK_CODEC_SPEECH_MODEL=/path/ggml-base.bin \
OCIDECK_CODEC_SPEECH_OUTPUT=/tmp/codec-speech-evidence.json \
flutter test test/transcription/real_codec_speech_test.dart

# C. Batch whisper-server (build the server target from the pinned
#    whisper.cpp source once, then point the test at it):
cmake --build native/whisper_cli/build/build-macos-arm64 \
  --config Release --target whisper-server
./native/whisper_cli/build/build-macos-arm64/bin/whisper-server \
  -m /path/ggml-base.bin --host 127.0.0.1 --port 8090 &
OCIDECK_BATCH_ASR_URL=http://127.0.0.1:8090 \
  flutter test test/transcription/asr_batch_whisper_testbed_test.dart

# D. Decode-only installed helper (Windows/Linux release artefacts):
flutter test integration_test/desktop_audio_test.dart

# E. Browser storage roundtrip (real Chrome):
flutter test --platform chrome test/browser_storage_web_test.dart

# F. Jitsi testbed (Docker):
cd testbed/jitsi-meet && ./run.sh up && ./run.sh users && cd ../..
make test-jitsi-integration
```

## Release gate for transcription changes

When a change touches `lib/services/transcription/`, the transcription
dialogs, `web/whisper/` or the bundled helpers, the merge request must
name which of these ran — and cells touched by the change get fresh dates:

1. `make check` (always; includes the transcription VM suite — 65 test
   files including boundary/consent contracts)
2. Probe **A** when the live-server path changes
3. Probe **B** when decode, the file source or the local engine changes
4. Probe **C** when the batch server contract changes
5. Probe **D** on the platform whose installed helper changed
6. Probe **E/F** when web storage or call audio changes

Physical-device checks (real microphone, real two-person call per OS)
stay a separate release checklist item — a VM without a device proves no
physical capture, and a green build is never a feature test.

## Open cells — next actions

- Windows x64 + Linux x64 full file→ASR→document→save/reopen on installed
  artefacts (needs the candidate builds; decode half is `desktop_audio_test`)
- Firefox browser pass (install/profile issue on the research machine)
- Physical microphone and call capture per desktop OS
- macOS x64 pass of probes B and C on an Intel machine
- Package-form checks: Flatpak + native package on a real Linux desktop
