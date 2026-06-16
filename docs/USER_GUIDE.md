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
spider/radar), and **free Markdown**. Each card in the chooser shows a miniature
wireframe of the layout, and the dialog works entirely with the keyboard
(`Tab`/`Enter` to choose, `Esc` to cancel). Each type has a dedicated editor on
the left and a live preview on the right.

Text fields support inline Markdown (`**bold**`, `*italic*`, `` `code` ``,
`[links](…)`). Free-Markdown slides also render fenced code with syntax
highlighting and `$…$` / `$$…$$` LaTeX math.

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

### Charts

Pick a type (**bar**, **line**, **pie**, or **spider/radar**) and a title, then
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
- **Speaker notes**.
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

When a second display is connected, OciDeck automatically shows the **slide on the
beamer** and the **presenter view on your laptop** (current slide, next slide,
notes, clock). Use an *extended* (not mirrored) display. Notes:

- The keyboard stays on the laptop; clicking the beamer also advances.
- On macOS the "external" screen is the one without the menu bar.

### Annotating while presenting

Draw on the slide live with **D** pen, **T** highlighter, **E** eraser, **X**
laser pointer, and **C** to clear; `Esc` puts the tool away. Drawings are a
separate layer (never written into the Marp Markdown), mirror live to the beamer,
and are saved in a `<name>.ink.json` sidecar so they persist with the deck.

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
  title", including the skipped state), charts read out their data as a text
  alternative, and the fullscreen presenter announces every slide change.
- **Slide quality** — while you edit, OciDeck checks each slide for missing
  alt text/captions, low theme contrast, and overcrowded text (font auto-fit
  shrinking too far). Issues appear as badges on slide thumbnails, in a
  collapsible **Slide quality** bar in the editor, and inline hints on image
  caption fields. Before export you can get a confirmation dialog listing open
  issues (**Settings → General → Accessibility → Warn on export**; on by
  default). Quality checks warn but do not block export once you choose
  **Export anyway**.

## Markdown mode

The toolbar code icon switches the editor to **Markdown mode**: the whole deck is
shown as one Marp Markdown document (the same structure OciDeck writes to disk).
Use this for bulk edits, copy-paste from another tool, or tweaks that are faster
in raw text. Switch back with **Apply** (to parse the text back into typed slides)
or **Cancel** (discard your edits and return to the visual editor).

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
- The interface is available in Dutch, English, Italian, German, French, Spanish,
  Frisian, and Papiamento.
