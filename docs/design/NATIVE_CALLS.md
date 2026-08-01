# OciDeck — Native Calls: one interface, Jitsi + Matrix backends (Design)

> **Status:** design proposal — unbuilt · **Status last reviewed:** 2026-08-02 · **Published by:** Stichting LibreKAT

> **A design proposal — not yet implemented.**
> This document describes a *future* capability. It is kept separate from the
> current-state contributor docs ([`ARCHITECTURE.md`](../ARCHITECTURE.md),
> [`SOURCE_MAP.md`](../SOURCE_MAP.md)) so those keep describing what exists. When
> (parts of) this lands, fold the relevant sections into those docs and the
> [`USER_GUIDE.md`](../USER_GUIDE.md), and update the [`CHANGELOG.md`](../../CHANGELOG.md).
>
> It is written to be **picked up cold**: exact file paths, integration points,
> data shapes, invariants and open questions are spelled out.
>
> **Siblings.** [`COLLABORATION.md`](COLLABORATION.md) defines the transport-agnostic
> collaboration layer and the `MeetingProvider` seam (§7.1) that this document makes
> native. [`TEAMS_GUEST_CLIENT.md`](TEAMS_GUEST_CLIENT.md) fixes the one-shell
> invariant (T13/T14) every adapter obeys. [`SELF_ENCRYPTED_RELAY.md`](SELF_ENCRYPTED_RELAY.md)
> is the pure-Dart data-plane relay. This document is the **native media plane** and
> the **backend-neutral call interface** that unifies Jitsi and Matrix.
>
> **Gated.** This design does not authorise adding a WebRTC dependency. The
> media-plane dependency (`flutter_webrtc`) must pass a chain review first —
> [`assurance/ketenkeuring-flutter-webrtc.md`](../../assurance/ketenkeuring-flutter-webrtc.md) —
> and the **spine decision** (§5) is a maintainer call. Both precede any code.

---

## 1. Purpose & scope

OciDeck should let a user **join a video conference and present into it from
OciDeck's own interface** — not an embedded third-party UI — and, symmetrically,
**host** a conference/webinar of its own. Two families are in scope:

1. **Joining** an existing invitation (someone sends a Jitsi link — `meet.jit.si`
   or a self-hosted deployment).
2. **Hosting** an OciDeck-originated room on infrastructure the user brings (an org
   Jitsi, or a Matrix ecosystem via MatrixRTC/LiveKit).

Both are equally in scope. The through-line: **OciDeck is a client, never a server**
(COLLABORATION.md P1). It runs no SFU and no signalling server; it points at
deployments the user already has or freely creates, exactly as the WebDAV source
lets a user point at their own storage.

The deliberate choice made here is the **deep native** route: OciDeck speaks the
conference's signalling itself and renders raw media tracks in its own
presentation-centric layout. It does **not** embed the vendor's web client. Jitsi is
open source (Apache-2.0), so its client↔server conversation can be reimplemented in
Dart; that is what "native" means below.

---

## 2. Relationship to COLLABORATION.md

COLLABORATION.md §7 already reasoned about calls and §7.1 defines the
`MeetingProvider`/`MeetingSession` contract, with Jitsi listed as *"First proof of
concept"* and the note *"Official IFrame API for the first slice; evaluate
`lib-jitsi-meet` only for a fully native OciDeck layout."* This document **commits to
the fully-native layout** and specifies it. It does not replace §7.1's contract — it
implements it — and it adds two things §7 left open:

- a concrete **backend-neutral call interface** so Jitsi and Matrix calls are the
  same experience (§3); and
- the observation that a single **XMPP** spine can carry both the calls *and* the
  collaboration data plane (§5), which bears on the transport choice §6 of
  COLLABORATION.md decided (the self-encrypted Matrix relay).

The §7.1.6 hardening rules (self-hosted provider profiles, no probing, no blanket
claim, fragment stripping, vendor-SDK isolation, dual-session consent, meeting-media
≠ AI) apply unchanged and are treated as constraints in §8.

---

## 3. The unified interface (the heart of this design)

