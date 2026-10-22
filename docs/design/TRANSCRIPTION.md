# OciDeck — Transcription & recording: product contract and format design

*An optional, off-by-default extension that turns audio into an ordinary,
editable Markdown document — a file you can transcribe, a microphone you can
record, provisional text while you record and a definitive pass when you stop —
without a hidden upload, a bundled model, or a private file format.*

> **Status:** **design, not shipping behaviour** — the product contract, the
> on-disk contract and the provider-neutral boundary are fixed here **before**
> any platform code lands; deeltickets #2510–#2525 consume this document and
> may not contradict it without amending it first · **Status last reviewed:**
> 2026-10-22 · **Published by:** Stichting LibreKAT

> **This is a design doc, not shipping behaviour.** It is the format-first
> gate, the same role [`DOCUMENT_MODE.md`](DOCUMENT_MODE.md) played for
> documents: the disk contract and the shared-boundary decision are signed off
> here (core-values guardian, software architect) before implementation starts.
> When behaviour ships, [`FILE_FORMAT.md`](../FILE_FORMAT.md),
> [`USER_GUIDE.md`](../USER_GUIDE.md) and the [`CHANGELOG.md`](../../CHANGELOG.md)
> carry the truth; this document remains the *why*.

> Sibling design docs: [`AI_ASSIST.md`](AI_ASSIST.md) (the optional-AI
> capability this deliberately does **not** reuse), [`COLLABORATION.md`](COLLABORATION.md)
> §7.1.6 (meeting media is a separate consent domain), [`DOCUMENT_MODE.md`](DOCUMENT_MODE.md)
> (the document file kind the transcript rides on), [`OCIWACHT.md`](OCIWACHT.md)
> (the privacy projection every export passes), [`FORM_INTAKE.md`](FORM_INTAKE.md)
> (the unprefixed-marker precedent the transcript marker follows).

