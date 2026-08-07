# OciDeck — Document mode: product & format design

*A second kind of file next to the Marp deck: a **flowing Markdown document**
you edit like a word processor — headings, tables, images, charts, gantt,
mermaid — where the file on disk stays a plain, maximally interchangeable `.md`
that any Markdown reader opens.*

> **Status:** **implemented and merged** — document mode ships (open/edit/save, badge, Visueel\|Bron toggle, insert palette, formatting toolbar, document export to `.md` + flowing HTML via OciWacht, and presentation⇄document conversion including the zero-loss `documentToDeck` and its privacy gate, PR #1308). This design doc remains the "why" and the format contract; the contributor docs ([`USER_GUIDE.md`](../USER_GUIDE.md), [`ARCHITECTURE.md`](../ARCHITECTURE.md), [`FILE_FORMAT.md`](../FILE_FORMAT.md)) carry the behaviour. · **Status last reviewed:** 2026-08-07 · **Published by:** Stichting LibreKAT

> **This is a design doc, not shipping behaviour.** It is the *format-first*
> gate: the disk contract and the shared-editor decision must be signed off
> here (by the core-values guardian and the software architect) before any code
> lands. When implementation arrives, the contributor docs
> ([`ARCHITECTURE.md`](../ARCHITECTURE.md), [`SOURCE_MAP.md`](../SOURCE_MAP.md),
> [`FILE_FORMAT.md`](../FILE_FORMAT.md), [`USER_GUIDE.md`](../USER_GUIDE.md)) and
> the [`CHANGELOG.md`](../../CHANGELOG.md) carry the truth. This document remains
> the *why* and the *format contract*.

> Sibling design docs: [`GANTT_SLIDETYPE.md`](GANTT_SLIDETYPE.md) and
> [`PROCESS_IMPROVEMENT.md`](PROCESS_IMPROVEMENT.md) (rich content this mode
> re-uses), [`OCIWACHT.md`](OCIWACHT.md) (the privacy projection every export
> must pass through).

---

## 1. Purpose & scope

Today OciDeck reads and writes **Marp-compatible** Markdown only, by design: a
`.md` without `marp: true` is refused at the identity gate
([`file_service.dart`](../../lib/services/file_service.dart) — `OpenFailure.notPresentation`).
This document proposes a **document mode**: a second file *kind* in which the
same application edits an ordinary, flowing Markdown document — a report, a
memo, a note — with the full-screen Markdown editor (raw **and** visual) at the
centre, and the same rich content the slide side already offers (tables,
images, mermaid, gantt, charts, math).

### 1.1 The reframe (why this belongs in OciDeck)

The brief asked for a document mode that *"must not be inferior to a
professional word processor."* Taken literally that invites feature-parity with
Word, which is the wrong target. The right target — and the reason this belongs
in OciDeck rather than in yet another editor — is the **trust promise**:

> The same responsible professional (pentester, adviser, researcher, civil
> servant) who builds a deck in OciDeck also writes reports and memos. Those
> deserve the *same* promise the deck already gets: **local-first, no lock-in,
> an OciWacht privacy scan before it leaves the machine, and a plain,
> interchangeable Markdown master.** Today that person writes the report in a
> cloud word processor (lock-in, no personal-data check before sharing) and the
> deck in OciDeck. Document mode closes that gap.

So the success measure is the **promise**, not Word-parity. Any feature whose
only justification is *"Word has it"* is out of scope. In interface and docs we
do **not** claim *"not inferior to Word"*; we claim local / no-lock-in /
privacy-scanned / interchangeable text.

### 1.2 The thesis this mode expresses (not threatens)

Document mode is the *purest* form of OciDeck's core idea — *Markdown as the
simple, maximally interchangeable base; everything specific lives beside it* —
because a document is exactly that: a flat `.md` that opens in GitHub, VS Code
or any Markdown reader, with images in `images/`, chart data in `data/*.json`,
and diagrams as fenced blocks. The **only** danger is re-use-for-convenience:
if a document rides the Marp *deck* pipeline it drags `marp: true`, the
`---`-into-slides split, and the zero-width-space dash-escape into an innocent
text file — and then it is no longer a document but *deck exhaust*. Guarding
against that is what §3 is for.

---

## 2. Architecture decision: a Document abstraction, not a Deck flag

**Decision:** model a document as a **separate `Document` abstraction next to
`Deck`, built on the already-existing lossless source model
[`MarkdownSourceDocument`](../../lib/models/markdown_source_document.dart)** — a
`Deck` with a "document" boolean is explicitly rejected.

Why:

- `Deck` is a **deconstructed** model: a `List<Slide>` of typed slides plus
  presentation metadata (seal, signature, standards, TLP, rehearsal…). A
  document is by definition **byte-faithful** to a flat `.md`.
  `MarkdownSourceDocument` already holds `source` verbatim and normalises
  *nothing*; open→save without an edit is byte-identical — strictly better than
  the deck path can promise.
- A mode boolean would thread through dozens of `switch`/`if` sites in the
  model, serialiser and tab layer — the *"a flag interpreted wrong in thirty
  places"* smell.

**The seam is at tab level.** A tab carries either a deck session or a document
session (a sealed content type on `TabInfo`: `DeckTab | DocumentTab`). The
shared fields (origin, collaboration session, recovery, dirty-tracking, label)
stay on `TabInfo`; the kind-specific notifier hangs off the variant. This
re-uses the whole substrate — storage, privacy projection, export,
undo/dirty/atomic-write — without imposing the `Deck` model on flowing text.

The identity gate becomes a **router, not a wall**: the single open chokepoint
returns a sum type (*deck-open* **or** *document-open*) instead of *deck-open*
**or** *failure*; absence of `marp: true` routes to the document path. The user
chooses nothing on open. (New-file is the only place a choice is offered:
"New presentation" vs "New document".)

### 2.1 One editor, used in both modes (no double code)

**Product decision (owner):** the Markdown editing surface is **built once and
shared** between document mode and the presentation side. There is no separate
"document editor" and "deck editor"; there is one full-screen, live,
raw+visual Markdown editing surface — call it the **Markdown editing surface** —
used by:

1. document mode (the whole document), and
2. the presentation side wherever it edits Markdown/source (the raw deck source
   view and `freeMarkdown` slides).

This promotes *"no third render path"* from a red line to the **organising
principle**: the same insert palette, the same rich-block renderers, the same
find bar and outline serve both. The typed slide editors (bullets, finding,
chart…) stay as they are; the *shared* piece is the Markdown/source/visual
surface, which this work is expected to raise to word-processor quality for
**both** sides.

> Risk to watch: "shared" must not mean forcing the flowing-document paradigm
> onto typed slides, nor vice versa. The shared component is the Markdown
> surface and its block renderers — not the slide-vs-document layout. Keep the
> contract at "given Markdown text (+ an asset root + a theme), edit and render
> it"; both callers supply those.

---

## 3. The disk contract (format-first — the heart of this doc)

A document on disk is a **plain `.md`**. This contract *is* the reason the
feature exists; if it cannot be guaranteed byte-clean, the feature does not
ship.

**MUST:**

- **No `marp: true`, no `theme:`, no `paginate:`** injected. (The deck
  serialiser always writes these — see
  [`markdown_service.dart`](../../lib/services/markdown_service.dart) around the
  front-matter writer. The document path uses its **own** flat serialise route,
  never `generateDeck`.)
- **No forced slide `---` separators** and **no `themes/`/`logos/` project
  scaffold** (`_writeProject` is presentation-only).
- **No zero-width-space dash-escape.** `escapeDeckMarkdownDashLines`
  ([`deck_markdown_dashes.dart`](../../lib/utils/deck_markdown_dashes.dart))
  exists so a `---` inside a `freeMarkdown` body is not read as a slide
  separator. A document is **not** split on `---`, so this function is **never**
  called on a document body — a `---` stays a real thematic break, byte-clean.
- **No byte-changing normalisation** on save. Not the CRLF→LF / NBSP→space /
  invisible-character strip that `normalizeRichTextMarkdownForStorage` applies
  to slide bodies. The model is `MarkdownSourceDocument`; the serialise is
  *"write the bytes"*.
- **Author-set front matter is preserved byte-identically.** A document may
  legitimately carry Jekyll/Hugo/Obsidian front matter the author wrote;
  `mergeFrontMatter` already preserves unknown keys. The document path injects
  **no** owned keys.

**MUST NOT:**

- **No new on-disk marker** to "claim" a `.md` as OciDeck's — no `kind:`,
  no `ocideck:` front-matter key. That would pollute every README and break
  maximum interchangeability. **The discriminator is the *absence* of
  `marp: true`.**

**Consequences to verify (open questions the gate must close):**

- The truncation heuristic `_looksTruncated`
  ([`file_service_open.dart`](../../lib/services/file_service_open.dart))
  assumes a front-matter header with a slide body; a plain document with no
  `---` must be shown, provably, not to trip it.
- The identity gate widening keeps the existing order: size-cap → UTF-8 read →
  `MarkdownSafetyScanner` (fail-closed) → path containment run **before** the
  marp check, so a document inherits the safety scan automatically. (Verified in
  exploration: the scan runs ahead of the marp gate.)

### 3.1 The gate test

A **zero-body-loss round-trip test** is the acceptance gate for §3: open →
(no edit) → save yields **byte-identical** output; and every construct in §4
survives open→save unchanged. This is the mirror image of the existing
[`test/roundtrip_content_loss_test.dart`](../../test/roundtrip_content_loss_test.dart),
which *documents* what the deck path loses — the document path must lose
**nothing**.

---

## 4. Rich content in a document

Rich content is expressed as **portable Markdown constructs** so the `.md`
opens fine anywhere. The editor makes inserting them easy; the file stays plain.
Ordered by how well they degrade in a foreign reader ("the interchangeability
ladder"):

| Construct | On disk | Degrades outside OciDeck to | Re-use |
|---|---|---|---|
| **Tables** | GFM pipe table | a real table | `TableEditor` via a text-in/text-out adapter |
| **Images** | `![alt](images/x.png)` | a real image | shared block helper; asset copied into `images/` |
| **Mermaid** | ` ```mermaid ` fence | rendered on GitHub/GitLab, else a labelled code block | `DocMermaidView` + `MermaidRenderService` (already works in the reader) |
| **Gantt** | Markdown table (+ portable marker) | a readable table | `ganttTableToMermaid` (pure) → mermaid render |
| **Math** | `$$…$$` | source text | shared block helper (lift from slide layer) |
| **Charts** | ` ```chart ` fence + `data/*.json` | **raw JSON** (does not render) | see §4.2 |

### 4.1 Gantt: the portable marker

In slides a gantt is a portable Markdown table **plus** a per-slide
`_class:gantt` token. A document has no per-slide `_class`. **Do not invent a
document-only token.** Format-first choice to settle at the gate, both of which
leave readable content behind:

- **(a) Emit ` ```mermaid ` gantt** — fully portable, renders as a real gantt on
  GitHub/GitLab, degrades to a code block; or
- **(b) Keep the readable table** and recognise it by its fixed header shape (an
  HTML comment above it, which Marp/foreign tools ignore, can carry the two
  options `scale`/`sections`).

Either way the gantt→mermaid derivation must be **emitted into the document
export path** (§6); today gantt renders only via the Flutter preview, so
without this a gantt would silently vanish on HTML/PDF export.

### 4.2 Charts: full-fledged, pretty in visual mode, double-click to edit

**Owner decision:** charts are supported **full-fledged**, identical mechanism
to the slide side (no second chart mechanism). On disk: a ` ```chart ` fence
with data externalised to `data/*.json` (readable, no base64, no binary).

This is the **one** genuine interchangeability tension, and we name it in the
open: unlike mermaid (widely recognised) or a gantt table (a real table), a
` ```chart ` fence shows **raw JSON** in a foreign Markdown reader. It does not
cross the hard red line (it stays plain, parseable text with external data — no
lock-in, no binary), but it sits on the weakest point of "maximally
interchangeable". Accepted because (a) it is identical to the slide mechanism,
and (b) the user can always get a rendered, portable artefact via export (§6).

**Visual behaviour (owner decision):** in the visual (WYSIWYG) mode a chart is
shown as its **fully rendered, pretty** form — the same render the slide side
draws — as an embedded card; **double-click opens the chart editor**. "The
picture is always nicer for the user." This requires **unlocking the rich chart
renderer and editor from their `Slide` binding**:

- The chart preview family is currently `part of` `slide_preview.dart` and takes
  a `Slide`; the `ChartEditor` mutates a `Slide`. Both need a **`ChartSpec`/block
  contract** (spec in, block text out) so they render and edit inside a document
  with only a `ThemeProfile` (and, for the Procesverbetering chart types, the
  deck-wide `ImprovementY01Metric` — a document supplies a theme + y01 context or
  falls back to defaults).

### 4.3 The hybrid embed card (the one genuinely new piece)

The visual mode renders prose as WYSIWYG **but** shows table / chart / gantt /
mermaid / image / block-math as **atomic, fully-rendered embed cards with an
"Edit" affordance** (double-click, or an explicit button). The prose goes
through the visual bridge; the blocks the bridge cannot round-trip losslessly
(tables, raw HTML, footnotes — the known `markdownVisualLimitations`) are
**never touched by the bridge**. The source text (`MarkdownSourceDocument`) is
**always** the truth. This is the rule that lets a WYSIWYG mode exist without
ever silently corrupting a table.

---

## 5. Storage & working directory

The storage layer is **already content-agnostic** and re-used wholesale:

- `StorageConnection` (Local / WebDAV / S3 / Git, incl. the git-clone working
  directory) carries a document `.md` as well as a deck `.md`; no presentation
  assumption lives there.
- The **working directory is the `projectPath` concept that already exists**:
  images in `images/`, chart data in `data/*.json`, **beside** the `.md` —
  exactly like a deck. No new working directory, no new backend, no database.
- The whole `FileService` mechanism transfers 1:1: fail-closed
  `MarkdownSafetyScanner`, size-caps, `writeStringAtomic` ("never half-written"),
  the containment guard (`resolveContainedRealPath` refuses `../` and absolute
  paths, follows symlinks), and the sidecar machinery (path =
  `setExtension(mdPath, …)`).

Small required changes:

- **`RecentFile` gains a `kind` discriminator** (document | presentation) so the
  recent list shows the right icon/label and never says "12 slides" for a
  document (`slideCount` stays 0/meaningless).
- **Not-yet-saved documents:** re-use the web-asset lifecycle (`mem:` assets)
  so an inserted image lives in memory until first save, then materialises into
  `images/`; the existing "you will lose this image" warning already covers it.
- **First save = fewest steps:** default filename from the first H1, like a word
  processor names a document after its heading.
- **Web parity** stays deliberately weaker (save = `.md` download only; no
  sidecars/assets) — accepted for now, communicated honestly.

---

## 6. Export

**Decision (owner): in-tree only — the `.md` itself + continuous HTML +
print-to-PDF. No pandoc, no bundled converter, no `.docx`/`.odt` for now.**

**Pandoc / LibreOffice: rejected**, for three converging reasons:

1. A native subprocess **escapes NetGuard interception** and can itself fetch
   external images/CSS over URLs — egress OciDeck cannot see. (The subprocess
   *pattern* is proven safe for git in
   [`git_cli_io.dart`](../../lib/services/git/git_cli_io.dart) — shell-less,
   `includeParentEnvironment:false`, timed out — but git was *empirically*
   verified not to network; pandoc/LibreOffice would each need that same proof
   and would still fail #2 and #3.)
2. Not bundled and not guaranteed present = a hidden external binary dependency
   and de-facto lock-in on a third-party tool; bundling rebuilds the
   provisioning model that was deliberately removed in 2026.
3. Desktop-only (`dart:io Process` does not exist on web) — web loses the
   feature.

And it is **unnecessary**: the user *already has* the plain `.md`, so every
pandoc target is open to them on their **own** machine with their **own**
pandoc — precisely the thesis working as intended. Document that; do not take
the dependency on ourselves.

**What we build instead:**

- **Continuous HTML** is the natural foundation. `MarpHtmlService` is already a
  self-contained, offline, CSP-locked renderer with tables/images/charts/
  mermaid/gantt/math/highlight. The only change is a render **mode** in
  `_renderSections`: one continuous flow instead of per-`---`
  `<section class="slide">`, plus document CSS (page width, margins, typography)
  instead of the 16:9 slide CSS. The marked/mermaid/mathjax/chart render layer
  is unchanged.
- **PDF** = continuous, with **selectable text and an accessibility tree**, via
  print-to-PDF from that HTML — **not** the existing image-per-page PDF path
  (which pastes one PNG per page: no text, no WCAG). The accessibility promise
  currently lives only in the HTML export; the document PDF inherits it.
- **Non-negotiable:** every document export goes through
  `buildExportBundle → AudienceDeck` (OciWacht redaction), enforced by the
  compile-time audience-boundary gate. A document export that touches raw source
  instead of the projected content leaks personal data past OciWacht. Close the
  gantt→mermaid gap (§4.1) in this path.

Should `.docx`/`.odt` ever be wanted, it is written **in-tree** via
`package:archive` exactly as the PPTX writer already hand-builds OOXML — a
separate, later decision, never an external converter.

---

## 7. Conversion presentation ⇄ document

One **headless service** (`DocumentDeckBridge`) with two pure, isolation-tested
functions — **not** spread across the notifiers, because conversion crosses the
round-trip and projection contracts:

- `documentToDeckMarkdown` — the flat document becomes a deck by *interpreting*
  `---` (or `##`) as slide breaks; warn that a thematic `---` thereby becomes a
  slide boundary (loss of intent).
- `deckToDocumentMarkdown` — serialise the deck, **strip** the marp front
  matter / theme / `_class` / slide `---`, and thread the bodies into one
  flowing document (lossless on text, loses slide-structure semantics).

Rules:

- Both are **explicit user actions that produce a NEW file/tab**, never an
  implicit in-place mode toggle. The round-trip is **asymmetric and lossy** (a
  deck deconstructs to typed slides; a document is verbatim), so a silent
  back-and-forth would quietly discard content/formatting.
- **Always a copy + preview + an explicit list of what is dropped.** The brake
  is not a scary confirmation but reassurance: *"We make a copy; your original
  file stays unchanged."* For document→presentation, show the proposed split
  ("12 slides based on Heading 1") with a granularity choice **before**
  committing — guessing slide breaks must never be silent.
- **The seal never travels** to a converted file (that would be a false
  integrity claim); a converted file is a new artefact with its own (or no)
  seal.
- No lossless-bijection promise. The two formats are genuinely different
  intents; claiming a perfect bridge would be the real lie.

---

## 8. Red lines (unanimous across the lenses)

1. **Flat `.md` on disk** — no `marp: true`, no forced slide `---`, no ZWSP
   dash-escape, no `themes/` scaffold, no byte-changing normalisation. Own
   serialise path, not `generateDeck`. *Not guaranteeable byte-clean = do not
   ship.*
2. **No new on-disk marker** to recognise a document — absence of `marp: true`.
3. **Body round-trips byte-identically** — model = `MarkdownSourceDocument`;
   the gate is the zero-loss test (§3.1).
4. **No third render path, no second chart mechanism** — share with the slide
   side or do not build (else permanent drift).
5. **Export only via `buildExportBundle → AudienceDeck`** — never raw document
   text around OciWacht.
6. **No pandoc / bundled external converter**; the safety scanner stays
   fail-closed ahead of every document path; path containment applies unchanged
   to linked images/files.
7. **No lossy WYSIWYG that silently drops a table** — hybrid embed cards or fall
   back to raw, nothing in between.
8. Every new visible string via `l10n.d('…')` in all languages; design controls
   for the longest language (segmented control, insert menu, badges), no fixed
   widths.

---

## 9. Phased roadmap

Bigger-at-once than a minimal MVP (owner decision), but **building on what
exists**, with the shared editor as the spine. Each phase is separately
deliverable and valuable.

- **Phase 0 — Format-first (this doc, no code).** Sign off the disk contract
  (§3), the gantt/chart marker choice (§4.1), and the shared-editor mandate
  (§2.1). Define the zero-body-loss round-trip test as the gate. Guardian +
  architect sign off. *Deliverable: this design, agreed, + the gate test.*
- **Phase 1 — Foundation.** `Document` abstraction over `MarkdownSourceDocument`;
  flat serialise path (no marp scaffold); identity gate → router; sealed
  `TabInfo` content; `RecentFile.kind`; shell stripped of the slide strip and
  "Slide N" wording in document mode. *Deliverable: open/edit/save a flat `.md`
  losslessly.*
- **Phase 2 — Shared render + edit layer (highest leverage).** Consolidate the
  doubled rich-block renderers (images `![]()`, block-math, syntax-highlighting,
  ` ```chart ` fence) into **one** layer the reader and the slide `freeMarkdown`
  preview both consume; `part`-split `document_markdown_view.dart` before the
  1000-line ratchet. Establish the shared Markdown editing surface (live, no
  "Apply" wall). *Deliverable: one editor + one renderer, both modes.*
- **Phase 3 — Insert like a word processor.** "+" button **and** `/`-slash on the
  command palette, extended with chart / gantt / mermaid / formula;
  `TableEditor`/`ChartEditor` given a text/block callback; hybrid embed cards in
  visual mode with double-click-to-edit (§4.3); charts rendered pretty (§4.2).
  *Deliverable: rich insertion producing portable Markdown.*
- **Phase 4 — Navigation & export.** Outline rail (`buildMarkdownOutline`),
  `MarkdownFindBar`, reading-time status bar; continuous HTML (`MarpHtmlService`
  flow mode + document CSS) and selectable PDF, through the OciWacht gate;
  gantt→mermaid gap closed. *Deliverable: professional-looking export.*
- **Phase 5 — Conversion.** `DocumentDeckBridge`: non-destructive, always-copy,
  preview dialog, drop-list. *Deliverable: two clean modes over one backbone.*

## 10. Resolved decisions & what re-uses what

**Resolved (owner, 2026-08-05):**

- **Ambition:** bigger-at-once, building on existing pieces; **one shared editor
  across document and presentation modes**, no double code, maximum UX (§2.1).
- **Charts:** full-fledged, identical to the slide mechanism; visual mode shows
  the pretty rendered chart, double-click to edit (§4.2).
- **Export:** in-tree `.md` + HTML + print-PDF; no pandoc, no `.docx`/`.odt` for
  now (§6).

**Still open for Phase 0 sign-off:**

- ~~Gantt marker~~ — **resolved** (§11.2): for a document, option (a), the
  ` ```mermaid ` gantt fence, by construction (no per-slide `_class`).
- Exact shape of the shared editing-surface contract so it serves both typed
  slides and flowing documents without paradigm bleed (§2.1 risk note).

The export / conversion / storage format contract is settled in **§11**
(implementation sign-off 2026-08-06, three-lens review).

**Building blocks re-used (verified in exploration):**

| Need | Existing building block |
|---|---|
| Lossless source model | [`markdown_source_document.dart`](../../lib/models/markdown_source_document.dart) |
| Flowing renderer | [`document_markdown_view.dart`](../../lib/widgets/reader/document_markdown_view.dart), [`doc_mermaid_view.dart`](../../lib/widgets/reader/doc_mermaid_view.dart) |
| Editor surface (raw + WYSIWYG notes) | [`lib/widgets/markdown_editor/`](../../lib/widgets/markdown_editor/) |
| Outline / TOC | [`markdown_outline.dart`](../../lib/models/markdown_outline.dart) (`buildMarkdownOutline`) |
| Insert palette | the existing Markdown command palette |
| Storage & working dir | [`storage_connection.dart`](../../lib/models/storage_connection.dart), `FileService`, `projectPath` |
| Export + privacy gate | [`export_service.dart`](../../lib/services/export_service.dart), `buildExportBundle → AudienceDeck` |
| Rich content | `MermaidRenderService`, `ganttTableToMermaid`, the chart preview/editor family (to be unbound from `Slide`) |

---

## 11. Implementation contract — export, conversion & storage (format-first sign-off 2026-08-06)

*This section turns §5–§7 into code-level decisions, grounded in the actual
export/projection internals, so the build follows a signed-off design rather
than discovering the format at the keyboard. Reviewed by the core-values
guardian, the security architect and the privacy expert (see the review note at
the end).*

### 11.1 The load-bearing fact: OciWacht projects a **Deck**, not flat text

The privacy boundary is not text-shaped. `PrivacyScanner` and
`PrivacyProjection._project` operate on the **deconstructed `Deck`/`Slide`**:
the scanner fragments *typed slide fields* (`customMarkdown`, `bullets`,
`tableRows`, `title`, …) and the projection redacts those fields. There is **no
public route that scans or redacts a flat Markdown `String`** — `redactText`
only applies author `[[…]]` marks, it does **not** detect PII.

Consequence, and it is a red line: a document export **cannot** hand flat
document text to OciWacht. To be projected it must first become a `Deck`. This
is *why* §6's "every document export goes through `buildExportBundle →
AudienceDeck`" needs a concrete bridge.

### 11.2 Export path (task: export) — **revised after the privacy review (2026-08-06)**

> **A naive single-`freeMarkdown` wrap is rejected.** The first draft wrapped
> the whole body into *one* `freeMarkdown` slide and read
> `bundle.audience.deck.slides.single.customMarkdown` back. The privacy review
> found three defects that all stem from treating a whole document as one slide:
> (1) externalised ` ```chart ` data in `data/*.json` is **never hydrated** for a
> non-`chart` slide, so it escapes the scanner entirely — a PII leak; (2) a GFM
> table inside one raw `customMarkdown` fragment loses its **column-header
> context**, so context-gated detectors (BSN under a "BSN" column) fire weaker
> than on a typed slide; (3) the **slide-wide escalation** that couples "there is
> a person here" to every special-category term, safe when a slide is small,
> over-redacts across an entire document. The wrap is therefore **not** the
> design. Export deconstructs into **typed slides**, exactly what OciWacht was
> built for.

**The path, corrected:**

```
// 1. Pre-scan hydration — fold every data/*.json chart series INLINE into the
//    body so the scanner sees the values, whatever slide type it lands in.
String hydrated = hydrateDocumentChartData(body, projectPath)   // pure + tested

// 2. Structural deconstruct into a real Deck via the EXISTING deck parser, so a
//    GFM table becomes a typed `table` slide (column context), a heading section
//    becomes its own slide (LOCAL escalation scope), prose becomes freeMarkdown.
Deck deck = DocumentDeckBridge.documentToDeck(hydrated)         // §11.3, shared

// 3. The one, audited boundary — unchanged.
ExportBundle bundle = buildExportBundle(deck, deck.slides, profile: …, …)

// 4. Read the projected body back DEFENSIVELY — join over all slides, never
//    assume `.single` (which relied on an undocumented cross-file invariant).
String projectedBody = DocumentDeckBridge.deckToDocumentMarkdown(bundle.audience.deck)
```

- **Deconstruction is the redaction enabler.** Because tables become `table`
  slides and each section is its own slide, the scanner keeps the column-header
  context (fixes finding 2) and the escalation stays section-local (fixes finding
  3). Chart data is hydrated *before* the scan and is **never** re-inlined from
  `data/*.json` *after* projection (fixes finding 1). No second scanner is built;
  the existing per-field projection does the work.
- **`.md` export** = `projectedBody`: a **projected copy for a recipient**, not
  the master. The interface must name it so — *"export a redacted copy"* — and
  never label it the same as **Save**, which alone writes the byte-faithful,
  un-redacted sovereign master (§3.1). Conflating the two would let a user mistake
  a redacted export for their master and silently forfeit the round-trip
  guarantee (guardian finding). The `.md` export is a derived artefact on a new
  file, so it is exempt from the open→save byte-identity gate; the zero-body-loss
  test stays about round-trip, untouched.
- **Continuous HTML** = `MarpHtmlService.build(projectedBody, continuous: true,
  …)`. New `continuous` flag: `_renderSections` renders the whole markdown as
  **one flowing `<article>`** instead of per-`---` `<section class="slide">`,
  with document CSS beside the 16:9 slide CSS. **The flow mode MUST route the
  body through the same inert `<script type="text/markdown">` + `_guardMarkdown`
  + client-side DOMPurify pipeline** as slide mode — it may never inject rendered
  HTML directly (security finding). The document CSS **MUST carry no external
  `url()`/`@font-face`**; the CSP is the net, not the licence. The marked/
  mermaid/mathjax/chart/highlight render layer is otherwise **unchanged** — no
  third render path (red line §4). A document `---` becomes a real `<hr>`.
- **The writing surface takes an `ExportBundle`** (never a raw `Deck`/
  `List<Slide>`), registered `SurfaceKind.audience` in
  `tool/check_audience_boundary.dart`. Note precisely what that gate proves: the
  **signature**, not the **derivation**. It cannot see a surface that keeps the
  raw body in scope and passes a `String` one layer deeper to `build()` (its
  documented blind spot). The real guarantee is therefore a **mandatory
  fail-closed test** (see §11.5), not the compiler.

**PDF — honest scope.** OciDeck produces the **projected, accessible continuous
HTML**; a PDF is obtained by the user printing that HTML through their **own
browser/OS** (Print → Save as PDF). OciDeck ships **no** HTML→PDF engine:
`package:printing`'s `convertHtml` is unsupported on desktop, a bundled headless
browser rebuilds the removed provisioning model and escapes NetGuard (the pandoc
reasons, §6), and the image-per-page `pw.Document` path has **no** text layer
(rejected for documents, §6). We do **not** promise the PDF keeps a text layer or
accessibility tree — that depends on the user's browser/OS, which we do not
control (guardian finding). The claim is bounded to what we produce: *"OciDeck
gives you accessible HTML; whether the PDF preserves that is up to your
browser."* The HTML that the user prints carries the **already-projected**
(redacted) body, so nothing un-scanned leaves the machine.

**Gantt in a document needs no special case.** A document has no per-slide
`_class:gantt`; a gantt is authored as a ` ```mermaid ` gantt fence, which the
unchanged mermaid layer already renders in the flow HTML. So §4.1's export gap
(a deck-only problem) **does not exist for documents** — resolving §4.1 for
document mode as **option (a), the ` ```mermaid ` fence**, by construction.

### 11.3 Conversion `presentation ⇄ document` (task: conversion)

One headless, isolation-tested service `DocumentDeckBridge` with two **pure**
functions (not spread across notifiers — conversion crosses the round-trip and
projection contracts):

- `deckToDocumentMarkdown(Deck) → String`: serialise the deck bodies into one
  flowing document; **strip** the marp front matter, `theme:`/`paginate:`, every
  `_class`, and the slide `---` separators; thread the slide bodies with blank
  lines. Lossless on *text*; loses slide-structure semantics (stated, not
  hidden). Also the projected-body reader for export (§11.2 step 4).
- `documentToDeck(String) → Deck` (and its `documentToDeckMarkdown` string form):
  interpret `##`/`---` as slide breaks. **The existing deck parser must NOT be
  fed sections raw** — the privacy re-review (2026-08-06) *empirically* found that
  `_inferSlideType` sends a heading-led section (`## Kop` + prose, the dominant
  document shape) to an **empty `bullets` slide**, silently dropping the prose
  *and* any table — content that then never reaches OciWacht. `documentToDeck`
  therefore **constructs typed slides directly, bypassing `_inferSlideType`**:
  it walks the body and, per block,
  - starts a **new `freeMarkdown` slide at each heading** (the heading text stays
    *verbatim in the slide body*, so it is scanned and the level round-trips) —
    one slide per heading section keeps the slide-wide escalation *section-local*;
  - accumulates prose, ` ```mermaid ` and code fences into that section's
    `freeMarkdown` `customMarkdown` (all scanned as text);
  - splits a **GFM table into its own `table` slide** (`tableRows`, so the scanner
    keeps column-header context) and a **` ```chart ` fence into its own `chart`
    slide** (so chart-data hydration applies).

  **Binding invariant:** after deconstruction, *every non-empty source line
  reappears in a typed, scanned field* (`customMarkdown` or `tableRows`) — zero
  loss is a privacy requirement, not a tidiness wish, enforced by a
  deconstruction-invariant test/gate. The reverse, `deckToDocumentMarkdown`,
  emits each slide's body (freeMarkdown → its `customMarkdown`; table → a GFM
  table; chart → a ` ```chart ` fence) joined with blank lines. **Warn** that a
  thematic `---` becomes a slide boundary (loss of intent).

Rules (from §7, now binding):

- Both are **explicit user actions producing a NEW file/tab** — never an
  in-place toggle. The round-trip is asymmetric and lossy.
- **Always copy + preview + an explicit drop-list.** The reassurance is *"we
  make a copy; your original stays unchanged."* Document→presentation shows the
  proposed split ("N slides from Heading 1") with a granularity choice **before**
  committing — never a silent guess.
- **The seal never travels** to a converted file (a converted artefact is new;
  a travelled seal would be a false integrity claim).
- No lossless-bijection promise anywhere in UI or docs.

`documentToDeck` is **shared** with the export path (§11.2): the same structural
deconstruction that makes a presentation is what gives the export its typed-slide
redaction. One deconstruction, two callers — no second, drifting mechanism.

### 11.4 Storage & working directory (task: storage)

**Decision: a document stays a single flat `.md` with the same beside-file
working directory as a deck — no project folder, no new backend.** This is
already the behaviour and the minimal one:

- Assets live **beside** the `.md`: images in `images/`, chart data in
  `data/*.json`, addressed relative. The insert-image path already passes
  `projectPath = dirname(filePath)` to the shared `ImageService`, which copies
  into `images/` (or keeps a `mem:` asset while the document is unsaved and
  materialises it on first save — the existing web-asset lifecycle and its "you
  will lose this image" warning cover it).
- The whole `FileService` substrate transfers 1:1: fail-closed
  `MarkdownSafetyScanner` ahead of every path, size caps, `writeStringAtomic`,
  the `resolveContainedRealPath` containment guard, sidecar machinery.
- **Web parity stays deliberately weaker** (save = `.md` download only; no
  sidecars/assets). The honesty must **land in-interface, not only here**: a
  warning at *insert time* (a chart/image into an unsaved-on-web document) and
  again at *web export*, so a user never silently ships an `.md` that references
  `images/`/`data/` files the download does not contain (guardian finding).
- `RecentFile.kind` carries document|presentation so the recent list shows the
  right icon/label (done); no on-disk `kind:` marker — recognition stays the
  *absence* of `marp: true` (red line §2).

Nothing here reopens the disk contract (§3); it records that the storage layer
is content-agnostic and needs no document-specific structure.

### 11.5 Review note & binding build requirements

**Review status: NOT yet signed off — export/conversion build is blocked.**
Reviewed 2026-08-06 by the core-values guardian (**akkoord-mits**), the security
architect (**akkoord-mits**) and the privacy expert (**niet-akkoord**, twice).
The privacy expert's second pass *empirically tested the parser* and found that
even the revised design's "reuse the existing deck parser" step leaks: a
heading-led section drops to an empty `bullets` slide, so PII in the dominant
document shape never reaches OciWacht (§11.3). The build must therefore implement
the **custom, zero-loss `documentToDeck`** of §11.3 and pass a re-review before
any export/conversion code lands. The following are **binding**:

1. **Custom typed-slide deconstruction, not a whole-document wrap and not the raw
   parser** — heading→title, each table/chart→own typed slide, prose→scanned
   `freeMarkdown`; enforce the **zero-loss invariant** (§11.3). This keeps table
   column-context and section-local escalation (privacy findings 2, 3) *and*
   closes the empty-`bullets` drop the re-review found. Export and conversion
   share this one `documentToDeck`.
2. **Pre-scan chart-data hydration** — fold every `data/*.json` series inline
   *before* `buildExportBundle`, and **never** re-inline external data after
   projection (privacy finding 1, the leak). **Mandatory fail-closed test**, in
   the **heading-led** shape the re-review named:
   `## Kop\n\ntoelichting met TOKEN\n\n| Naam | BSN |…` with externalised chart
   data, redacted profile → the export contains the redaction block and **not**
   the token or the raw table/chart values.
3. **Deconstruction-invariant gate** — verify no non-empty source section maps to
   an empty typed field (the empty-`bullets` trap), so a future parser regression
   cannot silently reintroduce the drop.
4. **Defensive projected-body read** — join over `bundle.audience.deck.slides`,
   never assume `.single` (security finding 2).
5. **Flow mode on the inert pipeline** — `continuous` renders through the same
   `<script type="text/markdown">` + `_guardMarkdown` + DOMPurify path; document
   CSS carries no external `url()`/`@font-face` (security finding 3).
6. **Honest promises** — the export UI distinguishes **Save** (byte-faithful
   master) from **Export → redacted copy**; the PDF claim is bounded to the HTML
   we produce, not the user's browser output (guardian findings 1, 2).
7. **Signature/closing names are not auto-found** — document plainly (or add a
   sign-off heuristic), consistent with the "we don't find everything" tone
   (privacy finding 4).

The audience-boundary gate proves the **signature**, not the derivation (its
documented blind spot); requirements 2 and 3 are the guarantees the compiler
cannot give. Every export route (`.md`, HTML, the printed PDF) must carry the
**already-projected** body — nothing un-scanned leaves the machine.
