# Changelog

All notable changes to OciDeck are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project aims to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Informatieveiligheid slide types (scaffold)** — five new slide types for
  pentest reporting (*Bevinding*, *Bevindingenoverzicht*, *Checklist*,
  *Scope-matrix*, *Ondertekening*) are registered end to end: enum, metadata,
  picker wireframes, editor, preview and Markdown round-trip (each rides its own
  Marp `_class` token — `finding`, `findings-summary`, `checklist`,
  `scope-matrix`, `sign-off`). They belong to the *Informatieveiligheid*
  category and only appear in the add-slide picker once that module is enabled.
  For now each behaves as a free-Markdown body; the structured editors follow per
  type. Localised in all interface languages. See
  [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) §4.
- **Animated GIFs play** — an imported animated GIF (or WebP/APNG) now keeps
  animating in the preview, presentation and audience window instead of freezing
  on its first frame. The decode-size cap that guards against memory-bomb images
  now only downscales pictures that actually exceed the limit, so within-limit
  animations decode at native resolution and play. Exports (PDF/PPTX) still
  capture a single still frame, as before.
- **Crop images to fit** — when a picture is bigger than its slot and part falls
  outside, a **Crop** button (image slide, title background, bullets + image, and
  each image of a two-images slide) opens a live editor. Drag the image to choose
  which part stays in view; for the full-slide image and title background you can
  also zoom in the same dialog. The crop is a non-destructive focal point — the
  original file is untouched and it round-trips in the `.md`
  (`ocideck_image_focus`, see [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) §8). See
  [docs/USER_GUIDE.md](docs/USER_GUIDE.md) → *Images*.
- **Search the documentation** — *Settings → Documentation* now has a search box
  above the document list. Type one or more words and the list narrows to the
  documents whose title or body contains all of them, each shown with a short
  excerpt where the words are highlighted. Clearing the box restores the full
  grouped list. Bodies are searched in the current interface language. See
  [docs/USER_GUIDE.md](docs/USER_GUIDE.md) → *Accessibility*.
- **Play-only lock** — a deck can be marked *play-only* in its file
  (`ocideck_play_only: true` in the front matter, or the **Play only (locked)**
  switch in *Presentation properties*). A play-only deck opens locked: the
  editor, toolbar, menus, shortcuts and export are gone — only the first slide is
  shown with a **Play** button. Starting playback switches the app to full
  screen; the presentation runs exactly as normal. Closing the deck restores the
  normal working of the app. The lock lives in the file, so it travels with the
  deck when shared; to remove it, delete the `ocideck_play_only` key from the
  markdown. See [docs/USER_GUIDE.md](docs/USER_GUIDE.md) → *Play-only decks* and
  [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) §3.
- **Findings are highlighted in the code, not just the gutter.** After
  **Check** in markdown mode, each line with a validation issue now gets a
  coloured band behind the code with a stronger left accent bar — red for
  errors, amber for warnings — so problems stand out where you edit. The bands
  scroll with the text and clear as soon as you start typing (the findings are
  stale then), matching the existing line-number markers.
- **Per-slide markdown view** — markdown mode can now show a single slide's
  markdown instead of the whole presentation. A graphical sliding toggle at the
  top of the markdown editor switches between **Full presentation** and **This
  slide** (with a `n/total` counter); selecting another slide reloads its
  markdown. Both scopes edit and quality-check the same way — **Apply** in the
  per-slide scope parses just that fragment back into the deck (and splits into
  several slides if you add `---` separators), with user notes and annotations
  re-anchored exactly as in whole-deck mode. See
  [docs/USER_GUIDE.md](docs/USER_GUIDE.md) → *Markdown mode*.
- **Optional password encryption for `.ocideck` packages** — when you export a
  package you can now protect it with a password. OciDeck encrypts every file in
  the package with **AES-256** (the WinZip AES standard). The export dialog shows
  an intelligent, entropy-based strength meter (a long passphrase beats a short
  password with symbols — it never forces a mandatory "!") and can generate a
  strong random password (choose **32** or **256** characters) that you can copy
  to share out of band. Opening an encrypted package prompts for the password,
  with a clear message on a wrong one. Encryption is entirely optional; existing
  unencrypted packages keep opening as before. See
  [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) §7.1 for the format and its caveats.
- **Roomier documentation reader with adjustable text size** — the in-app reader
  now uses the full window width, so wide tables get the space they need instead
  of being squeezed into a narrow column (running text still keeps a readable
  line length). A subtle **A−/A+** control in the app bar enlarges or shrinks the
  document text; the choice is remembered and is separate from the app-wide
  interface text size.
- **All project documentation is now readable in-app** — Settings →
  Documentation previously listed only the user guide, shortcuts and file
  format. It now also opens the architecture overview, build instructions,
  quality checks, source-code map, license compliance and the SBOM, plus a
  separate **Design** section for forward-looking specs (starting with the
  real-time collaboration design). Every title is translated in all languages,
  and a new guard test fails the build if a document lands in `docs/` without
  being bundled and shown in the reader, so nothing can silently go missing
  again.
