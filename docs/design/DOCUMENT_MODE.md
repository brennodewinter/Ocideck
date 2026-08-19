# OciDeck — Document mode: product & format design

*A second kind of file next to the Marp deck: a **flowing Markdown document**
you edit like a word processor — headings, tables, images, charts, gantt,
mermaid — where the file on disk stays a plain, maximally interchangeable `.md`
that any Markdown reader opens.*

> **Status:** **implemented and merged** — document mode ships (open/edit/save, badge, Visueel\|Bron toggle, insert palette, formatting toolbar, document export to `.md` + flowing HTML via OciWacht, and presentation⇄document conversion including the zero-loss `documentToDeck` and its privacy gate, PR #1308). Since 2026-08-08 a document may also carry a **document-wide style** — a `theme:` front-matter key resolved against a `ThemeProfile`, written byte-surgically and opt-in only (§12) — and an inserted **page break** (a plain `---` that renders as a rule in the visual editor and becomes a real page boundary on print/PDF/LaTeX export, §13), with an opt-in **chapter page break** setting that starts every `H1` chapter on a new sheet on export (§13.5). Since 2026-08-16 the editor also has a third view, **Pagina's**, that lays the document out on real sheets with measured page breaks, the size setting reaches all 66 ISO 216 formats, and a printer's **bleed** can enlarge the exported sheet (§14). Since 2026-08-17 that page setup may also **travel in the document itself**, in the Pandoc keys `papersize:` and `geometry:`, written only on request — which reverses the "settings, not file content" position of §14.5 (§15, including the open point in §15.4). This design doc remains the "why" and the format contract; the contributor docs ([`USER_GUIDE.md`](../USER_GUIDE.md), [`ARCHITECTURE.md`](../ARCHITECTURE.md), [`FILE_FORMAT.md`](../FILE_FORMAT.md)) carry the behaviour. · **Status last reviewed:** 2026-08-19 · **Published by:** Stichting LibreKAT

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
> must pass through). **Generic visual-table sorting** and an optional
> **timeline view for two- or three-column GFM tables** have an implementation.
> Section 17 remains their format contract; its explicit acceptance evidence is
> the release norm.

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

- **No `marp: true`, no `theme:`, no `paginate:`** injected *automatically*. (The
  deck serialiser always writes these — see
  [`markdown_service.dart`](../../lib/services/markdown_service.dart) around the
  front-matter writer. The document path uses its **own** flat serialise route,
  never `generateDeck`.) One exception, added 2026-08-08, does **not** weaken
  this: a user may deliberately pick a **document-wide style**, which writes a
  single `theme:` key byte-surgically (§12) — never `marp:`/`paginate:` alongside
  it, and never on its own accord. A document with no style still carries no front
  matter, so §3.1's byte contract holds unchanged.
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
  ([`file_service_open.dart`](../../lib/services/file/file_service_open.dart))
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
| **Tables** | GFM pipe table | a real table | `TableEditor` via a text-in/text-out adapter, on the app-wide `markdown_table_codec` — so a document table is a full office table (per-column alignment, and multi-line cells via `<br>`), shared with the report slides / import / clipboard rather than a document-only copy |
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

**When the bridge cannot round-trip, Visual stays editable (owner decision,
2026-08-08).** An earlier build dropped the *whole* document to a read-only
rendered view the moment any `markdownVisualLimitations` construct appeared
(raw HTML, a footnote, an escaped punctuation mark) — no formatting toolbar, no
editing, only a note. That decided *for* the user that the document was not
theirs to edit. It now degrades instead of locking: Visual falls back to the
shared editor's **editable source surface** with the **full formatting toolbar**
and a short warning ([`markdownSourceModeHint`]), while the insert palette in
`_DocEditorToolbar` stays available throughout. The rich possibilities are
offered with a warning, never withheld. Source text is still the single truth —
the bridge still never touches those constructs — so no round-trip guarantee is
weakened; only the read-only wall is gone. (`DocumentEditorScreen._visualLayout`
now always mounts `MarkdownNotesEditor`, which owns the WYSIWYG↔source
degradation itself.)

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
- **Save and crash recovery are kind-agnostic (delivered 2026-08-08).** The
  app-wide `Ctrl/Cmd+S` and the *File → Save* menu item route through
  `saveDocumentWithDestination` for a document tab and `saveDeckWithDestination`
  for a deck, so the shortcut saves a document identically in Visual and Source —
  it previously reached the deck-only save and, in Visual, could not save at all.
  A new or no-longer-writable file falls back to *Save as…*. Crash recovery no
  longer skips document tabs: `RecoverySnapshot` carries a `kind`
  (presentation | document) — an older snapshot without the key reads as a
  presentation — and the autosave tick snapshots a dirty document as its own
  byte-faithful source (including the `theme:` front matter, no sidecars), which
  `restoreRecovered` puts back as an unsaved document tab. This realises the
  "recovery / dirty-tracking as shared `TabInfo` fields" of §2 for documents; the
  earlier code deferred it ("their own recovery path later").

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

