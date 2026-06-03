# OciDeck

A desktop application for building [Marp](https://marp.app/) presentations through a structured, slide-by-slide editor — no raw Markdown wrangling required. Compose decks from typed slide templates (title, bullets, quotes, tables, images, video, audio), preview them live, present them fullscreen, and export to Marp Markdown, PDF, and PPTX.

Built with Flutter for macOS, Windows, and Linux.

## Features

- **Structured slide editors** — dedicated editors per slide type: title, bullets, two-column bullets, bullets + image, single/two images, quote, table, section divider, image-only, video, audio, and free-form Markdown.
- **Live preview** — see each slide rendered as you edit, with inline Markdown, footers, and TLP (Traffic Light Protocol) marking.
- **Fullscreen presenter** — keyboard-driven navigation, presenter view, and a slide-grid overview.
- **Media handling** — drag-and-drop images, an image carousel picker, captions, and descriptions stored as sidecar metadata.
- **Import / export** — round-trips Marp Markdown, imports existing slides, and exports to PDF and PPTX. Decks are saved as a self-contained package with copied assets.
- **Productivity** — find & replace, slide finder, undo/redo, skip-slide state, and tabbed multi-deck editing.
- **Crash recovery** — automatic snapshots so work survives an unexpected exit.
- **Theming** — a bundled Marp CSS theme (`assets/themes/ocideck.css`) and Google Fonts.

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
  theme/      # App theming
```

State is managed with [Riverpod](https://riverpod.dev/).

## File format

Presentations are saved as standard, Marp-compatible Markdown (`.md`) with a
defined project folder layout and an optional portable `.ocideck` package. The
full specification — front matter, per-slide markup, style profile, captions,
and the package format — is documented in
[`docs/FILE_FORMAT.md`](docs/FILE_FORMAT.md).

## License

All rights reserved. _(Update this section if you intend to open-source the project.)_