OciDeck gets **no** Jitsi screen and **no** Matrix screen. There is **one** call and
presenter interface that renders solely from provider-neutral abstractions. The
backend sits underneath and is invisible to the UI; switching backend changes no
pixel.

Two observations make this natural rather than forced:

1. **Both are WebRTC + SFU.** Jitsi (the videobridge, JVB) and MatrixRTC / Element
   Call (LiveKit) differ **only in signalling** — Jitsi: XMPP / Jingle / Colibri2;
   MatrixRTC: Matrix room events + LiveKit. The *media* (audio/video tracks over
   `flutter_webrtc`) is identical. **The media core is shared; only the signalling
   adapter differs.**
2. **The contract already exists.** COLLABORATION.md §7.1.1 specifies
   `MeetingProvider` / `MeetingSession` / `MeetingCapabilities` for exactly this
   ("one shell for every adapter", invariants T13/T14). An adapter supplies *facts*
   (capabilities, role, tracks, events), never its own screen.

**Two parallel provider-neutral seams** — the UI is agnostic on *both*:

| Plane | Seam | Implementations |
|---|---|---|
| **Data** — ops, locks, chat, presenter-sync (next/prev, pointer) | `CollabTransport` (exists, `lib/collab/collab_transport.dart`) | loopback + WebDAV-async (built); **XMPP** + Matrix-relay (planned) |
| **Media** — audio/video/screen/roster | `MeetingSession` (§7.1.1, new) | **Jitsi** (XMPP/Jingle/Colibri2), **MatrixRTC/LiveKit**, fake (tests) |

```mermaid
flowchart TB
    UI["OciDeck call and presenter UI<br/>renders only from MeetingCapabilities, MeetingEvent, MeetingParticipant"]
    UI --> MS["MeetingSession — provider-neutral (COLLABORATION.md 7.1.1)"]
    UI --> CT["CollabTransport — data plane (lib/collab)"]
    MS --> JIT["Jitsi adapter<br/>XMPP / Jingle / Colibri2"]
    MS --> MRTC["MatrixRTC / LiveKit adapter<br/>Matrix events + LiveKit"]
    MS --> FAKE["Fake adapter (tests)"]
    JIT --> WEBRTC["flutter_webrtc — shared media core (libwebrtc)"]
    MRTC --> WEBRTC
    CT --> XMPPT["XMPP transport"]
    CT --> RELAY["Matrix relay transport"]
```

**Provider-neutral media model** (new, above `flutter_webrtc`). Both the Jitsi and
Matrix adapters fill exactly this; the UI renders tiles from the participant list and
controls from `MeetingCapabilities`:

```dart
class MeetingParticipant {
  final String id;
  final String displayName;
  final MeetingRole role;         // guest/attendee/presenter/moderator/... (§7.1.1)
  final MediaStreamTrack? audio;  // flutter_webrtc — same type for Jitsi and Matrix
  final MediaStreamTrack? video;
  final bool micMuted, camOff, isDominantSpeaker, isScreenShare;
}
```

The UI composes both seams: the **slide** (from the deck), the **participant tiles**
(from `MeetingSession`), driven by **presenter-sync** (from `CollabTransport`). One
coherent interface, backend-agnostic on both planes.

**Why this also settles the join-and-host choice.** Hosting is a backend choice *per
room*, not per UI. An OciDeck webinar runs on a Jitsi deployment the user controls
**or** on MatrixRTC (which reuses the self-encrypted-relay account). Joining someone
else's Jitsi uses the same interface. The user sees the same thing every time.

---

## 4. What "reimplementing the protocol" means technically

Jitsi is not a single wire protocol you copy; it is a layered stack. The split is
what decides feasibility:

| Layer | What it does | Rebuildable in Dart? |
|---|---|---|
| **Media** — WebRTC (ICE/DTLS/SRTP; VP8/VP9/AV1/Opus), routed by the SFU | the audio/video bytes | **No, not in pure Dart.** libwebrtc is a very large C++ codebase. Route = `flutter_webrtc` (native libwebrtc, MIT) — **shared** by Jitsi and Matrix. |
| **Signalling (Jitsi)** — XMPP→Prosody, MUC (XEP-0045), Jingle (XEP-0166/0167/0176) from Jicofo, Colibri2 to the JVB | who is present, which tracks, SDP/ICE, muted-state, dominant speaker, lastN | **Yes** — this is what `lib-jitsi-meet` (JS) does; stanza plumbing, not cryptography. **This is the real work.** |
| **Signalling (Matrix)** — Matrix room events + LiveKit token/signalling | the same, via Matrix + LiveKit | **Yes** — REST / room events; ties into the relay route. |

