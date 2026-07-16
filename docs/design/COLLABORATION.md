# OciDeck — Real-time Collaboration, Presenting & Calls (Design)

> **Status: design proposal — not yet implemented.**
> This document describes a *future* capability and the architecture chosen for
> it. It is deliberately kept separate from the current-state contributor docs
> ([`ARCHITECTURE.md`](../ARCHITECTURE.md), [`SOURCE_MAP.md`](../SOURCE_MAP.md),
> [`FILE_FORMAT.md`](../FILE_FORMAT.md)) so that those keep describing what
> exists. When (parts of) this lands, fold the relevant sections into those docs
> and the [`USER_GUIDE.md`](../USER_GUIDE.md), and update the
> [`CHANGELOG.md`](../../CHANGELOG.md).
>
> It is written to be **picked up cold**: exact file paths, integration points,
> data shapes, invariants and open questions are spelled out so a later
> implementation session has everything it needs without re-deriving context.
>
> Sibling design doc: [`GIT_STORAGE.md`](GIT_STORAGE.md) (versioned storage in a
> git repository). The two are complementary and split along a clean seam:
> **this document is synchronous collaboration** — authors in the room at the same
> time, live co-editing and presenting in one session; **git is asynchronous
> collaboration** — clone, branch, review, merge, release. A room is a disposable
> sync channel; a git repo is durable versioned storage. Both share the principle
> *file = truth*, and neither depends on the other landing.

---

## 1. Purpose & scope

OciDeck should be able to put the *presentation* at the centre of remote
collaboration, teaching and webinars — **as a client, never as a server**. Four
capabilities are in scope:

1. **Calls** — audio/video where OciDeck receives the streams and renders them in
   its own presentation-centric interface (not an embedded third-party UI).
2. **A data channel** — presentation control (next/previous slide), real-time
   co-authoring of a deck, and chat.
3. **Teaching / courses / webinars** — one presenter to many, without OciDeck
   building or operating a conferencing system.
4. **Interoperability** — plug into infrastructure that already exists rather
   than standing up our own.

The chosen spine is **Matrix** (an open, federated messaging protocol) for the
data channel and signalling, with **WebRTC** for media and an **SFU** only when
a group is large. OciDeck hosts **nothing**: users authenticate against an
existing (or freely created) homeserver, exactly as the WebDAV/Nextcloud source
lets a user point at their own storage.

---

## 2. Design principles (invariants)

These are non-negotiable. Every phase must preserve them.

- **P1 — OciDeck is a client, never a central dependency.** No OciDeck-operated
  server, relay or account system. Rendezvous, identity and media relaying are
  always the user's own or existing public infrastructure. This is the same
  stance as the WebDAV source (`lib/services/webdav_service.dart`).
- **P2 — Room = transport, file = truth.** The durable artifact is always the
  saved deck (`.md` project / `.ocideck` package). A collaboration "room" is a
  disposable, replayable sync channel. Losing a room never loses a deck.
- **P3 — Owner-authoritative.** Exactly one participant is the authority at any
  moment; it serialises operations, assigns versions, and is the only one that
  persists. This deliberately sidesteps CRDT/OT convergence.
- **P4 — E2EE by default.** Collaboration content and media are end-to-end
  encrypted so the homeserver / SFU cannot read them. This is a *cross-cutting
  principle*, not a later add-on (see §9). It is what makes confidential
  co-authoring and confidential webinars possible on infrastructure we don't
  control.
- **P5 — Sync the deck *model*, not re-parsed Markdown.** Operations act on the
  in-memory `Deck`/`Slide` model. Never serialise → send → re-parse Markdown per
  hop: it would trip the escaping edge cases documented for
  `markdown_service.dart` (caption-pipe sentinel, decimal video seconds, note
  `--\>`, cell `\<br>`).
- **P6 — Transport-agnostic collaboration layer.** The sync/lock/authority logic
  is defined against a thin `CollabTransport` interface. Matrix is the primary
  implementation; a loopback (tests), WebDAV (async), and a raw SFU data channel
  are alternates behind the same interface.
