# Changelog

All notable changes to OciDeck are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project aims to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Question slides (interactive quiz)** — a new `question` slide type that turns a
  presentation into a short quiz. Three kinds, chosen in the editor: **multiple
  choice** (one correct answer shown with a random pick of wrong ones), **true /
  false** (the prompt is a statement; the editor sets whether it is true), and
  **multiple correct answers** (tick all correct, then **Confirm**). The answer
  pool is unlimited; a configurable number of options (default 4) is drawn at
  random each run. Options: an optional **answer-time** countdown (running out =
  wrong), an **on-wrong** policy (*try again* — blocks advancing until correct, a
  click draws a fresh set — or *allow continuing* — reveal, lock, move on), and an
  optional **image** with a pan-and-zoom detail popup. Presenting **blocks
  advancing** until the question is answered correctly (or answered and locked);
  correct turns green, wrong turns red and highlights the right answer. On a
  two-screen setup the audience window is interactive and stays in sync. The quiz
  spec round-trips in a fenced ` ```question ` JSON block; the live answer state is
  session-only and a static export shows the question without interactivity.
- **User notes (recipient / course)** — personal notes per slide, fully separate
  from speaker notes (`Slide.notes`). Stored in a `<name>.user-notes.json`
  sidecar (fingerprint-anchored like annotations). Hidden by default while
  presenting; `Ctrl/Cmd + N` toggles a local **My notes** panel on the presenter
  window only. Visual editor: collapsible **User notes** block below **Speaker
  notes** (matching amber/blue headers, each with a discard button). Slides
  that carry user notes show a blue badge on their thumbnail in the slide list.
- **Find & replace in Markdown mode** — an in-editor find bar searches the live
  markdown buffer (`Ctrl/Cmd+F`; replace row via `Ctrl/Cmd+H`), with next/previous
  navigation, match counter, case sensitivity, and replace current / replace all.
  Visual mode keeps the existing find & replace dialog over slide fields.
- **Presentation timer / rehearsal mode** — the presenter view now doubles as a
  rehearsal clock that measures without coaching. A **countdown** runs against a
  target time (default under *Settings → General → Presentation*, or set live with
  `K` as `MMSS`; `0` turns it off) and turns red when you go over. The clock bar
  also shows the time spent on the **current slide**, accumulated per slide across
  the run. `R` resets the run (elapsed and per-slide timings, keeping the target).
  Leaving the presenter after a run shows a **summary** (total vs. target, time per
  slide) with copy-to-clipboard. Session-only: nothing is persisted to disk or the
  `.md` file.
- **Duplicate clean-up in the image library** — a footer button finds
  byte-identical images by md5 checksum, keeps one file per group (preferring
  the one used in slides, then the oldest), merges the tags/descriptions and
  captions of the copies onto it, repoints slides that used a copy — in open
  decks and in `.md` presentations on disk that are not currently open — and
  deletes the copies after confirmation.
- **Untagged-images filter in the image library** — a toggle next to the search
  box shows only images without a description/tags, making it easy to see which
  ones still need attention.
- **Delete warning covers decks on disk** — deleting an image from the library
  now also warns when presentations that are not currently open still
  reference it.
- **Source-code slides** — a "code sheet" with per-language syntax highlighting,
  stored as a fenced code block. Background, text colour and monospace font are
  part of the style profile, with a syntax-colouring toggle; turning it off renders
  the block in a single colour (e.g. green on black for a CRT-terminal look). The
  code is sized to fill the panel — larger when there's room, smaller for long
  fragments.
- **Charts** — bar, line, pie, and **spider/radar** chart slides. Data is entered
  in an in-app grid or imported from CSV; the spec is stored as JSON in a ```chart
  block. Data can stay inline or be linked to a CSV in a separate `data/`
  directory. Rendered natively in-app (preview, presenter, PDF, PPTX) and as
  self-contained SVG in the HTML export.
  - Optional **min/max**: horizontal reference lines on bar/line charts, or a
    fixed scale on spider/radar charts shown as a small legend beside the figure.
  - **Legend hover** highlights the matching series (or pie slice). Line-chart
    tooltips attach to the dot under the cursor (showing every overlapping dot),
    and spider/radar points show a tooltip on hover too.
- **Custom theme colours** — every style-profile colour can be entered as a custom
  hex value in addition to the presets.
- **Per-slide TLP classification** — each slide can carry its own Traffic Light
  Protocol level; slides classified stricter than the level the deck is shown at
  are withheld when presenting and exporting.
- **Export release ceiling** — an optional maximum TLP level that may be
  exported. When set, a deck classified *above* it cannot be exported in any
  format; the gate is enforced at the single export chokepoint and fails closed
  (no file is written when blocked, and the export dialog explains why).
  Classifying a deck stays optional — the ceiling only stops decks that exceed
  it, and it is off by default.
- **Classification enforcement** — extends the export gate with an optional
  **required minimum TLP**, a **classification required** flag (reject decks
  with no TLP level), and a **classification watermark** on every slide
  (diagonal `TLP · organisation`, WYSIWYG in preview and raster exports).
  Settings live under *Settings → General → Accessibility → Classification
  enforcement*. The title-bar TLP chip highlights in orange when export is
  blocked because the deck is unclassified.
- **Export metadata** — PDF, PPTX, and HTML exports embed title, author,
  description, keywords, and TLP (Subject prefix, Keywords, HTML `<meta
  name="classification">` / `<meta name="tlp">`, plus a fixed HTML banner).
- **Dual-screen presenter** — on a second display the beamer shows the slide
  while the laptop shows the presenter view (current/next slide, notes, timer),
  kept in sync over method channels.