A community effort is already rewriting `lib-jitsi-meet`'s XMPP module to Dart
(unfinished) — confirmation of both the decomposition and that it is non-trivial. The
official `jitsi-meet-flutter-sdk` is mobile-only, embeds Jitsi's *own* UI and has no
desktop target — unsuitable (OciDeck: own interface, macOS-primary). Jitsi itself is
**Apache-2.0**, so there is no AGPL obstacle of the kind the Matrix SDK raised (#976).

---

## 5. XMPP as a candidate single spine (data + media)

`lib/xmpp/` is **not** a Jitsi detail; it is standalone infrastructure. XMPP is open,
federated and bring-your-own-server — a match for **P1**. And because **Jitsi already
runs on XMPP (Prosody)**, one XMPP server can carry the call signalling *and* the
whole collaboration data plane of COLLABORATION.md §5–6. One connection, two
consumers:

- **Media plane** — the Jitsi adapter consumes the connection for
  Jingle/MUC/Colibri2 signalling (`MeetingSession`).
- **Data plane** — `XmppTransport implements CollabTransport` carries deck-ops, locks,
  chat, presence and presenter-sync — a **fourth transport** beside loopback,
  WebDAV-async and the Matrix relay. The authority/version logic in
  `collab_session.dart` is already transport-agnostic and is not rewritten.

Mapping onto the data-plane primitives:

| Data plane | Matrix (§6.1) | XMPP equivalent | Fit |
|---|---|---|---|
| Session = room | Matrix room | MUC (XEP-0045) | equal |
| Ops (ordered) | timeline event | MUC message / PubSub (XEP-0060) + MAM catch-up (XEP-0313) | slightly more self-assembly |
| Snapshot (large) | chunked/attachment | chunked / HTTP File Upload (XEP-0363) | equal |
| Locks / authority | room **state** | PubSub item per slide (last-wins) | Matrix more natural |
| Roles owner/editor/viewer | power levels | MUC affiliations/roles | **XMPP more natural** |
| Chat | `m.room.message` | XMPP message | XMPP is built for this |
| Presence / who-views-what | presence | XMPP presence + custom extensions (as Jitsi's muted/nick) | **XMPP more natural** |
| E2EE by default (P4) | Olm/Megolm (AGPL) → own minimal scheme | OMEMO = Double-Ratchet = **the red line** → the same own scheme | **equal** |

So **the Jitsi route with an XMPP server reaches substantially what the separate
Matrix relay does — on one spine instead of two.** Honest caveats (the real work, not
dealbreakers):

- **E2EE is no better.** OMEMO is also Double-Ratchet (libsignal) — exactly the red
  line from the relay chain review ("no own ratchet"). You therefore reuse the same
  minimal X25519→AES-GCM scheme over a private event type; E2EE is neither gained nor
  lost versus the relay.
- **Ordering/catch-up is more DIY** than Matrix's `/sync` (via MAM/PubSub), but the
  pure-Dart relay route requires that plumbing too (relay chain review, finding 4).
  Lateral, not worse.
- **Public Jitsi ≠ your XMPP server.** `meet.jit.si` / `8x8.vc` lock their Prosody
  down (anonymous auth, focus-only). "One server for both" holds fully for an
  **own/cooperating** deployment; against public Jitsi the data plane is a *separate*
  XMPP account. The client code (`lib/xmpp/`) is shared regardless.
- **An XMPP account is needed** (bring-your-own, P1 holds), creatable in-app via
  in-band registration (XEP-0077), the way COLLABORATION.md §8 describes for Matrix.

**When which spine.** *Co-authoring without calls* → the Matrix relay (`http` +
`cryptography`, no XMPP client) is lighter, and it is already **GO**
([`ketenkeuring-self-encrypted-relay.md`](../../assurance/ketenkeuring-self-encrypted-relay.md)).
*Also Jitsi calls* → XMPP is the spine you already have; a second Matrix stack beside
it is the detour. For "join and host equally", this favours **XMPP as the single
spine**.

**This is a maintainer-level spine decision** (as the relay choice was) and warrants
its own chain review. It is Open Question 0 (§10); nothing here bakes it in silently.
The interface of §3 is unaffected either way — the spine choice changes which
`CollabTransport` carries the data plane, not the call UI.

---

## 6. Design principles (inherited)

All COLLABORATION.md §2 invariants (P1 client-only, P2 room=transport/file=truth, P3
owner-authoritative, P4 E2EE-by-default *for OciDeck collaboration content*, P5 sync
the model, P6 transport-agnostic, P7 two modalities one session) apply. Three points
specific to external calls, from §7.1:

- A `MeetingProvider` joins a *separately operated* system that controls identity,
  admission, signalling, media and recording. OciDeck **must not inherit an E2EE
  claim** from the collaboration session for that media; it describes the provider's
  boundaries truthfully (`MeetingPreflight`, including an explicit `unknown` E2EE
  value).
- The external meeting session and the OciDeck collaboration room are **separate
  trust domains**; no membership crosses automatically (§8).
- The call UI renders controls **only** from live `MeetingCapabilities`; it never
  imitates a control the adapter cannot perform, and it removes lost controls
  immediately when role/capability changes arrive.

---

## 7. Phased delivery (native-first, interface-first)

Even the direct-native route builds the shared interface first (as `CollabTransport`
was built loopback-first), so Jitsi and Matrix share it. This is **not** an IFrame
proof-of-concept — the end state is the native client; no vendor UI ever appears.

| Phase | Content | Verified by |
|---|---|---|
| **F0 — Gate & design** | This document; the `flutter_webrtc` chain review (GO/NO-GO). **Maintainer knot** — a network dependency may not enter without the gate (§8). | the chain-review document; `make licenses` / `make sbom` dry-run |
| **F1 — Unified interface + media core + fake** | `MeetingProvider`/`MeetingSession`/`MeetingParticipant`, `MeetingLinkResolver`, typed events, `meeting_media_core.dart` (flutter_webrtc wrapper) + a **fake adapter**, no external SDK. Call UI already renders from capabilities/tracks. | resolver/contract unit tests; fake tiles in the UI |
| **F2 — XMPP core** | `lib/xmpp/`: connect, SASL (anon + token), MUC join, presence, chat. **Immediately usable standalone** as a channel (§5). | stanza parsers against vectors; integration test against a local `docker-jitsi-meet` |
| **F3 — Jitsi media** | Jingle + ICE + Colibri2 on `lib/xmpp/`; `MeetingSession` for Jitsi; receive remote tracks into OciDeck tiles; camera/mic uplink; **screen share**. Covers **joining**. | Docker room with a second client; functional test |
| **F4 — Presenting** | The **slide into the call** as an own video track via `SlideRasterizer` **through the projection boundary** (`AudienceDeck`, §8). Presenter layout (slide large + tiles); presenter-sync over the data plane (§5). Covers **presenting**. | image review of the layout; projection-boundary test |
| **F5 — Hosting + Matrix backend + E2EE** | Host via `MeetingProviderProfile` (own/public Jitsi, bring-your-own-URL). **MatrixRTC/LiveKit adapter** behind the same `MeetingSession` (ties into the relay phases) → Matrix calls identical to Jitsi calls. Optional media E2EE (SFrame / frame cryptor) — **macOS caveat** (§10). Covers **hosting** on both backends. | host test; security review |

Native Jitsi covers both joining and hosting: hosting = point at a Jitsi deployment
you control. LiveKit/MatrixRTC remains the cleaner backend for a *pure* own SFU
(COLLABORATION.md §7 says so) and arrives in F5 behind the same contract.

---

## 8. Hard constraints (existing gates that break the build)

- **Optional module, default off.** A **6th `ModuleEntry`** in
  `lib/state/module_registry.dart` (beside `infoSafety`, `ai`, `onlineStorage`,
  `imports`, `procesverbetering`), on the Uitbreidingen tab. *"Off means no shell
  action and no adapter code reached"* (COLLABORATION.md §7.1.1). Own prefs key,
  default `false`; follow the `info_safety_provider.dart` pattern.
- **Privacy projection boundary (the sharpest).** "The slide into the call" is by
  definition a **new `audience` output channel**. `tool/check_audience_boundary.dart`
  **breaks the build** until that channel takes an `AudienceDeck`
  (`PrivacyProjection.forAudience(...)`, `lib/services/privacy/privacy_projection.dart`),
  never a raw `Deck`. The slide therefore passes OciWacht redaction before it enters
  a track/screen-share. The audience window must not leak presenter notes or
  diagnostics (COLLABORATION.md §7.1.4).
- **Chain review + SBOM + promise.** `flutter_webrtc` must clear the GO/NO-GO gate
  ([`ketenkeuring-flutter-webrtc.md`](../../assurance/ketenkeuring-flutter-webrtc.md));
  it lands in `pubspec.lock` (no Cargo blind spot). The public promise in
  [`ARCHITECTURE.md`](../ARCHITECTURE.md) — *"the only HTTP client dependency is
  `http`"* and *"never phones home"* — must be **updated honestly**: a second network
  stack exists, behind a default-off module.
- **NetGuard boundary, explicit.** The signalling origin (Prosody/Matrix) goes
  through the same `NetGuard` / redirect-refusal / DNS-rebind posture as WebDAV, via
  `MeetingProviderProfile`. The **media (ICE/TURN/STUN, UDP) bypasses NetGuard** — an
  acknowledged, fundamental hole; document it in `SECURITY.md`/`assurance/` and bound
  egress to configured/approved TURN origins. Fragment strip: Jitsi honours
  `#config.…` overrides → `MeetingLinkResolver` removes the fragment (muted/camera-off
  come from OciDeck, not the sender — COLLABORATION.md §7.1.6).
- **Native means no vendor iframe.** A benefit of the native route: the vendor-SDK
  isolation of §7.1.6 (sandboxed iframe / postMessage bridge) largely falls away — no
  vendor JS runs in the page. On the **web build** a CSP `connect-src`/`media-src`
  delta for the signalling origin still applies (`tool/check_web_hardening.dart`).
- **Two consent domains.** Meeting media (audio/video/screen/roster) **never** enters
  AI Assist merely because AI is enabled; a meeting session **never** grants automatic
  access to a collaboration room (COLLABORATION.md §7.1.6). The meeting session is
  root-scoped (`lib/state/meeting_session_provider.dart`), deliberately outside the
  per-tab collab scope.
- **The usual ratchets.** l10n for every `l10n.d('…')` (all 30 non-NL languages, `make add-l10n`);
  files ≤ 1000 lines (`part`/`part-of`); methods ≤ 150; no `catch(_)`/`print`; atomic
  writes; every new `lib/` file referenced by a test (coverage gate); documentation
  duty (USER_GUIDE/SOURCE_MAP/FILE_FORMAT/CHANGELOG) per shipped phase.

---

## 9. Implementation reference (paths & integration points)

**Read/extend (existing):**

| Concern | Path | Anchor |
|---|---|---|
| Meeting contract (source) | `docs/design/COLLABORATION.md` | §7.1, §7.1.6 |
| Shell invariant | `docs/design/TEAMS_GUEST_CLIENT.md` | T13/T14 |
| Module register | `lib/state/module_registry.dart` | pattern `info_safety_provider.dart` |
| Projection boundary | `lib/services/privacy/privacy_projection.dart` · `tool/check_audience_boundary.dart` | `forAudience`, `SurfaceKind` |
| Slide → image | `lib/services/slide_rasterizer.dart` | `SlideRasterizer` (1280×720) |
| Presenter / dual-screen | `lib/widgets/presentation/fullscreen_presenter.dart` · `audience_window.dart` | sync model |
| Transport seam | `lib/collab/collab_transport.dart` · `collab_session.dart` | `CollabTransport` |
| BYO-server precedent | `lib/models/webdav_settings.dart` | `WebdavServer`, `trustedInternal`, `NetGuard` |
| Secret storage | `lib/services/secret_store.dart` | keychain (XMPP/Matrix token) |

**New files (proposed):**

```
lib/xmpp/xmpp_connection.dart       RFC 6120/6121: TCP/TLS or WebSocket, SASL
lib/xmpp/xmpp_muc.dart              XEP-0045 MUC, presence, roster
lib/xmpp/xmpp_stanza.dart           stanza (de)serialisation (IQ/message/presence)
lib/meetings/meeting_provider.dart  MeetingProvider / MeetingSession / MeetingPreflight
lib/meetings/meeting_participant.dart  the provider-neutral media model (§3)
lib/meetings/meeting_link_resolver.dart  local allowlisted URL recognition; no probing
lib/meetings/meeting_provider_profile.dart  bring-your-own-deployment (join + host)
lib/meetings/meeting_media_core.dart  shared flutter_webrtc wrapper (PC, tracks, screen)
lib/meetings/providers/jitsi/jitsi_signaling.dart  Jingle + source-signalling + Colibri2
lib/meetings/providers/jitsi/jitsi_presence.dart   Jitsi presence extensions
lib/meetings/providers/matrixrtc/…  Matrix/LiveKit adapter (F5)
lib/state/meeting_session_provider.dart  root-scoped meeting lifetime
```

**Dependency (after F0 GO):** `flutter_webrtc` (MIT); optionally a permissively
licensed XMPP core. Pin + SBOM; keep `make deps-check` (OSV) green.

**Security caps to mirror** (match `file_service.dart`/`webdav_service.dart`): bound
inbound stanza/event sizes and counts; reject oversized input; no signalling
redirects; keep the WebDAV `NetGuard`/SSRF stance for any new outbound signalling
host; run any crypto in an isolate with static helpers.

---

## 10. Open questions (decide in/before F0–F1)

0. **Spine (fundamental, maintainer decision — §5).** One XMPP spine for data and
   media, or the two-spine split (Matrix relay for data + Jitsi/LiveKit for media)
   that COLLABORATION.md §6 decided? "Join and host equally" leans single-XMPP; it
   touches the already-approved relay route and warrants its own chain review. **This
   decision shapes the whole design** and precedes the rest.
1. **XMPP library** — fork a permissive core (e.g. `moxxmpp`) vs. `lib/xmpp/` from
   scratch. Jingle/Colibri2/Jitsi-presence are net-new either way.
2. **E2EE on macOS** — `flutter_webrtc` frame cryptor is known to crash on iOS/macOS
   (OciDeck's primary target). Is media E2EE v1-blocking, or does it land on
   Linux/Windows/web first?
3. **Web parity** — how much media on the web build (CSP, `flutter_webrtc` web
   maturity)? (COLLABORATION.md open question 6.)
4. **Signalling depth for v1** — simulcast/SVC/lastN/dominant-speaker as a later
   optimisation; v1 can start at a fixed quality.
5. **Default deployment/homeserver** — suggest a public Jitsi (`meet.jit.si`) for
   convenience vs. bring-your-own only? Must not become a de-facto OciDeck dependency
   (P1).

---

## 11. Verification

- **Testbed:** a local `docker-jitsi-meet` stack (Prosody + Jicofo + JVB); never a
  public service in the suite.
- **Unit:** stanza / Jingle / Colibri2 parsers against stored vectors; `make
  mutate-parsers` to prove the tests catch changes.
- **Integration:** F2 join + chat; F3 receive/send tracks; F4 slide track + presenter
  layout; the later MatrixRTC adapter against the *same* `MeetingSession` tests.
- **Interface-agnostic:** a test that runs the same UI layer against the fake, Jitsi
  and (later) Matrix adapters and asserts the UI knows nothing provider-specific.
- **Projection boundary:** a test that the slide→call channel demands an
  `AudienceDeck` (a raw `Deck` fails the build).
- **Gates:** `make check` green (l10n 31 languages, SBOM/licences, coverage,
  ratchets, docs); the chain-review document adopted.