- `documentToDeck` — deconstruct the flat document into a typed `Deck`, building
  slides **directly** (one per `##`/`---` section, GFM tables → `table` slides,
  ` ```chart ` → `chart` slides) so the OciWacht projection misses nothing —
  **never** via the deck parser's `_inferSlideType` (see §11.3).
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
  third render path (red line §4). A document `---` becomes a real `<hr>`, which on
  screen reads as a rule but in `@media print` is a page break (§13):
  `.document hr{page-break-after:always}` in
  [`marp_html_service_css.dart`](../../lib/services/marp_html/marp_html_service_css.dart).
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
- `documentToDeck(String) → Deck`:
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

---

## 12. Document-wide style — the `theme:` front-matter key (added 2026-08-08)

*A document may carry one **style**: a font-and-styling profile chosen
document-wide and written into the source as a single YAML front-matter key. It
is the only front-matter key the document path ever writes, it is written only on
the user's explicit request, and it is written byte-surgically — so §3's disk
contract stands unchanged. The picker in the toolbar owns it; the writer never
types it as text.*

### 12.1 What is on disk — the `theme:` key

A styled document opens with a leading YAML front-matter block whose one owned key
is `theme: <profile-name>`:

```
---
theme: LibreKAT
---

# Rapport
…
```

The value is the **name of a `ThemeProfile`** — the same profiles the slide side
uses (the built-ins `LibreKAT`, `Standaard`, `Security` and `Vigilis`, plus any the user
created), each carrying a font and styling. There is deliberately **no** new
kind of profile for documents: a document reuses the deck's style profiles by
name so a house style is defined once.

The style key is a portable YAML key any Markdown reader hides; it is **not** a
recognition marker. Recognition stays exactly what red line §8.2 says — the
*absence* of `marp: true`. A document that carries only `theme:` (verified against
[`markdown_service.dart`](../../lib/services/markdown_service.dart)
`sniffFrontmatter`, which sets `marp` only for `marp: true`) opens as a **document**,
never a deck. `theme:` never drags `marp:`/`paginate:` with it.

### 12.2 Byte-faithfulness — the red line held

The style lives behind
[`document_front_matter.dart`](../../lib/utils/document_front_matter.dart), a pure
byte-surgical string transform (`splitDocumentFrontMatter`, `documentStyleName`,
`withDocumentStyleName`) that never re-serialises the whole document. The
consequences that matter:

- A document **without** a style carries **no** front matter, so open→save without
  an edit is byte-identical — §3.1's zero-body-loss contract is untouched.
- Choosing a style on a plain document **prepends** a minimal `---`/`theme:`/`---`
  block; choosing **"Geen"** (none) removes it again. When `theme:` was the only
  key, the whole block is dropped and the exact plain body returns; when the author
  wrote other front-matter keys by hand, only the `theme:` line is touched and
  every other key and the body stay verbatim. Set-a-style-then-clear-it therefore
  round-trips to the original bytes.
- CRLF/LF and existing quoting are preserved; an unusual custom profile name (a
  colon, a leading dash, surrounding spaces) is YAML-quoted so it round-trips.

`MarkdownDocument` exposes this as `body` (source minus the block), `frontMatter`
(the verbatim block, or `''`), `styleName`, and the two producers `withBody` and
`withStyleName`, with `frontMatter + body == source` always true.

### 12.3 The editor edits the body; the picker owns the style

[`document_editor_screen.dart`](../../lib/widgets/document_editor_screen.dart)
binds the text surface to the document **body**, not the raw source: every
write-back puts the front matter in front again, so `document.source` stays
byte-faithful. The `theme:` line is therefore **never** shown as editable text —
it is managed by the **Style** picker (`_DocEditorToolbar._styleMenu`), which lists
"Geen (platte tekst)" plus every profile name and lands the choice byte-surgically
as a discrete undo step. The resolved profile styles the Visual writing surface
and rendered preview via `MarkdownEditorTheme.documentSurface(profile:)` and
`DocumentMarkdownView(themeProfile:)`. The raw Source editor deliberately stays
neutral and monospace: it edits Markdown rather than simulating the final page.
With no style, the rendered document falls back to the app theme, so a plain
document reads exactly as before.

### 12.4 Resolver precedence

[`document_style.dart`](../../lib/services/document_style.dart)
(`resolveDocumentStyleProfile`) resolves the effective profile in this order:

1. **Enforced house style** — when the settings switch `documentStyleEnforced` is
   on *and* the settings default `documentDefaultStyle` resolves to a profile, it
   wins and the per-document `theme:` is ignored.
2. **The document's own `theme:`**, when it names a profile that exists.
3. **The settings default** document style.
4. **`null`** — no document style; the caller keeps its own default (the app font
   in the editor; on export, the project's active profile), so a plain `.md`
   behaves exactly as it did before this feature.

A name that matches **no** known profile (an unknown or since-removed style) falls
through to the next step rather than erroring — an absent profile never breaks a
document. Export drives the same resolution:
`resolveDocumentStyleProfile(settings, styleName) ?? activeProfileFor(project)`,
so enforce → per-document `theme:` → settings default → project profile, and a
document with no style changes nothing about export.

### 12.5 Settings and conversion

- **Settings → General → Document style** carries the two fields:
  `documentDefaultStyle` (the default for documents without their own `theme:`,
  or "Geen") and `documentStyleEnforced` (use the default everywhere as a house
  style, ignoring each document's `theme:`). Both are display-and-export choices
  only — they write **nothing** into any `.md`; only the per-document picker does
  that. Enforce can be turned on only once a default is set.
- **Conversion to a presentation** takes the document **body**, not the front
  matter, so the style does **not** travel: the `theme:` line is an OciDeck styling
  hint, not slide content, and a new presentation gets its own theme (§11.3). The
  export path likewise reads `document.body`; the style reaches the output as the
  *resolved profile* handed to the renderer, never as a `theme:` line copied into
  the exported text.

---

## 13. Page break — the `---` thematic break (added 2026-08-08)

*A document stays a continuous flow on screen, but an author needs to say "start
the next part on a new sheet." Document mode expresses that with the **plainest
portable thing** the format already has: a Markdown **thematic break** (`---`). No
new marker, no OciDeck-only token — a foreign reader simply sees a horizontal
rule, and OciDeck's own export turns it into a real page boundary. This keeps
red line §8.1 (flat, maximally interchangeable `.md`) intact.*

### 13.1 What it is on disk

A page break is a literal `---` line in the body — the same thematic break any
Markdown reader renders as a horizontal rule. The insert palette's **Page break**
item (`_DocEditorToolbar`, `l10n.d('Pagina-einde')`) drops a plain `---` at the
cursor via `DocumentEditorScreen._insertPageBreak`. It writes **no** new key and
no OciDeck-specific syntax; recognition of the file as a document is unchanged
(the *absence* of `marp: true`, §2). Because a document is **never** split on
`---` (§3, red line §8.1), `escapeDeckMarkdownDashLines` is never called on a
document body and the `---` stays a byte-clean thematic break.

### 13.2 Where it takes effect — export and print, not the screen

On the writing surface and in the continuous HTML the document stays continuous;
the break is a **layout instruction for paged output**, applied at the edges:

- **HTML / print-to-PDF** — the flow HTML renders the `---` as a real `<hr>`
  (§11.2). On screen that is a rule; in `@media print` the rule becomes a page
  boundary: `.document hr{page-break-after:always;border:0;height:0;margin:0}` in
  [`marp_html_service_css.dart`](../../lib/services/marp_html/marp_html_service_css.dart),
  so when the user prints (or *Save as PDF*) the content after each `---` starts on
  a fresh sheet. This rides the same continuous-HTML path — no third render path.
- **LaTeX** — [`markdown_to_latex.dart`](../../lib/services/latex/markdown_to_latex.dart)
  maps the `hr` AST node to `\newpage` instead of a `\rule`, so a thematic break
  is a page break in the compiled PDF, not a drawn line. Every thematic-break
  form the parser recognises (`---`, `- - -`, `***`) yields the same `hr` node and
  therefore the same page break.

### 13.3 Rendering in the visual editor — and the latent crash it fixed

In the visual (WYSIWYG) editor a `---` arrives through `MarkdownQuillCodec` as a
`BlockEmbed('divider')`. Flutter Quill draws a **`RenderErrorBox`** for any embed
type it has no builder for, so before this change *any* document containing a
`---` — most visibly an inserted page break, but also one an author typed — broke
the visual surface. [`divider_embed_builder.dart`](../../lib/widgets/markdown_editor/divider_embed_builder.dart)
registers a `DividerEmbedBuilder` (added to `embedBuilders` in
[`wysiwyg_notes_field.dart`](../../lib/widgets/markdown_editor/wysiwyg_notes_field.dart)
beside the existing `TableEmbedBuilder`) that draws the block as a horizontal
rule, so the surface stays intact and the rule reads as the page break the export
will honour.

### 13.4 Front-matter hardening — a leading `---` is a page break, not front matter

A page break at the very top of a document collides with the front-matter reader
of §12: `---\n…\n---` looks like a YAML front-matter block. `splitDocumentFrontMatter`
([`document_front_matter.dart`](../../lib/utils/document_front_matter.dart)) now
treats a fenced block as front matter **only when it actually opens with a YAML
mapping key** (`_opensWithYamlKey`); a block whose first real line is a heading,
prose or anything else is body, so a leading `---` page break — or a `---\n# Kop\n---`
pair of rules — is never swallowed as a `theme:` block. This keeps §12.2's
byte-faithfulness rule true in the presence of page breaks: an unstyled document
carries no front matter, whatever `---` lines its body holds.

### 13.5 Chapter page break — an opt-in setting (added 2026-08-08)

Beside the author-placed `---`, a document can also start **every new chapter on a
new page** without a break being typed anywhere. This is a setting, not a marker
in the file: `AppSettings.documentChapterPageBreak`
([`settings.dart`](../../lib/models/settings.dart)), a bool that defaults to
**off**, persisted under the same key and set through
`SettingsNotifier.setDocumentChapterPageBreak`
([`settings_provider.dart`](../../lib/state/settings_provider.dart),
[`parts/settings_provider_document_style.dart`](../../lib/state/parts/settings_provider_document_style.dart) —
it mirrors `documentStyleEnforced`). The switch lives in **Settings → General →
Document style** as *Nieuw hoofdstuk op een nieuwe pagina*
([`settings_dialog_general.dart`](../../lib/widgets/dialogs/parts/settings_dialog_general.dart)).

Like the `---` break, it changes **only the paged output** — the writing surface
and the on-screen HTML stay continuous — and it never touches the `.md`. The flag
travels from `DocumentEditorScreen` through `writeDocumentExport`
([`document_export_service.dart`](../../lib/services/document_export_service.dart))
into the two paged renderers:

- **HTML / print-to-PDF** — when the setting is on, `MarpHtmlService.build`
  injects a print-only rule that starts every chapter on a fresh sheet:
  `@media print{.document h1{page-break-before:always;break-before:page}}`, with
  `.document h1:first-child` reset to `auto` so the very first chapter does **not**
  get a break (otherwise the export opens with a blank sheet)
  ([`marp_html_service.dart`](../../lib/services/marp_html_service.dart)). The CSS
  is only present when the flag is set; with it off the export is byte-for-byte
  what it was.
- **LaTeX** — `markdownToLatex` writes a `\newpage` before every `\section` except
  the first (an `H1` becomes a `\section`), tracked with a "seen a chapter yet"
  flag so the first heading opens the document rather than a blank page
  ([`markdown_to_latex.dart`](../../lib/services/latex/markdown_to_latex.dart)).

Both the `---` break and this setting can be in play at once: the `---` breaks
where the author placed it, the setting adds a break before each chapter heading.

### 13.6 Writing the chapter breaks into the document (added 2026-08-17)

The setting of §13.5 is app-wide and does **not** travel with the file, so a
document that paginates by chapter here runs on at the recipient. The answer is
not a fourth front-matter key — that would be an OciDeck-only spelling of
something the format already expresses. FILE_FORMAT.md §14.6 has the portable
form: a `---` in front of an `H1` is a page break every reader honours.

**Hoofdstukken op nieuwe pagina** in the insert palette
([`document_editor_toolbar.dart`](../../lib/widgets/parts/document_editor_toolbar.dart))
is therefore a one-off *edit of the body*, not a stored preference:
`applyChapterBreaksToDocument` → `applyChapterPageBreaks`
([`document_source_rewrites.dart`](../../lib/widgets/parts/document_source_rewrites.dart))
inserts a plain `---` before every `H1` but the first, and the screen commits it
through the same `documentProvider.edit` route as every other source rewrite, so
it is visible in **Bron** and one discrete undo step. Two properties make it safe
to press twice:

- **Idempotent** — a heading that already has a thematic break above it (blank
  lines in between allowed) is skipped, so a second run returns the body
  byte-for-byte and the snack bar says nothing changed.
- **One grammar** — the `H1` positions come from
  `DocumentMarkdownView.chapterHeadingLines` and the break test from
  `DocumentMarkdownView.isThematicBreakLine`, the same fence-skipping
  classification the view renders with. A `#` or `---` inside a fenced block is
  code, never a heading or a break. The rewrite works on `document.body`, so the
  front matter is untouched by construction.

A break is written with a blank line in front of it: `---` directly under a text
line is a setext `H2` of that line, not a rule.

---

## 14. Working on real pages (added 2026-08-16)

*A document mode that only ever shows a continuous scroll answers "what does it
say" but not "where does it fall". That second question is what a word processor
is for, and it is why an author picks a page size at all. This section covers the
third editor view, the widening of the size setting to the whole ISO 216 grid,
and the printer's bleed.*

### 14.1 The **Pagina's** view — a third *view*, not a third render path

The document editor's toggle gains a third setting beside Visueel and Bron:
**Pagina's** ([`document_editor_toolbar.dart`](../../lib/widgets/parts/document_editor_toolbar.dart),
`_DocViewMode.pages`). It lays the document out on sheets of the chosen size,
with the margins, the style's repeating header/footer band
(`DocumentChromeBand` — so the page number appears exactly when the style shows
page numbers, and a document without a style gets a bare sheet) and the bleed
drawn as a rim with the trim line marked.