- **P7 — Two modalities, one session.** *Building* (co-authoring) and
  *presenting* have different QoS needs but share one session/room. Only live
  audio/video needs the media plane; everything else is small events on the data
  plane.

---

## 3. Precedent already in the codebase

OciDeck already synchronises presentation state between **two local windows** —
the presenter window and the audience window (`main.dart` routes a second-window
launch to the audience window; the fork lives at
`third_party/desktop_multi_window`). During presentation the presenter window is
the single source of truth and pushes state over a "window channel":

- interactive **question** slides forward `answerSelected` / `answerSubmit` and
  the presenter pushes the resulting `QuestionView` back;
- **timeline** step mode pushes `timelineStep`;
- **checklist / editable table** sync the same way.

**The collaboration layer is the generalisation of this pattern** from two local
windows to N networked participants, with the "single source of truth" becoming
the session *owner* (P3). Reusing this mental model — and, where practical, the
message shapes — keeps the design coherent with what contributors already know.
See [`ARCHITECTURE.md`](../ARCHITECTURE.md) § Data model for the window-channel
description.

---

## 4. Architecture overview

```
                       ┌──────────────────────────────────────────┐
                       │                 SESSION                   │
                       │            (one Matrix room)              │
   DATA PLANE  ────────┤  ops · locks · snapshot · presence · chat │
   (always on,         │  presenter-sync (next/prev)               │
    no extra infra)    │  → Matrix timeline events + room state    │
                       ├──────────────────────────────────────────┤
   MEDIA PLANE ────────┤  audio / video / screen                   │
   (only when live A/V) │  small group → P2P WebRTC (homeserver TURN)│
                       │  large group → SFU (BYO / ecosystem)      │
                       └──────────────────────────────────────────┘
                                        │
                       room = transport │ (disposable, replayable)
                                        ▼
                          FILE = TRUTH: .md project / .ocideck
```

- The **data plane** carries everything except live A/V. It needs no
  infrastructure beyond the user's homeserver account, and it delivers the bulk
  of the value (co-authoring, chat, presenter control).
- The **media plane** is bolted on and is the *only* place infrastructure scales
  with audience size — and even then OciDeck runs none of it.

---

## 5. The collaboration layer (transport-agnostic)

New code, independent of any network. Build and unit-test this **first** against
a loopback transport before touching Matrix.

### 5.1 Operation model

Operations mutate the in-memory `Deck` (`lib/models/deck.dart`, class `Deck` at
line 100) and `Slide` (`lib/models/slide.dart`, class `Slide` at line 127).

```dart
/// A single authoritative change to the deck, ordered by [version].
sealed class DeckOp {
  int get version;          // assigned by the authority, monotonic per session
  String get authorId;      // Matrix user id of the originator
}

// Examples (mirror the typed Slide fields, NOT markdown text):
class SetSlideField extends DeckOp { String slideId; String field; Object? value; ... }
class ReorderSlide  extends DeckOp { String slideId; int newIndex; ... }
class InsertSlide   extends DeckOp { int index; Slide slide; ... }
class RemoveSlide   extends DeckOp { String slideId; ... }
class SetDeckMeta   extends DeckOp { String field; Object? value; ... } // title, tlp, ...
```

- Ops are **field-level** and typed, mirroring `Slide`'s fields (see
  `SOURCE_MAP.md` and `slide.dart`). They are **not** Markdown diffs (P5).
- Each op is idempotent given its `version`; applying in version order
  reproduces the authority's deck exactly.

### 5.2 Snapshot

- A snapshot is the serialised `Deck` *model* at a version, used by joiners and
  periodic re-baselining (so a late joiner never replays the whole op log — P2).
- **Do not** reuse `generateDeck()` → `parseDeck()` for snapshots (P5, and it
  would regenerate slide ids — see §5.5). Use a dedicated model (de)serialiser
  (JSON of the `Deck`/`Slide` fields). This is new code; keep it beside the ops.
