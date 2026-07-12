# OciDeck — User Guide

OciDeck builds [Marp](https://marp.app/) presentations through a structured,
slide-by-slide editor. You compose typed slides, preview them live, present them
(on one or two screens), and export to Markdown, PDF, PPTX, or a self-contained
HTML file. Files stay standard Marp Markdown, so a deck remains usable in other
Marp tools.

## Creating and opening decks

- **New / Open**: use the welcome screen or `Ctrl/Cmd + O`. Multiple decks open in
  **tabs**. Opening a deck that is already open just jumps to its existing tab —
  the same file is never loaded into two tabs at once, so you can't accidentally
  edit two out-of-sync copies.
- **Start from a template**: the new-presentation dialog offers a searchable
  catalogue of starting points — from an empty deck to shift briefings, security
  and privacy work decks, crisis and flight-prep sessions, and **conversation-
  preparation** templates. The latter help you prepare for a difficult or
  important talk (job interview, performance review, salary negotiation,
  resolving a conflict, giving or receiving criticism, delivering bad news,
  setting boundaries, a strained relationship, client and sales conversations,
  supplier negotiations, a pitch, or getting buy-in in a meeting). The
  high-stakes, emotional ones weave in the *Crucial Conversations* method; each
  comes with fill-in preparation tables and a progress checklist. Everything is
  placeholder text you overwrite with your own content.
- **Save**: `Ctrl/Cmd + S`. Saving lays out a tidy project folder next to your
  `.md` (`images/`, `data/`, `logos/`, `themes/`) and copies assets in. See
  [`FILE_FORMAT.md`](FILE_FORMAT.md).
- **Crash recovery**: unsaved work is snapshotted automatically and offered back
  after an unexpected exit.

## Command palette

Press `Ctrl/Cmd + K` for a searchable list of the common actions — present,
export, save, add a chart, find & replace, the image library, toggle
markdown/visual mode, full-deck preview, new tab, open, package/URL import,
settings, and setting each TLP level. Start typing to filter (accents and case
don't matter), use `↑`/`↓` to move, `Enter` to run, and `Esc` to close. Actions
that aren't available yet (for example export before you've saved) stay visible
but greyed out. The palette is also in the `⋮` menu.

## Nextcloud (WebDAV)

You can use a folder on your Nextcloud as a source for decks and assets.

- **Set it up** in *Settings → Nextcloud*: enter the server URL
  (`https://cloud.example.com`), your username, an **app password** (create one
  in Nextcloud under *Settings → Security*, don't use your login password), and
  an optional subfolder. Use **Test connection** to check it before saving. The
  app password is stored encrypted in your operating system's keychain, not in
  the plain settings file.
- **Self-hosted / home server**: if your Nextcloud runs on a private or LAN
  address, tick **Trusted internal server** — otherwise the connection is
  refused (the same safeguard that stops a deck from reaching internal hosts).
- **Open** via the welcome screen (*Open from Nextcloud*) or the `…` menu:
  browse the folder and pick an `.ocideck` package or a Marp `.md`. The file is
  downloaded, checked by the same safety scan as any other deck, and opened in a
  tab.
- **Save back** with *Save to Nextcloud* (`…` menu). Choose a target path and a
  format: a single **`.ocideck` package** (one file, assets included) or a
  **flat `.md` plus its asset folders** (`images/`, `themes/`, …) mirrored into
  the same folder. A deck opened from Nextcloud remembers where it came from, so
  saving suggests the original location.

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

Not sure what a slide type is for? Click the small **"What can I do here?"**
button at the top of the editor for a one-line hint about the selected type (for
example, how to import CSV data into a chart, how to trim a video, or how to
paste a table from a spreadsheet). The info icon next to a slide's **TLP** picker
explains that slides classified above the deck's level are left out when you
present or export. The editor header keeps everything on one strip: the type and
style pickers, that hint, a compact **Quality** chip (its colour shows the
status; hover or open it for the counts) and a gear button for **Slide
settings** — the less-used per-slide options (audio, logo, footer, timing, TLP).
Each expands just below the strip; a set per-slide TLP shows as a small badge on
the gear so the classification stays visible at a glance.

Text fields support inline Markdown (`**bold**`, `*italic*`, `` `code` ``,
`[links](…)`). Free-Markdown slides also render fenced code with syntax
highlighting, `$…$` / `$$…$$` LaTeX math, and ` ```mermaid ` diagrams (rendered
in preview, presenter, PDF/PPTX, and HTML export).

### Large image

A single image fills the slide as a background. Tick **Afbeelding slidevullend**
(slide-filling) to have the image **cover** the whole slide, cropping whatever
falls outside the frame — handy for full-bleed photos. Leave it off to show the
**full** image (letterboxed if its aspect differs); the **Zoom** control then
scales it from edge-to-edge fit down to smaller, or zoomed in past the frame.
An optional title overlay can sit on top.

**Crop to fit.** When a picture is cropped (slide-filling or zoomed in) and the
wrong part shows, click **Bijsnijden** (Crop). A live editor opens with the image
inside its slot: **drag** the picture to choose which part stays in view, and —
for the large image and title background — **zoom** in the same dialog. The crop
is non-destructive: it stores a focal point, never rewrites the image file, and
travels with the deck in the `.md`. The same **Bijsnijden** button is on the
title background, the bullets-and-image panel, and each image of a two-images
slide (remote/URL images can't be cropped this way).

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
- **Ordering** — enter the answers **in the correct order** in the editor (the
  up/down arrows rearrange them). At presentation time a random subset is drawn
  (keeping its relative order as the right answer) and shown shuffled — never
  accidentally already in the right order. The viewer taps the options in the
  order they think is correct — each tap assigns the next position number,
  tapping again removes it — and presses **Confirm** once every option has a
  place. On a wrong answer the options are revealed **in the correct order**:
  correctly placed ones turn green, misplaced ones turn red with an explicit
  *Your order: n* line showing where the viewer had put them.

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
media** in *Settings → Beveiliging* (Security), from an **online source**: paste a direct
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

## Organising the slide list

The rail on the left lists every slide as a thumbnail.

- **Select** a slide by clicking it. Hold **Shift** to select a range, or
  **Ctrl/Cmd** to add/remove individual slides; **Ctrl/Cmd+A** selects them all.
- **Reorder** by dragging a thumbnail's drag handle. With several slides
  selected, dragging any one of them moves the **whole selection** as a single
  block (keeping its order); a scattered selection is gathered together at the
  drop point. The selection follows to the new position.
- **Add, paste, find or import** slides with the buttons under the list. New
  slides are inserted **right after the current slide**, not at the end, so they
  land where you are working. Bulk actions (delete, skip, copy to another deck)
  apply to the whole selection.

## Image library

Image fields open a library that shows every image found in the deck's
directories, with a grid and a coverflow view, search, and a preview pane. Per
image you can store a **caption** (source/credit line, shown on the slide) and a
searchable **description** — in practice your tags. The search box matches file
names and descriptions.

Supported formats are PNG, JPEG, **GIF (including animated)**, BMP and WebP.
Animated GIFs (and animated WebP) play in the preview, presentation and audience
window. Very large images are decoded at a capped size to protect memory; a
picture within that limit — which covers virtually all animations — plays at
native resolution. PDF/PPTX export captures one still frame.

- **Filter untagged images** — the label toggle next to the search box shows
  only images that have no description/tags yet, so you can see at a glance
  which ones still need attention.
- **Auto-tag with AI** — when the optional AI backend is on, an auto-tag button
  walks every image that still has **no** tags, asks a local vision model for a
  handful of searchable keyword tags in your interface language, and saves them to
  the description sidecar so the picture becomes findable. It only fills empty
  descriptions — a tag you (or an earlier run) wrote is never overwritten — and an
  **Ongedaan maken** action clears exactly the tags that run wrote, so a bad bulk
  pass is fully reversible.
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

### Play-only decks

You can hand out a deck **locked for presenting only**. Turn on **Play only
(locked)** under *Presentation properties* (or add `ocideck_play_only: true` to
the file's front matter by hand). When such a deck is opened, OciDeck shows a
stripped-down screen: **just the first slide and a Play button** — no editor, no
toolbar, no menus, no export, and the editing shortcuts are gone. Pressing
**Play** switches the app to full screen and runs the presentation exactly as
usual.

The lock is part of the file, so it stays with the deck when you share it.
**Closing the deck always brings back the normal working of the app** — you can
open and edit other decks as usual. To *unlock* a play-only deck for editing,
remove the `ocideck_play_only` key from its markdown.

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

**Password-protecting a package (optional).** When you export a package, a dialog
lets you switch on **AES-256 encryption** and set a password. Encryption is off by
default. A strength meter gives honest, entropy-based feedback — a long passphrase
beats a short password with symbols, and nothing is forced — and a **Generate
strong password** button creates a random 32- or 256-character password you can
**copy** to pass along separately. Keep the password safe: if you lose it, the
package can no longer be opened. Opening an encrypted package (from a file, drag &
drop, URL, or Nextcloud) prompts for the password, with a clear message on a wrong
one. Note that the file *names* inside the package stay visible, and the WinZip-AES
key derivation is weak, so a strong password is what actually protects it — see
[FILE_FORMAT.md](FILE_FORMAT.md) §7.1.

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
- **Document reader** — the in-app reader for the bundled guides uses the full
  window width, so wide tables get room instead of being squeezed into a narrow
  column, while running text stays at a comfortable line length. Its app bar has
  a subtle **A−/A+** control to enlarge or shrink the document text; the choice
  is remembered and is independent of the interface text size above.
- **Searching the documentation** — *Settings → Documentation* has a search box
  above the list. Type one or more words and the list narrows to the documents
  whose title or body contains **all** of them, with a short excerpt showing
  where each match sits and the words highlighted. Clearing the box restores the
  full grouped list. The search runs over the documents in your current
  interface language.
- **Keyboard** — the panel divider between the slide list and the editor can be
  focused with `Tab` and resized with `←`/`→`; the add-slide dialog is fully
  keyboard-operable.
- **Screen readers** — slide thumbnails announce a concise label ("Slide 3/12:
  title", including skipped state and whether the slide has user notes), charts
  read out their data as a text alternative, and the fullscreen presenter
  announces every slide change. Icon-only buttons carry a label so their purpose
  is read aloud.
- **Image alt-text (WCAG 1.1.1)** — the image, two-images and bullets-with-image
  editors have a dedicated **Alt-tekst** field, separate from the visible caption.
  A screen reader announces the alt-text when set, falling back to the caption and
  then a generic "image"; the slide-quality check nudges until either is present.
  Alt-text travels in the `.md` (see [FILE_FORMAT.md](FILE_FORMAT.md) §8). When the
  optional AI backend is on, a **Stel alt-tekst voor (AI)** button drafts one with
  a local vision model — draft-only, marked as an AI concept and cleared for
  sealing only after you review it; a **Wis AI-alt-teksten** command removes every
  still-unreviewed AI draft in one undoable step.
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

A too-dense bullet slide offers a one-click **Split slide** fix (also available
from the slide thumbnail's menu). It divides the bullets evenly between the two
pages when both halves fit; a slide too full for two pages fills the first page to
the readable optimum and leaves the rest, which you can split again. Splitting a
**bullets + image** slide keeps the image on the continuation page too, so both
pages match and share one font size — swap the follow-up to a plain bullets page
via the slide **type** picker if you prefer.

#### Settings

Under *Settings → General → Accessibility*:

| Setting | Default | Effect |
| --- | --- | --- |
| **Warn on export** | On | Ask for confirmation before exporting when warnings or errors are open. Informational tips do not count. |
| **Block export on serious quality issues** | Off | Refuse export entirely while any **error**-severity issue remains. Works together with *Warn on export* — when blocking is on, errors cannot be overridden with **Export anyway**. |

When *Warn on export* is off, quality issues are ignored at export time (they
still show while editing).

## Information security module (pentest reports)

OciDeck has an optional module for writing **MIAUW-conforming penetration-test
reports** ("Informatieveiligheidsonderzoek"). It is **off by default** and adds a
set of security slide types, a guided finding flow, a compliance overview and
report-automation commands. Everything below is offline; the AI helpers are the
same optional, off-by-default backend used elsewhere.

### Enabling the module

Turn it on under **Settings → Uitbreidingen (Extensions)**. Once enabled, the
security slide types appear in a dedicated *Informatieveiligheid* tab of the
add-slide picker, and the module's command-palette actions become available.

### Starting from the MIAUW report template

Once the module is on, the new-presentation dialog gains a
**MIAUW-pentestrapport** template. It scaffolds a complete, MIAUW-conforming
report in one step: a cover page, the four MIAUW parts as section dividers
(*Algemeen*, *Plan van aanpak*, *Executie*, *Rapportage*), a document-management
overview, a sign-off page, a scope matrix, a management summary, a research
timeline, an example finding, a per-standard checklist and an appendix list.
Overwrite the placeholders with your own content, then fill the structured
slides with the wizard and the automation commands below. The template stays
hidden until the module is enabled, so the catalogue is unchanged for everyone
else.

### Security slide types

- **Finding** — one vulnerability, authored as a **group**: a structured header
  card plus optional detail and evidence slides that share one finding id, so the
  whole finding moves and round-trips as a unit. The header carries the scope
  object, the CVSS 4.0 vector (with a live, derived score and severity band), CWE
  and CVE references, and the description / reproduction / impact / recommendation
  sections. Severity is always **derived** from the vector, never typed.
- **Checklist** — a standard-driven test list with a MIAUW tri-state per item
  (*Getoetst* / *Afwijking* / *Niet toetsbaar* / *Niet getoetst*) and an optional
  link to a finding id.
- **Scope matrix** — the scope objects, each with a type (Web / Infra / IoT /
  Firmware / API / Mobile / Other) that automatically fixes its test standard
  (Web→WSTG, Infra→PTES, …), a coverage status and a note.
- **Findings summary** — a management overview: the number of findings per CVSS
  severity band, rendered as a severity-coloured bar chart. **Vernieuw uit deck**
  recomputes the counts from the deck's findings.
- **Sign-off** — the truthful-reporting page (MIAUW 1.6) with the deck-wide visual
  signature and certification, and **Afronden & verzegelen** to seal the report.

### The finding wizard

Adding a **Bevinding** opens a step-by-step wizard instead of a blank slide:

1. **Basis** — title, finding id, scope object.
2. **CVSS 4.0** — a per-metric builder (a dropdown per metric) with a live score
   and severity read-out, plus the scope object's **CIA rating** (Confidentiality
   / Integrity / Availability). The CIA rating pre-fills the CVSS Environmental
   requirements (`CR`/`IR`/`AR`), so the offered score is **CIA-weighted** by
   default (you can still override any metric).
3. **CWE & CVE** — a searchable **CWE picker** over a bundled offline catalog of
   the most pentest-relevant weaknesses. Picking one sets the CWE and, only when
   they are still empty, fills the description and recommendation with a short,
   neutral snippet — a good starting point written without an LLM. A CVE field
   accepts one or more ids.
4. **Inhoud** — the four narrative sections, and a choice to add a detail and/or
   evidence placeholder.

On finish the wizard inserts the whole finding group in one step. The same CWE
picker is also available from the finding editor's **Kies CWE…** button.

### AI drafting for finding text (optional)

When the optional AI backend is on, the finding editor shows a **Tekst voorstellen
(AI)** button under the *Beschrijving*, *Mogelijke impact* and *Aanbeveling*
fields. It drafts that field with a local model, grounded **only** on your own
facts for this finding (title, scope object, CVSS, CWE/CVE and the fields you have
already filled) — and it is forbidden to invent identifiers: any CWE, CVE or CVSS
id the model emits that is not already in your facts is stripped out
(PENTEST_MIAUW §16). It is **draft-only**: an AI-drafted field is marked with an
**AI-concept** badge and **Afronden & verzegelen** stays blocked until you press
**Nagekeken** on each one, so the truthful-reporting signature always covers
human-verified text. Off by default; desktop only.

### MIAUW compliance overview

The **MIAUW-compliance** command (command palette) opens a gap-analysis panel that
scores each MIAUW requirement (EIS) as **Voldaan** / **Openstaand** / **Uitgesloten
door klant**, grouped by the four parts. Content-derivable requirements are checked
automatically from the deck (does every finding carry a CVSS vector, scope, CWE and
sections; is there a management summary, scope matrix, checklist, timeline and
sign-off; is the deck sealed); organisational requirements are tagged *Handmatig*.
**Every requirement is waivable** with a mandatory reason — it is a gap analysis,
never a hard gate, that only *warns* when a foundational requirement (1.1, 1.6) is
excluded. Waivers travel in the deck front matter.

### Report automation

Three more command-palette actions remove mechanical bookkeeping:

- **Bevindingen hernummeren** — renumbers every finding sequentially (`F-01`,
  `F-02`, … in deck order), rewriting each group's shared id and its heading
  prefix in one undoable step (skipped on a sealed deck).
- **Scope-dekking controleren** — lists scope objects that are in scope but neither
  tested nor referenced by any finding — the "did you test everything you scoped"
  guardrail.
- **Bewijs-hashes kopiëren** — computes the MIAUW-required SHA1 (plus SHA-256) of
  every evidence image and copies the appendix hash table to the clipboard.
- **Managementsamenvatting** — shows the management overview derived live from the
  deck: the number of findings per severity band, how many scope objects were
  tested, and the test standards used (WSTG, PTES, MASTG, … from the scope objects
  and checklists). It regenerates from the deck, so it always matches the report.

### Trusted timestamp (RFC 3161)

Once a report is finalised and sealed, its content is protected by a SHA-512 hash.
To anchor that hash to a point in time, the **RFC3161-tijdstempel** command opens a
small dialog that lets you:

- **Export a request (`.tsq`)** — a timestamp request over the seal hash, which you
  hand to OpenKAT or any RFC 3161 timestamp authority (TSA) out-of-band.
- **Import the token (`.tsr`)** — the token the TSA returns. OciDeck verifies it
  offline (its message imprint must equal the current seal hash) and, when it
  matches, stores it in the deck (`ocideck_seal_tsr`) and shows the timestamp.

This keeps OciDeck a *producer of hashes* — it never has to contact the TSA itself.
The stored token is verified again every time the deck opens, so a "timestamped on
…" or "does not match" status is always shown (PENTEST_MIAUW §8-A2).

### Security theme

A built-in **Security** theme profile ships a clean, professional report look and
severity colour tokens (Critical / High / Medium / Low / Informational). The
tokens drive finding cards, CVSS badges and the findings-summary chart, and can be
retuned per profile under *Settings → presentation style → Severity (bevindingen)*.

## Markdown mode

The toolbar code icon switches the editor to **Markdown mode**: the whole deck is
shown as one Marp Markdown document (the same structure OciDeck writes to disk).
Use this for bulk edits, copy-paste from another tool, or tweaks that are faster
in raw text. Switch back with **Apply** (to parse the text back into typed slides)
or **Cancel** (discard your edits and return to the visual editor).

### Whole presentation or a single slide

A sliding toggle at the top of the markdown editor chooses the **scope**:

- **Full presentation** — the entire deck as one document (the default), for
  bulk edits and front-matter changes.
- **This slide** — only the currently selected slide, shown without front matter.
  The label carries the slide number (e.g. `This slide · 3/12`). Selecting a
  different slide in the rail reloads its markdown; switching scope is animated.

Both scopes edit and check the same way. **Apply** in *This slide* scope parses
just that fragment back into the deck, replacing the one slide — and if you add
`---` separators it splits into several slides. Editing and applying discard the
same way as the whole-deck view: unapplied fragment edits are lost when you
switch slides or scope, and only what you **Apply** changes the deck. User notes
and ink annotations re-anchor to the reparsed slide exactly as in whole-deck
mode.

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
- **App appearance** (a dark interface, the accent and panel colours, and the
  **interface font** — Roboto, Inter, Lora or EB Garamond, all bundled so the
  choice also holds on the web build) is configurable in settings. Create a
  custom app theme (the built-ins are read-only) to change them.
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
