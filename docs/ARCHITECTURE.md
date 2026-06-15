# OciDeck — Architecture

A high-level map of how OciDeck is put together, for contributors. For how files
are stored on disk, see [`FILE_FORMAT.md`](FILE_FORMAT.md).

## Stack

- **Flutter** desktop app (macOS, Windows, Linux), Dart 3.12+.
- **State**: [Riverpod](https://riverpod.dev/).
- **Storage**: standard Marp Markdown (`.md`) as the single source of truth, with
  sidecars for anything that isn't plain Marp.

## Module layout

```
lib/
  models/     # Deck, Slide, Settings/ThemeProfile, Chart, Annotation
  services/   # markdown, markdown_validator, file, export, classification_policy,
              # image, caption,
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
   a slide as Flutter widgets. The *same* widget is used for the editor preview,
   thumbnails, the fullscreen presenter, and — via `services/slide_rasterizer.dart`
   — the **PDF and PPTX** exports (rasterized to images). So anything that must
   appear in PDF/PPTX must render here. Charts use `fl_chart`.
2. **HTML export** — `services/marp_html_service.dart` produces a single
   self-contained `.html` that renders in a browser using inlined JavaScript
   (marked, highlight.js, mermaid, MathJax). Charts are pre-rendered to inline
   **SVG in Dart** here (no JS chart library). Fidelity differs from the in-app
   renderer by design.

Both worlds converge at one chokepoint: `services/export_service.dart`
(`ExportService.export()`) is the only place that writes an export, so the
**classification gate** lives there rather than in the export dialog. A
`ClassificationPolicy` enforces an optional *release ceiling* and refuses,
**fail-closed**, to export a deck classified above it — no format can bypass it.
The ceiling is stored in app settings (`maxReleaseExportTlpKey`, off by default);
the dialog also runs the same check up front so a blocked export is explained
before any work starts.

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

When a second display is present (`shouldUseDualScreen`), the presenter runs in
two OS windows:

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

- **`desktop_multi_window`** (MixinNetwork) — published 0.3.0 dropped the native
  window-geometry API. The fork adds macOS `window_setFrame`,
  `window_coverScreen` (borderless fill of a chosen screen), and `window_close`,
  exposed on `WindowController`. It also tracks the mouse for **non-key
  windows** (matched by `macos/Runner/MainFlutterWindow.swift` for the main
  window): macOS only delivers mouse-moved events to the key window by default,
  and the borderless audience window deliberately never becomes key, so chart
  tooltips and hover states would otherwise never appear on the beamer. This is
  what makes the dual-screen audience window possible.
- **`screen_retriever_macos`** (leanflutter) — a packaging fix for recent
  Xcode/CocoaPods.

If you bump either upstream, re-apply the local changes (they're small and
documented in the diff) and re-test the dual-screen presenter.

## Localization

`l10n/app_localizations.dart` holds Dutch source strings (`d('…')`) and
translation maps for en/it/de/fr/es/fy/pap. A test enforces that every literal
`.d('…')` has a translation in every language — add new strings to all maps.