§2.1's "no third render path" is not violated, and that is the load-bearing
design point. `PagedDocumentView`
([`paged_document_view.dart`](../../lib/widgets/reader/paged_document_view.dart))
renders the document through the **same** `DocumentMarkdownView` the other two
views use, once, and then shows a window on that single continuous render per
sheet (a `Transform.translate` inside a clip). A dedicated page renderer would be
a second layout engine, and a second engine is precisely the thing that drifts
away from the first without anyone noticing.

It is a **reading and checking** view: typing stays in Visueel or Bron. That is a
deliberate scope limit rather than a missing feature — an editable paged surface
would need a caret model that spans sheet boundaries, which is a different piece
of work.

### 14.2 Page breaks are measured, not estimated

`documentPageOffsets`
([`document_pagination.dart`](../../lib/services/document_pagination.dart)) is a
pure function from *measured* block heights plus a page height to the vertical
offset at which each sheet starts. The heights come from the real render: the
`blockWrapper` hook on `DocumentMarkdownView` wraps every block in a render
object that reports its own laid-out height
(`_MeasuredBlock`/`_RenderMeasuredBlock`), and the view holds off drawing sheets
until every block has reported.

A rule of thumb that predicts how tall a paragraph becomes rots the moment the
font, the text size or the line height changes, and a page break half a line off
is immediately visible — so no estimate is used anywhere in this path. The rules
the function applies:

