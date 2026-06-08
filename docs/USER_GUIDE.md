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
spider/radar), and **free Markdown**. Each type has a dedicated editor on the left
and a live preview on the right.

Text fields support inline Markdown (`**bold**`, `*italic*`, `` `code` ``,
`[links](…)`). Free-Markdown slides also render fenced code with syntax
highlighting and `$…$` / `$$…$$` LaTeX math.

### Source-code slides

Choose a programming language for syntax highlighting (or "plain text") and paste
your code. It renders as a "code sheet" whose background and text colour come from
the active **style profile**. Turn **syntax colouring** off to show the whole block
in a single colour — e.g. bright green on black for a classic CRT-terminal look.
Stored as a fenced code block in the Markdown.

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
  shows its value in a tooltip too.
- Charts render in the preview, presenter, PDF, and PPTX, and as inline SVG in the
  HTML export.

## Per-slide options

Below each editor you can set:

- **Auto-advance** after N seconds.
- **TLP of this slide** — a Traffic Light Protocol level (see below).
- Show/hide the **logo** and **footer** on this slide.
- **Speaker notes**.
- An optional **audio** attachment.

## Traffic Light Protocol (TLP)

A deck has an overall TLP level (shown as a marking on the slides). Each slide can
*also* carry its own level. When you present or export, slides whose level is
**stricter** than the level chosen for the deck are **withheld** — so the same
deck can be shown safely to audiences with different clearances. Order, least to
most restrictive: none < CLEAR < GREEN < AMBER < AMBER+STRICT < RED.

## Presenting

Start the fullscreen presenter from the toolbar. See
[`SHORTCUTS.md`](SHORTCUTS.md) for the full key list; highlights: arrows to move,
`G` for the grid overview, `B`/`W` to blank, `P` for presenter view, `H` for the
in-app cheatsheet.

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

## Theming and language

- **Style profiles** control deck colours (including the source-code background and
  text, with an optional syntax-colouring toggle), fonts, logo, and footer. Every
  colour can be picked from the presets or entered as a custom hex value. The
  bundled Marp theme is `assets/themes/ocideck.css`.
- **App appearance** (including a dark interface) is configurable in settings.
- The interface is available in Dutch, English, Italian, German, French, Spanish,
  Frisian, and Papiamento.
