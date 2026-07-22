# OciDeck — Optional AI Assistance (Design)

> **Status:** design; phases 0–3 shipped, phase 4 unbuilt — not a current-state reference · **Status last reviewed:** 2026-07-23 · **Published by:** Stichting LibreKAT

> **Phases 0–3 are built and shipped. Only Phase 4 (the MCP server
> surface) is unbuilt.** This header said "design proposal — not yet
> implemented" long after the code had overtaken it; corrected 2026-07-18.
>
> What exists today: the shared `/v1` client and guardrails
> (`ai_client_service.dart`, `ai_security_gate.dart`, settings in
> `settings_dialog_ai.dart`), image alt-text (`image_alt_ai_service.dart`,
> `alt_text_field.dart`), auto-tagging incl. the bulk "tag untagged" action
> (`image_carousel_picker_actions.dart`), and pentest field drafting
> (`finding_ai_service.dart`, `ai_suggest_field.dart`).
>
> Treat §§1–6 as a **specification of shipped behaviour**, not a proposal — but
> not as a current-state reference either: it has not been re-read line by line
> against the code, so where the two disagree, the code wins. The current-state
> docs are [`ARCHITECTURE.md`](../ARCHITECTURE.md),
> [`SOURCE_MAP.md`](../SOURCE_MAP.md), [`FILE_FORMAT.md`](../FILE_FORMAT.md) and
> [`USER_GUIDE.md`](../USER_GUIDE.md).
>
> **How far that distrust reaches, as of 2026-07-22.** What has been checked is
> narrow and worth naming so the rest is not mistaken for checked: every file
> named in the paragraph above exists at the path given, and `AiSettings.enabled`
> is indeed a setting of its own that is off by default. That is all. The prose,
> the data shapes and the guardrail descriptions in §§2–6 have still never been
> compared to the code line by line. Read a claim here as a claim; if you check
> one, either fix it or note that it held, with the date — an unchecked section
> that quietly looks checked is worse than one that says so.
>
> It is written to be **picked up cold**: exact file paths, integration points,
> data shapes, invariants and open questions are spelled out so a later
> implementation session has everything it needs without re-deriving context.
>
> Sibling design docs: [`PENTEST_MIAUW.md`](PENTEST_MIAUW.md) (the first
> consumer), [`GIT_STORAGE.md`](GIT_STORAGE.md), [`COLLABORATION.md`](COLLABORATION.md).

---

## 1. Purpose & scope

AI assistance in OciDeck is a **single, optional, off-by-default capability** that
several features consume — not a feature bolted onto one place. It was first
specified inside the pentest module ([`PENTEST_MIAUW.md`](PENTEST_MIAUW.md) §16);
this document lifts the backend, privacy model and guardrails out into a shared
capability so any feature can use it, and adds a second consumer (image tagging).

Core stance: **privacy-first, local-first, human-in-the-loop.** Nothing is sent
anywhere by default; the strongest tier runs entirely on-device; every AI output
is a *draft* a human accepts or edits. The capability is **desktop-only** — the
web build ships a strict CSP and `supportsNetworkDeckSources = false`, and the
per-image sidecars return null on web.

### Consumers
- **A — Pentest report drafting** (MIAUW): drafting the free-text finding fields
  and the management summary. Detailed in [`PENTEST_MIAUW.md`](PENTEST_MIAUW.md)
  §16; only the pentest-specific coupling (seal/attestation, EIS 1.6) lives
  there. This document owns the shared backend it calls.
- **B — Image tagging & alt-text**: generating WCAG alt-text and searchable
  keyword tags for images. Detailed in §6 below. Useful to *all* users, not just
  pentesters — which is exactly why AI is a general capability, not a
  pentest-module sub-feature.

### Goals
- One backend, one request builder, one settings surface — reused by every
  consumer.
- Off by default; zero network egress unless the user turns it on and picks a
  backend.
- Genuinely useful on-device (local model) so privacy and capability aren't a
  trade-off.

### Non-goals
- No bundled model weights (the user installs/pulls their own).
- No AI in the deterministic paths — CVSS scoring, CWE/CVE ids, compliance, and
  generated roll-ups stay deterministic (see [`PENTEST_MIAUW.md`](PENTEST_MIAUW.md)
  §7/§10). AI only drafts free text and *suggests* image metadata.
- No access to meeting audio, video, screen content, captions, transcripts,
  roster or speaker metadata. [`COLLABORATION.md`](COLLABORATION.md) §7.1.6
  defines that as a separate consent domain requiring a future feature design;
  enabling AI Assist never enables meeting capture or an AI notetaker.

### Two connection directions