- a block that still **fits** on a page is never cut; it moves on whole to the
  next sheet (widow-and-orphan behaviour an author expects from a word
  processor);
- only a block that fits on **no** page — a table or image taller than the text
  area — starts on a fresh sheet and is cut across as many sheets as it needs,
  because there is no alternative;
- the block after such a run starts fresh again, so a stray line does not end up
  glued under a half-cut table.

### 14.3 It is a view, not a prediction of the export

Three engines paginate a document, and they are genuinely different code: this
Flutter render, the **browser** when the recipient prints the exported HTML, and
**LaTeX** when the `.tex` is compiled. They need not break in the same place, and
the docs say so rather than implying a WYSIWYG guarantee the architecture does
not support. The honest claim is: this view shows how the document falls on paper
well enough to spot an awkward break, and the export is authoritative for the
export.

### 14.4 The whole ISO 216 grid

`PageSizeSpec` always covered series A, B and C, numbers 0 through 10, portrait
and landscape ([`page_size.dart`](../../lib/models/page_size.dart)); the settings
only listed ten of those in one dropdown, so B1 or C6 was unreachable even though
the model and both exports handled them. The setting now picks **series**,
**number** and **orientation** separately
([`settings_dialog_general.dart`](../../lib/widgets/dialogs/parts/settings_dialog_general.dart)),
which reaches all 66 combinations without a 66-line list. Each number is labelled
with its dimensions read from the model (`A4 — 210 × 297 mm`), so the interface
and the export cannot disagree about what a name means.

### 14.5 Printer's bleed — and why there are no crop marks

`PageMargins.bleedMm` (default `0`) is the printer's bleed: the sheet grows by
that much on every side while the text block shifts along by the same amount, so
it keeps its position relative to the **trim** size. Ink that runs to the edge
then runs through where the printer cuts, instead of leaving a white sliver when
the cut lands a hair off.

It reaches both paged outputs:

- **HTML** — `_pageAtRuleCss`
  ([`marp_html_service_css.dart`](../../lib/services/marp_html/marp_html_service_css.dart))
  writes `size` as an explicit millimetre sheet (`216mm 303mm` for A4 with 3 mm)
  because the paper *name* can no longer describe an enlarged sheet, `margin`
  with the bleed added per side, and a `bleed` declaration for an engine that
  implements CSS Paged Media. The enlarged `size` is what does the work in every
  print engine; the `bleed` declaration is the standards-conformant addition.