> Tracker: epic
> [#2508](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/2508); this
> document settles
> [#2509](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/2509). §7 maps
> every section to the deelticket that consumes it.

---

## 1. Purpose & scope

OciDeck gains one optional module — **Transcriptie**, off by default, under
**Settings → Uitbreidingen** next to the existing module cards
(`moduleRegistry`, `lib/state/module_registry.dart`) — offering three user
routes:

1. **Transcribe an existing file.** Pick an audio or video file on disk;
   receive a Markdown transcript.
2. **Record, then transcribe.** Record a local source (microphone, and where
   the platform proves it, app/system audio or a combination); on Stop, run the
   definitive transcription over the stored audio.
3. **Live provisional text.** During a recording, show provisional text that
   the user can watch but not yet trust; on Stop, the definitive pass replaces
   it — it never silently becomes the saved text.

The result of every route is the same artefact: **a plain `.md` document**
(FILE_FORMAT.md §14) plus, where the user keeps it, the original audio beside
it in `media/`.

### 1.1 The promise this extends

Document mode already proved the shape: the file is the master, everything
OciDeck-specific lives beside it or in a comment a foreign reader ignores, and
the file keeps working when OciDeck is gone. A transcript is that shape under
more pressure — the *content* is speech, the *evidence* is a recording the user
may need to keep or must be able to destroy, and the *provenance* (who made
this text, from what, when) is part of its trustworthiness. This contract
exists so that seventeen implementation tickets cannot each invent their own
answer to "where does the audio go".

### 1.2 Non-goals

- **No meeting provider and no call-bot.** OciDeck records sources the OS or
  browser exposes; it never joins a call, never pretends to be a participant,
  and does not revive the closed Teams/Jitsi participation line
  ([`COLLABORATION.md`](COLLABORATION.md) §7.1.6 keeps meeting media a separate
  consent domain).
- **No bundled or silently downloaded model weights.** Models are user-managed
  (#2512/#2513); the app shows what is installed and what a route needs.
- **No mandatory server, cloud account, Ollama or Python install.** Local
  processing is an option everywhere it is proven feasible; a consciously
  chosen server is a second route (§4.5), never a requirement.
- **The existing AI assistant is not a speech engine.** `AiClientService`
  speaks chat/completions; it never receives audio, transcript text, or model
  bytes. An ASR server gets its own profile and protocol (§4.5). Any future
  opt-in that would let AI Assist see transcripts is a separate design, not an
  assumption of this one.
- **Android and iOS are out of scope.** They exist as Flutter project folders
  but are not release platforms (README.md, BUILD.md). The matrix carries them
  in a separate *not supported* column (§5) until a product/release decision
  changes that; this contract does not design for them and does not foreclose
  them either.

---

## 2. The product contract

### 2.1 What the user must be able to see beforehand

Before starting, the user can see which of the three routes works **on this
device, right now** — not on the spec-ideal device. That has three honest
tiers, and the contract names them rather than blurring them:

- **Detectable without asking.** Whether a microphone exists, whether
  PipeWire/PulseAudio is running, whether the browser grants `getUserMedia`,
  whether a local engine and model are installed. Probing costs nothing and
  prompts nothing; it may run while the settings page is open.
- **Only decidable after user action.** OS/browser *permission* — the TCC
  prompt, the browser mic prompt, the screen-recording grant. The design never
  claims these as "available": they are **"to try after permission"**, and the
  permission dialog appears only because the user pressed a button that needs
  it, never because a probe ran.
- **Limitations of the source itself.** A specific app's audio may be
  uncapturable (DRM-protected streams are excluded by the OS, not by us), a
  browser tab may share audio only in one engine family, an RDP session may
  present no capturable endpoint. The UI names the limit it actually sees and
  never promises "system audio" in the abstract.

**A conversation in the same room and an online conversation are not the same
source** and are never silently named as one. A microphone capture is a room
source; app/system capture is an online-call source; a combination is both.
The provenance line in the transcript (§3.1) names the source *kind* the
recording actually used, so a reader can tell "speaker in the room" from
"remote side of a call" without trusting the author's memory.

### 2.2 Source kinds

Four source kinds, spelled as the UI names them:

| Kind | What it is | What it is not |
|---|---|---|
| `bestand` (file) | An existing audio or video file the user picks; nothing is recorded. | A path to be silently copied — the file stays where it is until the user saves the transcript (§3.2). |
| `microfoon` | One input device's room capture. | A promise about what else is audible — a call's remote side may leak in through the speakers, but that is room capture, not app capture, and the provenance says `microfoon`. |
| `app-/systeemgeluid` | Another app's output or the output mix of an endpoint, captured without the microphone. | Never a universal claim. Per platform this is a specific API with specific exclusions (§5); where it cannot be proven it is not offered. |
| `combinatie` | Microphone **and** app/system audio in one recording — the online conversation where both sides matter. | A single mono mix that throws away who said what: where the platform gives separate channels, the durable file keeps them apart (§3.2), because that separation is the only honest basis for speaker labels later. |

### 2.3 Consent, permission and other people's voices

- **Recording is visible.** A recording has a visible start, a running
  indicator, and a stop under the user's finger at all times. There is no
  background capture and no capture that outlives its session.
- **Permission follows the button.** Probing never triggers a permission
  prompt; starting a source may. A denied permission is a normal outcome with
  a next step, not a crash path (§4.4).
- **Other participants did not consent to this app.** The contract surfaces
  that fact rather than hiding it: starting a source that captures more than
  the user's own voice shows a one-line reminder that recording others may
  need their consent. It is a reminder, not a legal gate — the same honesty
  the meeting-adapter rules apply (`COLLABORATION.md` §7.1.6: recording
  indicators and provider consent flows are preserved, not replicated).
- **A platform promise must not outrun the feature.** The macOS build today
  declares `NSMicrophoneUsageDescription` as *"wordt niets opgenomen of
  verstuurd"* — the string exists for the mic monitor (#2158), which is
  pass-through only. The moment a recording route lands, that text becomes
  false and must be rewritten in the same change that enables recording
  (#2516); shipping recording under a "nothing is recorded" permission string
  is a lie the OS shows in our name.

### 2.4 The result the user gets

- **An editable `.md` document** — not a deck, not a panel-only state. It
  opens in the document editor (§3.1) and in every other Markdown tool.
- **A clear choice about the original audio** — keep it beside the document
  (evidence, re-transcription input) or let it go; the contract never deletes
  silently and never keeps silently (§3.2).
- **Honest detail.** Timestamps and speaker labels appear only where the
  engine actually delivered them. A transcript without diarization has no fake
  speaker column; a transcript without word timings has no timestamp list.
  Absent is a fact, not an omission to paper over.

---

## 3. On-disk format

### 3.1 The transcript document

A transcript is a **document** in the sense of FILE_FORMAT.md §14: plain
UTF-8 `.md`, no `marp: true`, no front-matter requirement, byte-faithful
round-trip under §14.3. OciDeck knows it is a transcript by **one HTML comment
on a line of its own**, the same mechanism `<!-- form -->` and `<!-- toc -->`
use — unprefixed, ignorable by every other reader, and reported rather than
silently dropped when malformed (§14.14's rule applies to this marker too):

```markdown
<!-- transcript version=1 audio="media/opname-20261022-1403.m4a" -->
# Transcript — vergadering 22 oktober

Bron: [opname-20261022-1403.m4a](media/opname-20261022-1403.m4a)
Opgenomen: 2026-10-22 14:03 · Bron: microfoon · Duur: 0:41:12
Engine: whisper.cpp `base` (lokaal) · Taal: nl

---

Eerste alinea van de tekst…
```

**Marker.** `<!-- transcript version=1 audio="…" -->` is the first marker of
the file, at most once — directly under the front matter when the document
carries any, the first line when it does not (a document's front matter stays
the author's; the marker is the only line OciDeck owns up there). `version` is
a monotonically increasing integer — the
same role `ocideck_format` plays for decks, inside the marker because a
document carries no owned front-matter vocabulary (§14.1: OciDeck may join a
vocabulary, not mint a private one). `audio` is the **one machine-readable
pointer** to the source recording: a project-relative path into `media/`, run
through the same containment guard as every other asset reference — absolute
paths and `../` escapes are refused, not followed. `audio` is absent when the
original is gone (deleted by choice, or never kept); the marker stays, because
"this text came from a transcription" remains true and visible.

**Provenance is ordinary text.** The block under the heading — source link,
recording moment, source kind, duration, engine and model, language — is
written as human-readable lines, not attributes and not a sidecar. It is the
part a foreign reader must be able to see, the part the author may correct by
hand, and the part that must survive a paste into any other editor. OciDeck
writes it once at creation and then treats it as *content*: it never rewrites
it silently, and a hand-edit to it is an edit, not corruption. The `audio=`
attribute is authoritative for *finding the file*; the text is authoritative
for *saying what happened*. Where they disagree, the text is what a human sees
— which is why the attribute is only a path and carries no claims of its own.

**The audio link is an ordinary link.** `[name](media/name)` — clickable in
every Markdown reader, resolvable by OciDeck's existing asset containment, and
the only representation that still means something in a plain text editor.
Alternatives considered and rejected:

- **`<audio src="…">`** (the slide convention, FILE_FORMAT.md §5) — renders to
  nothing in GitHub and most plain readers, and transcripts are read more
  often outside OciDeck than slide audio is. A link degrades to text; a tag
  degrades to markup.
- **A front-matter key** — §14.1 forbids an `ocideck_`-prefixed vocabulary in
  documents, and no third-party vocabulary owns "this is a transcript".
- **A sidecar (`<name>.transcript.json`)** — the provenance would be invisible
  to any reader who only has the `.md`, which is exactly the reader the
  provenance exists for. Sidecars are for data *about* rendering or tooling
  (annotations, dispositions), not for facts the file itself must carry.
- **A fenced JSON block** — survives as a code block elsewhere (the ` ```chart `
  precedent), but the provenance is not data to be executed; it is a sentence
  a person should read. Ordinary text wins on the bewaker ladder: it is the
  first rung that holds.
- **Base64-embedded audio** — explicitly rejected by the epic and by the
  no-base64 rule (FILE_FORMAT.md §1): audio is bytes, bytes live beside the
  file, never in it.

**Timestamps and speakers are ordinary text too**, present only where
delivered (§2.4):

```markdown
[0:04:12] **Spreker 1:** De eerste zin.
[0:04:31] **Spreker 2:** Het antwoord.
```

`[h:mm:ss]` at the start of a paragraph, `**Spreker n:**` as plain emphasis —
both readable as themselves in any tool, both editable, both generated only
from real engine output. A `combinatie` recording that kept its channels
apart (§2.2) may label `microfoon`/`gesprekspartner` sides where the engine
maps them; a label the engine cannot support is absent, never guessed.

### 3.2 The audio file

- **Location:** `media/` beside the `.md` — the existing folder for video and
  audio (FILE_FORMAT.md §1), inside the same project-folder containment. A
  transcript document uses the document working-directory concept of §14.2;
  `media/` joins `images/` and `data/` there.
- **Naming:** generated on save as `media/<slug>-<yyyyMMdd-HHmmss>.<ext>`
  (collision-safe through the existing numbered-suffix rule); a transcript of
  an *existing file* may keep that file's basename. No absolute path is ever
  written into the marker.
- **Container:** the durable recording is written once, in a container the
  platform produces without extra dependencies — **PCM WAV is the baseline**
  everywhere (no codec negotiation, decodable by every engine and every stock
  player; 16 kHz mono ≈ 1.9 MiB/min, so a three-hour meeting fits the existing
  1 GiB media cap). A platform that natively yields a compressed container
  (`.m4a`, `.ogg`, `.webm`) may store that instead; the transcript never
  *requires* re-encoding. A `combinatie` source keeps its channels separate
  where the platform delivers them (§2.2).
- **Lifecycle.** Recording lands in the per-session **staging folder** under
  the OS temp directory — the same staging a picked image gets before first
  save (FILE_FORMAT.md §1), so the bytes are safe from the moment recording
  starts, and the ordinary save-time copy moves them into `media/` because
  the layout already matches. Until the transcript is saved, the recording is
  *not yet saved* and marked as such; staging cleanup shares the 7-day
  recovery period, so a crash cannot orphan a recording before recovery has
  had its chance, and recovery can offer the staged audio the same way it
  offers a recovered draft.
- **Keep or let go.** Saving a transcript asks once what happens to the
  original: **keep** (moved into `media/`, linked as above) or **do not keep**
  (the staged file is deleted with the session, `audio` absent from the
  marker). Deleting later removes the file and the attribute, and the
  provenance text gains nothing and loses nothing silently — the user edits
  it, the app does not rewrite history. Deleting the *document* offers the
  media file's deletion alongside it, the way any document's assets are
  handled.
- **File-source transcripts** work the same way through the other door: the
  picked file is *referenced* during transcription (it stays where the user
  put it) and the keep-choice on save decides whether a copy is moved into
  `media/`. A transcript that references audio outside its own folder is
  never written — containment would make it a lie on every other machine.
- **Web.** There is no project folder in the browser build; recorded audio
  lives in the `mem:` asset store (`WebAssetStore`, 256 MiB app-wide budget —
  a real constraint: a long WAV recording does not fit, so web recording
  either stores a compressed container or caps recording length honestly,
  decided by #2513/#2517's proof, not by this document's optimism). Saving the
  transcript offers **two downloads**: the `.md` and the audio file; the
  `.md`'s `media/` reference is honest about expecting the audio to be placed
  beside it on a real filesystem. Reloading the page without downloading loses
  the audio — the save flow says so before it happens, the same warning an
  unsaved `mem:` image already gets.

### 3.3 Round-trip and migration requirements (acceptance as requirements)

- A `.md` **without** the marker is a plain document — unchanged by any of
  this; the marker's absence is the absence of the feature in that file.
- A document **with** the marker parses to a typed transcript view; a
  malformed marker (a second one, a bad attribute, an almost-marker) is
  reported, and the file degrades to a plain document showing the raw comment
  — the form-marker's rule, applied again.
- Parse → serialize is byte-faithful through the document path (§14.3);
  required tests: marker round-trip, `audio`-absent round-trip, a document
  that gains and loses its audio file, and an almost-marker rejected by the
  checker. These tests are an acceptance condition of #2511, and no ticket
  before it needs the parser.
- Existing `.md` and `.ocideck` files are untouched: no new front-matter key,
  no change to the deck grammar, no package-format change. The only new
  on-disk artefact this design adds is `media/*.m4a|wav|…` in a document's
  working folder — a location decks already use.

### 3.4 Export and sharing

- A document **export** (§14.4) carries the projected text through OciWacht
  like any document — a transcript is exactly the kind of text the privacy
  scan exists for. The projected `.md` keeps the marker and the provenance
  text, and keeps the audio link as written: a recipient gets the *reference*,
  not the bytes, and a link to a file they do not have is honest about it.
- **Audio never travels inside an export.** Not embedded, not base64'd, not
  silently attached. Whoever should have the audio gets the file itself by a
  deliberate act.
- **No `.ocideck` package route for transcripts.** §14.4 does not offer the
  presentation package for documents and this design does not carve an
  exception; on desktop the working folder (document + `media/`) *is* the
  portable unit, and on web the two downloads are.
- **Import is just opening.** A `.md` + `media/` folder produced elsewhere
  (another OciDeck, a hand-made folder) opens: the marker resolves its `audio`
  through containment, a missing file shows the provenance as text with the
  link visibly unresolvable — the document is never refused for missing
  evidence.

---

## 4. The provider-neutral boundary

Two small interfaces, fixed here so #2512–#2525 build platform code *behind*
them instead of around them. They live in `lib/services/transcription/` —
services, headless, no UI imports (the `check_conventions` layer rule);
platform splits use the `lib/platform/` `_io`/`_web`/`_stub` pattern with the
choice in one place.

### 4.1 `CaptureSource` — where bytes come from

```dart
enum CaptureSourceKind { file, microphone, systemAudio, combination }

enum CaptureAvailability {
  available,              // detectable now, no prompt needed
  tryAfterPermission,     // real answer only after the user acts
  unavailable,            // this platform/setup cannot, with a reason
  untested,               // plausible on paper, not yet proven here
}

abstract class CaptureSource {
  CaptureSourceKind get kind;

  /// Detection only. Never triggers a permission prompt, never opens a
  /// device, never touches the network. Cheap enough to run in settings.
  Future<CaptureAvailability> probe();

  /// The one call that may ask for permission — because the user pressed
  /// a button that needs it. Fails closed with a typed [CaptureError].
  Future<CaptureSession> start(CaptureRequest request);
}

abstract class CaptureSession {
  /// The durable file being written (staging path; moved to media/ on save).
  /// Always present — a session that cannot store is not a session.
  String get durablePath;

  /// Live chunks for provisional transcription, when the source+engine pair
  /// supports it. Absent means "no live route", not "live failed".
  Stream<AudioChunk>? get liveChunks;

  /// One event when the source ends on its own — device gone, shared tab
  /// closed, permission revoked mid-capture. Absent where a source has no
  /// spontaneous end (a file does not "run"). The session boundary (#2510)
  /// subscribes to this and stops the recording: a capture that kept going
  /// after its source died would run invisibly, which §2.3 forbids.
  /// (Added when #2510 implemented this boundary — the spontaneous-end
  /// channel is what makes "stop provably on source/permission loss"
  /// testable instead of aspirational.)
  Stream<CaptureEndCause>? get ended;

  /// Stops capture; resolves when the durable file is complete and flushed.
  Future<RecordedAudio> stop();
}
```

### 4.2 `TranscriptionEngine` — where text comes from

```dart
enum EngineKind { local, batchServer, liveServer }

abstract class TranscriptionEngine {
  EngineKind get kind;

  /// What this engine can truthfully deliver on this device: languages,
  /// timestamps, diarization, streaming input, required model presence.
  /// The UI builds its offers from this and nothing else.
  Future<EngineCapabilities> capabilities();

  /// The definitive pass over a finished recording. Always present on every
  /// engine kind — provisional text never substitutes for it.
  Future<TranscriptResult> transcribe(
    AudioRef audio,
    TranscriptionOptions options,
  );

  /// Provisional text over live chunks (liveServer and capable local engines
  /// only). Output is marked provisional end-to-end until [transcribe] runs.
  Stream<PartialTranscript>? transcribeLive(Stream<AudioChunk> chunks);
}
```

**The one-recording-two-outputs rule.** A `CaptureSession` writes durable
audio *and* may feed `liveChunks`; both come from one capture, never two
microphone grabs. On `stop()`, the definitive `transcribe(durablePath)` runs
and *replaces* whatever the live stream showed — the stored text is always
the definitive one, and the provenance names the engine that made it, not the
one that previewed it. This is what makes "live where possible, definitive
always" one code path instead of a special case.

### 4.3 Engine kinds and the server route (#2524, #2525)

| Kind | What it is | Consent |
|---|---|---|
| `local` | An on-device engine — whisper.cpp behind the platform channel on desktop, a WASM engine inside browser limits on web. | None beyond installing it; nothing leaves the device. |
| `batchServer` | A user-configured ASR endpoint: upload a finished file, get a transcript back. | **Per task**: each submission names the host and asks. |
| `liveServer` | A user-configured endpoint with a *proven* streaming protocol for provisional text. | **Per session**: starting live names the host and asks. |

The server route is its own profile — host, protocol, credential in
`SecretStore`, validated through `NetGuard` with the same redirect-refusal and
private-address posture as WebDAV — and **not** a mode of `AiClientService`:
the AI backend contract is chat/completions text, the ASR contract is
audio-in/text-out, and conflating them would hand every configured chat
endpoint an implicit audio feed. Server provenance is written into the
transcript's provenance lines as what it was (`Engine: <server-profile-name>`
rather than `lokaal`), because a reader should be able to see the text came
off-device. **Local processing never falls back to upload**: if the local
engine fails, the user is told and chooses; silent rerouting to a configured
server is the hidden-upload this epic forbids.

### 4.4 Error taxonomy (typed, before platform code)

```dart
sealed class TranscriptionError { }

class PermissionDenied     extends TranscriptionError { ... } // after user action
class SourceUnavailable    extends TranscriptionError { ... } // device/source gone
class UnsupportedSource    extends TranscriptionError { ... } // DRM, RDP, browser cap
class DecodeFailed         extends TranscriptionError { ... } // file won't decode
class EngineUnavailable    extends TranscriptionError { ... } // not installed/no model
class CapacityExceeded     extends TranscriptionError { ... } // too long/big for route
class ServerRefused        extends TranscriptionError { ... } // network/TLS/CORS
class ConsentRequired      extends TranscriptionError { ... } // server route, not yet asked
class Cancelled            extends TranscriptionError { ... } // the user stopped it
class IoFailed             extends TranscriptionError { ... } // disk/budget failure
```

The taxonomy's real job is the **split it forces**: permission outcomes are
not capability outcomes, and both are distinct from "the engine isn't there".
The UI maps each type to a named next step (grant the permission / pick
another source / install a model / choose a smaller route), which is what
"an impossible route is explained beforehand" means mechanically.

---

## 5. Capability matrix

Statuses, per the issue's vocabulary: **beschikbaar** (detectable now),
**na toestemming te proberen** (real answer only after a permission grant),
**niet beschikbaar** (the platform/setup cannot), **niet getest** (plausible
on paper, unproven on real hardware). Cells are grounded in the platform
documentation cited per row; a cell only leaves *niet getest* behind when the
route is proven on the real platform in #2523 — this matrix claims no
universal capture anywhere.

### 5.1 Per release platform

| Platform | `bestand` | `microfoon` | `app-/systeemgeluid` | `combinatie` |
|---|---|---|---|---|
| **macOS** | beschikbaar¹ | na toestemming te proberen (TCC mic prompt; usage string must stop promising "no recording", §2.3) | na toestemming te proberen² | na toestemming te proberen (mic + screen-audio; channel separation niet getest) |
| **Windows** | beschikbaar¹ | na toestemming te proberen (mic privacy toggle) | na toestemming te proberen³ | na toestemming te proberen (niet getest) |
| **Linux** | beschikbaar¹·⁴ | na toestemming te proberen (no OS prompt on most setups; hardware presence decides) | niet getest⁵ | niet getest |
| **Web** | beschikbaar¹·⁶ | na toestemming te proberen (browser mic prompt; MediaRecorder support⁷) | browser-dependent — see 5.2 | niet getest |
| **Android / iOS** | niet ondersteund — not a release platform; separate product decision (§1.2) | | | |

¹ File decode is the engine's problem, not the OS's: WAV/PCM everywhere;
compressed formats need a decoder the ticket must prove (#2515). Formats a
platform cannot decode are `DecodeFailed`, not silent silence.
² ScreenCaptureKit (`SCStream` audio capture, macOS 13+; per-app capture
possible via content filters) under a *screen recording* consent the OS shows
— a heavier prompt than mic, and DRM-protected app audio is excluded by the
OS, not reported as success. ([developer.apple.com/.../screencapturekit](https://developer.apple.com/documentation/screencapturekit))
³ WASAPI loopback captures the **endpoint mix** — everything on an output
device, not per-app. Per-process include/exclude exists only via the process
loopback activation API on newer Windows 11. "The call's audio" is honest;
"only Teams' audio" is not. ([learn.microsoft.com/.../loopback-recording](https://learn.microsoft.com/windows/win32/coreaudio/loopback-recording))
⁴ Decoder availability varies (GStreamer/ffmpeg presence is setup-dependent);
that is a `capabilities()` answer, not an assumption.
⁵ PipeWire/PulseAudio expose sink *monitors* (the output mix); per-app
capture is possible through PipeWire stream routing but setup-dependent, and
a bare-ALSA setup has no monitor at all. Honest status until a real session
proves it. ([docs.pipewire.org/.../module_loopback](https://docs.pipewire.org/page_module_loopback.html))
⁶ `decodeAudioData` codec coverage is browser-dependent; formats the browser
cannot decode are `DecodeFailed`.
⁷ Chrome/Edge/Firefox record (Opus/WebM); Safari's MediaRecorder exists but
yields a different container/codec — the definitive pass runs on whatever the
browser produced, so the engine must accept it or the route is
`UnsupportedSource` on that browser.

### 5.2 Web, per browser family — app-/systeemgeluid

`getDisplayMedia` audio support is a browser-property matrix, not a platform
one ([developer.mozilla.org/.../getDisplayMedia](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getDisplayMedia)):

| Browser | Tab audio | Whole-system audio |
|---|---|---|
| Chromium (Chrome/Edge) | beschikbaar na toestemming | Windows/ChromeOS: na toestemming; macOS/Linux: niet beschikbaar |
| Firefox | niet beschikbaar (audio request ignored) | niet beschikbaar |
| Safari | niet beschikbaar | niet beschikbaar |

The UI therefore never offers "systeemgeluid" on web in the abstract — it
offers *tab audio* where the browser proves it, names the browser boundary
where it does not, and an online meeting in Firefox/Safari is `microfoon`-only
with the honest label "room capture may include speaker output".

### 5.3 Engines

| Route | Status |
|---|---|
| Local desktop engine (whisper.cpp behind platform channel, #2512) | beschikbaar-path; model management user-driven, nothing bundled |
| Local web engine (WASM, #2513) | niet getest — whisper.wasm is proven for tiny/base-class models inside WASM memory and threading limits; heavier local models on web are not claimed ([whisper.wasm README](https://github.com/ggml-org/whisper.cpp/blob/master/examples/whisper.wasm/README.md)). WASM threads also need COOP/COEP isolation headers — a real constraint for the hosted bundle, checked on the actual deployment. |
| Batch server (#2524) | proven per configured profile only; protocol + consent in §4.3 |
| Live server (#2525) | proven per configured profile only; unproven protocol ⇒ route absent |

---

## 6. Decisions taken (and what would change them)

1. **Transcript = plain document, not a new file kind.** Follows §14 and the
   epic; revisiting means inventing a third file kind and paying its whole
   toolchain cost.
2. **Marker carries `audio`, provenance stays text.** Chosen over
   sidecar/JSON/front-matter for the reasons in §3.1. Changes only if a real
   need appears for machine-readable provenance fields — and then via marker
   attributes, not a new vocabulary.
3. **Audio in `media/`, keep-or-let-go at save.** Copies the staging→save
   flow every asset already uses. Changes only if copying proves the wrong
   default for very large files — and then the alternative is a *link-only*
   document that openly says its evidence lives elsewhere, not a containment
   break.
4. **WAV baseline, compression allowed but never required.** Storage is
   cheap, codecs are not; revisiting is a packaging decision, not a format
   change.
5. **Server route is a separate profile, never `AiClientService`.** Structural
   non-goal of the epic; changing it means designing the opt-in this document
   refuses to assume.
6. **`combinatie` keeps channels apart where delivered.** Cheap now,
   impossible to retrofit honestly later; revisiting means accepting
   single-mix recordings and their weaker speaker claims forever.

## 7. What each deelticket consumes

| Issue | Consumes |
|---|---|
| #2510 (grenzen, toestemming, verwijdering) | §2.3 consent model, §4.4 error taxonomy, §3.2 lifecycle |
| #2511 (Markdown-resultaat) | §3.1 marker + provenance, §3.3 test requirements |
| #2512 (lokale engine desktop) | §4.2 `local` engine kind, §5.3 |
| #2513 (web-inferentie bewijs) | §5.3 WASM row, §3.2 web storage bounds |
| #2514 (instellingen-uitbreiding) | §1 module placement, §2.1 capability tiers, §5 matrix as in-app content |
| #2515 (bestand → transcript) | §3.2 file-source lifecycle, `DecodeFailed`/`CapacityExceeded` |
| #2516–#2520 (platform-mic + systeemroutes) | §4.1 boundary, §5.1 rows |
| #2521 (web tab/scherm) | §5.2 browser matrix |
| #2522 (live + definitieve pass) | §4.2 one-recording-two-outputs, §2 route 3 |
| #2523 (platformproeven, releasebewijs) | §5 matrix is its checklist — every *niet getest* is a test to run |
| #2524/#2525 (ASR-server routes) | §4.3 profile/consent/provenance, `ServerRefused`/`ConsentRequired` |

## 8. Open questions

- **Recording length caps on web.** The `mem:` budget makes a long PCM
  recording impossible; whether web records compressed-only, caps duration, or
  streams to a chosen destination is #2513/#2517's evidence to bring back —
  this contract fixes only that the limitation is *named*, not which one wins.
- **Whether `combinatie` on a single-mix platform may still be offered** with
  a degraded "one mix, no side attribution" label, or should be absent there.
  Lean: offer the mix, label it honestly — but that is a UX call for #2514's
  detection UI, not a format question, and either answer fits this contract.
- **Speaker vocabulary.** `Spreker n` / `microfoon` / `gesprekspartner` are
  placeholders for the strings #2511 picks; the contract fixes only that they
  are *plain text* and *only real*. Localising them is a l10n decision like
  every other generated line.