AI is deliberately **decoupled from OciDeck** — you bring the model, and it can
live anywhere. There are two, complementary directions (build the first; the
second is optional):

- **OciDeck calls a model** (§3) — a **provider-agnostic inference client**: pick a
  `base URL + model`, pointing at any OpenAI-compatible runtime, **local or
  remote**. No vendor is baked in. This powers the in-app "Suggest" actions and is
  how OciDeck's own optional AI gets a model.
- **An external AI agent drives OciDeck** (§10, optional, additive) — OciDeck
  exposes an **MCP server**, so any external MCP host (Claude Desktop, Cursor, an
  agent — using *any* model, local or remote) operates OciDeck through tools and
  resources. Here the AI lives entirely *outside* OciDeck. This is interop /
  automation, **not** how OciDeck obtains a model: MCP servers hold no model, and
  MCP *sampling* — the only server→model bridge — is deprecated as of the
  2026-07-28 spec RC (which now recommends direct provider APIs, i.e. §3).

---

## 2. Principles

| Principle | Consequence |
|---|---|
| Optional | A settings toggle, off by default; features hidden until enabled. |
| Local-first | Default backend is on-device; image/finding bytes never leave the machine. |
| Draft-only | Every output is a suggestion; a human accepts/edits before it is authoritative. |
| Never silently overwrite | Human-authored text is preserved; AI offers an explicit "regenerate". |
| Provenance-marked | AI output carries a flag + a visible "AI-generated — review" badge. |
| Consent-gated egress | Any off-device tier goes through the existing outbound-privacy consent + SSRF opt-in. |
| Meeting-media isolation | Shipped deck/image AI consumers cannot read `MeetingSession`; future meeting-derived AI needs separate per-meeting consent and provider support. |
| Graceful failure | Endpoint down / model absent / timeout → clear, non-blocking error; manual entry always works. |

---

## 3. The optional AI capability

### 3.1 Settings toggle & backend config
A settings section "AI-assistentie", **off by default**. When on, it exposes a
backend choice and per-consumer switches. Backend fields: mode
(`none | local | self-hosted | cloud`), base URL, model name, and a "test
connection" action. Default mode is **none** even when the toggle is on — nothing
fires until the user acts on a specific field.

### 3.2 Three-tier backend — a *provider-agnostic* client
Every consumer talks to one client speaking the OpenAI-compatible
`/v1/chat/completions` wire format. **This is a provider-agnostic standard, not a
dependency on OpenAI the company** — `base URL + model name` *is* the model
choice, and that one wire format is spoken by Ollama, LM Studio, llama.cpp, vLLM,
LocalAI, Jan, OpenRouter, Groq, Together and OpenAI alike, so any model runs
**locally or remotely through a single code path**. (It is also the direction MCP
now endorses: the 2026-07-28 spec RC deprecated MCP *sampling* and tells servers
to "integrate directly with LLM provider APIs" — see §10.) A native adapter (e.g.
the Anthropic Messages API via `anthropic_sdk_dart`) can be added later behind the
same interface, but the OpenAI-compatible client already reaches essentially every
local and hosted runtime, so it is the pragmatic default.

1. **Local on-device (default).** Ollama / LM Studio / llama.cpp at
   `http://127.0.0.1:11434/v1`. On-device inference is local IPC, not egress — no
   data leaves the machine, so it need not trip the outbound-privacy consent
   (only a one-time "point OciDeck at a local model" acknowledgement). Registered
   as a user-configured trusted endpoint (`NetGuard` blocks loopback by default).
2. **Self-hosted (second).** The user's own Ollama/vLLM on the LAN/VPN, reached
   via `NetGuard.safeResolveTrusted(allowPrivate: true)` behind the SSRF "trusted
   server" opt-in (mirrors `WebdavServer.trustedInternal`; socket pinned vs DNS
   rebind; secret in `flutter_secure_storage`). Listed in the privacy statement
   as an outbound destination.
3. **Consented cloud (last resort).** A third-party API, fail-closed behind the
   existing outbound-privacy consent **plus** a distinct per-use confirmation that
   names the provider and warns data leaves the device. Never a default; blocked
   on web unless the CSP is widened for the host.

Prefer `/v1` (portable to a future cloud tier) over Ollama's native
`/api/chat` + `images[]` (kept as a local fallback if the compat layer misbehaves).
Note Ollama's OpenAI-compat layer is officially experimental.

### 3.3 Reused primitives (all already in the tree)
`lib/state/consent_provider.dart` (outbound consent, fail-closed),
`lib/utils/net_guard.dart` `safeResolveTrusted(allowPrivate:)`,
`lib/models/webdav_settings.dart` `WebdavServer.trustedInternal`,
`lib/widgets/privacy_statement_content.dart` ("what leaves the device"),
`flutter_secure_storage` (keychain) for any endpoint secret.