- **LaTeX** — `articlePreamble`
  ([`latex_preamble.dart`](../../lib/services/latex/latex_preamble.dart)) hands
  `geometry` an explicit `paperwidth`/`paperheight` when there is a bleed, rather
  than the paper name from `\documentclass`.

**Crop marks are deliberately absent.** They belong with a bleed, and a switch
for them briefly existed, but no output path emits them: the documented PDF route
for a document is printing the exported HTML, and no browser implements the CSS
`marks` property, while the LaTeX path would need the `crop` package, which is
not in every TeX installation. A switch that does nothing in either path is worse
than no switch — the printer would receive an enlarged sheet with no indication
of where the trim size lies. The reasoning is recorded on `PageMargins` so the
question does not have to be re-litigated; if an output path ever emits them,
they come back with it.

Two properties follow from where the bleed lives:

- **Nothing is written to the `.md`.** Size, margins and bleed are `AppSettings`
  (`documentPageSize`/`documentPageMargins`), the same kind of display-and-export
  choice as §12.5's default style — the byte-faithful round trip of §3 is
  untouched. `FILE_FORMAT.md` §14.7 states this on the format side.
- **It is app-wide and persistent.** A bleed set for one print job applies to
  every next document until it is set back to 0. Because that is exactly the kind
  of setting that bites silently, a non-zero bleed is shown beside the page size
  in the bottom-right corner of the visual editor.

The serialised form of `PageMargins` gains an optional fifth field
(`"25,25,20,20,3"`); a four-field value from before this change reads back
unchanged with `bleedMm: 0`, and a six-field value from the short-lived crop-marks
period still yields its margins and bleed rather than silently falling back to
the defaults.

---

## 15. Page setup that travels with the document (added 2026-08-17)

§14.5 closed with two properties of the bleed: nothing is written to the `.md`,
and the setting is app-wide. They were written down as consequences of a
deliberate choice. They turned out to be the design flaw, and this section
records the reversal and its reasoning; `FILE_FORMAT.md` §14.7 carries the same
course change on the format side, and §14.8 there states what is on disk.

### 15.1 Why the settings-only model broke

A page size is close enough to a viewing preference that keeping it in
`AppSettings` looked right, and §12.5 had already settled that the *default*
style belongs there. The bleed is not that kind of thing. It exists for one print
job, on one document, agreed with one printer. Two failures followed directly
from storing it app-wide:

- **It leaks forward in time.** A bleed set for a poster keeps enlarging every
  next export until someone remembers to zero it. The editor's corner indicator
  was added to make that visible, which is a mitigation for a problem the storage
  location created.
- **It does not travel sideways.** The `.md` is the master a document mode exists
  to protect (§3). Handing that master to a colleague or a printer and having the
  sheet silently change is exactly the loss of authorial control the mode is
  supposed to prevent. The old text answered this with "tell the printer out of
  band", which asks the human to carry information the file could carry itself.

So the sheet becomes a property the *document* may hold, with the settings as the
fallback for every document that says nothing. Opt-in, because writing to
someone's file without being asked is the other way to lose their trust.

### 15.2 Why Pandoc's vocabulary, and not an owned prefix

The obvious implementation is `ocideck_page_size: A4` and friends: unambiguous,
trivially round-trippable, no clash with anything. It was rejected.

`FILE_FORMAT.md` §14.1 promises that a document is a file any Markdown tool reads
without knowing anything about OciDeck, and that OciDeck adds no key that only
means something inside OciDeck. An owned prefix would put bytes in a user's file
that no other program can act on — the file would still be *readable* elsewhere,
but the page setup would be OciDeck-only metadata riding along, and the promise
would have quietly become "no owned keys, except ours".

`papersize:` and `geometry:` are keys **Pandoc executes**. Run the file through
your own Pandoc and you get the page the keys describe; the same keys reach the
LaTeX `geometry` package that OciDeck's own `.tex` export already writes to. This
is the same test `theme:` passed in §12.1: join a vocabulary others already speak,
or do not write at all. That the vocabulary is slightly awkward for us — no
orientation on `papersize:`, no notion of a bleed — is the price of that rule, and
§15.3 pays it rather than escaping it with a private key.

To keep the promise checkable rather than cultural, the writable keys are a
register: `kDocumentOwnedKeys` in
[`document_front_matter.dart`](../../lib/utils/document_front_matter.dart) holds
exactly `theme`, `papersize` and `geometry`, and the generic writer asserts
against it. Beside it stands `kDocumentRetiredKeys`, the recorded exit: the entry
point for a key is easy, and the way out has to be equally easy or the format
accretes forever. It is declared and empty; no write path consults it yet, which
is fine while nothing has been withdrawn, but it is a stub and not a mechanism.

### 15.3 Why the bleed goes as explicit millimetres

A bleed makes the sheet larger than the trim format. `papersize: a4` on a sheet
of 216 × 303 mm would be a false statement in the file — and a dangerous one,
because a printer's toolchain would believe it and produce a page 6 mm too small
with the text block in the wrong place. There is no Pandoc key for "A4 plus 3 mm".

So with a bleed (and, for the same reason, in landscape, which `papersize:`
cannot express) the paper name is dropped and the sheet is written as
`paperwidth`/`paperheight` inside `geometry`, with the margins measured from the
edge of the enlarged sheet. That is not a new convention: it is byte-for-byte the
shape `articlePreamble` already emits for a bleed (§14.5). The file and the LaTeX
export therefore cannot disagree about the page — and a foreign toolchain that
knows nothing of bleeds still lays out the correct sheet, because what it reads
is the effective size, which is complete on its own.

The cost is that "A4 + 3 mm" is not literally in the file. OciDeck reconstructs it
on the way back in: a sheet evenly larger than a known ISO format on both axes
(same amount, up to 20 mm) is read as that format plus a bleed, purely so the
editor can say *A4 · +3mm* instead of *216 × 303 mm*. That inference is interface
sugar. If it ever disagrees with the file, the file wins — the millimetres are
the record.

