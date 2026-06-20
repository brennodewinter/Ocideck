# OciDeck — Architecture

A high-level map of how OciDeck is put together, for contributors. For how files
are stored on disk, see [`FILE_FORMAT.md`](FILE_FORMAT.md).

## Stack

- **Flutter** desktop and web app (macOS, Windows, Linux, web), Dart 3.12+.
- **State**: [Riverpod](https://riverpod.dev/).
- **Storage**: standard Marp Markdown (`.md`) as the single source of truth, with
  sidecars for anything that isn't plain Marp.

## Module layout

```
lib/
  models/     # Deck, Slide, Settings/ThemeProfile, Chart, Annotation
  services/   # markdown, markdown_validator, file, export,
              # classification_policy, classification_enforcement_policy,
              # export_metadata, image, caption,
              # description, image_dedup (md5 duplicates),
              # image_reference (.md rewrites), recovery, rasterizer,
              # marp_html, annotation_codec, rehearsal_controller
  state/      # Riverpod providers: deck, editor, settings, tabs, clipboard
  widgets/    # app shell, panels, dialogs, per-type editors, slides, presenter
  l10n/       # AppLocalizations (8 languages)
  theme/      # app theming
  utils/      # small shared helpers (clipboard table parsing, URL launching)
```

## Data model

- **`Deck`** holds metadata, a list of **`Slide`**s, the active **`ThemeProfile`**,
  the deck-wide TLP level, and an in-memory **annotation layer** (`Map<slideId,
  List<InkStroke>>`) that is *never* serialized into the Markdown.
- **`Slide`** is a single immutable value with a `SlideType` and typed fields. A
  few types reuse `customMarkdown` for their payload: free-Markdown (raw),
  `code` (the source), and `chart` (the JSON spec).
- Slide ids are **regenerated on every parse**, so they are stable only within a
  session. Anything persisted that must survive a reload (annotations) re-anchors
  by slide order + a content fingerprint rather than by id.

## Markdown round-trip

`MarkdownService` is the contract:

- `generateDeck` / `generateSlide` write Marp Markdown. OciDeck extras live in
  front-matter keys and `<!-- … -->` comments that Marp ignores.
- `parseDeck` / `_parseBlock` read it back. `code` and `chart` slides are detected
  by their `_class` and parsed separately (their fenced block would otherwise
  confuse the generic line parser).

`MarkdownValidator` (`lib/services/markdown_validator.dart`) performs a
structural pre-flight before applying raw markdown in the editor: it reports line-
anchored errors/warnings for the same shapes the parser expects (front matter,
slide separators, `_class`, fences, OciDeck HTML fragments, chart JSON, etc.).
See `docs/FILE_FORMAT.md` §10 and `docs/USER_GUIDE.md` (Markdown mode).

This service is heavily covered by the round-trip tests — treat it as the
source-of-truth for the file format and keep `FILE_FORMAT.md` in sync.

## The two rendering worlds

Charts, diagrams, and slides are rendered in **two independent places**, which is
the key thing to understand before touching rendering:

1. **In-app** — `widgets/slides/slide_preview.dart` (`SlidePreviewWidget`) renders
   a slide as Flutter widgets. Free-Markdown ` ```mermaid ` blocks are rendered
   to inline SVG via `services/mermaid_render_service.dart` (shared WebView +
   bundled `mermaid.min.js`). The *same* widget is used for the editor preview,
   thumbnails, the fullscreen presenter, and — via `services/slide_rasterizer.dart`
   — the **PDF and PPTX** exports (rasterized to images). So anything that must
   appear in PDF/PPTX must render here. Charts use `fl_chart`.
2. **HTML export** — `services/marp_html_service.dart` produces a single
   self-contained `.html` that renders in a browser using inlined JavaScript
   (marked, highlight.js, mermaid, MathJax). Charts are pre-rendered to inline
   **SVG in Dart** here (no JS chart library). Fidelity differs from the in-app
   renderer by design.

Both worlds converge at one chokepoint: `services/export_service.dart`
(`ExportService.export()`) is the only place that writes an export.

### Classification enforcement

Export blocking is decided by `ClassificationEnforcementPolicy`
(`services/classification_enforcement_policy.dart`), evaluated inside
`ExportService.export()` **before** any file bytes are built — fail-closed, so no
format (PDF/PPTX/HTML/package) can bypass the gate. The export dialog and status
bar run the same policy up front for UX (explain early, disable misleading work).

The policy combines three optional rules from `AppSettings`:

| Setting key | Rule |
| --- | --- |
| `maxReleaseExportTlpKey` | Release **ceiling** — deck TLP must not exceed this level. |
| `minRequiredExportTlpKey` | **Floor** — deck TLP must be at least this level. |
| `requireClassificationOnExport` | Deck must have a TLP level (`TlpLevel.none` is rejected). |

`ClassificationPolicy` remains as a thin wrapper around the ceiling only
(backward compatible); new code should use `ClassificationEnforcementPolicy`.
The gate evaluates **deck-wide** `Deck.tlp`, not per-slide levels (those still
control visibility via `slideVisibleAtTlp`).

`ExportDocumentMetadata` (`services/export_metadata.dart`) is built from deck
metadata and passed into PDF (`pw.Document` title/author/subject/keywords/creator/producer),
PPTX core properties, and HTML `<meta>` tags. HTML also gets a fixed
`.tlp-export-banner` when classified.

### Visual TLP marking

In-app slides (`SlidePreviewWidget`) compute `effectiveTlp(deckTlp, slideTlp)` —
the stricter of deck and slide — and render FIRST TLP 2.0 markings from
`widgets/slides/previews/overlays.dart`:

- `_ClassificationBanner` — full-width top bar
- `_TlpOverlay` — bottom-right (or bottom-left) badge
- `_ClassificationWatermark` — optional diagonal watermark (`TLP · organisation`),
  controlled by `AppSettings.classificationWatermarkEnabled`

The same widget tree is rasterized for PDF/PPTX (`slide_rasterizer.dart`), so
markings are WYSIWYG. The watermark setting is threaded through preview, presenter,
audience window, thumbnails, and export dialog.

## Presenter

`widgets/presentation/fullscreen_presenter.dart` drives presenting:

- Keyboard navigation, presenter view, blank screen, grid overview, auto-advance,
  and the **annotation tools** (pen/highlighter/eraser/laser).
- Neighbour slide images are **precached** and `gaplessPlayback` is on, so slide
  changes never flash black (important for screen recording).
- **Rehearsal timing** lives in `services/rehearsal_controller.dart` — a plain,
  unit-testable controller (injectable clock) that the presenter feeds via a
  cheap, idempotent `observe(id, index)` on every build, so it captures every
  navigation path. It measures only: elapsed, remaining against a target, and
  per-slide time — no pacing logic. State is **session-only** (no prefs, no `.md`);
  `_exit` shows a summary (`rehearsal_summary.dart`) and discards it. The default
  target lives in `AppSettings.presentationTargetSeconds`.

### Dual-screen mode

When a second display is present (`shouldUseDualScreen` on macOS, Windows, or
Linux), the presenter runs in two OS windows:

- The **laptop** window shows the presenter view.
- A borderless **audience** window (`audience_window.dart`) fills the external
  screen with the slide.
- They sync over method channels (`ocideck/audience`, `ocideck/presenter`):
  current index, blank state, ink strokes, and the laser pointer. Media plays only
  on the beamer to avoid double audio.

This needs a real second window, which `window_manager` (single-window) can't do,
hence the vendored multi-window fork below.

## Sidecars (separate layers)

To keep the `.md` pure Marp, four kinds of data live beside it (see
`FILE_FORMAT.md` §6):

- **Captions** — `.ocideck_captions.json` (per image, in `images/`).
- **Descriptions/tags** — `.ocideck_descriptions.json` (searchable image
  metadata, used by the library's search and the untagged filter).
- **Annotations** — `<name>.ink.json` (`services/annotation_codec.dart`).
- **Linked chart data** — `data/*.csv` (the living source for a chart).

## Vendored forks

Two upstream plugins are forked into `third_party/` and wired via `pubspec.yaml`
(path dependency / `dependency_overrides`):

- **`desktop_multi_window`** (MixinNetwork) — vendored fork with
  `window_setFrame`, `window_coverScreen` (borderless fill of a chosen screen),
  and `window_close` on **macOS, Windows, and Linux**. macOS additionally tracks
  the mouse for non-key windows so chart hover works on the beamer.
- **`screen_retriever_macos`** (leanflutter) — a packaging fix for recent
  Xcode/CocoaPods.

If you bump either upstream, re-apply the local changes (they're small and
documented in the diff) and re-test the dual-screen presenter.

## Localization

`l10n/app_localizations.dart` holds Dutch source strings (`d('…')`) and
translation maps for en/it/de/fr/es/fy/pap. A test enforces that every literal
`.d('…')` has a translation in every language — add new strings to all maps.