- **Annotation layer** — draw on slides while presenting (pen, highlighter,
  eraser, laser pointer). Kept fully separate from the Marp Markdown, mirrored
  live to the beamer, and persisted in a `<name>.ink.json` sidecar.
- **App theming** — customizable app appearance profiles, including a dark
  interface.
- **Paste a table into a table cell** — pasting a spreadsheet selection (Excel,
  Numbers, LibreOffice Calc, Google Sheets), CSV (comma or semicolon), or a
  markdown table into any cell of the table editor fills the whole grid from
  that cell, growing rows and columns as needed. Works with `Ctrl/Cmd+V` and
  `Shift+Insert` on macOS, Windows, and Linux; plain text still pastes into the
  single cell.
- **Slide-type chooser previews** — the add-slide dialog shows a miniature
  wireframe of each layout (in the spirit of other presentation tools) instead
  of an abstract icon, and is fully keyboard-operable (`Tab`/`Enter`/`Esc`).
- **Accessibility (WCAG 2.1)**:
  - An **interface text size** setting (100–200%, Settings → General →
    Accessibility) that scales all editor text; slides themselves keep their
    fixed design size.
  - The panel divider is focusable and **keyboard-resizable** (arrow keys), with
    a visible focus state, and presents itself to screen readers as a slider.
  - **Screen-reader support**: slide thumbnails announce one concise label
    ("Slide 3/12: title") instead of their full content; charts expose their
    type, title, and underlying values as a text alternative; the presenter
    announces each slide change.
  - Improved contrast for hint/label text in the editors.
- **Slide quality** — continuous accessibility and readability checks while you
  edit. A bar below the preview summarises open issues (tips, warnings, errors);
  expand it or open **View issues…** for the full list. Filter by severity, click
  an issue to jump to the relevant slide field or open *Settings → Colours* with
  the matching theme colour highlighted. Checks cover style-profile contrast
  (body, title, table, code, accent, checklist, footer), alt text and media
  descriptions, missing image/video files on disk, and text density (bullets,
  tables, code, markdown, title, quote). Thumbnail badges and inline editor hints
  mark affected slides and fields. Export respects *Warn on export* and optional
  *Block export on serious quality issues* under *Settings → General →
  Accessibility*.
- Project documentation: contributing guide, security policy, architecture and
  build notes, user guide, keyboard-shortcut reference, third-party notices, and
  the EUPL-1.2 licence text.

### Changed
- **Bullet slides** can now carry an optional **subheading** under the title; the
  **two bullet columns** type can have an optional **heading above each column**,
  separate from the slide title.
- Slide text auto-sizing now measures with the deck's own font, so text grows to
  use the available space more accurately instead of staying smaller than needed.
- The two bullet columns are measured **independently** and then rendered at a
  **shared size** set by the busiest column, so the two columns always look
  typographically related. Dense two-column slides spend less height on the
  title, headings, and gaps so the list items themselves render larger.
- Slide transitions in the presenter no longer flash a black frame (neighbour
  images are precached and `gaplessPlayback` is enabled) — important for
  recording.
- **Spider/radar charts** now use the available space: axis labels are measured
  and placed snugly around the polygon (up to three lines, full remaining
  width), so the diagram renders considerably larger and long labels stay
  readable instead of being truncated.
- Bullet auto-fit now stops growing at ≈32 pt (on a 16:9 deck) — the upper end
  of the 24–32 pt range presentation-design guidance recommends for body text —
  so slides with few bullets no longer render body text that competes with the
  title.
- After resizing the slide panel (dragging the divider or resizing the window),
  the list scrolls the slide being edited back into view.
- **Speaker notes** in the visual editor now use the same collapsible header
  pattern as user notes, with a discard button in the header row.

### Fixed
- Hover on charts (tooltips, legend highlight) now works on a second screen:
  macOS only delivered mouse-moved events to the key window, so the borderless
  beamer window never saw them; the stuck hover state after the pointer left a
  window is gone for the same reason.
- Bar-chart x-axis labels could run through each other: the spacing maths now
  matches how bar groups are actually laid out, and the final label shrinks to
  the real gap when it sits closer than a full step.
- A crash in the slide list ("A _RenderLayoutBuilder was mutated…") when its
  keyed items were rebuilt during layout — both the resize-detection inside the
  panel and the shell's width computation now avoid LayoutBuilders above the
  reorderable list.
- A scheduler crash when jumping away from a slide before a quality-focus callback
  ran on a caption or editor field (`ref` used after the widget unmounted).
- **Saving can no longer corrupt a deck.** Decks, sidecars, theme CSS, copied
  chart data, exported packages and URL-imported files are now written
  atomically (to a temp file, then renamed into place), so a crash, full disk or
  process kill mid-write leaves the original file intact instead of half-written.
- **Save failures are no longer silent.** A failed write (read-only volume, full
  disk, permission denied) now shows an error and keeps the deck marked as
  unsaved, instead of being swallowed and reported as success. `Save` reliably
  reports failure so closing a tab/window no longer crashes or loses work, and a
  *Save As* whose file cannot be re-read afterwards surfaces a warning rather
  than silently treating the deck as saved.
- **Windows (CRLF) markdown files now open correctly** — line endings are
  normalised before parsing, so frontmatter and slide separators are no longer
  missed and the whole deck no longer collapses into a single slide.
- A truncated or corrupt `.md`, or a file with non-UTF-8 bytes, now reports
  "could not open" instead of silently opening as an empty presentation that
  could be overwritten.
- Rapid double `Cmd/Ctrl+S` can no longer start two overlapping writes to the
  same file.

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