### 15.4 Open point: the format does not survive the round trip

The reconstruction above recovers the bleed and the margins. It does **not**
recover the *format*: `documentPageSetup` derives the size from `papersize:`
only, so a document pinned with a bleed or in landscape reads back with
`size: null` and falls through to the receiving machine's setting. A document
pinned as A4 + 3 mm, opened where the setting says A5, is laid out on A5 + 3 mm.

This is a gap, not a decision. Pandoc is unaffected (it reads the explicit
millimetres and is correct), but OciDeck's own screen and exports are not. Two
things follow from the same root and belong in one fix: `_inferBleed` already
searches the ISO grid for the matching format and then throws that format away
instead of returning it, and the editor's "pinned to this document" state keys on
`papersize:` alone, so precisely the documents that most need pinning — bleed
work for a printer — are shown as unpinned. Recorded here and in
`FILE_FORMAT.md` §14.8 so it is not rediscovered as a surprise.

### 15.5 The write is a decision, not a toggle

The control is the page-size indicator that already sat in the corner of the
visual editor. It stopped being decorative: it now shows *where the current page
setup comes from* — a pin and an accent border when the document carries it,
the plain border when it comes from settings — and clicking it opens a
confirmation dialog that says what will happen before it happens.

That is deliberately heavier than a switch in the settings panel. The action
writes into the user's own file, which is the one place OciDeck has promised to
touch only when asked (§3, §12.2). A control that lives where the information
already is, and that asks once, is the shape that fits a byte-faithful format:
nobody discovers afterwards that their `.md` grew two lines.

---

## 16. Writing comfort — width, zoom, orphaned headings and footnotes (added 2026-08-18)

Four complaints from real use, and what each one turned out to be.

### 16.1 The width setting that was quietly overruled

`AppSettings.documentEditorMaxWidth` had a "full width" option that appeared to
do nothing. It did nothing: the visual layout used the page's text width
*whenever the page-break lines were on*, and those are on by default. One switch
therefore controlled two unrelated things, and the one the user could see was the
wrong one.

They are now separate. `DocumentEditorWidth` — `page`, `column`, `full` — is a
choice in the toolbar, because it is a choice you make *while writing*: the whole
screen for a wide table, back to the sheet afterwards. The page-break lines are
drawn only in `page`; outside it the button is disabled and says why, instead of
falling silent. A line that claims to show where the sheet breaks must be
measured on the width the sheet actually has, or it is decoration.

### 16.2 Zoom that stays honest

A zoom that scales only the text would move every page break: the column stays
the same, the lines wrap differently, and the break lands somewhere else than on
paper. So the zoom multiplies three things by the same factor — the text scale,
the column width, and the page height the break arithmetic uses. Relative layout
is then identical at any zoom, and a break falls at the same place in the text at
50% as at 250%.

In the **Pagina's** view the zoom is geometric instead: the sheet is drawn larger
or smaller (`PagedDocumentView.scale`, a parameter that existed but was never
passed) and the layout on it is untouched. That is the right meaning there — you
zoom to see better, not to make it break elsewhere. A second, horizontal scroll
catches a sheet that no longer fits the window.

### 16.3 A heading is not the last thing on a page

`documentPageOffsets` knew only block *heights*, so a heading could be the last
thing that fitted on a sheet with its text on the next one. The rule added is
"keep with next, and with enough of it": below a heading at least two lines of
body text must fit on the same sheet, counted over as many following blocks as
it takes. Two lines and not one, because a heading with a single orphaned line
under it reads no better than a heading alone — which is exactly how the
complaint was phrased.

Two headings in a row travel as a group, and an oversized block (a table taller
than the text area) takes the heading above it along instead of demanding a fresh
sheet and leaving it behind. LaTeX does all of this itself; the browser is told
with `break-after: avoid` plus `orphans`/`widows`, so screen and print say the
same thing.

### 16.4 Footnotes: two embeds, one optional key

The format side is `FILE_FORMAT.md` §14.9. Three decisions are worth recording
here.

**Why two embeds and not one.** The obvious rich-text shape is a single inline
embed carrying both the marker and the note text. It was rejected: the definition
would then be stored at the position of the *reference*, and the first edit in
the visual editor would move it there in the file. A document mode whose promise
is byte-faithfulness (§3) cannot rearrange an author's file as a side effect of
opening a different view. So the reference is an inline embed and the definition
a block embed on its own line, and the bytes come out where they went in.

**Why the number is not the label.** The label is the author's handle and stays
in the file; the number is the reader's, and is assigned by reading order
everywhere — screen, LaTeX, HTML. This is Pandoc's behaviour and it is the reason
inserting a note between two others costs nothing.

**Why the space for a note hangs on the block, not on the page.** A note at the
foot of a sheet takes room away from that sheet, which changes what fits, which
can move the reference to the next sheet — the classic loop that layout engines
solve by iterating until it settles. It does not need to be a loop here.
`documentPageOffsets` takes a `reservedRoom` per block: the room a block's own
footnotes claim at the bottom of whatever sheet the block lands on. Move the
block and the claim moves with it; the room on the old sheet is free again by
construction. One pass, no iteration, and no risk of a layout that oscillates.

The only surface that cannot keep the promise is the HTML export: an HTML page
has no pages. It puts every note at the back with a link there and back, and
`KNOWN_LIMITATIONS.md` says so rather than letting the export quietly differ from
the screen.

---

## 17. Visual table sorting and a timeline view (implemented 2026-08-19)

> **Status: implementation present.** The code uses the portable
> marker-and-table contract, a shared local table sorter, a Visual-mode embed,
> and document render/export paths. The explicit acceptance evidence in §17.8
> remains the norm for this behaviour; implementation does not turn those
> requirements into historical notes.