- Matrix events are capped at ~64 KiB, so large snapshots must be **chunked** or
  sent as an encrypted attachment, not a single state event (see §6.3).

### 5.3 Authority state machine

The authority (owner, or a temporary stand-in) is the only writer of versions.

- Receives intents, applies them in receive order, assigns the next `version`,
  rebroadcasts the authoritative op.
- Holds the **lock table** (§5.4).
- **Handover (owner drops):** a deterministic successor order is agreed at session
  start; the successor with the **highest observed version** takes over (version
  wins, fixed order breaks ties). The temporary authority hands back when the
  original owner returns. Only the owner may `saveDeck` / end the session; a
  temporary authority keeps the session alive but does not persist.

### 5.4 Locking

Per-slide (optionally per-block) **soft locks** eliminate both conflict *and*
edit latency: while you hold a slide's lock you are the sole writer, so you edit
locally with no round-trip and broadcast ops for that slide.

- Acquire on focus, release on blur / slide change.
- `ForceUnlock` is an explicit authoritative op; the losing client receives an
  event ("your edit was ended by the owner") — never a silent drop.

### 5.5 Invariant: slide ids are session-scoped

**`Slide.id` is a UUID regenerated on every `parseDeck()`** (stable only within a
session — see `ARCHITECTURE.md` § Data model). Consequences the collab layer
**must** honour:

- Fix slide ids at session start from the snapshot and **never re-parse Markdown
  mid-session** (that would regenerate ids and desync every op).
- Annotations (`Deck.annotations`, keyed on slide id) and user notes re-anchor by
  content fingerprint on reload (`annotation_codec.dart`); any annotation sync
  must use the same fingerprint anchoring, not raw ids across a reload boundary.

### 5.6 Transport interface

```dart
abstract class CollabTransport {
  Future<void> join(SessionRef ref, {required Role role});
  Future<void> sendOp(DeckOp op);
  Stream<DeckOp> get ops;                 // ordered, gap-free (see §6.4)
  Future<void> sendSnapshot(Uint8List snapshot, {required String toParticipant});
  Stream<SnapshotChunk> get snapshots;
  Future<void> setLock(String slideId, {required bool held});
  Stream<LockEvent> get locks;
  Future<void> sendChat(String text);
  Stream<ChatMessage> get chat;
  Stream<PresenceEvent> get presence;
  Future<void> leave();
}
```

Implementations: `LoopbackTransport` (tests), `MatrixTransport` (primary),
later `WebdavAsyncTransport`, `SfuDataChannelTransport`.

### 5.7 Wiring into providers

Riverpod is already the state layer (`flutter_riverpod: ^3.3.1`). Follow the
`deck_quality_provider.dart` pattern:

- Add `lib/state/collab_session_provider.dart` exposing a
  `collabSessionProvider` (a `StateNotifierProvider` over a `CollabSession` that
  owns a `CollabTransport` and drives the authority state machine).
- Override it **per tab** in the existing `ProviderScope` overrides list inside
  `lib/widgets/app_shell.dart` (the per-tab `IndexedStack` loop, ~lines 250–270,
  alongside `deckProvider` / `editorProvider` / `deckQualityProvider` overrides).
  A collaborating tab's `deckProvider` is fed by the session; a non-collaborating
  tab behaves exactly as today. This preserves the per-tab provider scoping —
  see [OciDeck per-tab provider-scope] note in the project memory: **any new
  deck-facing provider must also be overridden here** or it silently reads
  `deck == null`.
- Store the active `SessionRef` on `TabInfo` (`lib/state/tabs_provider.dart`,
  cf. `TabInfo.webdavOrigin` at line 44) so "resume session" / "save from
  session" know the context.

---

## 6. Matrix mapping (primary transport)

Proposed dependency: the **`matrix`** Dart SDK (the one FluffyChat uses; mature
on the messaging/E2EE side). Not yet in `pubspec.yaml` (today it has
`flutter_riverpod`, `archive`, `http`, `flutter_secure_storage`, `crypto`; **no
WebRTC/Matrix**).

### 6.1 Concept mapping

