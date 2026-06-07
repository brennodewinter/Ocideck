# Changelog

All notable changes to OciDeck are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project aims to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Source-code slides** — a dark "code sheet" with per-language syntax
  highlighting, stored as a fenced code block.
- **Charts** — bar, line, and pie chart slides. Data is entered in an in-app grid
  or imported from CSV; the spec is stored as JSON in a ```chart block. Data can
  stay inline or be linked to a CSV in a separate `data/` directory. Rendered
  natively in-app (preview, presenter, PDF, PPTX) and as self-contained SVG in
  the HTML export.
- **Per-slide TLP classification** — each slide can carry its own Traffic Light
  Protocol level; slides classified stricter than the level the deck is shown at
  are withheld when presenting and exporting.
- **Dual-screen presenter** — on a second display the beamer shows the slide
  while the laptop shows the presenter view (current/next slide, notes, timer),
  kept in sync over method channels.
- **Annotation layer** — draw on slides while presenting (pen, highlighter,
  eraser, laser pointer). Kept fully separate from the Marp Markdown, mirrored
  live to the beamer, and persisted in a `<name>.ink.json` sidecar.
- **App theming** — customizable app appearance profiles, including a dark
  interface.
- Project documentation: contributing guide, security policy, architecture and
  build notes, user guide, keyboard-shortcut reference, third-party notices, and
  the EUPL-1.2 licence text.

### Changed
- Slide transitions in the presenter no longer flash a black frame (neighbour
  images are precached and `gaplessPlayback` is enabled) — important for
  recording.

## [1.0.0]

### Added
- Initial release: structured, slide-by-slide editor for Marp presentations with
  typed slide templates, live preview, fullscreen presenter, deck-wide TLP
  marking, media handling, import, and export to Marp Markdown, PDF, PPTX, and
  self-contained HTML. Decks save as a self-contained project/package with copied
  assets. Localized in Dutch, English, Italian, German, French, Spanish, Frisian,
  and Papiamento.

[Unreleased]: https://example.com/ocideck/compare/v1.0.0...HEAD
[1.0.0]: https://example.com/ocideck/releases/tag/v1.0.0