The motivating case was an incident report assembled from several sources. Its
facts were correctly preserved in a three-column `Tijd | Gebeurtenis | Status`
table, but source order was not guaranteed to be chronological and the decisive
turn in the response was hard to see. Two capabilities follow from that case,
and they must remain separate:

1. **sorting by a column is a standard table operation in Visual mode**; and
2. **a timeline is an optional visual representation of a suitable table**.

The timeline may offer the standard sort action when events appear out of
order. It does not own a second sorting mechanism.

### 17.1 Product boundary

Every visually editable GFM table gets sorting in its active-column controls.
This is useful without a timeline: findings can be sorted by severity,
measures by deadline, inventory by owner and figures by amount. Sorting therefore
belongs to the generic table model, editor and source rewrite path.

A timeline is narrower. It turns an explicitly marked two- or three-column
table into a static, vertical sequence in Visual and Pagina's mode and in
document exports. It is not a new document type, a general card designer, a
process-modelling surface or an automatically inferred replacement for any
table that happens to contain a date.

The user always decides to activate the timeline view. OciDeck may analyse a
table and propose a helpful next action, but it never changes representation or
row order merely because a document was opened.

### 17.2 Generic table sorting in Visual mode

The active-column controls offer:

- **Sort ascending**;
- **Sort descending**; and
- **Sort as…**, where the author explicitly chooses automatic, text, number,
  date or time **and** ascending or descending direction.

Sorting is a real edit, not transient presentation state. When applied it
rewrites the body-row order in the ordinary GFM table, so source mode, a foreign
Markdown reader and every export see the same order. No sort key or current
sort direction is stored as OciDeck metadata.

The operation has these invariants:

- the header and delimiter row never move;
- complete rows move as units; no cell crosses into another row;
- cell bytes and inline Markdown are not normalised, corrected or rewritten;
- alignment, escaped pipes, `<br>` line breaks and extra cell content survive;
- the sort is **stable**: equal keys retain their original relative order;
- unknown, empty or unparseable values go last by default and retain their
  relative order there;
- one applied sort is one undo/redo transaction; and
- a failed or cancelled sort leaves the source byte-identical.

A directly chosen ascending or descending sort uses automatic recognition. If
that has no single usable interpretation, OciDeck asks how to read the column.
When a usable interpretation leaves values unrecognised, it shows the compact
attention-point dialog before mutation. For example:

> 16 rows can be sorted as times. Three values have no exact time and will stay
> together at the end in their current order.

The actions are **Sorteren toepassen**, **Waarden bekijken** and **Annuleren**.
**Waarden bekijken** lists the affected row numbers and literal cell values.
A warning explains the consequence and the remedy; `Invalid value` is not
acceptable interface copy.

Time-like parsing is deliberately conservative and local. It may derive an
ephemeral key from exact times, dates, years, numeric phases, ranges (start
value), and qualified values such as `circa 13:10`. The displayed source stays
unchanged. A label such as `After the incident; time not recorded` remains an
unknown value, not a guessed timestamp. Crossing midnight or combining several
days requires an explicit date column or date-bearing cells; OciDeck never
invents the day.

### 17.3 One shared, explainable table analysis

Sorting and timeline suitability use one Flutter-free analyser over decoded GFM
rows. It profiles each column without network access or a language model and
returns evidence, not a verdict hidden in a boolean. A `TableColumnProfile`
needs at least:

- non-empty and empty counts;
- the dominant parse kind (text, number, date, time or mixed);
- successfully and unsuccessfully parsed row indices;
- whether values are already monotonic in source order; and
- a confidence plus human-readable reasons.

The analysis result distinguishes:

- **suitable** — the requested operation has a clear interpretation;
- **suitable with attention points** — it can proceed without data loss, but
  specific rows deserve review; and
- **not yet suitable** — OciDeck cannot choose safely and offers a concrete
  correction or the ordinary table view.

Examples of acceptable messages:

> This table appears suitable as a timeline. 19 events found.

> Three events have no exact time. They remain visible and keep their current
> relative order.

> I cannot yet determine which column defines the sequence. Choose the first
> timeline column or keep this as a table.

The analyser never assigns meaning to words such as `reported`, `confirmed`,
`critical` or `complete`. Such cells remain author-owned text.

### 17.4 Timeline disk contract

The source of a document timeline is still a real GFM table. A single portable
view hint immediately above it marks the table:

```markdown
<!-- timeline -->
| Time | Event | Status |
| --- | --- | --- |
| 13:24 | All users signed out | Reported |
```

The comment applies only to the immediately following GFM table. It carries no
layout, colour, animation, inferred type or sort state. Removing it returns the
ordinary table view without changing a cell. A foreign Markdown reader ignores
the comment and renders a normal table; an older OciDeck must preserve both the
unknown comment and table through its byte-faithful document path.

The marker and table form one atomic `TimelineTableBlock` in every visual-edit,
move, replace, undo, conversion and export path. Treating the marker as raw HTML
and the table as an unrelated block would make Visual mode fall back to source
or could orphan the marker when the table is edited. The implementation must
therefore add an explicit supported embed rather than rely on generic raw-HTML
handling.

Version one accepts exactly:

- two columns: **marker** and **event**; or
- three columns: **marker**, **event** and **metadata**.

The column roles are positional, while the original column headers remain
visible as their labels. `Year | Milestone`, `Phase | Decision` and
`Time | Event | Source` are therefore as valid as an incident table. The third
column is displayed with its own header — for example `Status · Reported` — so
OciDeck does not silently turn a source, owner or conclusion into a status.

When analysis suggests that suitable columns are in another order, the dialog
may offer **Reorder columns and create timeline** as an explicit, undoable table
edit. Role mappings are not hidden in the marker. Tables with four or more
columns remain ordinary tables in the first version; widening this contract is
a later format decision.

### 17.5 Timeline activation and friendly failure