| Collab concept            | Matrix mechanism                                   |
|---------------------------|----------------------------------------------------|
| Session                   | a room                                             |
| Operation                 | custom timeline event, type `nl.ocideck.op`        |
| Snapshot                  | targeted encrypted event(s)/attachment (chunked)   |
| Lock / current authority  | room **state** events (`nl.ocideck.lock`, keyed by slide id) |
| Roles (owner/editor/viewer)| **power levels**                                  |
| Chat                      | `m.room.message`                                   |
| Presence / who-views-what | presence + ephemeral `nl.ocideck.viewing` events   |

### 6.2 Ordering & delivery come for free

Matrix is store-and-forward: events are persisted server-side and delivered in a
canonical order; a client that drops offline catches up on the next `/sync` since
its sync token. This means the **transport-level gap detection** described for a
raw WebSocket route is unnecessary — the ordered op stream and reconnect
catch-up are handled by Matrix. App-level `version` numbers are still needed for
the authority/conflict logic (§5.3), not for transport reliability.

### 6.3 Snapshot delivery

Because events cap at ~64 KiB, a full-deck snapshot is sent to a specific joiner
as **chunked** encrypted events or as an encrypted attachment referenced by
event — not crammed into one state event. Re-baseline periodically so late
joiners start from `snapshot + recent ops`.

### 6.4 What lands in Matrix vs the file (P2)

- **In Matrix (transient):** start snapshot, op stream, locks, presence, chat,
  signalling. This is the *replay of a session*.
- **The file (durable):** on session end the owner calls the existing save path
  (`lib/services/file_service.dart` → `saveDeck()` at line 690, or
  `buildPackageBytes()` at line 53 in
  `lib/services/parts/file_service_package.dart`) and distributes the final
  version. A gone room / homeserver is never a lost deck.

### 6.5 Session lifecycle

1. **Begin** — owner has an in-memory `Deck`; creates/opens a room; pushes the
   snapshot; fixes slide ids (§5.5).
2. **Live** — ops/locks/chat/presenter-sync flow as events; each client applies
   ops to its in-memory deck via `collabSessionProvider`.
3. **End** — owner persists to file and distributes; room may be closed/left.

---

## 7. Media plane (presenting & calls)

Proposed dependencies: **`flutter_webrtc`** (media on all targets incl. web);
**`livekit_client`** if/when using LiveKit as the SFU.

- **Presenter control** (next/prev, follow-mode, pointer) is **data plane** —
  small events, built on §5–6, no media stack. This alone delivers the "teaching
  control" story.
- **Small group live audio** — P2P WebRTC; signalling as Matrix call events; TURN
  provided by the user's homeserver. **No SFU, no OciDeck infra.** Honest note:
  the VoIP/Dart side is younger than the messaging side; expect more DIY with
  `flutter_webrtc` here.
- **Large audience (course/webinar)** — needs an **SFU**. One presenter → many
  passive viewers is the *favourable* fan-out topology and scales well. OciDeck
  runs no SFU: it follows a **bring-your-own-SFU-URL** config, mirroring the
  WebDAV `trustedInternal` opt-in (`lib/models/webdav_settings.dart`,
  `WebdavServer` at line 10). Options users point at: their org's LiveKit/Jitsi,
  a Matrix homeserver's Element Call / MatrixRTC, public Jitsi, or a managed SFU.
- **Broadcast variant** (optional) — WHIP/WHEP or HLS for one-way lecture to
  hundreds of purely passive viewers.

**Jitsi caveat (why not "just use Jitsi"):** meet.jit.si is the lowest-friction
public option to *use*, but Jitsi is built to be consumed through *its own
client*. Getting raw streams for OciDeck's own interface means either embedding
Jitsi's UI (contradicts the "presentation-central, own interface" goal) or
speaking lib-jitsi-meet signalling from Flutter (significant work). Hence the SFU
is abstracted behind the transport, with LiveKit/MatrixRTC as the cleaner target.

---

## 8. Account onboarding — make getting an account easy (requirement)