- **`Ctrl/Cmd + W` closes the presentation** — pressing the standard
  window-close shortcut during a presentation now exits it, just like closing a
  window elsewhere. It works from any mode and from both the presenter and the
  beamer window (in dual-screen mode the beamer asks the presenter to close).
- **Fifteen conversation-preparation templates** — the new-presentation wizard
  now helps you prepare for a difficult or important conversation. Work
  conversations: **job interview** (STAR answers), **performance review**,
  **salary negotiation**, **asking for more responsibility** and **raising a
  workplace problem**. Difficult personal conversations: **resolving a
  conflict**, **giving or receiving criticism**, **delivering bad news**,
  **setting boundaries** and **discussing a strained relationship or
  friendship**. Commercial/persuasive conversations: **client conversation**,
  **sales conversation** (SPIN), **supplier negotiation** (BATNA/ZOPA),
  **pitch** and **getting buy-in in a meeting**. The genuinely high-stakes,
  emotional conversations weave in the *Crucial Conversations* method (Patterson,
  Grenny, McMillan & Switzler): start with heart, separate facts from your
  story, make it safe, STATE your path, listen (AMPP) and move to action; the
  commercial and interview templates use a scenario-specific framework instead.
  Each has fill-in preparation and anticipation tables plus a progress checklist
  for agreements, and its title and description are translated in all 30
  non-Dutch languages.
- **Three shift-briefing templates** — the new-presentation wizard now offers a
  **Security briefing** (current events and previous shift, points of attention,
  special notes for the day, building/site maintenance and staffing), an
  **Operational police briefing** (hotspots/hot times/hot crimes, person and
  vehicle wanted notices with threat level, priorities and area assignments,
  officer safety) and an **Enforcement briefing (BOA)** (focus locations and
  nuisance, ongoing actions, powers and legal framework, cooperation with and
  escalation to the police). Each is an enriched briefing with fill-in tables,
  a pre-shift checklist with progress, and a handover/debrief. Titles and
  descriptions are translated in all 30 non-Dutch languages.
- **In-app documentation reader** — a new **Documentation** tab in Settings
  lists the user guide, keyboard shortcuts, the file-format reference and the
  full EUPL 1.2 licence; each opens in a spacious, accessible full-screen reader
  that **renders** the Markdown (headings, lists, tables, code, links) instead
  of showing raw source in a cramped box. Text follows the OS text-size setting,
  is selectable, and links open externally; the reading column is width-bounded
  for legibility. The consent screen's "read the full licence" now opens the
  same reader. Documents load **locale-aware**: a translated variant
  (e.g. `docs/USER_GUIDE.de.md`) is used automatically when bundled, otherwise
  the source-language document. Built on the app's own inline-Markdown renderer —
  no new dependency. The few new UI strings are translated in all 30 non-Dutch
  languages.
- **Dead-code gate (`make check-dead-code`)** — a new quality check, wired into
  `make check` and CI, that walks the `lib/` import graph from the app
  entrypoint and fails on any orphaned `.dart` file reachable via no
  `import`/`export`/`part` (both branches of a conditional import counted). This
  closes the analyzer's blind spot: `flutter analyze --fatal-infos` already
  rejects unreachable code and unused imports/private elements, but a whole
  detached file stayed green. A companion **`make fix`** helper applies
  `dart fix --apply` + reformat for local cleanup. See `docs/CHECKS.md`.
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
- **The markdown checker is more critical and less noisy.** It now warns about
  **unknown front-matter keys** (a typo like `pagenate:`, or a Marp option
  OciDeck does not implement such as `header`/`footer`/`size`/`style`) and about
  **unsupported directive comments** (Marp's per-slide `<!-- _paginate -->`,
  `<!-- _header -->`, `<!-- _color -->`, …), which the parser silently drops — so
  you now get told instead of wondering why they have no effect. At the same
  time, plain prose speaker-note comments no longer trigger a spurious "missing
  `_class`" warning, and HTML shown inside a code block (a `<div>`, an
  `![img](…`, a `<video>`) is no longer mis-flagged as broken markup. Unclosed
  code fences are detected by real open/close tracking rather than a parity
  count, so two unclosed fences can no longer cancel each other out.
- **The documentation list is now grouped into named sections.** Settings →
  Documentation previously showed one long flat list with a single **Design**
  heading at the bottom, so every other document floated without a category. The
  documents are now organised under headings by audience — **User** (user guide,
  shortcuts, file format), **Technical** (architecture, build, quality checks,
  source map), **License and compliance** (license compliance, SBOM, the EUPL
  license) and **Design** — with each heading translated in all languages.
- **Switching between slides in the rail is snappier.** Clicking a slide in the
  side rail used to rebuild and repaint every visible thumbnail just to move the
  selection outline, which could stutter while building a large or content-heavy
  deck. Each thumbnail now tracks its own selection, so only the previously and
  newly selected cards refresh; the mini-previews are also isolated so an
  unrelated card never triggers a re-render of its neighbours.
- **Text-heavy slides lay out faster.** The routine that sizes bullet and
  rich-text bodies to fit their slide used to run a fixed number of measurement
  passes; it now stops as soon as the size has settled to within a fraction of a
  point (visually identical). On dense slides that roughly halves the text-
  measurement work behind every preview and thumbnail.
