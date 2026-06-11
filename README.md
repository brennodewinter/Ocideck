# OciDeck

A desktop application for building [Marp](https://marp.app/) presentations through a structured, slide-by-slide editor — no raw Markdown wrangling required. Compose decks from typed slide templates (title, bullets, quotes, tables, images, video, audio, source code, charts), preview them live, present them fullscreen — even across two screens — and export to Marp Markdown, PDF, PPTX, and self-contained HTML.

Built with Flutter for macOS, Windows, and Linux.

> **What's in a name?** *OciDeck* is a small wink: **Oci** is borrowed from the *Ocicats* — the cats of [Brenno de Winter](https://nl.wikipedia.org/wiki/Brenno_de_Winter) — and **Deck** is short for a presentation deck. So: the cats' presentation tool.

## Features

- **Structured slide editors** — dedicated editors per slide type: title, bullets, two-column bullets, bullets + image, single/two images, quote, table, section divider, image-only, video, audio, source code, charts, and free-form Markdown.
- **Source-code slides** — a "code sheet" with per-language syntax highlighting, stored as a fenced code block. Background, text colour and monospace font come from the style profile, with an optional syntax-colouring toggle (turn it off for a single-colour, CRT-terminal look). The code auto-sizes to fill the panel.
- **Charts** — bar, line, pie, and spider/radar charts rendered natively (preview, presenter, PDF, PPTX) and as self-contained SVG in the HTML export. Data is entered in an in-app grid or imported from CSV; the spec is stored as JSON in the Markdown, with optional linking to a CSV kept in a tidy `data/` directory. Optional min/max draw reference lines (bar/line) or fix the scale (radar); legend hover highlights a series, and line tooltips pick the dot under the cursor.
- **Live preview** — see each slide rendered as you edit, with inline Markdown, footers, and TLP (Traffic Light Protocol) marking. Free-Markdown slides render fenced code with syntax highlighting and `$…$` / `$$…$$` LaTeX math.
- **Traffic Light Protocol** — a deck-wide classification plus an optional **per-slide TLP level**; slides classified stricter than the level the deck is shown at are automatically withheld, both when presenting and exporting. An optional **export release ceiling** can block exporting any deck classified above a chosen level — enforced for every format, off by default.
- **Fullscreen presenter** — keyboard-driven navigation, presenter view, blank screen, auto-advance, and a slide-grid overview.
- **Dual-screen presenter** — when a second display is connected, the beamer shows the slide while the laptop shows the presenter view (current/next slide, notes, timer), kept in sync.
- **Annotation layer** — draw on slides while presenting (pen, highlighter, eraser, laser pointer). Kept as a separate layer that never touches the Marp Markdown, mirrored live to the beamer, and saved in a `.ink.json` sidecar.
- **Media handling** — drag-and-drop images, an image carousel picker, captions, and descriptions stored as sidecar metadata. The library can filter images without tags and clean up md5-identical duplicates (merging their tags/captions and repointing every deck — open or on disk — to the kept file).
- **Import / export** — round-trips Marp Markdown, imports existing slides, and exports to PDF, PPTX (with speaker notes), and a self-contained offline HTML deck (code highlighting, math, charts, and mermaid diagrams render in the browser). Decks are saved as a self-contained package with copied assets.
- **Productivity** — find & replace, slide finder, undo/redo, skip-slide state, multi-select with bulk copy-to-another-deck / delete / skip, and tabbed multi-deck editing. Paste a spreadsheet selection (or CSV / a markdown table) into a table cell to fill the whole grid. `Ctrl/Cmd+O` opens, `Ctrl/Cmd+S` saves.
- **Accessibility** — WCAG 2.1-oriented: interface text scaling up to 200%, keyboard-operable panel divider and dialogs, screen-reader labels for slides and charts (charts read out their data), and slide-change announcements while presenting.
- **Crash recovery** — automatic snapshots so work survives an unexpected exit.
- **Theming** — customizable deck style profiles (deck and source-code colours via presets or custom hex, fonts, logo, footer) and app appearance (including a dark interface), a bundled Marp CSS theme (`assets/themes/ocideck.css`), and a bundled EB Garamond font (no network fetch).
- **Localized** — Dutch, English, Italian, German, French, Spanish, Frisian, and Papiamento.

## Requirements

- Flutter SDK `^3.12.0` (Dart 3.12+)
- A desktop target enabled: macOS, Windows, or Linux

## Getting started

```sh
make setup      # flutter pub get
flutter run -d macos   # or -d windows / -d linux
```

## Development

The `Makefile` is the entry point for all quality checks. Run `make help` for the full list.

```sh
make check        # format check + static analysis + full test suite (the quality gate)
make check-full   # check + dependency freshness report
make format       # auto-format all Dart code
make analyze      # flutter analyze only
make test         # full test suite only
```

Targeted test groups speed up focused work:

| Target | Covers |
| --- | --- |
| `make test-contracts` | Markdown generation/parsing, save-load round-trips, field migration |
| `make test-preview`   | Slide rendering, footers, TLP, inline Markdown, text styles |
| `make test-export`    | PDF/PPTX export and project file-save behavior |
| `make test-state`     | Providers, undo/redo, search/replace, settings, recovery |
| `make test-services`  | Image, caption, and description sidecar services |
| `make test-presenter` | Fullscreen presenter navigation and keyboard shortcuts |

Run `make check` before pushing — it is the same quality gate (format check,
static analysis, full test suite) you would wire into CI.

## Project layout

```
lib/
  models/     # Deck, Slide, Settings data models
  services/   # Markdown, export, file, image, caption, recovery, rasterizer
  state/      # Riverpod providers (deck, editor, settings, tabs, clipboard)
  widgets/    # UI: app shell, panels, dialogs, per-type editors, presenter
  l10n/       # AppLocalizations (8 languages)
  theme/      # App theming
  utils/      # Small shared helpers (clipboard table parsing, URL launching)
```

State is managed with [Riverpod](https://riverpod.dev/).

## File format

Presentations are saved as standard, Marp-compatible Markdown (`.md`) with a
defined project folder layout and an optional portable `.ocideck` package.
Anything that isn't plain Marp is kept in side files so the `.md` stays pure and
portable: image captions, the annotation layer (`.ink.json`), and linked chart
data (`data/*.csv`). The full specification — front matter, per-slide markup,
style profile, sidecars, and the package format — is documented in
[`docs/FILE_FORMAT.md`](docs/FILE_FORMAT.md).

## Documentation

| Document | What it covers |
| --- | --- |
| [User Guide](docs/USER_GUIDE.md) | Using the app: slide types, charts, presenting, exporting, theming |
| [Keyboard shortcuts](docs/SHORTCUTS.md) | Editor and presenter shortcuts |
| [File format](docs/FILE_FORMAT.md) | The Marp Markdown, front matter, sidecars, and `.ocideck` package |
| [Architecture](docs/ARCHITECTURE.md) | How the code fits together (for contributors) |
| [Build & release](docs/BUILD.md) | Building from source and producing distributables |
| [Contributing](CONTRIBUTING.md) | Setup, the quality gate, and how to propose changes |
| [Security policy](SECURITY.md) | How to report a vulnerability |
| [Changelog](CHANGELOG.md) | Notable changes per version |
| [Third-party notices](THIRD_PARTY_NOTICES.md) | Bundled components and their licences |
| [Licence compliance](docs/LICENSE_COMPLIANCE.md) | Open-source policy and the `make licenses` check |

## Contributing

Contributions are welcome! Please read [`CONTRIBUTING.md`](CONTRIBUTING.md) and our
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). In short: `make check` must pass, new
UI strings must be translated in all languages, and file-format changes must be
reflected in `docs/FILE_FORMAT.md`. For security issues, see
[`SECURITY.md`](SECURITY.md).

## License

Copyright © Brenno de Winter.

OciDeck is licensed under the **European Union Public Licence v. 1.2 (EUPL-1.2)**.
You may use, study, share, and modify the software under the terms of that
licence. The full text is in [`LICENSE.md`](LICENSE.md); the official versions in
all EU languages are available from the
[EUPL collection](https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12).

SPDX-License-Identifier: `EUPL-1.2`