A broad, open-source tool cannot assume users already have a Matrix account, but
requiring one is accepted as a reality. The friction must be minimised **inside
OciDeck**:

- **In-app registration.** Use Matrix's registration API to let a user create an
  account without leaving OciDeck: pick/confirm a **default suggested
  homeserver**, run the homeserver's registration flow (username, password, and
  whatever stages it requires — email/terms/recaptcha), done. No browser detour.
- **Free choice preserved (P1).** The default is a convenience, not a lock-in:
  advanced users type their own homeserver URL (org or community) and log in.
  Same field pattern as the WebDAV server config.
- **Credential storage.** Store the access token / device keys in the OS keychain
  via the existing `SecretStore` (`lib/services/secret_store.dart`, class at
  line 13; `flutter_secure_storage: ^10.3.1` already present). Add a
  `matrixSession` key alongside the WebDAV password keys; keep the homeserver URL
  and user id in `shared_preferences` (as WebDAV does), secrets in the keychain.
- **Recovery setup prompt.** Guide the user to set up a **Security Key / Phrase**
  (SSSS) at account creation so their cryptographic identity is portable across
  devices (see §9.3). Frame it plainly ("save this recovery key or you can't move
  devices").

Design the "unverified new device" moment explicitly — a fresh login shows as an
unverified device to collaborators until verified; the UI must make verification
(emoji/QR or recovery key) obvious rather than leaving cryptic "unable to
decrypt" states.

---

## 9. End-to-end encryption — a core principle (requirement)

E2EE is **P4**, not a phase: it is what makes private co-authoring *and*
confidential webinars possible on infrastructure OciDeck doesn't control.

### 9.1 What the account provides for free

- A verifiable **cryptographic identity** (Ed25519 signing + Curve25519 keys per
  device).
- **Olm/Megolm E2EE** so the homeserver relays ciphertext it cannot read —
  including custom `nl.ocideck.op` events (any event type can be encrypted).
- **Cross-signing + device verification** to prove a collaborator is who they
  claim — directly reinforcing owner authority (P3): you can prove the owner is
  the real owner, not an impostor.
- A **signed, hash-linked event chain** → tamper-evidence on the op log.

### 9.2 Uses in OciDeck

- **Confidential collaboration & webinars.** Ops, chat and (via SFrame /
  insertable streams) media are end-to-end encrypted; a public homeserver or an
  untrusted SFU sees only ciphertext. This is the reconciliation of *independence*
  (use others' infra) with *confidentiality* (they can't read it), and it is what
  a "private webinar" actually requires.
- **Provenance signing.** On session end the owner may sign the distributed final
  deck with the identity key — tie this to the existing classification gate
  (`lib/services/classification_enforcement_policy.dart`) and package encryption
  (`lib/services/parts/file_service_package.dart`, AES-256 with password).

### 9.3 Honest constraints (must be designed for)

- **Device-switch key model.** A fresh device generates new keys and cannot read
  old encrypted history unless **Key Backup + SSSS** were set up beforehand
  (§8). *For OciDeck this is largely a non-issue* because the durable artifact is
  the **file**, not room history (P2): a new device only needs to join the *live*
  session (whose Megolm keys are shared on join) and participate. The one place it
  matters is portable **identity** for provenance/authority signing → require
  SSSS recovery at onboarding.
- **Metadata is not hidden.** E2EE hides content, not the fact: the homeserver
  still sees who is in which room, when, and traffic volume.
- **E2EE UX is famously fiddly** (key management, "unable to decrypt", backup).
  Budget real time for it; do not treat it as a checkbox. Feasible in Flutter —
  FluffyChat does full E2EE via the `matrix` SDK — but the complexity is
  inherited.

---

## 10. Phased roadmap

Each phase stands alone; the boundary "pure client vs leans on ecosystem" is
explicit. **E2EE (§9) is switched on as early as the transport carries content,
not deferred.**

### Phase 0 — Foundation: transport-agnostic collab layer (pure client)
Build §5 with a `LoopbackTransport`; unit-test ops, versioning, locking,
handover with no network. Add `lib/state/collab_session_provider.dart`; wire the
per-tab override in `app_shell.dart`. *No Matrix, no account.*
Optional 0.5: `WebdavAsyncTransport` — async co-authoring over the Nextcloud a
user already configured (`webdav_service.dart`); near-free given Phase 0, not
real-time.

### Phase 1 — Matrix data plane + easy onboarding (leans on: homeserver account)
Add the `matrix` SDK; in-app registration/login against a default-or-chosen
homeserver (§8); `MatrixTransport` implementing §5.6 with the §6.1 mapping;
session lifecycle (§6.5). Deliver real remote co-authoring + chat + presenter
control. **Turn on room encryption here** (§9) — content is E2EE from the first
networked byte.
Web note: CSP `connect-src` must allow the homeserver `wss:` (see the web-build
hardening note in project memory / `make build-web`).

### Phase 2 — Identity hardening & provenance (pure client)
Cross-signing/verification UX; SSSS recovery flow; optional owner-signature on the
distributed deck tied to the classification gate.

### Phase 3 — Presenting + small-group audio (leans on: homeserver TURN)
Presenter role as broadcast authority (data plane); P2P live audio via
`flutter_webrtc`, signalling over Matrix call events, TURN from the homeserver.
No SFU, no OciDeck infra.

### Phase 4 — Large audience media / webinars (leans on: an SFU it doesn't run)
SFU adapter (LiveKit / MatrixRTC, or org Jitsi) behind the transport;
bring-your-own-SFU-URL config mirroring `trustedInternal`; SFrame media E2EE for
confidential webinars; optional WHIP/WHEP/HLS broadcast.

### Phase 5 — Enrichment & federation (leans on: homeserver + bridges)
Q&A, polls, richer chat (all data-plane events); recording via SFU egress;
federation/bridges so external systems interoperate (requirement 4 in full).

### Coverage against the four goals

| | Calls (1) | Data channel / co-author / chat (2) | Teaching / webinars (3) | Interop (4) | Infra outside OciDeck |
|---|---|---|---|---|---|
| Phase 0–1 | — | ✅ core (E2EE on) | control ✅ | Matrix account | homeserver |
| Phase 2 | — | ✅ + provenance | ✅ trusted | — | homeserver |
| Phase 3 | small ✅ | ✅ | ✅ + voice | — | homeserver TURN |
| Phase 4 | ✅ large | ✅ | ✅ webinar (E2EE) | — | **SFU (ecosystem)** |
| Phase 5 | ✅ | ✅ | ✅ | ✅ federation | homeserver + bridges |

**Recommended evaluation point:** after Phase 1–2 there is remote, encrypted,
independent co-authoring + chat + presenter control — the bulk of the value —
with OciDeck hosting nothing. Phases 3–4 are the video build-out; only Phase 4
introduces an infrastructure dependency (an SFU, still not run by OciDeck).

---

## 11. Implementation reference (paths & integration points)

**Read/extend these existing files:**

| Concern | Path | Anchor |
|---|---|---|
| Deck model | `lib/models/deck.dart` | `Deck` (line 100), `annotations` map |
| Slide model | `lib/models/slide.dart` | `Slide` (line 127), `SlideType` |
| Markdown (de)serialise | `lib/services/markdown_service.dart` (+ `markdown_service_parse.dart`) | `parseDeck` (334), `generateDeck` (40), `generateSlide` (219) |
| Providers | `lib/state/deck_provider.dart`, `editor_provider.dart`, `deck_quality_provider.dart` | `deckProvider`, `editorProvider`, `deckQualityProvider` |
| **Per-tab override site** | `lib/widgets/app_shell.dart` | `ProviderScope` overrides in the tab loop (~250–270) |
| Tab context | `lib/state/tabs_provider.dart` | `TabInfo` (cf. `webdavOrigin`, line 44) |
| File open/save | `lib/services/file_service.dart` (+ `parts/file_service_*.dart`) | `openDeckDetailed` (568), `saveDeck` (690) |
| Package build/decode | `lib/services/parts/file_service_package.dart` | `buildPackageBytes` (53), `decodePackageEntries` (716) |
| Atomic writes | `lib/utils/atomic_file.dart` | `writeBytesAtomic` (23) |
| BYO-server precedent | `lib/services/webdav_service.dart`, `lib/models/webdav_settings.dart` | `WebdavServer` (10), `trustedInternal`, `NetGuard` |
| Secret storage | `lib/services/secret_store.dart` | `SecretStore` (13), keychain keys |
| Logger | `lib/utils/log.dart` | `logError` / `logWarning` (no `catch(_)`) |
| In-app doc reader | `lib/widgets/reader/`, `lib/services/documentation_service.dart` | asset `.md`, language variants |

**New files to add (proposed):**

- `lib/collab/deck_op.dart` — `DeckOp` sealed hierarchy + `applyOp`.
- `lib/collab/deck_snapshot.dart` — model (de)serialiser (JSON, not Markdown).
- `lib/collab/collab_transport.dart` — the `CollabTransport` interface + `LoopbackTransport`.
- `lib/collab/collab_session.dart` — authority state machine, lock table, handover.
- `lib/collab/matrix_transport.dart` — Matrix implementation (Phase 1).
- `lib/state/collab_session_provider.dart` — Riverpod wiring.
- Media (Phase 3+): `lib/collab/media/…` (WebRTC/SFU adapters).

**Dependencies to add (proposed, none present today):**

- `matrix` (Dart SDK) — Phase 1.
- `flutter_webrtc` — Phase 3.
- `livekit_client` (or chosen SFU client) — Phase 4.
- Pin new JS/native bundles in `MANIFEST.json` and keep `make deps-check` (OSV)
  green, per the bundled-JS CVE convention.

**Security caps to mirror** (match the existing defensive posture in
`file_service.dart` / `webdav_service.dart`): bound event/snapshot sizes and
counts; reject oversized inbound ops; no HTTP redirects; keep the WebDAV
`NetGuard`/SSRF stance for any new outbound host; run compression/crypto for
snapshots in an isolate (keep helpers static — see the perf-patterns note).

**Cross-cutting checks** (see [`CHECKS.md`](../CHECKS.md) and the ratchets):
files ≤ 1000 lines / methods ≤ 150 (split with `part`/`part-of` like
`file_service.dart`); no `catch(_)`/`print`; atomic writes only (no bare
`writeAs*`); l10n test requires every user-facing `.d(...)` string in all 30
non-NL languages (single string literal per `.d`); update `USER_GUIDE.md` /
`FILE_FORMAT.md` / `CHANGELOG.md` when a phase ships.

---

## 12. Open questions (decide before/while implementing)

1. **Snapshot format** — plain JSON of `Deck`/`Slide`, or a versioned schema with
   migration? (Affects forward-compat of long-lived sessions.)
2. **Op granularity** — field-level only, or also intra-field text ops for large
   `customMarkdown` / rich-text bodies while a single editor holds the lock?
   (Locking makes field-level sufficient for v1.)
3. **Default homeserver** — which one do we suggest, and do we run a fair-use
   check / show its terms? (Must not become a de-facto OciDeck dependency — P1.)
4. **Presence granularity** — expose "who is viewing which slide" to all, or only
   to the owner?
5. **Federation reach (Phase 5)** — which external systems are first-class bridge
   targets for requirement 4?
6. **Web parity** — how much of media (Phase 3–4) do we commit to on the web
   target given CSP and `flutter_webrtc` web maturity?

---

## 13. Summary

Matrix as the spine turns "OciDeck is a client" from an aspiration into the
mechanism: users bring an existing (or easily created) account, OciDeck hosts
nothing, E2EE keeps content private on infrastructure we don't control, and the
saved file remains the single source of truth while the room is just a
disposable, replayable sync channel. The data plane — co-authoring, chat,
presenter control, all encrypted — is the high-value, low-infra core; live audio
and video are a later, optional media plane that only leans on an SFU (still run
by someone else) when an audience is large.