---

## 4. Grounding & guardrails (shared)

- **Grounded prompts.** Each consumer sends only the user's own facts (finding
  details / the image bytes) + any local reference context; "leave blank if
  unknown".
- **No fabricated identifiers.** Consumers that involve CWE/CVE/CVSS never let the
  model emit ids (see [`PENTEST_MIAUW.md`](PENTEST_MIAUW.md) §16).
- **Untrusted input** (pasted notes, arbitrary image content) is delimited as
  data; the model has no tools and cannot act.
- **Draft-only + provenance.** Output lands in a suggestion surface with an
  `ocideck_ai_*` marker; a human accepts/edits it. Consumers may gate downstream
  actions on markers being cleared (the pentest seal does — §16 there).
  Since 2026-07-22 the marker also leaves the app: while any slide still carries
  one, every PDF/PPTX/HTML export declares it in its document properties and its
  filename (`-ai-concept`), and the HTML adds a banner —
  [`FILE_FORMAT.md`](../FILE_FORMAT.md) §11. Export is not blocked by it; the
  seal still is. A reviewed deck declares nothing, which is the point of the
  review step.
- **Low temperature, output shaping** in the prompt (length caps, locale, format).
- **Cache by input hash** to avoid recompute/cost.
- **No ambient meeting context.** The AI request builder accepts only the
  consumer's explicit deck/image payload. It has no dependency on meeting state,
  media tracks, captions, roster or speaker events. Do not add `MeetingSession`
  to the shared AI client or global prompt context; a future meeting-derived
  consumer gets its own threat model, consent gate, provenance and retention
  design first.

---

## 5. Consumer A — pentest report drafting

Drafts the four free-text MIAUW fields (description 4.7.4, impact 4.7.6,
recommendation 4.7.7, management summary + root-cause 4.3.4). It sits on top of
the deterministic CWE-keyed snippet/finding-template library, never replacing it,
and is bound to the finalise/seal attestation so the EIS 1.6 signature always
covers human-verified text. Full design: [`PENTEST_MIAUW.md`](PENTEST_MIAUW.md)
§16. It calls the §3 backend of this document.

---

## 6. Consumer B — image tagging & alt-text

Generate, on demand, (a) **WCAG alt-text** for an image and (b) **searchable
keyword tags** — using a local vision model. OciDeck already distinguishes three
per-image text concepts, so the design slots into the existing model rather than
inventing storage:

- **Caption** (`imageCaption`/`imageCaption2`) — a *visible* credit line, today
  doubling as the accessibility label via `imageSemanticsLabel()`.
- **Description/tags** (`DescriptionService`, `.ocideck_descriptions.json`
  sidecar) — *invisible*, searchable free text that powers the image-library
  search and its "untagged only" filter.
- **Alt-text** — does not exist yet as a dedicated field; the caption stands in.

### 6.1 What it produces & where it lands
- **Alt-text → a new per-slide field.** Add `imageAltText`/`imageAltText2`
  (`String = ''`) to `lib/models/slide.dart` (constructor / `fromX` / `copyWith`),
  round-tripped as an `<!-- ocideck_image_alt: … -->` (and `_alt2`) HTML comment
  — implemented by copying the `ocideck_image_focus` pattern exactly: a
  `_writeImageAlt` in `markdown_service_serialize.dart` at every image branch, and
  a `_parseImageAlt` pre-scan in `markdown_service_parse.dart` that strips/decodes
  the comment before the generic notes scan (keeps each method under the length
  ratchet). Escape `-->` the way `_escapeNotes` does. Then make
  `imageSemanticsLabel()` prefer `imageAltText` → `imageCaption` → the
  `'Afbeelding'` l10n fallback. Alt-text is *per-usage* (WCAG 1.1.1), so it belongs
  in the `.md` (and travels in the exported package), not a per-file sidecar.
- **Keyword tags → the existing `DescriptionService` sidecar.** Populate
  `.ocideck_descriptions.json` at image-import time
  (`ImageService.pickImageDetailed` / `pasteImageDetailed`) or via an
  "auto-tag untagged images" action in
  `lib/widgets/dialogs/parts/image_carousel_picker_actions.dart` — it already
  feeds `_relevance` search and the `_untaggedOnly` filter. Verbose keyword lists
  stay out of the `.md`.

Why not the markdown `![alt](path)` slot: the parser (`_reImageMd`) discards it,
and background/title/quote/twoImages already use that slot for Marp directives —
inconsistent across slide types. Rejected.