**Invoegen → Tijdlijn** opens the ordinary table editor with a three-column
starter table (`Tijd`, `Gebeurtenis`, `Status`). Only **Toepassen** inserts the
portable marker plus table; **Annuleren** changes nothing. A new timeline is not
inserted while all event cells are empty; the document stays unchanged and the
same editor reopens with the entered values plus a concrete prompt to add an
event. An existing editable two- or
three-column table gains **Als tijdlijn weergeven**. Activation runs the
local suitability check and then previews the positional roles and found event
count; it never scans the whole document for tables to convert automatically.

When usable marker values are not ascending, that preview says so and offers
**Huidige volgorde behouden** or **Sorteren en tijdlijn maken**. The latter
uses the generic marker-column sort from §17.2; the former leaves source order
intact. Timeline rendering itself never sorts a private copy. A table with
another number of columns, or without body rows, remains visually editable with
a diagnosis that says what must change (and may be switched back to an ordinary
table).

Rows that lack an exact marker remain events. They receive an open or otherwise
non-deceptive node and their literal marker text. Empty event cells are an
attention point with a row number and an edit action; they are not silently
dropped. A table that cannot be rendered safely remains a fully editable table
and gets a message that says what must change.

### 17.6 Document rendering and pagination

The document renderer is static and vertical. It uses one unambiguous spine,
marker labels on the left and all event cards on the right in source order.
Cards never alternate across the spine: that presentation flourish weakens
reading order and page breaking on portrait paper.

All rows render. There is no presentation timeline's twelve-event ceiling and
no hover-only detail. Each event is a separately measurable page unit; a page
breaks between events whenever the card fits on a sheet. Only a single card
that is itself taller than the available page area is cut, because scaling or
hiding its text would harm readability and completeness. In **Pagina's**, every
sheet that continues a timeline — at a later event or inside such an oversized
card — restarts the rail at its top and shows the localised **Tijdlijn · vervolg**
label plus that card's first-column marker (date, time, phase, or another
author-chosen marker) in its top margin. An empty marker stays empty; the view
does not infer one. Pagina's,
continuous HTML, print/PDF and LaTeX must preserve the same event order and
complete text.

The text remains real, selectable, searchable and exposed to assistive
technology. Status/source/metadata styling is neutral. OciDeck does not infer
red, amber or green from cell contents. Screen-only line drawing may be subtle,
must honour reduced motion and is neither stored nor used in export.

### 17.7 Architecture seams

The implementation has one headless table-analysis and stable-sort service.
The existing `markdown_table_codec` decodes cells for analysis and display,
but it **must not rewrite a sorted table**: decoding trims cells and encoding
normalises the table, which contradicts the byte-preservation invariant in
§17.2. Applying a sort instead permutes the original raw body-row lines as
opaque slices. Only their order changes; spacing, escapes, `<br>` elements and
delimiter variants remain byte-for-byte intact. The visual table, timeline
activation dialog and tests consume that one service; none implements its own
value parser or comparator.

The timeline path consists of:

- a Flutter-free `DocumentTimeline`/entry model that keeps the exact table
  source authoritative and derives headers, events and optional metadata;
- one document-timeline codec that recognises and writes the atomic marker plus
  table block;
- a document-reader timeline view that owns the flowing card layout; and
- a visual-editor embed that edits through the existing table controller and
  writes marker plus table back together.

`DocumentDeckBridge` and the OciWacht document-projection/export path recognise
the marker and following table before generic comment/table handling, and carry
them as one unit. Splitting them or inserting a blank line would make the marker
lose its meaning; re-encoding the table would lose the byte-preservation
property.

Presentation and document timelines may share contrast rules, typography and
small card primitives. The document must not import the private 16:9 slide
renderer: that renderer takes a `Slide`, owns reveal state and caps events for a
bounded canvas. Likewise, the timeline table is not converted to the current
presentation `TimelineEvent(marker, title, description)` if that would fold the
third column into a description or lose its header. Until a genuinely lossless
shared superset exists, document⇄presentation conversion keeps the complete
marked table as portable Markdown or a table representation rather than
pretending it round-tripped as a typed presentation timeline.

Every export still passes through the OciWacht audience projection (§11.2).
Timeline recognition must happen on projected table cells, never on a parallel
raw-source path.

### 17.8 Acceptance evidence

The feature is not complete until tests and visual checks prove at least:

- stable ascending and descending sorts for text, numbers, dates and times;
- equal keys, empty cells, mixed formats, qualified times, ranges and unknown
  markers preserve the documented order;
- sorting moves complete rows, changes no cell bytes and is one undoable edit;
- a raw-row fixture containing unusual spacing, escaped pipes, `<br>` content,
  leading/trailing cell spaces and delimiter variants survives sorting exactly;
- cancelled and failed sorting are byte-identical no-ops;
- a marked two-column and three-column table round-trip losslessly;
- removing only `<!-- timeline -->` restores the ordinary table;
- malformed marked tables fail back to a visible, editable table;
- a 19-event, multi-source incident fixture renders without omission in Visual,
  Pagina's, continuous HTML, PDF/print and LaTeX;
- page breaks occur between event cards whenever a card fits; every unavoidable
  continuation of one oversized card is apparent;
- search, selection, keyboard operation, screen-reader order, 200% text and
  reduced motion remain usable;
- document→presentation→document keeps the marker immediately followed by the
  same table and never loses the third column or any raw table bytes;
- projected Markdown, HTML and LaTeX recognise that same atomic marker+table
  block after OciWacht rather than separating or re-encoding it;
- OciWacht projects every cell before every export; and
- the behaviour works in light/dark themes and all supported interface
  languages without relying on translated column names.

The format and product decision is deliberately small: one ignored comment, a
real table, a standard table sort and a derived view. If OciDeck disappeared,
the user's ordered facts would still be a useful Markdown table.
