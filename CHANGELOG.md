# Changelog

All notable changes to OciDeck are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project aims to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Dark mode for the editor** — selecting the dark app-appearance profile
  (*Settings → Appearance*) now also darkens the editor chrome, not just the
  Material widgets. Every semantic `AppTheme` colour token resolves per mode
  (`AppTheme.isDark`, tied to the profile), so surfaces, text, borders and status
  tints flip together. Slide content stays a fixed white canvas (a slide is a
  design surface), and brand/accent colours are unchanged across modes.
- **Advisory supply-chain scan (`make trivy`)** — an optional [Trivy](https://trivy.dev)
  scan that checks the resolved Dart packages (`pubspec.lock`) for known CVEs —
  previously only licence-checked, not vulnerability-scanned — and sweeps the
  repo for committed secrets. Scanners and scope live in `trivy.yaml`. It is
  advisory: not part of `make check`/`check-full` (it needs the external `trivy`
  binary and Dart/pub advisory data is still sparse), and the matching CI job
  runs with `exit-code: 0` so it reports without blocking merges. Documented in
  `docs/CHECKS.md`. The CI job pins `trivy-action` to `v0.36.0`, and `make trivy`
  bypasses a stale docker credential helper via an empty `DOCKER_CONFIG` so the
  (auth-free) vuln-DB download can't be blocked by it.
- **Pinned-Action freshness monitor (`make check-actions`)** — an advisory check
  that reads `.github/pinned-actions.json` and asks each exact-pinned third-party
  CI Action's release API whether a newer version exists, so a stale pin stands
  out (the Action analogue of `make deps-check`). Floating `@vN` Actions
  auto-update and are not tracked. Documented in `docs/CHECKS.md`.
- **Contextual help in the editor** — a subtle "What can I do here?" button at
  the top of the slide editor expands a short, slide-type-specific hint (e.g.
  chart: CSV import; video: trimming/cut-at-playhead; table: paste from a
  spreadsheet). An info tooltip next to the per-slide TLP control explains that
  slides above the deck's level are left out when presenting and exporting. Every
  slide type has a hint (enforced by an exhaustive switch); all hints are
  translated in the 30 non-Dutch languages.
- **Command palette (Ctrl/Cmd+K)** — a searchable overlay listing the common
  actions (present, export, save, new chart, find & replace, image library,
  toggle markdown/visual mode, full-deck preview, new tab, open, package/URL
  import, settings, and setting each TLP level). Type to filter (accent- and
  case-insensitive), arrow keys to move, Enter to run, Esc to close; disabled
  actions (e.g. export before saving) stay visible but greyed. Also reachable
  from the "⋮" menu. Labels reuse the existing menu/tooltip strings; the few new
  strings are translated in all 30 non-Dutch languages.
- **Software Bill of Materials (SBOM)** — a complete, machine-readable inventory
  of every shipped component (Dart/Flutter packages direct + transitive, the
  vendored JS/CSS export bundles, the plugin forks in `third_party/`, the bundled
  fonts, and the build SDKs) in **both** common machine-readable formats —
  CycloneDX 1.6 (`sbom/ocideck.cdx.json`) and SPDX 2.3 (`sbom/ocideck.spdx.json`)
  — plus a human-readable Markdown view (`sbom/ocideck.sbom.md`). Generated
  from the existing sources of truth by `dart run tool/generate_sbom.dart`
  (`make sbom`); each component carries its version, SHA-256, purl and licence
  (classified by the same logic as `make licenses`). A `make sbom-verify`
  staleness gate — wired into CI, `make check-full`, and the test suite — fails
  the build if dependencies change without the SBOM being regenerated. The SBOM
  ships in the web build (`build/web/sbom/`) and as a release artifact, and is
  the artefact required by the **EU Cyber Resilience Act** (Reg. (EU) 2024/2847,
  Annex I Part II §1). See [`docs/SBOM.md`](docs/SBOM.md).
- **Ordering questions** — a fourth question kind next to multiple choice,
  true/false and multiple-correct: the answers as entered in the editor are the
  correct order (rearranged with up/down arrows). Presenting draws a random
  subset, keeps its relative order as the right answer and shows it shuffled
  (never accidentally already correct); the viewer taps the options into order
  and confirms. A wrong answer reveals the options **in the correct order**,
  marking each misplaced one in red with an explicit *Your order: n* line —
  correctly placed ones turn green. Timer, on-wrong policy (retry with a fresh
  draw, or lock-and-continue) and the interactive audience window work exactly
  as for the other kinds. Round-trips in the ```` ```question ```` JSON block
  as `"kind": "ordering"`; translated in all 30 non-Dutch languages.
- **Nextcloud (WebDAV) as a file source** — browse a folder on your Nextcloud
  and open `.ocideck` packages or Marp `.md` decks straight from it, and save a
  deck back, either as a single `.ocideck` package or as a flat `.md` plus its
  asset folders. Configure the server under *Settings → Nextcloud* (server URL,
  username, app password, optional subfolder) with a **Test connection** button.
  The **app password is stored encrypted in the OS keychain**, never in the
  preferences file. A self-hosted server on a private/LAN address is only
  reachable after ticking **Trusted internal server**; deck-supplied URLs stay
  blocked by the SSRF guard. Downloads pass through the same safety gate and
  size/zip limits as every other import. Entry points: the welcome screen, the
  `…` menu (*Open from Nextcloud* / *Save to Nextcloud*).
- **OciDeck logo on startup** — the welcome screen and the first-run consent
  dialog now show the OciDeck cat logo.
- **One-command builds for every target** — `make build-web` (hardened),
  `make build-macos` / `build-windows` / `build-linux`, and `make build-all`
  (web plus the host's native desktop target). A release CI workflow
  (`.github/workflows/release.yml`) builds web, macOS, Windows and Linux on a
  version tag and uploads each as an artifact. See [`docs/CHECKS.md`](docs/CHECKS.md).
- **Edit a table while presenting** — tables can be changed live during a
  presentation (filling in figures, ticking items in front of an audience).
  It is opt-in per table: a new **Table editable while presenting** checkbox in
  *Per-slide options* (off by default, so tables stay read-only otherwise),
  round-tripping in the `.md` as a `table-editable` `_class` token. On an
  editable table a subtle pencil icon (top-right) toggles editing — dimmed when
  off, highlighted when on — alongside the **E** key. While editing, the arrow
  keys move the text cursor inside the cell, **Tab** / **⇧Tab** switch cells
  (a new row is added past the last cell), and `Esc` leaves editing; changes
  mirror to the beamer in dual-screen mode.
- **Online media by URL** — image and video slides accept an `http(s)` URL as
  the source, rendered live (no local copy). Off by default: the new
  **Online media** security setting must be enabled before any remote source is
  fetched; until then the slide shows a placeholder with the URL. On export, a
  remote source also emits a clickable literal URL.
- **YouTube/Vimeo embeds** — a video slide can embed a YouTube or Vimeo link,
  played by the official iframe player (designed to extend to more providers).
- **Watch a video in parts ("cut")** — a video can be split at a playback point:
  the first part stays on this slide and the remainder moves to a new slide with
  the same source, which can be cut again. Works for local, online and embedded
  video. The trim window round-trips in the `.md` (a `#t=START,END` media
  fragment on `<video>`, or `data-start`/`data-end` on the embed iframe).