### 6.2 Where it hooks (UI)
- **Image editors** (`ImagePickerBar` / `_CaptionField` in
  `lib/widgets/editors/_editor_field.dart`, used by `image_slide_editor.dart`,
  `two_images_editor.dart`, `bullets_image_editor.dart`): a "Suggest alt-text"
  button next to the caption/alt field, plus a **"decorative" toggle** that writes
  empty alt and skips the model.
- **Image library** (`image_carousel_picker.dart`): a bulk "auto-tag untagged
  images" action that fills the description sidecar → images become searchable.
- **Quality nudge** (`slide_quality_analyzer.dart`,
  `SlideQualityCategory.altText` / `_checkMediaAltText`): offer "generate
  alt-text" inline; **update `_checkMediaAltText` to count `imageAltText`** so the
  nudge clears once alt-text exists.

### 6.3 Vision model & API
- **Byte source:** the same resolvers the renderer uses —
  `File(resolveSlideAssetPath(imagePath, projectPath)).readAsBytes()` for project
  files (honour `isRenderPathContained`) and `WebAssetStore.bytesFor(path)` for
  `mem:`/web. Send the **original encoded bytes** (validated by
  `ImageService.looksLikeImage`: PNG/JPEG/GIF/BMP/WebP), but **resize to
  ~1024–1568 px longest edge + JPEG** before base64 to bound payload/latency
  (base64 adds ~33%; models tile/downscale internally anyway — mirrors the
  existing `CappedImage` 4096 discipline).
- **Request:** `POST /v1/chat/completions` with a multimodal content array:
  `{"type":"text","text":"…"}` + `{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,…"}}`.
  Use the **object** form (`image_url.url`), not the bare-string shorthand. Only
  base64 data URIs work — Ollama's `/v1` layer does **not** fetch remote image
  URLs.
- **Recommended models (configurable, never hard-coded — the roster moves):**
  default **`gemma3:4b`** (~3.3 GB, ~4–6 GB RAM, produces a *short* single-
  sentence caption when asked, 140+ languages) or **`llava-phi3`** (~2.9 GB) for
  speed; **`llama3.2-vision:11b`** (~8 GB, ≥8 GB VRAM) as the quality upgrade;
  **`qwen2.5vl:7b`** for document/chart/screenshot-heavy decks (OCR strength, but
  verbose + slow); **`moondream`** (~1.5 GB) as a CPU-only fallback. Detect what
  the endpoint has pulled rather than assuming a tag.

### 6.4 Accessibility (WCAG) & guardrails
- **WCAG SC 1.1.1:** meaningful image → concise content/function description;
  **decorative → empty `alt=""`** (present-but-empty is valid; *missing* alt is
  the violation) → the decorative toggle writes empty alt and skips the model;
  complex image (chart) → short alt + longer description nearby.
- **Prompt shaping:** ~1 sentence / ≤~125 chars + a handful of tags, in the deck's
  locale; **strip "image of/photo of"** prefixes (the AT already announces the
  role); low temperature.
- **Never silently overwrite** human-authored (non-AI-marked) alt-text — offer an
  explicit "regenerate" instead; store an AI-provenance flag and show a badge.
- **Cache by image hash**; fail gracefully (model not pulled / endpoint down /
  timeout) without blocking manual entry.
- No local VLM is reliable enough to auto-apply — **draft-only is mandatory**; the
  human remains responsible for whether the alt-text serves the image's purpose.

---

## 7. Phased implementation plan

| Phase | Content |
|---|---|
| **0 · Shared backend** — *shipped* | OpenAI-compatible `/v1` client + the §3 settings toggle & 3-tier backend + §4 guardrails; reuse consent/`NetGuard`/keychain. |
| **1 · Consumer B (image alt-text)** — *shipped* | `imageAltText` field + `ocideck_image_alt` round-trip + `imageSemanticsLabel` preference + vision call + editor "Suggest"/decorative toggle + quality-nudge update. |
| **2 · Consumer B (tags/library)** — *shipped* | Auto-tag into `DescriptionService`; "auto-tag untagged" bulk action in the carousel; import-time hook. |
| **3 · Consumer A (pentest)** — *shipped* | Wire the pentest field-drafting (§16 there) onto the shared backend. |
| **4 · MCP server surface** (optional, additive) — **the only one still open** | OciDeck as a localhost Streamable-HTTP MCP server (§10) so external agents can drive it. Independent of Consumers A/B — sequence any time after Phase 0; desktop-only. |

