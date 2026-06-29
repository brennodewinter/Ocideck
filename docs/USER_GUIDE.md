# OciDeck — User Guide

OciDeck builds [Marp](https://marp.app/) presentations through a structured,
slide-by-slide editor. You compose typed slides, preview them live, present them
(on one or two screens), and export to Markdown, PDF, PPTX, or a self-contained
HTML file. Files stay standard Marp Markdown, so a deck remains usable in other
Marp tools.

## Creating and opening decks

- **New / Open**: use the welcome screen or `Ctrl/Cmd + O`. Multiple decks open in
  **tabs**.
- **Save**: `Ctrl/Cmd + S`. Saving lays out a tidy project folder next to your
  `.md` (`images/`, `data/`, `logos/`, `themes/`) and copies assets in. See
  [`FILE_FORMAT.md`](FILE_FORMAT.md).
- **Crash recovery**: unsaved work is snapshotted automatically and offered back
  after an unexpected exit.

## Slide types

Add a slide and pick a type: **title**, **section** divider, **bullets**, **two
bullet columns**, **bullets + image**, **two images**, **large image**, **video**,
**audio**, **quote**, **table**, **source code**, **chart** (bar, line, pie, or
spider/radar), **cockpit** (a dashboard of aviation-style instrument gauges),
**question** (an interactive quiz slide), **timeline** (an animated timeline of
dated events), and
**free Markdown**. Each card in the chooser shows a miniature
wireframe of the layout, and the dialog works entirely with the keyboard
(`Tab`/`Enter` to choose, `Esc` to cancel). Each type has a dedicated editor on
the left and a live preview on the right.

Text fields support inline Markdown (`**bold**`, `*italic*`, `` `code` ``,
`[links](…)`). Free-Markdown slides also render fenced code with syntax
highlighting, `$…$` / `$$…$$` LaTeX math, and ` ```mermaid ` diagrams (rendered
in preview, presenter, PDF/PPTX, and HTML export).

### Source-code slides

Choose a programming language for syntax highlighting (or "plain text") and paste
your code. It renders as a "code sheet" whose background, text colour and
**monospace font** come from the active **style profile** (e.g. Courier). Turn
**syntax colouring** off to show the whole block in a single colour — e.g. bright
green on black for a classic CRT-terminal look. The text is sized to fill the
panel — larger when there's room, smaller for long fragments. Stored as a fenced
code block in the Markdown.

### Tables

The first row is the header. Press `Enter` inside a cell for a new line within
that cell. To bring in existing data, **paste a table into any cell** with
`Ctrl/Cmd+V` (or `Shift+Insert`): a selection copied from a spreadsheet (Excel,
Numbers, LibreOffice Calc, Google Sheets), CSV text (comma- or
semicolon-separated), or a markdown table fills the grid from that cell onward,
adding rows and columns as needed. Ordinary text — even a sentence with a comma
in it — still pastes into just the one cell.

By default a table can only be changed in the builder. To also let it be edited
live during a presentation, tick **Table editable while presenting** in
*Per-slide options* (shown only on table slides). See
[Editing a table while presenting](#editing-a-table-while-presenting).

### Charts

Pick a type (**bar**, **stacked bar**, **line**, **pie**, **spider/radar**, or
**scatter**) and a title, then
enter data in the grid: the first column is the labels, each further column is a
named series. Use **Row** and **Series** to add data; the small ✕ removes a
row/column. Each series and (for pie/radar) each label can be given its own colour.

- **CSV import** — click **CSV importeren**. You can either keep the data **in the
  slide** (inline) or store it **as a CSV file**. A linked CSV lives in the deck's
  `data/` directory and stays the source of truth (edit it in a spreadsheet); the
  grid then shows it read-only until you **Ontkoppelen** (unlink).
- **Min/max** (optional, bar/line/radar) — on bar and line charts these draw
  horizontal **reference lines**; on a spider/radar chart they fix the **scale**
  (centre to outer ring), shown as evenly spaced values in a small legend beside
  the chart. Leave them empty to scale automatically.
- **Reading values** — hovering a legend entry highlights its series (or pie
  slice). On a line chart the tooltip belongs to the dot under the cursor and
  shows every overlapping dot at once; on a spider/radar chart hovering a point
  shows its value in a tooltip too. For screen readers every chart also carries
  a text alternative with its type, title, and the values per series.
- Charts render in the preview, presenter, PDF, and PPTX, and as inline SVG in the
  HTML export.

### Question slides

A question slide turns the presentation into a short quiz. Pick **Question** in
the chooser, then choose the **kind** in the editor:

- **Multiple choice** — one correct answer is shown together with a random pick of
  wrong ones. Add as many answers as you like (no limit) and tick the correct ones;
  set **how many options are shown** (default 4). At presentation time one correct
  answer plus random wrong ones are drawn, so each run differs.
- **True / false** — the prompt is a statement; a switch in the editor sets whether
  it is **true or false**. The viewer picks *Juist* (true) or *Onjuist* (false).
- **Multiple correct answers** — several answers may be correct. The viewer ticks
  **all** correct ones and presses **Confirm**; it is only right when exactly the
  correct set is selected.

Common options for every kind:

- **Answer time** (optional) — a countdown starts the moment the slide appears;
  running out counts as a wrong answer.
- **On a wrong answer** — *try again* (you cannot continue; a click shows a fresh
  random set for another attempt) or *allow continuing* (the right answer is
  revealed, the slide locks, and you may move on without a retry).
- **Image** (optional) — shown beside the question with a split bar, with a
  magnifier button that opens a **pan-and-zoom** detail view of the photo.

While presenting, you **cannot advance** past a question until it is answered
correctly (or answered and locked). A correct answer turns green and lets you
continue; a wrong answer turns red and highlights the correct one. On a
**two-screen** setup the audience window is interactive: clicks there register the
answer and both screens stay in sync. The answer state is session-only — it is
never written to the `.md` file, and a static export shows the question without
interactivity.

### Timeline slides

A timeline slide turns a list of dated events into an animated visual. Pick
**Timeline** in the type chooser, give the slide a title, then add events; each
event has a **marker** (a year or phase, optional), a **title** and an optional
**description**. Drag the handle to reorder, and use the buttons to add or remove
events.

Two display options sit above the event list:

- **Layout** — *Automatic* lays the events out as a horizontal rail, stacking
  the cards onto extra levels when there are many so they stay readable; you can
  also force *Horizontal* or a *Vertical* spine (cards alternating left/right).
- **Animation** — *Draw in on open* first draws the line, then places the events
  onto it one after another when the slide appears; *Step by step* reveals one more event on each click while
  presenting (and stays in sync on the audience window); *No animation* shows
  everything at once. With *Draw in on open* selected, an **Animation speed**
  slider sets how long the draw-in takes (from ~0.4 s up to ~6 s).

The timeline picks up the active style profile (accent colour, fonts and slide
background), so it matches the rest of the deck. Events are stored as an ordinary
Markdown list, so the slide stays readable and Marp-compatible in the `.md` file.

### Video slides

A video slide plays a clip from a **local file** or, when you enable **Online
media** in *Settings → Privacy*, from an **online source**: paste a direct
`http(s)` link to an `.mp4`/`.mov`, or a **YouTube/Vimeo** link to embed the
official player. Image fields accept an online URL the same way. Online media is
off by default for your privacy — until you turn it on, an online slide shows a
placeholder with the URL instead of loading anything, and on export an online
source is written as a clickable link.

**Watching a video in parts (cutting).** You can split a video so you watch it in
pieces across slides. Play the video in the preview, then click **Knip hier**
(Cut here): the part up to that point stays on this slide, and the remainder
becomes a **new slide** with the same source — which you can cut again. You can
also type the start/end seconds by hand. When presenting with autoplay, each
segment stops at its cut point and advances to the next slide. Cutting works for
local files, online files and YouTube/Vimeo embeds.

## Image library

Image fields open a library that shows every image found in the deck's
directories, with a grid and a coverflow view, search, and a preview pane. Per
image you can store a **caption** (source/credit line, shown on the slide) and a
searchable **description** — in practice your tags. The search box matches file
names and descriptions.

- **Filter untagged images** — the label toggle next to the search box shows
  only images that have no description/tags yet, so you can see at a glance
  which ones still need attention.
- **Clean up duplicates** — the button in the footer finds byte-identical
  images by md5 checksum. Per group one file is kept (preferring the one used
  in slides, then the oldest), tags and captions of the copies are merged onto
  it, slides that referenced a copy are repointed to the kept file, and the
  copies are deleted — after a confirmation that lists exactly what will
  happen. References are updated in the open decks *and* in `.md`
  presentations found on disk in the search directories, so presentations
  that are not currently open keep working too.
- **Deleting an image** warns when it is still in use — in open decks (per
  slide) and in presentations on disk that are not currently open (per file,
  marked "not open").

## Per-slide options

Below each editor you can set:

- **Auto-advance** after N seconds.
- **TLP of this slide** — a Traffic Light Protocol level (see below).
- Show/hide the **logo** and **footer** on this slide.
- **Table editable while presenting** (table slides only) — off by default;
  when on, the table can be changed live during a presentation.
- **Speaker notes** — collapsible amber block at the bottom of the editor (stored
  in the Marp Markdown and included in PPTX export). Use the discard button in the
  header to clear the field; undo restores cleared speaker notes.
- **User notes** — collapsible blue block below speaker notes (stored in a
  sidecar, not in the Markdown). Use the discard button in the header to remove
  them for that slide. Slides with user notes show a blue badge on the thumbnail
  in the slide list.
- An optional **audio** attachment.

## Traffic Light Protocol (TLP)

A deck has an overall TLP level (set from the **TLP** chip in the title bar, or
under *Presentation properties*). Each slide can *also* carry its own level
(*Per-slide options*). When you present or export, slides whose level is
**stricter** than the level chosen for the deck are **withheld** — so the same
deck can be shown safely to audiences with different clearances. Order, least to
most restrictive: none < CLEAR < GREEN < AMBER < AMBER+STRICT < RED.

Classifying a deck is **optional** by default. An organisation can tighten that
with the **classification enforcement** settings under *Settings → General →
Accessibility* (see *Exporting* below).

### Visual marking (WYSIWYG)

When a slide is classified, OciDeck shows the official FIRST TLP 2.0 marking in
the preview, presenter, audience window, thumbnails, and raster exports (PDF/PPTX).
What you see on screen is what leaves the app — the marking is not a separate
overlay added only at export time.

For each visible slide, the **effective** level is the **stricter** of the deck
level and that slide's own level. On top of that:

- **Banner** — a full-width black bar at the top with the coloured TLP label
  (e.g. `TLP:AMBER`).
- **Badge** — the same label in a compact box at the bottom-right (or bottom-left
  when the logo sits bottom-right), so the footer text can step aside.
- **Watermark** (optional, off by default) — a faint diagonal repeat of the TLP
  label and the deck's **organisation** field across the slide. Enable it under
  *Settings → General → Accessibility → Classification watermark*.

Slides with no classification show none of the above. Per-slide TLP that is
stricter than the deck still contributes to the effective marking on slides that
are shown.

## Presenting

Start the fullscreen presenter from the toolbar. See
[`SHORTCUTS.md`](SHORTCUTS.md) for the full key list; highlights: arrows to move,
`G` for the grid overview, `B`/`W` to blank, `P` for presenter view, `K` for the
countdown, `R` to reset the timing, `H` for the in-app cheatsheet.

### Rehearsing and timing

The presenter view (`P`) is also a rehearsal clock — it measures, it does not
nag. The clock bar shows four things:

- **Elapsed** — time since the run started (or since the last `R`).
- **Remaining** — a countdown against a **target time**. It turns red and shows a
  minus sign once you go over; there is no "speed up" coaching, just the number.
- **This slide** — how long you have spent on the current slide. Time accumulates
  per slide across the whole run, even if you jump back and forth.
- **Clock** — the wall-clock time.

Set the target time up front under *Settings → General → Presentation*, or change
it live while presenting with **`K`** (type the minutes and seconds as `MMSS`,
`Enter` to confirm, `0` to switch the countdown off). **`R`** resets the run —
elapsed time and per-slide timings — while keeping the target.

When you leave the presenter after a run of at least ten seconds, a **summary**
shows the total time against the target and the time spent per slide, with a
button to copy the times to the clipboard. This is **session-only**: nothing is
written to disk or into the `.md` file.

### Two screens (beamer + laptop)

When a second display is connected on **macOS, Windows, or Linux**, OciDeck
automatically shows the **slide on the beamer** and the **presenter view on your
laptop** (current slide, next slide, notes, clock). Use an *extended* (not
mirrored) display. Notes:

- The keyboard stays on the laptop; clicking the beamer also advances.
- On macOS the "external" screen is the one without the menu bar.

### Annotating while presenting

Draw on the slide live with **D** pen, **T** highlighter, **⇧E** eraser, **X**
laser pointer, and **C** to clear; `Esc` puts the tool away. Drawings are a
separate layer (never written into the Marp Markdown), mirror live to the beamer,
and are saved in a `<name>.ink.json` sidecar so they persist with the deck.

### Editing a table while presenting

Tables marked **editable while presenting** (see *Per-slide options*) can be
changed live without leaving the presentation — handy for filling in figures or
ticking items in front of an audience. On such a slide a subtle pencil icon
appears top-right: dimmed when off, highlighted when on. Click it, or press
**E**, to toggle editing (read-only tables keep **E** as the eraser). While
editing, the **arrow keys** move the text cursor inside the cell, **Tab** /
**⇧Tab** jump to the next / previous cell (a new row is added past the last
cell), and `Esc` leaves editing. Changes are written back to the deck and mirror
to the beamer in dual-screen mode.

### User notes (recipient / course)

Separate from **speaker notes** (the collapsible amber block above). User notes
are for the person following the presentation — for example during a course. They
are stored in a `<name>.user-notes.json` sidecar, never written into the Marp
Markdown, and hidden by default while presenting. Press `Ctrl/Cmd + N` in the
presenter to open a local **My notes** panel on the laptop only (never mirrored
to the beamer). `Esc` closes the panel before other layers.

In the visual editor, expand **User notes** below **Speaker notes** to author them
per slide. Both blocks share the same layout: a collapsible header (icon, title,
discard button) and the markdown editor underneath. The discard button is enabled
only when the field has content. Clearing user notes is immediate and is not part
of undo/redo; clearing speaker notes can be undone.

Slides that carry user notes show a **blue badge** on their thumbnail in the slide
list so you can spot them without opening each slide.

## Exporting

Export to:

- **PDF** and **PPTX** (PPTX includes speaker notes) — rendered from the in-app
  slide renderer.
- **Self-contained HTML** — one offline file; code highlighting, math, charts, and
  mermaid diagrams render in the browser.
- **Portable package** (`.ocideck`) — a single zip with the Markdown and all
  assets, to hand the whole deck to someone else.

**Classification enforcement (optional).** Under *Settings → General →
Accessibility → Classification enforcement* an organisation can configure up to
four independent rules. All are off by default; together they form a single
**export gate** that applies to PDF, PPTX, HTML, and the portable package.
When a rule blocks export, **no file is written** (fail-closed) and the export
dialog shows the reason. The status bar export button tooltip repeats that reason
when the deck is saved and clean.

| Setting | Effect |
| --- | --- |
| **Release ceiling** | Blocks export when the deck's TLP is **higher** than the chosen maximum (same as before — a deck at RED cannot export when the ceiling is AMBER). |
| **Required minimum level** | Blocks export when the deck's TLP is **lower** than the chosen minimum (e.g. minimum GREEN rejects CLEAR and unclassified decks). |
| **Classification required** | Blocks export when the deck has **no** TLP level set, even if no minimum is configured. |
| **Classification watermark** | Does not block export; adds the diagonal watermark described under *Traffic Light Protocol*. |

The gate evaluates the **deck-wide** TLP from front matter, not per-slide levels.
Per-slide stricter levels still affect which slides appear in the export (they are
withheld), but they do not satisfy "classification required" on their own — set
the deck level explicitly.

When export is blocked because the deck is unclassified, the **TLP** chip in the
title bar gets an orange border and its tooltip explains that a level is required.

**Export metadata.** PDF, PPTX, and HTML exports embed document properties derived
from the deck: title, author (falling back to organisation), description, keywords,
and TLP. When a TLP level is set, it is prefixed in the PDF/PPTX **Subject**
(`TLP:GREEN — My deck`), added to **Keywords** (`TLP`, the label, and the stable
key), and written to HTML `<meta name="classification">` and `<meta name="tlp">`.
HTML exports also show a fixed top banner with the TLP label when classified.
These properties are for discovery and handling downstream — they do not replace
the visible banner, badge, and optional watermark on the slides themselves.

**Slide quality at export.** When the deck has open quality issues, the export
dialog shows a summary banner with a link to the full issue list. Depending on
your settings (see *Slide quality* below), export may ask for
confirmation or be blocked entirely.

| Setting | Effect |
| --- | --- |
| **Warn on export** (on by default) | When there are warnings or errors, a confirmation dialog lists the issues before export proceeds. Choose **Export anyway** to continue. Informational tips alone do not trigger this dialog. |
| **Block export on serious quality issues** (off by default) | When any issue is at **error** severity, export is blocked until you fix the deck. The export dialog shows the reason and the issue list; there is no "Export anyway". Warnings and tips alone do not block. |

These gates apply to PDF, PPTX, HTML, and the portable package. They are
independent of classification enforcement — both can apply at once.

## Accessibility

OciDeck aims for WCAG 2.1 in the editor:

- **Interface text size** — Settings → General → Accessibility offers 100–200%
  text scaling for the whole editing environment, on top of what the operating
  system asks for. Slides keep their fixed 16:9 design size, so what you see is
  still exactly what you present and export.
- **Keyboard** — the panel divider between the slide list and the editor can be
  focused with `Tab` and resized with `←`/`→`; the add-slide dialog is fully
  keyboard-operable.
- **Screen readers** — slide thumbnails announce a concise label ("Slide 3/12:
  title", including skipped state and whether the slide has user notes), charts
  read out their data as a text alternative, and the fullscreen presenter
  announces every slide change. Pictures expose their caption as alt text (and a
  generic "image" when uncaptioned, which the slide-quality analyser flags), and
  icon-only buttons carry a label so their purpose is read aloud.
- **Slide quality** — while you edit, OciDeck continuously checks the deck for
  accessibility and readability problems. See the subsection below.

### Slide quality

The **Slide quality** bar sits below the editor preview. It summarises open
issues and can be expanded to browse them. Filter chips let you show **All
issues** or only **Errors**, **Warnings**, or **Tips**. Click a slide-specific
issue to jump to that slide and focus the relevant editor field; click a **theme
(entire presentation)** issue to open *Settings → Colours* with the matching
colour field scrolled into view and highlighted.

Issues also appear as badges on slide thumbnails (amber for warnings, red when
errors are included), as a blue badge when a slide has **user notes**, and as
inline hints on relevant editor fields (for example image captions).

Skipped slides are not checked. Export and presentation use the same analyser on
the slides that will actually be shown.

#### Severity

| Severity | Meaning | Export (default settings) |
| --- | --- | --- |
| **Tip** | Good practice, not a hard readability problem | Ignored at export |
| **Warning** | Likely problem; review recommended | Confirmation dialog when *Warn on export* is on |
| **Error** | Serious problem (very low contrast or extreme text density) | Confirmation dialog when *Warn on export* is on; hard block when *Block export on serious quality issues* is on |

#### Checks performed

Issues are grouped in three categories. The table lists what the analyser looks
for (`lib/services/slide_quality_analyzer.dart`).

| Category | Severity | What is checked |
| --- | --- | --- |
| **Contrast** | error / warning | Style profile: body text, title, table text, table header, code colours, and accent colour against their backgrounds (WCAG 2.1 AA). Footer text at 70% opacity against the slide background when a footer is configured. Checklist marker colours against the slide background when the deck contains checklist slides. Section slides: title colour against the section background. |
| **Alt text** | tip / warning | Charts: no title, series names, or linked data description. Video slides: no title, subtitle, or speaker notes describing the content. Missing image captions are not reported as quality issues. Missing image or video **files on disk** when the deck is saved in a project folder (path in the slide points to a file that is not there). |
| **Text density** | error / warning | Bullet slides (one column, two columns, bullets + image): auto-fit shrinks text below 70% of design size (warning) or 20% (error), or the slide has too many bullets/words, long prose-like bullets, multiple sentences in a bullet, deep nesting, or strongly imbalanced two-column content. Rich-text and free-Markdown list items use the same bullet readability checks. Tables: cell text at the minimum readable size. Source-code and free-Markdown slides: very long content. Title slides: long title + subtitle combined. Quote slides: long quote + author combined. |

Theme-wide contrast issues are listed once for the whole deck; slide-specific
issues name the slide number.

#### Settings

Under *Settings → General → Accessibility*:

| Setting | Default | Effect |
| --- | --- | --- |
| **Warn on export** | On | Ask for confirmation before exporting when warnings or errors are open. Informational tips do not count. |
| **Block export on serious quality issues** | Off | Refuse export entirely while any **error**-severity issue remains. Works together with *Warn on export* — when blocking is on, errors cannot be overridden with **Export anyway**. |

When *Warn on export* is off, quality issues are ignored at export time (they
still show while editing).

## Markdown mode

The toolbar code icon switches the editor to **Markdown mode**: the whole deck is
shown as one Marp Markdown document (the same structure OciDeck writes to disk).
Use this for bulk edits, copy-paste from another tool, or tweaks that are faster
in raw text. Switch back with **Apply** (to parse the text back into typed slides)
or **Cancel** (discard your edits and return to the visual editor).

### Find & replace

Markdown mode has an **in-editor find bar** (IDE-style) that searches the live
markdown buffer — including front matter, `\n---\n` separators, HTML comments, and
any text you have not yet applied back to the deck. This is separate from the
**Find & replace** dialog in visual mode (`Ctrl/Cmd + H`), which searches
individual slide fields.

- **`Ctrl/Cmd + F`** — open the find bar and focus the search field.
- **`Ctrl/Cmd + H`** — open the find bar with the replace row visible.
- **Enter** / **Shift + Enter** (in the find field) — jump to the next or
  previous match (wraps around).
- **Esc** — close the find bar.

The bar shows a match counter (`1 / 3`), previous/next buttons, a case-sensitivity
toggle, **Replace** (current match only), and **Replace all**. Each match is
selected in the editor so you can jump quickly to a slide title, separator, or
other section. You can also open find from the **More** menu (⋯) while in
markdown mode.

### Syntax check

Markdown mode includes a **syntax check** that validates your text against what
OciDeck's parser (`MarkdownService`) can read reliably. Broken structure often
does not fail loudly — the deck may load with the wrong slide types or missing
content — so the check catches problems before you apply.

- **Check** — run validation at any time while editing. Results appear in a
  summary bar; expand it for a list of issues. Line numbers in the gutter are
  highlighted (red = error, amber = warning). Click an issue or a line number to
  jump to that line.
- **Apply** — always runs the check first. If anything is found, a dialog lists
  the problems and offers **Back to editor**, **Cancel**, or **Apply anyway**.
  Choosing **Apply anyway** proceeds despite the warnings (you may still see the
  existing "Markdown could not be processed" banner if parsing returns `null`).

The check is **structural**, not a full Marp linter: it mirrors OciDeck's own
splitting rules (front matter, `\n---\n` slide separators, `_class` comments,
fenced blocks, and the HTML fragments OciDeck generates). Valid Marp that OciDeck
does not model (e.g. arbitrary directives) is not reported.

#### Checks performed

Issues are reported with a **line number**, a **severity**, and a short message.

| Area | Severity | What is checked |
| --- | --- | --- |
| **Document** | warning | The file is empty. |
| **Document** | error | No slide content after the front matter. |
| **Document** | error | `MarkdownService.parseDeck` returns `null` (unrecoverable parse failure). |
| **Front matter** | error | Opening `---` without a closing `---` line. |
| **Front matter** | warning | A line inside the block is not `key: value`. |
| **Front matter** | error | `tlp:` value is not a known key (`clear`, `green`, `amber`, `amber+strict`, `red`, or empty/`none`). |
| **Comments** | error | `<!--` without a matching `-->` on the same line. |
| **Comments** | warning | A comment looks like metadata but lacks `_class:`, `_style:`, `ocideck_…`, `skip`, `tlp:`, or `advance:`. |
| **Fenced code** | error | An odd number of ` ``` ` lines in the file (unclosed fence). |
| **Slide class** | error | A malformed `<!-- _class: … -->` (present but not parseable). |
| **Slide class** | warning | An unknown token in `_class` (only `title`, `section`, `two-bullets`, `split`, `quote`, `video`, `table`, `code`, `chart`, `logo-safe`, `no-logo`, `no-footer` are recognised; other tokens are kept as custom CSS classes but may change auto-detection). |
| **Per-slide metadata** | error | `<!-- tlp: … -->` with an unknown level. |
| **Per-slide metadata** | error | `<!-- advance: … -->` where the value is not a number. |
| **Per-slide metadata** | error | `<!-- ocideck_list_style: … -->` not `bullets`, `numbered`, or `checklist`. |
| **Two-column bullets** | error | `ocideck_two_bullets_left/right` or `*_title` comments with invalid base64/JSON. |
| **Images** | error | `![…](…` without a closing `)`. |
| **Video / audio** | error | `<video>` / `<audio>` tag incomplete, or `<video>` without `src="…"`. |
| **`code` slides** | error | `_class: code` but fewer than two fence lines (no closed fenced block). |
| **`chart` slides** | error | Missing ` ```chart ` block, unclosed fence, or JSON that is not a valid `{…}` object. |
| **`chart` slides** | warning | Empty JSON inside a closed ` ```chart ` block. |
| **`split` slides** | error | Missing or unclosed `<div class="split-text">` or `<div class="split-image">`. |
| **`two-bullets` slides** | error | Missing or unclosed `<div class="ocideck-two-bullets">`. |
| **`table` slides** | warning | `_class: table` but no `\| … \|` rows. |
| **`table` slides** | error | Table present but no separator row (`\| --- \|`), or the second row is not a valid GFM separator. |
| **HTML layout** | error | Unbalanced `<div>` / `</div>` within a slide (extra closing tag, or an opening tag left open). |

Implementation: `lib/services/markdown_validator.dart` (unit tests in
`test/markdown_validator_test.dart`).

## Theming and language

- **Style profiles** control deck colours (including the source-code background,
  text, font and an optional syntax-colouring toggle), fonts, logo, and footer.
  Every colour can be picked from the presets or entered as a custom hex value. The
  Colours and Logo tabs show which profile you're editing. The bundled Marp theme
  is `assets/themes/ocideck.css`.
- **App appearance** (including a dark interface) is configurable in settings.
- **Cockpit colour schemes** set the status colours of the cockpit instruments —
  *good* (green), *warning* (amber), *critical* (red) and *too low/cold* (blue,
  used below a meter's lower bound), plus the artificial horizon's *sky* (blue)
  and *ground* (brown). Manage them on the **Cockpit** tab in
  settings: the built-in *Standaard* scheme keeps the original colours, and you
  can make a copy to create and name your own variants. The chosen scheme applies
  to every cockpit slide — in the editor, the presenter and all exports. Like the
  style profile, these colours are app settings and are not stored in the `.md`
  file.
- The interface is available in Dutch, English, Italian, German, French, Spanish,
  Frisian, and Papiamento.
