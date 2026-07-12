# OciDeck — Architecture

A high-level map of how OciDeck is put together, for contributors. For how files
are stored on disk, see [`FILE_FORMAT.md`](FILE_FORMAT.md). For a one-line
description of **every** file under `lib/`, see [`SOURCE_MAP.md`](SOURCE_MAP.md).

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
              # marp_html, annotation_codec, rehearsal_controller,
              # webdav (Nextcloud source), secret_store (keychain)
  state/      # Riverpod providers: deck, editor, settings, tabs, clipboard,
              # webdav
  widgets/    # app shell, panels, dialogs, per-type editors, slides, presenter
  l10n/       # AppLocalizations + translations/<lang>.dart (31 languages)
  theme/      # app theming
  utils/      # small shared helpers (clipboard table parsing, URL launching)
```

## Data model

- **`Deck`** holds metadata, a list of **`Slide`**s, the active **`ThemeProfile`**,
  the deck-wide TLP level, and an in-memory **annotation layer** (`Map<slideId,
  List<InkStroke>>`) that is *never* serialized into the Markdown.
- **`Slide`** is a single immutable value with a `SlideType` and typed fields. A
  few types reuse `customMarkdown` for their payload: free-Markdown (raw),
  `code` (the source), `chart` (the JSON spec), `cockpit` (the JSON spec of
  its instrument meters), and `question` (the JSON quiz spec — kind, prompt,
  answers, option count, time limit).
- **Question slides** are interactive. The authored `QuestionSpec` round-trips in
  `customMarkdown`; the live per-presentation state (`QuestionView` — the random
  options drawn, the pick, correct/wrong, timer) is **session-only** and never
  serialized. During presentation the presenter window is the single source of
  truth: the audience window forwards clicks (`answerSelected` / `answerSubmit`)
  and the presenter pushes the resulting `QuestionView` back over the window
  channel, the same pattern as the checklist/table sync.
- **Timeline slides** keep their events in the normal `bullets` field as
  `marker :: title :: description` list items (no `customMarkdown`), so the `.md`
  stays a readable Markdown list. The layout (`TimelineLayout`) and animation
  (`TimelineReveal`) are typed `Slide` fields that round-trip as extra `_class`
  tokens (`timeline-horizontal/-vertical/-steps/-static`) rather than in the
  content. In *step* mode the revealed-event count is **session-only**, mirroring
  the `_richTextPage` pattern: the presenter intercepts next/prev and pushes a
  `timelineStep` over the window channel so the audience window reveals in sync.
- Slide ids are **regenerated on every parse**, so they are stable only within a
  session. Anything persisted that must survive a reload (annotations) re-anchors
  by slide order + a content fingerprint rather than by id.
- **`CockpitColorScheme`** is a named set of cockpit status colours (good /
  warning / critical / cold). Schemes live in `AppSettings` (a managed list plus
  a globally selected name, mirroring `ThemeProfile`/`AppAppearanceProfile`), not
  in the deck — the colours are styling. The active scheme is resolved from
  settings and threaded into `SlidePreviewWidget` and the export chain alongside
  `themeProfile`; the cockpit painter and the export SVG read the four colours
  from it instead of hardcoded constants. For the beamer window it travels in the
  transient audience payload, like the inlined style profile.

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
   Video sources are classified once by `models/video_source.dart`
   (`VideoSource`: local file / remote file / YouTube / Vimeo) so the preview,
   markdown serializer and exporter agree. Local and remote files play through
   the shared `_MediaPlaybackHost` (`video_player`, file vs `networkUrl`), which
   also seeks to the segment start and stops at the segment end (the per-slide
   trim window that powers "cut a video across slides"). YouTube/Vimeo play in a
   second on-screen WebView (`_VideoEmbedPreview`, the same pattern as the
   Mermaid host) wired to the provider's iframe API for end-detection and
   playhead reporting; remote rendering is gated by the **Online media** setting.
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
- The single `_FullscreenPresenterState` is split for navigability into
  `widgets/presentation/parts/presenter_*.dart` (questions, table, ink, playback,
  displays, navigation, keys, notes, overlays). Each is a `part of` the main file
  and adds one `extension _PresenterX on _FullscreenPresenterState`, so the state
  and all imports stay in the main library. Two rules for this pattern: extensions
  can't call the protected `setState`, so they go through the main class's
  `_rebuild(fn)` wrapper; and `static` members used by a part must live at
  top-level (e.g. `_questionTickMs`, `_digits`), since extensions don't see class
  statics. The main file keeps the fields, lifecycle (`initState`/`dispose`/
  `build`), `_slideCanvas`, and the shared getters.
- Neighbour slide images are **precached** and `gaplessPlayback` is on, so slide
  changes never flash black (important for screen recording).
- **Rehearsal timing** lives in `services/rehearsal_controller.dart` — a plain,
  unit-testable controller (injectable clock) that the presenter feeds via a
  cheap, idempotent `observe(id, index)` on every build, so it captures every
  navigation path. It measures only: elapsed, remaining against a target, and
  per-slide time — no pacing logic. State is **session-only** (no prefs, no `.md`);
  `_exit` shows a summary (`rehearsal_summary.dart`) and discards it. The default
  target lives in `Deck.presentationTargetSeconds` (front matter: `ocideck_target_seconds`).

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
- **User notes** — `<name>.user-notes.json` (`services/user_notes_codec.dart`).
  In the visual editor, slides with user notes are marked on thumbnails in the
  slide list (`widgets/slides/slide_thumbnail.dart`).
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

## Information-security module (optional, off by default)

The MIAUW pentest-reporting module (design: `docs/design/PENTEST_MIAUW.md`) is
gated behind `state/sec_module_provider.dart`: `secModuleRevealProvider` stays
false until the user enables it in Settings, so its UI (a dedicated slide-picker
tab, command-palette actions, the report template) is hidden otherwise. It rides
the existing rails rather than adding a parallel stack:

- **Slide types** — `finding`, `findingsSummary`, `checklist`, `scopeMatrix` and
  `signOff` are ordinary entries in the `slideTypeMeta` registry
  (`models/slide.dart`); each carries a `_class` token and round-trips its
  structured data as `<!-- ocideck_* -->` comments like every other type. A
  **finding** is authored as a *group*: a header slide plus detail / evidence
  slides sharing one `ocideck_finding_id` and a `FindingRole`.
- **Domain services** (pure, network-free) — the native **CVSS 4.0** engine
  (`services/cvss/`), the offline **CWE** and **MIAUW EIS** catalogs, the finding
  numbering / evidence hashing / scope-coverage / management-summary /
  compliance-analyzer derivations, and the audit-dossier index builder
  (`services/audit_dossier.dart`).
- **Document integrity** — `services/document_integrity.dart` seals a finalised
  deck with a SHA-512 hash over the canonicalised content (front matter
  `ocideck_finalized` / `ocideck_seal_*`), re-verified on open. An optional **RFC
  3161** timestamp (`services/rfc3161_timestamp.dart`, with a hand-rolled ASN.1
  DER codec in `utils/asn1_der.dart` — no new dependency) anchors that hash in
  time; OciDeck only produces and verifies, never contacts a TSA itself.
- **Audit dossier** — `parts/file_service_dossier.dart` reuses the AES-256
  package builder to bundle the sealed report, its evidence and the hash tables
  into one encrypted `.ocideck` archive plus an `AUDIT_DOSSIER.md` index.
- **Optional AI** — a shared, off-by-default backend (`services/ai_*`) drafts
  finding text and image alt-text behind the outbound-privacy consent; drafts are
  marked `ocideck_ai_assisted` and block sealing until a human reviews them.

## Localization

Dutch is the source language: UI code calls `d('Nederlandse brontekst')` (literal
source) or `t('key')` (keyed). `l10n/app_localizations.dart` keeps only the
`AppLocalizations` class and delegate, and **assembles** the three lookup maps
(`_strings`, `_dutchSourceStrings`, `_dutchSourceStringAdditions`) from one file
per language. The translation data lives in `l10n/translations/<lang>.dart` (31
languages), each a `part of '../app_localizations.dart'` that declares
`_strings<Lang>`, `_dutchSource<Lang>`, and (for the languages that need later
additions) `_dutchSourceAdd<Lang>` (Dutch only needs `_stringsNl`, being the
source). For a Dutch source string `d()` reads the additions map before the
primary map, so a key must never live in both (guarded by
`test/l10n_duplicate_keys_test.dart`); every `d()`/`t()` string is required in all
languages by `test/app_localizations_test.dart`.

**Homographs — use `t()`, not `d()`.** Because `d('bron')` keys on the Dutch
text, a word that spells the same but means different things in different
contexts collapses to one translation. Reach for a keyed `t('...')` string in
that case, so each meaning gets its own value. Concrete example: the cockpit
artificial-horizon roll angle `d('Bank')` (translated as aviation *Roulis /
Rollen / Alabeo*) and the financial bank on the About page (`t('bankLabel')` →
*Banque / Banco / …*) — one Dutch word, two meanings, two keys. This is the one
class the shadowing guard cannot catch, because it is a semantic collision, not a
data duplicate.

- **Translate or add a string:** edit the relevant language file(s). A test
  (`test/app_localizations_test.dart`) fails unless every literal `d('…')` has a
  translation in *every* language.
- **Add a language:** create `translations/<lang>.dart`, add its `part` directive
  and its entry in each of the three assembly maps in `app_localizations.dart`,
  and register it in `supportedLocales` and `languageNames`.