- **Redesigned settings dialog** — the settings window moves from a flat tab bar
  to a sidebar navigation (sections on the left, a titled content area on the
  right, a footer action bar), without changing any of the settings themselves.
- **"Over OciDeck" screen** — a new About section in Settings, opened from the
  OciDeck logo at the bottom of the settings sidebar. It explains where the name
  comes from (the *Ocicat* breed of the author's cats plus a slide *deck*),
  introduces publisher **Stichting LibreKAT** with its mission, contact details
  and a link to librekat.nl, and shows the three mascot cats (Branie, Keiko,
  Otis) with photos. Translated in all 30 non-Dutch languages.
- **Title background can fill the whole slide** — a "fill slide" toggle on title
  slides shows the background image edge-to-edge (cover, cropping the overflow)
  instead of being limited to the zoom slider. Toggling it back off restores the
  zoom you had set.
- **Low-contrast title text is detected and auto-fixed** — when a title slide's
  text has too little contrast against its background image, the slide-quality
  panel flags it (with the measured ratio) and offers a one-click **Herstel**
  that picks the smallest effective change: enable the grey wash, or switch the
  title text light/dark for that one slide (a new per-slide title text colour
  that round-trips in the `.md`). The check also feeds the export gate.
- **Timeline slides** — a new `timeline` slide type that turns a list of dated
  events into an animated, eye-candy timeline. Each event is a plain Markdown
  list item using `marker :: title :: description` (marker and description
  optional), so the `.md` stays a readable, Marp-compatible list — no JSON block.
  The renderer draws a glowing accent spine with nodes and cards that alternate
  above/below (horizontal rail) or left/right (vertical spine), styled from the
  active profile (accent, fonts, background). When a horizontal rail gets
  crowded the cards stack onto multiple *floors* (heights) so they tile instead
  of colliding. On enter, the line draws itself first and the events are then
  placed onto it one after another. **Layout** is *auto* (horizontal
  for short timelines, vertical for longer ones) or forced horizontal/vertical;
  **animation** is *draw-in on open*, *step-by-step* (each click reveals the next
  event, kept in sync on the audience window) or *none*. Layout and animation
  round-trip as `_class` tokens (`timeline-horizontal` / `timeline-vertical` /
  `timeline-steps` / `timeline-static`); the events live in the list itself. The
  draw-in **animation speed** is adjustable per slide via a slider (≈0.4–6 s) and
  round-trips in an `ocideck_timeline_duration` comment.
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
- **Calmer slide editor.** The editor header now packs everything onto one
  strip: the type and style pickers, a "What can I do here?" hint, a compact
  **Quality** chip (the word coloured by status; the counts move to its tooltip
  and its expanded panel) and a gear button for **Slide settings**. Each of the
  three toggles expands its content just below the strip. The secondary
  per-slide controls (audio, logo, footer, table option, timing, TLP) live
  behind the gear (collapsed by default); a set per-slide TLP still shows as a
  small badge next to the gear so the classification stays visible. Speaker and
  user notes keep their own collapsible fields.
- **Settings: "Privacy" is now "Licentie en Privacy", with a separate
  "Beveiliging" (Security) tab.** The renamed tab keeps the licence/privacy
  statement and the consent controls. The **Online media** toggle and the
  crash-recovery-files control move to the new *Beveiliging* tab, since they are
  security choices rather than privacy ones. The tab title and the new tab are
  translated in all 30 non-Dutch languages.
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
- **Maintainability: the two largest source files were split up.** The
  localization data now lives one file per language under `lib/l10n/translations/`
  (`app_localizations.dart` shrank from ~7,600 to ~160 lines and only assembles
  the lookup maps), and `fullscreen_presenter.dart` (~3,500 → ~1,270 lines) was
  split into themed `part` files under `widgets/presentation/parts/`. No
  behavioural change; see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

### Fixed
- **Code-colour contrast is judged against the large-text threshold.** The
  theme quality check treated the code text/background pair as normal body text
  (WCAG AA 4.5:1), so the LibreKAT house-style green on the dark code panel
  (~3.6:1) drew a spurious "too little contrast" warning even though code on a
  slide renders at display size. It is now checked against the large-text
  threshold (3.0:1), consistent with the title and table-header pairs; code that
  is dense enough to render small is still caught separately by the density
  check.
- **Web: a saved deck no longer reads as "not saved yet".** On the web build,
  saving is a browser download, which returns no file path, so the status bar's
  filename slot stayed on "Not saved yet" right next to the green "Saved" chip.
  It now shows the downloaded filename (with a tooltip explaining it went to your
  downloads folder); desktop is unchanged.
- **Consent dialog no longer crashes its action bar.** A `Spacer` in the
  `AlertDialog` actions (which are laid out in an OverflowBar, not a Flex) threw
  a layout error that the release build swallowed into a dark placeholder box
  (and spammed the console on web). The two actions are now split with
  `actionsAlignment` instead.
- The export quality gate now includes the asynchronous title-image contrast
  warnings, so the gate and the on-screen quality panel no longer disagree.
- Turning the title "fill slide" option back off no longer discards the zoom you
  had dialled in.
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
- **Uncaught errors are now caught and logged.** The app runs inside a guarded
  zone with framework- and platform-level error handlers, so an unexpected
  error during a presentation no longer disappears silently or leaves the UI
  wedged; in release a build failure shows a quiet placeholder instead of a red
  error box.
- The Mermaid diagram render cache is now bounded (LRU), so a long session with
  many distinct diagrams can no longer grow memory without limit.
- Crash recovery no longer leaves a stale autosave file after a deck is saved:
  the periodic autosave and the "saved → discard" cleanup are now serialised
  per tab, so the app won't falsely offer to restore already-saved work on the
  next start.
- Importing a package (`.ocideck` zip) is more robust: a corrupt archive entry
  is skipped instead of aborting the whole import, and an entry that declares an
  oversized uncompressed size is rejected before being inflated into memory.
- Audience-window sync failures during a presentation are now logged instead of
  silently swallowed, so a beamer that drifts out of sync leaves a trace.
- **Switching to Markdown mode and back no longer wipes slide drawings.** Ink
  annotations are re-anchored across the toggle (previously they were dropped,
  and a following save deleted their sidecar — permanent loss). Linked chart
  data is also kept across the toggle.
- Front-matter parsing is more forgiving: indented keys and missing spaces after
  the colon (e.g. hand-edited files) are now read correctly instead of being
  silently ignored.
- Rapidly switching between slides with video or audio can no longer leave an
  orphaned media player or double-dispose a controller.
- Undo no longer risks merging edits to different slides into one step (the
  coalescing key is now the stable slide id, not its position).

### Security
- **The web build is now self-contained and CSP-hardened.** CanvasKit and the
  Roboto UI font are bundled locally instead of fetched from Google's CDN, so the
  running app makes **zero third-party requests**, and `web/index.html` ships a
  strict Content-Security-Policy (`script-src 'self' 'wasm-unsafe-eval'`, no
  `unsafe-inline`/`unsafe-eval`). Build with `make build-web`.
- **Deck asset paths are confined to the project folder on every read path.**
  An untrusted `.md` can no longer use absolute or `../` image/logo/chart paths
  to make the slide-quality analyzer probe arbitrary files (a file-existence
  oracle that ran automatically on open), the exporter precache read files
  outside the project, the Save-As chart copy read outside the project, or the
  copy-to-clipboard action exfiltrate an arbitrary file. All of these now use
  the same containment guard as the preview (`resolveSlideAssetPath`).
- A deck `.md` is now size-capped (32 MiB) on open to avoid loading and parsing
  a maliciously oversized file.
- The HTML export now carries a **nonce-based Content-Security-Policy** so an
  injected inline script that survives sanitization still cannot execute when
  the file is opened. Mermaid in the export runs in strict mode and its SVG is
  re-sanitized with DOMPurify; the in-app mermaid webview has its own CSP.
- **Image decoding is dimension-capped** everywhere a deck-supplied image is
  shown, exported, or precached, so a tiny but huge-dimensioned file can no
  longer exhaust memory and crash the app.
- **URL import now resolves the hostname** and refuses it when it maps to an
  internal address, closing the SSRF bypass where a public name points at a
  loopback/private/metadata IP.
- **Copy-to-clipboard follows symlinks** and refuses a project-internal symlink
  that points outside the project, so it can't be used to exfiltrate an
  arbitrary file.
- **Imported images are validated by magic bytes** (not just the file
  extension) and capped at 64 MiB; video/audio imports are capped at 1 GiB.
- **URL import pins the connection** to the validated address, closing the
  DNS-rebinding window where a host re-resolves to an internal IP at connect
  time.
- **Symlink containment now also covers the render/export path** (cached), not
  just copy-to-clipboard, so a project-internal symlink pointing outside the
  project can't be rendered into an export.

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