Consumer B is sequenced before the pentest consumer because it is useful to all
users and exercises the shared backend end-to-end with a simpler grounding story.
Phase 4 is **independent and optional**: it does not block the client or the
consumers, and gives OciDeck the "AI lives outside the app / another application
drives it" capability without touching how OciDeck gets a model.

---

## 8. Open questions

Five of the six below were **answered by the code** as Phases 0–3 landed, without
anyone coming back to close them here. Recorded as settled (2026-07-18) rather
than deleted, so the reasoning stays findable and nobody reopens a decision that
is already load-bearing.

1. **AI toggle vs the Informatieveiligheid module.** *Settled: separate.*
   `AiSettings.enabled` is its own main switch, off by default and independent of
   the module; the pentest consumer simply also requires it.
2. **Alt-text storage.** *Settled: `.md` comment.* `<!-- ocideck_image_alt: … -->`
   (plus `…_alt2`), lifted by `markdown_service_parse.dart`, so it travels in the
   package — no third sidecar.
3. **Model roster.** *Settled: backend-agnostic, no shortlist.* The model name is
   free text the user fills in from what their endpoint offers; `ai_settings.dart`
   states the reason — the roster shifts, so hard-coding it would date badly.
4. **Bundled tag vocabulary?** *Settled: free text.* Auto-tagging writes into
   `DescriptionService`; no controlled vocabulary was introduced.
5. **Transport.** *Settled: `/v1` only.* No Ollama `/api/chat` fallback was kept;
   the base URL carries `/v1` and the client appends `chat/completions`.
6. **MCP server surface (§10).** **Still open** — the one genuine question left.
   Optional interop, desktop-only, and dependent on a community Dart MCP package
   (`mcp_dart`) until the official `dart_mcp` ships an HTTP transport. Phase 4
   exists precisely so this can be decided on its own timing.

---

## 9. Licensing / models note

No model weights are bundled or redistributed; the user supplies the runtime and
model. Document the recommended local runtimes (Ollama/LM Studio, their licences)
and the fact that model outputs are unverified drafts in the
[`USER_GUIDE.md`](../USER_GUIDE.md) and an about/AI screen when this lands.

---

## 10. MCP server surface — external agents drive OciDeck (optional, additive)

A **separate, optional** capability from the §3 client, and the honest home for
"let AI live outside OciDeck / another application drives it": OciDeck exposes
itself as an **MCP server** so an external MCP host — Claude Desktop, Cursor, an
IDE, any agent, running **any model, local or remote** — can operate OciDeck. This
is interop/automation, **not** a way for OciDeck to obtain a model.

### 10.1 Why this, and not MCP for inference
MCP is a *tools/context* protocol; a server holds no model. The only server→model
bridge is **sampling**, which (a) requires an external host to be running and
driving OciDeck, and (b) is **deprecated** in the 2026-07-28 spec RC (SEP-2577),
which tells servers to "integrate directly with LLM provider APIs" — i.e. the §3
client. So OciDeck's *own* AI uses §3; MCP is used only the other way around.

### 10.2 What OciDeck exposes
- **Tools:** `add_finding`, `set_cvss` (validate + score via the native engine,
  §7 of PENTEST_MIAUW), `tag_image` / `list_untagged_images`, `add_slide`,
  `read_deck` / `read_slide`, `finalize_seal` (guarded). The host's LLM chooses
  which to call; each tool runs OciDeck's own deterministic logic (so e.g. CVSS is
  still scored natively, never by the model).
- **Resources:** the deck, a slide, an embedded image (read-only context).
- **Prompts:** a few report-drafting templates.
- **Elicitation** (still supported; 2026 RC = Multi-Round-Trip /
  `InputRequiredResult`) for confirmations. **No sampling** (deprecated).

### 10.3 Transport & feasibility (Flutter)
A running Flutter GUI **cannot** be a clean stdio subprocess of a host, so expose
an **in-process Streamable-HTTP MCP server bound to `127.0.0.1:<port>`** — via
`mcp_dart` (MIT; HTTP + full capabilities) or the turnkey `flutter_mcp`; the
official `dart_mcp` is stdio-only today (adopt once it ships HTTP). Security per
the MCP local-server rules: **bind loopback only, validate the `Origin` header
(DNS-rebind guard), require a local auth token**. **Desktop-only** — the web build
can neither bind a socket nor spawn a subprocess (consistent with
`supportsNetworkDeckSources = false`). Pin the MCP package version into
`MANIFEST`/`make deps-check` like the other vendored deps.

### 10.4 Consent
A **distinct** consent gate — *"an external application may read and modify this
deck"* — separate from the §3 outbound consent, because here control of the model,
the conversation and data-egress moves to the external host. Off by default, with
a clear indicator while a server session is active.