- **The RASCI / TVB template no longer pre-fills the role assignments.** The
  RASCI matrix, the role overview and the tasks/responsibilities/authority table
  used to ship with example assignments (CISO, management, SOC, IT, …) baked into
  every cell, which presumes an organisation structure the template cannot know.
  Those assignment cells are now empty (`…`) and the three tables are live-
  editable, so you fill in who holds which role for your own organisation; only
  the generic example role and task labels remain as scaffolding.
- **Found slides insert at the cursor, not at the end.** The *Slide zoeken*
  (find slides) picker now inserts each chosen slide right after the current
  slide and selects it, so consecutive picks stay in order at your position —
  matching *Add slide*, *Paste slide*, *Paste image* and *Import slides*, which
  already inserted at the cursor.
- **Move a whole multi-selection at once.** Select several slides (shift- or
  cmd-click, Ctrl/Cmd+A) and drag any one of them: the entire selection moves as
  a single contiguous block, preserving its order, and the selection follows to
  the new position. A non-contiguous selection is gathered into one block at the
  drop point. Dragging a single slide is unchanged.
- **Splitting an over-full bullet slide now divides evenly.** When both halves
  fit within the per-page optimum, "Split slide" halves the bullets (e.g. 10
  bullets become 5/5 instead of 8/2) rather than cramming page 1 and leaving a
  near-empty continuation. Slides too full to fit in two pages still fill page 1
  to the optimum and leave the remainder, which you can split again. Applies to
  single-column, checklist and two-column slides.
- **A split "bullets + image" slide keeps its image on the continuation page.**
  The follow-up page is now itself a *bullets + image* slide that inherits the
  same picture (previously it became a full-width, image-less bullets slide), so
  the two pages look consistent and share one font size. You can still swap the
  continuation to a plain bullets page (or give it a different image) per page via
  the slide **type** picker.
- **Opening the same presentation twice now jumps to its tab** instead of
  loading a second copy. Every open-from-path flow (file picker, recent files,
  drag-and-drop, deep link) checks whether the file is already open — comparing
  normalised absolute paths — and, if so, selects that existing tab rather than
  creating a duplicate. This prevents version confusion where two tabs edit the
  same file independently. In-memory opens on the web (which carry no file path)
  are unaffected.
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
- **Folder pickers that a browser cannot honour are hidden on the web.** In the
  browser there is no file system — decks open from their bytes and every export
  is a download — so choosing a folder has no meaning. Three controls relied on a
  native directory picker that the browser does not implement, so their button
  did nothing when clicked (no error, no dialog): the *presentation folder* and
  *export folder* settings (*Settings → General*), and the **Find slides** /
  **Import slides** buttons in the slide list. All of these are now hidden when
  running on the web.
- **Deleting a slide keeps focus on the slide above it.** Removing a slide (via
  its context menu or the Delete/Backspace key) now selects the slide *above* the
  deleted one instead of jumping back to the first slide; deleting the first
  slide moves focus to the new first slide. The slide-list rail now also scrolls
  that focused slide back into view instead of snapping to the top — previously,
  deleting a slide below the selected one left the list showing the first slide.
- **A `---` inside a fenced code block no longer splits a slide.** Slide
  separation is now fence-aware: a `---` line inside a ```` ``` ```` or `~~~`
  block (a code sample, a diff hunk, an embedded YAML document) is treated as
  code, not as a slide break, so such slides are no longer silently torn in two.
  The parser and the in-app markdown checker share one splitter so they always
  agree on the slide boundaries.
- **The markdown checker now matches the parser on Windows/Mac line endings.**
  The checker normalises CRLF/CR up front, like the parser already did; without
  this a pasted CRLF document made it silently skip the front-matter and
  slide-structure checks while the parse still succeeded.
- **The documentation reader no longer throws while you drag its scrollbar.** On
  desktop the reader's scrollbar was not bound to its own scroll view, so
  dragging the thumb raised *"The Scrollbar's ScrollController has no
  ScrollPosition attached"* (repeatedly). The reader now gives the scrollbar and
  its scroll view a shared `ScrollController`, so dragging works cleanly.
- **"Continue numbering" is now available on a split bullets-with-image slide.**
  A "bullets + image" slide is a `bulletsImage` slide, edited in the bullets-
  with-image editor — which was missing the *Continue numbering from previous
  slide* toggle that the plain bullets editor already had. So after splitting a
  numbered bullets-with-image slide, its second half could not be told to carry
  on the count, even though the renderer (`numberedListStartFor`) already
  supported it. The toggle now appears in that editor too, under the same
  condition (a numbered list whose preceding slide is also numbered).
- **The slide rail now continues a numbered list across a split.** After
  splitting a numbered slide and ticking *Continue numbering from previous
  slide* on the second half, the builder's thumbnail rail still restarted the
  count at 1, even though the main preview and the actual presentation continued
  it (7, 8, 9…). The rail thumbnails now compute the same start number
  (`numberedListStartFor`) as the main preview and the presenter/audience views,
  so the overview matches what is shown.
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
