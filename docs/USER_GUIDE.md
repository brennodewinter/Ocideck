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
- **Opened from a URL**: a deck fetched from a web address (the URL import, or a
  `?deck=…` share link on the web build) shows an **“Extern”** privacy badge in
  the status bar. Opening such a link made your device contact that server;
  hover the badge to see the source host. Decks you open from your own disk carry
  no badge.
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

## Storage

Everything about *where your decks live* sits under *Settings → Storage*, as one
list: **File connections**.

A connection is a place your presentations come from and go to. Folders on this
computer, WebDAV servers and git repositories all sit in that one list, mixed
together — because the question you actually ask is "where does this client's
work live?", not "which protocol is this?". Give each one a name (*Client A –
Nextcloud*, *Private*) so you can tell them apart at a glance.

- **Add** one with *Add connection* and pick the kind. A folder is done as soon
  as you pick it; a WebDAV server or git repository opens its settings straight
  away so you can fill them in.
- **Order matters.** Drag connections with the handle on the left. The topmost
  usable connection *of each kind* is the default for that kind: it is the
  library that opening and saving start from, and the server the app reaches for
  when it doesn't ask. So promoting a connection is how you say "this client is
  what I'm working on now" — without deleting anything.
- **Every row shows its status**: the folder name, the server host, or
  `owner/repo`, in green once the connection is usable and grey while it is
  still incomplete. A half-filled connection stays in the list; it just doesn't
  count as a usable source.
- **Export folder** is where exports land. Leave it empty and they land next to
  the presentation file.

When an action needs a server and you have more than one of that kind, OciDeck
asks which. With exactly one it doesn't ask at all, and a deck you opened from a
connection saves back to that same connection without asking either — that goes
for git as much as for WebDAV. Actions that belong to an open deck (its history,
its versions, review, merge, tagging) never ask: they follow the repository the
deck came from. If you deleted that connection, OciDeck says so rather than
guessing at another one.

Upgrading from an older version needs no work: your libraries, your WebDAV
server and your git repository become connections in that order, so the ones
that were the default stay the default.

The two network kinds are described in full below.

## Git repository

You can open decks from a git repository — your own Forgejo, for now. Every
saved version stays retrievable, which a plain folder cannot give you.

- **Set it up** on a git connection in *Settings → Storage*: the server URL
  (`https://git.example.org`), the owner (user or organisation), the repository
  name, and a **personal access token**. Scope the token to just that repository
  where your forge supports it. It is stored encrypted in your operating
  system's keychain, not in the plain settings file. A public repository needs
  no token at all.
- **Self-hosted on a private address**: tick **Trusted internal server**, the
  same safeguard as for Nextcloud.
- The git entries below only appear in the `…` menu **once a repository is
  configured**. Until then they are hidden rather than shown-but-failing, so the
  menu never offers an action that cannot succeed.
- **Open** via the `…` menu (*Open from git…*): pick a deck and it is fetched,
  checked by the same safety scan as any other deck, and opened. A repository is
  untrusted input — coming from your own forge does not make it trusted.
- **Save** via the `…` menu (*Save to git…*): the deck is written back as one
  commit — the markdown and its images, which go into the shared pool exactly as
  opening reads them. A deck you opened from git offers its own name and updates
  in place; a new deck is published by choosing a name (it becomes
  `decks/<name>`). If someone moved the branch since you opened it, the save is
  refused so you do not overwrite their work — reload and save again. Video and
  audio are not written yet; you are told when a deck has them.
- **Lose your connection while saving** and the deck's text is kept locally and
  queued instead of failing — you see "saved, syncs when you're back online".
  The queue survives closing the app; it empties on your next successful save
  and via *Sync now* in the `…` menu. An image you add while offline is pooled
  and committed when the queue syncs, so a reconnect gets the whole deck —
  unless you close the app first (an unsaved in-memory image does not survive a
  restart, the same limit a plain saved deck already has). Your text is always
  safe.
- **Which forge**: pick the **forge type** on the git connection in *Settings →
  Storage* — Forgejo/Gitea, GitHub, or GitLab — next to the server URL, owner
  and repository. Everything
  below works the same whichever you choose; only the token differs (a personal
  access token in all three, but each calls it something slightly different). On
  GitLab the deck browser cannot show file sizes: its listing does not include
  them.
- **Layout**: a repository holds many decks under `decks/<name>/deck.md`, with
  images shared in one `assets/` pool so the same picture is stored once.
- **Editing happens on a concept branch — *Uitbrengen ter review…*.** When you
  edit a deck opened from git, your saves do not land straight on the main
  branch. The first save of an editing round starts a dated *concept* branch
  (`decks/<name>/<date>`) and every save goes there; you never have to name or
  pick it. This works the same on the REST and native-git planes, and stays
  offline-safe — a round can begin on a plane and the branch is created for you on
  reconnect. When it is ready, *Uitbrengen ter review…* in the `…` menu opens a
  pull request from your concept to the main branch, so it can be reviewed before
  it goes out; you get the link back. If your organisation has set a TLP release
  ceiling, the release is checked against the **strictest** classification
  anywhere in the deck (a single `TLP:RED` slide counts), and a deck over the
  ceiling is refused before anything is pushed.
- **Merge the concept and record the version — *Concept mergen…* and *Versie
  vastleggen…*.** Once the review is done, *Concept mergen…* merges the pull
  request into the main branch (you can let it clean up the concept branch) and
  puts your tab back on the main branch, so your next edit starts a fresh round.
  *Versie vastleggen…* then records the version you presented as a release tag
  (`decks/<name>/vX`) on the main branch — the same versions *Versies…* lists and
  opens read-only. Recording a version passes the same classification check as
  releasing for review, so a version can never be tagged past its ceiling.
- **If someone else edited at the same time, it merges.** Saving no longer sends
  you back to reload. OciDeck compares what you started from, what you made of
  it, and what they made of it, and merges the two. Edits to different slides,
  identical edits, and reorderings resolve by themselves and your save simply
  goes through. Only slides you both changed differently — or where one of you
  deleted what the other edited — are put to you as a choice per slide, with your
  own version kept until you pick. Neither side's work is thrown away. If the
  deck's classification differs, the stricter of the two wins. This works both in
  the browser and on desktop with native `git`; on desktop it becomes a real
  merge commit, so `git log` shows the two lines of work coming together.
- **Native git (desktop):** if you have `git` installed (2.19 or newer),
  the git connection in *Settings → Storage* shows it, and OciDeck keeps a real
  clone of the repository.
  Then **each save is a genuine local commit** — durable and offline: edit away
  from a network, save as often as you like, and every commit is waiting to push
  when you reconnect (*Sync now*, or automatically on your next successful save).
  If someone moved the branch while you were offline, your commit is kept safely
  on your machine and the sync is held rather than overwriting their work. On the
  web, or a desktop without `git`, the REST path above is used and nothing
  changes. On macOS the check looks for the Xcode command-line tools first, so it
  never prompts you to install anything. Once a deck is open from git this way,
  *Git history…* in the `…` menu shows its commit timeline, with a badge on each
  commit for whether it is on the forge yet or still waiting to push.
- **Open an earlier version — *Versies…*.** When a deck has been released as a
  version, *Versies…* in the `…` menu lists those versions, newest first. Pick
  one to open it **read-only**: a snapshot of how the deck was at that release,
  to look at — not something you can save over, so reviewing an old version can
  never overwrite your current work. This works in the browser too.
- **Compare two versions — *Vergelijken…*.** In that same list, *Vergelijken…*
  lets you pick two releases and see what changed between them: slides added,
  removed, changed or moved. A deck has no slide IDs, so slides are matched on
  their content — an identical slide is recognised even if it moved, and a
  reworded slide shows up as one *changed* entry instead of an addition plus a
  deletion. For a changed slide, *Verschillen* shows the two side by side with
  the differing fields listed.
- **Search every deck — *Zoeken in alle decks…*.** Find & replace works inside
  the deck you have open; this searches every deck in the repository. Each hit
  names the deck and the slide it is on, with the line it was found in, so you
  can tell a passing mention from the slide you actually wanted. Pick a hit and
  that deck opens. Two things it will tell you rather than hide: if a deck could
  not be read it is named as skipped (the hits you do see are still real), and
  if there were more hits than fit it says so instead of quietly cutting the
  list. Searching reads every deck in the repository, so it runs when you press
  *Zoeken* — not while you type.
- **Which decks use an image — *Afbeeldingen in de repository…*.** Images are
  stored once and shared by every deck that uses them, so before you touch one it
  helps to know who else depends on it. This overview lists every image in the
  repository with the decks that reference it. Three answers are possible, and
  the difference matters: a deck uses it; no deck uses it any more but a
  *released version* still does (removing it would break a version you already
  presented); or nothing references it at all. That last group is listed at the
  bottom as a suggestion — it is what this branch can see, and another branch may
  still be using them. If a deck or a released version could not be read, the
  suggestion list is withheld entirely and the overview says which one was
  unreadable, because the unreadable one could be the single user of an image and
  a deletion cannot be undone. Removing an image stays a manual act; this screen
  only tells you what you would be removing.
- **A repository is a trust boundary.** Everyone who can read it reads *every*
  deck in it, so use one repository per client, engagement or classification
  level — the forge's permissions are what separate them, not OciDeck.

Unlike WebDAV, this also works in the browser version.

## WebDAV

You can use a folder on a WebDAV server as a source for decks and assets.
Nextcloud is the most common one, but any WebDAV server works.

- **Pick the server type** on the WebDAV connection in *Settings → Storage*.
  This is the only thing that differs between servers — the protocol underneath is plain WebDAV
  either way:
  - **Nextcloud or ownCloud** — enter just the server URL
    (`https://cloud.example.com`). The DAV path
    (`/remote.php/dav/files/<username>`) is derived for you.
  - **Other WebDAV server** — there is no path to guess, so the path you put in
    the server URL *is* the WebDAV root
    (`https://dav.example.com/dav/files`).
- **Fill in the rest**: your username, your password, and an optional subfolder.
  On Nextcloud, use an **app password** (create one under *Settings → Security*)
  rather than your login password. Use **Test connection** to check it before
  saving. The password is stored encrypted in your operating system's keychain,
  not in the plain settings file.
- **Self-hosted / home server**: if the server runs on a private or LAN
  address, tick **Trusted internal server** — otherwise the connection is
  refused (the same safeguard that stops a deck from reaching internal hosts).
- **Open** via the welcome screen (*Open from WebDAV*) or the `…` menu:
  browse the folder and pick an `.ocideck` package or a Marp `.md`. The file is
  downloaded, checked by the same safety scan as any other deck, and opened in a
  tab.
- **Save back** with *Save to WebDAV* (`…` menu). Choose a target path and a
  format: a single **`.ocideck` package** (one file, assets included) or a
  **flat `.md` plus its asset folders** (`images/`, `themes/`, …) mirrored into
  the same folder. A deck opened from WebDAV remembers where it came from, so
  saving suggests the original location.
- **If someone else got there first**: saving back to the file you opened only
  goes through if that file hasn't changed on the server since. If it has, you
  get a choice — *Save as* (keep both versions) or *Overwrite* (discard theirs).
  Nothing is overwritten silently. Servers that don't report a version (an
  `ETag`) can't be checked; there you keep the old behaviour of a plain write.

## Slide types

Add a slide and pick a type: **title**, **section** divider, **bullets**, **two
bullet columns**, **bullets + image**, **two images**, **large image**, **video**,
**quote**, **table**, **source code**, **chart** (bar, horizontal
bar, stacked bar, horizontal stacked bar, combo, line, area, pie, donut,
spider/radar, scatter, waterfall, or heatmap/risk matrix), **cockpit** (a
dashboard of aviation-style instrument gauges),
**question** (an interactive quiz slide), **timeline** (an animated timeline of
dated events), and
**free Markdown**. Each card in the chooser shows a miniature
wireframe of the layout, and the dialog works entirely with the keyboard
(`Tab`/`Enter` to choose, `Esc` to cancel). Each type has a dedicated editor on
the left and a live preview on the right. You can change an existing slide's type
at any time from the **TYPE** control in the editor header: it opens the same
chooser, so adding and re-typing a slide always offer exactly the same set of
types. (Both pickers are category-filtered: the five Informatieveiligheid types —
finding, findings-summary, checklist, scope matrix and sign-off — appear only once
the security module is enabled; see the pentest-reporting section below.)

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

### Bullets and lists

A bullets slide has an optional title and subheading and a list you edit row by
row: **Enter** adds a bullet, **Tab** / **Shift+Tab** indents, drag the handle to
reorder. The list style picker switches the whole list between plain **bullets**,
**numbered**, a **checklist** (tick-boxes with an optional progress bar), and
**rich text** (a free-Markdown body). Plain bullets can use a dot or a cat-paw
marker.

**Group headings ("tussenkoppen").** To split one slide's bullets into visually
separated groups — an agenda's *morning* and *afternoon*, pros versus cons —
click **Tussenkop toevoegen** (Add group heading), or turn any row into one with
the divider button on its left. A group heading renders as a bold accent label
above a thin rule; leave its text empty for a **wordless divider** — just the
rule, a plain break between two groups. Headings carry no bullet, checkbox or
number, and don't count toward the list. They work the same on plain, numbered
and checklist lists and in two-column and bullets-with-image layouts, and they
travel with the deck in the `.md` (see FILE_FORMAT § Bullets).

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

Pick a type and a title, then enter data in the grid: the first column is the
labels, each further column is a named series. Use **Row** and **Series** to add
data; the small ✕ removes a row/column. Each series and (for pie/donut/radar)
each label can be given its own colour.

The available types:

- **Bar**, **stacked bar**, **line**, **area** (a filled line), **scatter** —
  cartesian charts (labels on the x-axis, values on the y-axis).
- **Horizontal bar** — bars laid left-to-right; best for rankings and long
  category names.
- **Horizontal stacked bar** — a stacked bar turned a quarter turn: one bar per
  label with the series stacked left-to-right. Best for part-to-whole
  comparisons with long category names; a wide enough segment prints its value.
- **Combo** — bars for every series **except the last**, which is drawn as a
  line on its own right-hand axis (e.g. revenue bars + a growth-% line). With a
  single series it falls back to a plain bar chart.
- **Pie** / **Donut** — proportional slices; the labels are the segments. A
  donut prints the series total in its centre hole. Both show at most the first
  two series.
- **Spider/radar** — needs at least three labels (axes); each series is a
  filled area.
- **Waterfall** — uses the **first** series; each value is an up or down step
  that builds on the previous running total (green up, red down). Good for
  budget/bridge stories.
- **Heatmap** — a coloured grid: each series is a row, each label a column, the
  cell colour follows the value. Label the axes *likelihood* and *impact* and it
  serves as a **risk matrix**.

- **CSV import** — click **CSV importeren** to fill the grid from a CSV file.
  Where the data ends up is not something you have to decide: see below.
- **A separate data file** — chart data is kept in a file in the deck's `data/`
  directory, and the presentation itself keeps only a reference to it. That is
  what keeps a `.md` readable when a chart has forty rows, and what makes its
  changes legible in version history.

  This happens by itself when you save; older presentations move over the first
  time you save them, and you should not notice anything. The file is named
  after the chart's title, and keeps that name afterwards even if you rename the
  chart. A chart you have not put any numbers in yet gets no file.

  You lose nothing by linking. The grid stays fully editable — edit it and the
  file is rewritten when you save. You can just as well edit the file itself, in
  a spreadsheet or by hand, and the app picks it up next time the deck opens.
  The two do not fight: saving only rewrites a data file whose numbers you
  actually changed in the app, so an edit you made elsewhere while the deck was
  open is still there afterwards.

  New data files are written as JSON. A deck that already uses a `.csv` keeps
  using CSV, so anything else pointing at that file keeps working. Colours,
  title and min/max stay with the slide, never in the data file — so you can
  replace the file wholesale without the chart losing its look.

  **Ontkoppelen** (unlink) brings the numbers back into the slide.
- **What the CSV may look like** — comma, semicolon and tab separated files are
  all read; the separator is detected per file, so a Dutch Excel export (which
  uses `;`) needs no conversion. A value may be wrapped in double quotes to hold
  a comma, as in `"Amsterdam, NL"`, and `""` inside such a value is one literal
  quote. A line break *inside* a quoted value is not supported. With a semicolon
  or tab separator a comma is read as a decimal mark, so `10,5` is ten and a
  half.
- **Thousands and decimals** — `1,234` is one thousand two hundred thirty-four
  in one country and one-point-two-three-four in another. OciDeck works it out
  from the file as a whole rather than from the one cell: a `10,5` somewhere in
  the same file proves the comma is a decimal mark, a `10.5` proves it groups
  thousands, and `1.234,56` settles itself because the last mark is always the
  decimal one. Nothing is assumed from your language or your region.

  When the file genuinely does not say — every comma followed by exactly three
  digits, so `1,234 · 2,500 · 12,000` reads equally well either way — the import
  **asks**, showing what those very numbers become under each reading. Closing
  that question cancels the import rather than picking one for you.
- **Values that are not numbers** — a cell such as `12%` or `€ 1.000` cannot be
  read as a number at all. It is charted as 0 **and named after the import**, so
  you can correct it at the source rather than discovering a wrong chart on
  stage. An empty cell is left alone — that is a missing value, not a mistake.
- **Min/max** (optional) — offered for the cartesian types (bar, line, area,
  scatter, combo, waterfall) and radar. On the cartesian charts they draw
  horizontal **reference lines**; on a spider/radar chart they fix the **scale**
  (centre to outer ring). They are not shown for pie, donut, horizontal bar,
  horizontal stacked bar, or heatmap. Leave them empty to scale automatically.
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
events. **PTES-fasen laden (Load PTES phases)** seeds the seven Penetration
Testing Execution Standard phases (Voorafgaande afspraken → Rapportage) as
ready-to-edit events, keeping any events you already have.

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

When an embedded video does not play, the slide now **says why** instead of
showing a blank rectangle: the owner disabled embedding (by far the most common —
the clip can only be watched on YouTube/Vimeo itself), the video was removed or is
private, the link is invalid, or there is no connection to the source. While a
valid embed is still loading you see a small spinner, so a slow load is no longer
mistaken for a broken one.

The same Security tab has **CVE opzoeken (online)** for the finding editor's
**Zoek CVE…** action — also off by default, and additionally gated on your
consent. When on, you can set the **CVE mirror** base URL (default
`https://cveapi.librekat.nl`). The lookup is SSRF-safe and desktop-only.

A **privacy badge** (the PrivacyKat shield) sits next to that switch, and hovering
it says what turning it on costs you: your search term goes to the configured
mirror, and *if that mirror finds nothing, the same term is then sent to ENISA and
MITRE as well*. Whoever runs those servers can infer which specific vulnerability
you are looking for — which, for a pentester, is often the most sensitive thing
they know. The badge blocks nothing; it makes the trade visible before you take it.

### The local CVE database (offline lookup)

The way to not disclose which vulnerability you are researching is to stop asking
anyone. Under *Settings → Beveiliging → **Lokale CVE-database*** you can put the
**whole CVE list on your own device**. Once it is there, **Zoek CVE…** searches
locally and **nothing leaves your machine** — no search term, to nobody. It does
not even need the online-lookup switch: offline search needs no permission,
because it sends nothing.

It also does **not** quietly fall back to the internet when a local search finds
nothing. That would leak the very term you kept local, at exactly the moment you
were looking for something unusual.

**What it costs you — read this before you press the button.** The source is
**CVE List V5**, the official CVE Program list, published on GitHub:

| | |
| --- | --- |
| **Download** | ~550 MB (the full daily archive) |
| **Disk, during the build** | ~1.5 GB temporarily (it is a zip inside a zip) |
| **Disk, afterwards** | a few hundred MB (the index; the archives are deleted) |
| **Time** | ten to thirty minutes, depending on your connection and machine |
| **Records** | 300,000+ CVEs |

On a metered connection, don't. The app asks you to confirm, with those numbers,
before it starts — and shows a progress bar with the phase it is in (finding the
latest release, downloading, unpacking, indexing) and a **Afbreken** (Cancel)
button. Cancelling or failing part-way leaves **nothing** half-installed: a
partial index is thrown away and an existing working one is left untouched.

Once built, the card shows how many CVEs you have, how big the index is, which
release it came from and when it was built. **Bijwerken** rebuilds it from the
latest release; **Verwijderen** removes it.

**Desktop only.** The feature does not appear on the web build at all — there is
no filesystem there for an index of this size, and a 550 MB download has no
business in a browser tab. Rather than show a button that cannot work, the web
build hides the section.

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

Both notes blocks **start collapsed on a slide that has none, and start expanded
on a slide that has them** — so the block is open exactly when there is something
to read. Expanding or collapsing by hand sticks while you stay on that slide (and
on that page of a multi-page rich-text slide); moving to another slide asks the
question again for that slide.
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

## Privacy check

OciDeck reads your slides for data that may be privacy-sensitive — identification
numbers, contact details, addresses and names, bank accounts — and reports what it finds in the
**quality panel**, alongside the contrast and readability checks. Each privacy
row carries the **PrivacyKat shield** mark instead of the generic warning icon,
so at a glance you can tell a personal-data finding from a contrast or density
one. It is on by default and can be switched off under *Settings → Security →
Privacy check*.

It runs **entirely on this device**. Slide content is not sent anywhere, no
findings are kept outside the session, and no statistics leave your machine.

### It never shows you the value it found

A finding says *what kind* of data it saw and where, with a masked fragment
(`j…l`) — never the value itself. A privacy check that lists the citizen service
numbers it found has moved the problem, not solved it.

### Why some findings are only a hint

The BSN check is the clearest example of the design. A citizen service number is
validated by the *elevenproof*, but roughly **one in eleven random nine-digit
numbers passes that test** — order numbers, invoice numbers, customer numbers.
A scanner that warned on all of those would be switched off within a week, and
then it detects nothing at all.

So the check needs both the checksum **and** a context word nearby ("BSN",
"burgerservicenummer"):

- checksum **and** context → a real warning;
- checksum but no context → an informational hint, which interrupts nobody.

Phone numbers follow the same three-step logic. In international form (`+CC`
followed by the national number) the calling code is checked against the list of
*assigned* ITU country codes together with a valid E.164 length — that is a real
validation, so it becomes a proper warning. A national number needs a separator
(`06-24681357`); a bare run of digits needs a context word ("tel", "mobiel",
"phone"), because `0417164300` on its own is just as likely to be an old bank
account number.

(You will notice this manual never prints a real-looking international number.
That is deliberate — and the check would flag it if it did.)

The same reasoning runs through everything: known example values are ignored on
purpose. The example IBAN from every Dutch banking manual, the official test-BSN
range, the card schemes' test numbers, `example.com` addresses, the reserved
"drama" phone ranges that films and manuals use (`555-01xx`, `+49 30 23125 xx`) —
none of them belong to anyone, and a deck that lights up red on its own demo
content destroys your trust in every other finding.

### A special-category datum is a statement, not a word

When health, criminal, religious or union data is traceable to a person on the
same slide, redaction takes the **whole line**, not just the keyword that fired.
Blanking only the word would leave you with

> Marieke de Vries reported sick with a ████████

— the name is still there, the sick note is still there. Nothing was removed; a
word was covered. So the whole statement goes.

### It is an aid, not a guarantee

**The check does not guarantee that everything is found; it reduces the chance
that personal data leaks out unintentionally.** That sentence is the whole promise,
and it is deliberately the smaller of the two you might have expected.

The check does not read text inside **images**, does not open **linked files**,
and cannot see sensitive information without a recognisable pattern. A slide with
no findings is a slide in which *we* found nothing — not a slide that is proven
clean. The green *Ready to export* means the checks we run found nothing to say;
it does not mean the deck is safe to send.

So the decision about what you share, and the responsibility for it, stay with
you. A tool that let you outsource that judgement would be more dangerous than no
tool at all — you would stop looking.

Found something you want gone? Wrap it in double square brackets — see below.

## What to do with a finding

A finding is not a verdict. A police briefing contains personal data by
definition; a pentest report contains captured credentials by definition. The
tool should not fight you about that — but it should let you say what you decided,
and it should let the *recipient* know what they are holding.

Under **Slide settings** (the gear in the editor header), each slide offers:

| Setting | What happens |
| --- | --- |
| **Follow the presentation** | Inherit the deck-wide setting (the default). |
| **Only report** | Findings stay in the quality panel; nothing shows on the slide. |
| **Accept** | The data belongs here. The notice disappears. Nothing changes on the slide. |
| **Accept + warn** | The data stays, and the slide gets a **PERSONAL DATA** badge — the PrivacyKat shield mark next to the TLP marking, travelling into the PDF, the PPTX and the HTML. Whoever receives the deck knows what they have. |
| **Leave out of display and export** | The data found is redacted everywhere: screen, presentation, audience window, PDF, PPTX, HTML, speaker notes, document metadata. Your Markdown keeps the original text. |

The same four values exist deck-wide (`privacy:` in the front matter). A slide
**overrides** the deck — unlike TLP, where the stricter level wins. A deck set to
*accept* (the whole briefing is known) with one slide set to *leave out* (this one
detail is for nobody) has to just work, and the author of that slide knows best.

### Before you export

If the deck still holds findings you have not decided about, OciDeck says so
before writing the file: how many are unresolved, and — just as important — how
many you *did* handle (accepted, warned, redacted). You can go past it deliberately.

Under *Settings → Security* you can also set this to **do nothing**, or to **block
the export** until every certain finding has a choice. Blocking is enforced at the
export chokepoint itself, not only in the dialog: a gate that lives only in a
dialog is not a gate.

The **status bar** carries this gate too, next to the classification and quality
gates: it counts the findings still without a choice, and turns red when the gate
is set to block. Before, that corner could read a green *Ready to export* while a
blocking privacy gate was waiting one click away — the status bar promised the
opposite of what the export would do. It no longer can.

The point of the gate is narrow, and worth stating: **it does not punish personal
data, it punishes *unnoticed* personal data.** A police briefing where everything
is deliberately accepted goes through without a peep — otherwise you would learn
exactly one thing, which is that this dialog can be clicked away. Informational
hints never hold up an export either: we said ourselves that we are not sure about
those.

### Switching off a single rule

If one rule keeps misfiring on your content — an order-number format that trips the
BSN check, say — click **Never report this rule again** on the finding itself. The
rule is switched off and stays off, and you can turn it back on under
*Settings → Security*, where the disabled rules appear as chips.

This escape hatch matters more than it looks. Without it, the only way out of a
noisy rule is switching off the whole check — and in practice that is a one-way
door: once it is off, nobody turns it back on. A surgical switch keeps everything
else working.

**A disabled rule is not redacted either.** That is deliberate, and it is the
opposite of the master switch below. The master switch says *don't bother me*,
which is not a judgement about your content, so a deck set to *leave out* keeps
redacting. Switching off a rule says *this rule is wrong about my content* — and
honouring that means we must not black it out either. Someone who disables the BSN
check because their order numbers trip it does not want those order numbers blacked
out in the export.

### Rules that start out off

Three of the heaviest article-9 categories — political opinion, ethnic origin and
sexual orientation — are **off by default**. Not because they matter less; because
their keywords appear far too often in ordinary business language. A slide about
diversity policy is *about* ethnicity without containing any ethnic data.

They are there, and one tap under *Settings → Security* turns them on. That choice
belongs to you, not to us.

### Turning the warnings off does not turn redaction off

The privacy check can be switched off under *Settings → Security*. That switches
off **warnings** — it does not switch off redaction. A deck that says *leave out*
keeps leaving data out, even for someone who never wants to see a notice.
Otherwise you could silence the messages and leak your briefing without noticing.

### Accepting is not consent for an AI backend

If you use the optional AI assistance, everything the scanner finds is stripped
before the text leaves your device — **even on a slide you marked as accepted**.
Deciding that a room may see a name is not deciding that a language model may.

## Two versions from one source

When a deck holds findings, the export dialog asks **who this export is for**:

| Profile | What comes out |
| --- | --- |
| **Full** | Only what you set to *leave out* is removed. Everything else stays readable — so the client or auditor can actually verify the findings. |
| **Redacted** | Everything the check finds is removed, including on slides you accepted. "This room may see it" is not the same as "everyone may see it". |

This is the heart of the pentest-report case, and without it you would have to
choose *between* those two — at which point the full version always wins, because
that is the one that has to go out the door.

The profile lands in the **filename** (`report-geredigeerd.pdf`). That is not
cosmetic: the most expensive mistake you can make with this feature is sending the
full copy to the wider circle. A mix-up should be something you can *see*, not
something you have to remember.

The redaction manifest follows the profile too, so a redacted report stays
verifiable against the source — see below.

## Redaction — leaving data out

Some decks carry things the room should not see: a citizen service number in a
police briefing, a captured credential in a pentest report, a customer's address
in a training deck. Wrap that text in **double square brackets** and OciDeck
leaves it out of everything it shows and exports.

```markdown
The suspect, [[Jan de Vries]], was arrested at [[Kalverstraat 12]].
```

On the slide, in the presentation, in the audience window, in the PDF, the PPTX
and the HTML you get `████████`. Anywhere.

### It is left out, not covered up

This is the part that matters, and it is where most redaction goes wrong. A black
rectangle drawn over text is not redaction — the text is still in the file, one
copy-paste away. OciDeck removes the characters *before* anything is rendered or
written, so:

- the PDF has **no text layer** under the blocks — they are pixels;
- the PPTX **speaker notes** (`ppt/notesSlides/…`) do not contain the value,
  even though they are plain text in the file and invisible on the slide;
- the HTML **source** does not contain it — not in the embedded Markdown, not in
  a `<meta>` tag, not behind a CSS rule;
- the **document metadata** (title, author, keywords in the PDF/PPTX properties)
  does not contain it either;
- a **screen reader** cannot read it, because it never reaches the widget tree.

A test in the suite exports a deck with a known value and searches for it in
every one of those places. If it ever shows up, the build fails.

### Your file keeps the original

Redaction applies to what you *share*, never to what you *store*. The Markdown on
disk keeps `[[Jan de Vries]]` exactly as you typed it, so you can lift the
brackets later, or produce a full version for the client and a redacted one for
wider distribution from the same source. Saving a deck after redacting changes
nothing about its contents.

### Live table editing is off on a redacted slide

A slide with a redaction cannot be table-edited during a presentation. The
presenter writes a live edit back to the deck as a whole slide, and it only ever
saw the blocks — writing that back would overwrite your own data. A surface that
cannot see the data may not write it back either.

### What it does not do

Redaction only removes what you mark. It does not read your images: a screenshot
with a name in it stays a screenshot with a name in it. And a `~~strikethrough~~`
is not a redaction — it is styling, and the text travels with the file.

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
  the configured AI backend — draft-only, marked as an AI concept and cleared for
  sealing only after you review it; a **Wis AI-alt-teksten** command removes every
  still-unreviewed AI draft in one undoable step.
- **Slide quality** — while you edit, OciDeck continuously checks the deck for
  accessibility and readability problems. See the subsection below.

### Slide quality

The **Slide quality** bar sits below the editor preview. It summarises open
issues and can be expanded to browse them. Filter chips let you show **All
issues** or only **Errors**, **Warnings**, or **Tips**. Click a slide-specific
issue to jump to that slide and focus the relevant editor field; click a **theme
(entire presentation)** issue to open *Settings → Presentation style → Colours* with the matching
colour field scrolled into view and highlighted.

Issues also appear as badges on slide thumbnails, as a blue badge when a slide
has **user notes**, and as inline hints on relevant editor fields (for example
image captions).

### The two thumbnail badges

A thumbnail carries up to **two** badges, top right. The left one is quality
(the accessibility mark); the right one is privacy (the PrivacyKat shield).

They used to be one. That made the badge unreadable: the same amber dot could
mean contrast, or text density, or a citizen service number in the text. Someone
checking a deck for personal data could not see which slides were about that —
and someone looking at a contrast warning could think it was about personal data.

| Colour | Quality | Privacy |
| --- | --- | --- |
| **Red** | An error is included | — |
| **Amber** | Warnings | A finding we are reasonably sure about |
| **Slate** | — | A finding we are *not* sure about |
| **Grey** | You accepted these findings | You accepted these findings |
| *(none)* | Only tips, or nothing found | Nothing found |

The asymmetry in the slate row is deliberate. A quality tip is advice about
craft — "this bullet holds two sentences" — and a badge on every slide with a tip
makes the whole rail loud without telling anyone anything. An uncertain privacy
finding is a *possible personal datum*. Those are not the same stakes, so they do
not get the same threshold.

**Grey means found-and-decided, not clean.** Before, accepting a finding made the
slide go silent everywhere: the notice left the panel *and* the badge left the
thumbnail, and afterwards that slide looked exactly like a slide with nothing on
it. Accepting had become the same as hiding. The badge now stays and turns grey —
it says *there is something here, and you know about it*. The panel does go quiet,
which is right: a decision already made should not keep nagging.

### Reading and answering a badge

**Click** a badge to see what is behind it: the findings on that slide, each with
the rule, the field it sits in and a masked fragment — *"bank account number
(N…6), Bullets 3"* rather than a coloured dot. The list reads the raw results, so
a grey badge opens a full list too. A grey badge you cannot read would be as
uninformative as no badge at all.

Clicking a finding in the **quality panel** goes one step further: it jumps to the
slide, focuses the field and *selects the reported text*, so you see exactly which
characters the finding is about.

**Double-click** decides. On a coloured badge you accept what is there; on a grey
one you take that acceptance back. It works both ways on purpose — a decision you
cannot undo with the same gesture is one you do not dare to make.

Two exceptions, both deliberate: double-clicking does nothing on a slide set to
*leave out of display and export* or *accept + warn*. Those settings do something
to the data itself or to the recipient, and undoing them with a double-click would
put redacted personal data back into your export without anyone asking for it.
That choice belongs in **Slide settings**, where you can see what you are picking.

### Accepting quality findings

Quality findings can be accepted per slide, the same way privacy findings can. A
title image that deliberately contrasts softly, a table that genuinely has that
many rows — until now there was nothing to say about those. The notice stayed, the
badge stayed amber, and the only thing you learned was that badges can be ignored.

Accepting turns the badge grey, keeps the findings readable, and takes them out of
the export gate. It is stored per slide as `<!-- ocideck_quality: accept -->`; see
FILE_FORMAT.md §3.1c. There is no deck-wide equivalent — a deck that accepts every
contrast error at once is not a judgement, it is a switch, and that switch already
lives under *Settings*.

When the green bar shows no issues, expand it to see **which checks ran** —
contrast, alt text, media files, text density, and (when it is switched on) the
privacy check. If the privacy check is **off**, the panel says so there rather
than silently leaving it out: a green "nothing found" must never be mistaken for
"nothing was looked for".

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
| **Alt text** | tip / warning | Charts: no title, series names, or linked data description. Images: no alt text, caption, title, or speaker notes describing the content. Video slides are **not** nudged for a description — a clip that speaks for itself needs no title. Missing image captions are not reported as quality issues. Missing image or video **files on disk** when the deck is saved in a project folder (path in the slide points to a file that is not there). An **online** source (`http(s)` URL, including YouTube/Vimeo) is never reported as a missing file. |
| **Text density** | error / warning | Bullet slides (one column, two columns, bullets + image): auto-fit shrinks text below 70% of design size (warning) or 20% (error), or the slide has too many bullets/words, long prose-like bullets, multiple sentences in a bullet, deep nesting, or strongly imbalanced two-column content. Also a slide that is *dragged down by its split run* (see below). Rich-text and free-Markdown list items use the same bullet readability checks. Tables: cell text at the minimum readable size. Source-code and free-Markdown slides: very long content. Title slides: long title + subtitle combined. Quote slides: long quote + author combined. |

Theme-wide contrast issues are listed once for the whole deck; slide-specific
issues name the slide number.

A too-dense bullet slide offers a one-click **Split slide** fix (also available
from the slide thumbnail's menu). It spreads the bullets over as many evenly-sized
pages as needed so no page is left over-full: a list twice the readable optimum
splits in two, a longer one into three or more, and a list whose bullets barely
fit (only a couple at full size) into pages of just those few. Page breaks land on
group headings, so whole **tussenkoppen** groups stay together on a page rather
than being cut in half. Splitting a **bullets + image** slide keeps the image on
every continuation page too, so all pages match and share one font size — swap a
follow-up to a plain bullets page via the slide **type** picker if you prefer.
Two-column slides spread both columns across the same set of pages.

A bullet slide with multi-sentence or overly long bullets offers two more
one-click fixes in the quality panel. **Split sentences into bullets** turns each
multi-sentence bullet into one bullet per sentence — every word stays on the
slide. **Explanation to notes** does the opposite: for a bullet shaped like
*label : explanation* (split on a colon, a spaced hyphen, or the first full stop,
when the explanation is at least a few words) it keeps just the label on the slide
and moves the full original line to the speaker notes — the point survives where
you can still say it, and one undo brings it back.

#### A slide that is dragged down by its split run

The pages of a split run share **one** font size — the size of the fullest page —
so a list spread over several slides does not change size halfway through. That is
the point of a split, but it has a failure mode: if one page in the run is far
fuller than the rest, it pulls every other page down with it. A short slide with
five bullets can end up rendering at 20% of design size while its own content
would comfortably allow 85%, and the ordinary density check stays silent, because
the text *on that slide* is fine.

OciDeck reports this separately. The warning lands on the slide that renders too
small, names the size it gets and the size it would have on its own, and points at
the page responsible. The one-click fix **Take the full page out of the run**
detaches that page: the run is cut before and after it, so the over-full page
stands alone and every other page returns to its own size. Nothing moves and
nothing is merged — only the continuation markers change, so a single undo puts it
back.

Because this is the one warning you would not think to go looking for — the slide
on your screen looks broken while its own text is fine — the fix also sits in the
editor header, as a **Fix slide** button next to the **Quality** chip. It appears
only while the slide you are editing is being dragged down, and disappears once
you press it; the tooltip carries the full explanation. Every other fix stays in
the quality panel.

You do not have to wait for the warning. The continuation state is an ordinary
editor setting: bullet slides (one column, two columns, bullets + image) carry a
**Continuation of the previous slide** switch, shown whenever the slide before
could form a run with this one (same type, same list style). It states what it
costs — the slide shares one font size with the fullest page of the run — so you
can join or detach a page deliberately, without opening Markdown mode. Switching
the slide to a type or list style that cannot continue a run clears the flag
rather than leaving it behind invisibly.

This most often happens when a page was marked as a continuation by hand in
Markdown mode, or when one page of an existing split was later filled with pasted
prose. The over-full page keeps its own density warning and its own fixes (**Split
slide**, **Split sentences into bullets**, **Explanation to notes**) — detaching
tells OciDeck the page is not part of the list; it does not make the page shorter.

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
add-slide and **change-type** pickers, the MIAUW template appears in the
new-presentation dialog, and the module's command-palette actions become
available. While the module is off, none of those security types are offered
anywhere, so the picker stays short for everyone who does not need them — but a
report that already uses them always opens and renders correctly regardless (the
file is the source of truth; the toggle only governs *authoring*).

The same applies to the module's MIAUW record-keeping surfaces, so an ordinary
presentation is not asked for pentest metadata it has no use for:

- **Standards used** and **Tools used** (MIAUW EIS 4.3.2 / 4.8.2) in
  *Presentation properties*. A deck that already carries either value keeps
  showing both fields even with the module off — the data is never hidden from
  the person who entered it.
- **Insert tools appendix…** in the `…` menu, which turns *Tools used* into a
  table slide.

**Opening a security report while the module is off** surfaces a one-time
prompt — a snackbar with an **Enable** action — so you can turn the module on
right there instead of hunting through settings. It appears only when a deck you
open actually contains security slide types and the module is off, once per open
(never while you edit), and the slides render either way; it is purely a way to
discover the module.

The module's reference data is **part of the app itself**, so enabling it works
**offline and out of the box** — nothing is downloaded, there is no server, and
no outbound traffic is involved. You do not need to grant the outbound-traffic
consent for it, and turning the module on cannot fail: the data is already there,
so the switch is the whole story.

**What you actually have.** Once the module is on, the card lists **what is
available locally, in counts** — how many CWE weaknesses, WSTG test cases, MIAUW
requirements, CVSS score-table rows and finding templates the app can serve you,
with the upstream standard each one follows. The counts are taken from the
catalogues the app *actually* queries, so an empty list would show up as empty
rather than hiding behind a reassuring tick.

The data travels with the app version, which means it also updates with it:
there is no separate update, no cache to clean up and no pack to import. Upgrade
OciDeck and you have the newer reference data; that is the only path, and the
card no longer offers buttons suggesting otherwise.

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
  sections. Severity is always **derived** from the vector, never typed. On the
  rendered slide a **cockpit speedometer** sits next to the finding header — a
  green→amber→red gauge with the needle at the effective score (the CIA-weighted
  context score when the scope object is rated, else the base score) — so the
  reader sees the severity at a glance. A
  **Hertest (Retest)** dropdown records the retest outcome — *Opgelost* / *Nog
  aanwezig* / *Deels opgelost* (with an optional note); a resolved finding shows a
  green **Opgelost na hertest** badge on its card while keeping its severity. A
  **Gekoppelde test (Linked test)** picker links the finding to a test from the
  checklist(s) covering its scope object; picking one shows the test id as a chip
  on the finding card and marks that checklist row as an anomaly linked to the
  finding (changing or clearing the choice moves or removes the link). The
  finding editor also has an **Bewijs (Evidence)** section: **Screenshot
  toevoegen** and **Video toevoegen** attach a screenshot or a video as evidence.
  Each piece of evidence becomes its own slide right after the finding (part of
  the same finding group, so it moves and exports with the finding); the section
  lists them with a thumbnail and lets you jump to or remove each one. Give the
  finding an id first — evidence links to the finding by that id.
- **Uitvoering testen conform standaard** (the checklist slide type; the file
  format keeps the `checklist` class) — a standard-driven test list with a MIAUW
  tri-state per item
  (*Getoetst* / *Afwijking* / *Niet toetsbaar* / *Niet getoetst*) and an optional
  link to a finding id. **WSTG-testen laden (Load WSTG tests)** fills the list in
  one click with the complete **OWASP WSTG v4.2** checklist (97 tests across 12
  categories); the version is shown next to the button and lands in the standard
  label so it appears on the slide. Loading is non-destructive — it only adds the
  tests you don't have yet, keeping any rows and statuses already filled in — so
  you can re-load after editing without losing progress.
  A checklist can also be **linked to a scope object** via the **Scope-object**
  field at the top of the editor (free text, or pick one from the scope matrix);
  the linked object is shown in the checklist preview, so each scope element has
  its own test list. Beyond WSTG you can load your **own checklist templates**:
  create them under **Settings → Checklists** (a name, a standard label and its
  test items) and load them with the **Sjabloon laden…** menu next to the WSTG
  button. Templates are saved in the settings, so they are available in every
  deck.
- **Scope matrix** — the scope objects, each with a type (Web / Infra / IoT /
  Firmware / API / Mobile / Other) that automatically fixes its test standard
  (Web→WSTG, Infra→PTES, …), a coverage status, a note, and a **CIA rating**
  (Confidentiality / Integrity / Availability, each `H`/`M`/`L` or left empty).
  The rating captures how important the object is per dimension and drives the
  **context score** of every finding on that object (see below); leave it empty
  when the weighting is not known. A new matrix starts with one object; add,
  remove or reorder objects (move up/down) as you go.
  **Genereer checklists voor scope-objecten (Generate checklists for scope
  objects)** creates, in one click, a checklist slide for every scope object that
  does not have one yet — the full WSTG list for Web/API objects, and for the
  other objects either an empty checklist titled with the object's standard or,
  when you have templates, one you pick to pre-fill them. It skips objects that
  are already linked to a checklist, so you can re-run it after adding more
  objects.
- **Findings summary** — a management overview: the number of findings per CVSS
  severity band, rendered as a severity-coloured bar chart, plus an always-shown
  **Opgelost na hertest (Resolved after retest)** total. **Vernieuw uit deck**
  recomputes both from the deck's findings.
- **Sign-off** — the truthful-reporting page (MIAUW 1.6) with the deck-wide visual
  signature and certification, and **Afronden & verzegelen** to seal the report.
  The signature can be **typed** or **drawn**: click **Handtekening tekenen (Draw
  signature)** — in the sign-off editor or the seal dialog — to sign on a pad with
  the mouse, trackpad, touch or stylus. A drawn signature is stored as an embedded
  image inside the report (so it travels with the `.md` and is covered by the
  seal) and takes precedence over the typed name wherever the sign-off is shown.

### The finding wizard

Adding a **Bevinding** opens a step-by-step wizard instead of a blank slide:

1. **Basis** — title, finding id, scope object.
2. **CVSS 4.0** — a per-metric builder (a dropdown per metric) with a live
   **base** score and severity read-out. When the chosen scope object carries a
   CIA rating in the scope matrix, a **context** (CIA-weighted) score is shown
   next to the base score. Only the **base vector** is stored on the finding; the
   context score is derived from the scope object's rating, so re-rating the
   object re-scores every finding on it.
3. **CWE & CVE** — a searchable **CWE picker** over the full, offline MITRE CWE
   list (~940 weaknesses; the curated ones add a description/recommendation
   snippet). Picking one sets the CWE and, only when they are still empty, fills
   the description and recommendation — a good starting point written without an
   LLM. The **Zoek CVE…** button looks a CVE up online by id pattern (e.g.
   `2021-44228`) and appends the chosen id; it is off by default — enable **CVE
   opzoeken (online)** under Settings → Security (see below). A CVE field also
   accepts ids typed by hand.
4. **Inhoud** — the four narrative sections, and a choice to add a detail and/or
   evidence placeholder.

On finish the wizard inserts the whole finding group in one step. The same CWE
picker is also available from the finding editor's **Kies CWE…** button.

The same guided builder is available when editing an existing finding: the
finding editor's **CVSS-wizard** button opens the per-metric builder (seeded from
the current vector and the linked scope object's CIA rating) and writes the base
vector back. The **Scope-object** field there is a picker that lists the scope
matrix's objects (free text still allowed), and the score read-out shows the base
score plus the context score when the object is rated. The context score then
flows everywhere — the finding card, the previews and the PDF/PPTX export, and the
findings-summary and management-summary counts use the context severity band.

### AI drafting for finding text (optional)

When the optional AI backend is on, the finding editor shows a **Tekst voorstellen
(AI)** button under the *Beschrijving*, *Mogelijke impact* and *Aanbeveling*
fields. It drafts that field with your configured AI backend — local, self-hosted
or cloud, as set under *Settings → AI-assistentie* — grounded **only** on your own
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

### One-click audit dossier

The **Auditdossier exporteren** command bundles a delivered report into a single
hand-off archive (PENTEST_MIAUW §10.11). It only runs once the report is
**finalised and sealed**; otherwise it asks you to finalise first. The dossier is
an ordinary `.ocideck` package — the report source (`.md`) with all its assets and
evidence images — plus an `AUDIT_DOSSIER.md` index that restates, in one place:

- the report identity (title, author, organisation, version, date, TLP);
- the seal facts — finalised state, SHA-512 seal hash, seal time, and whether an
  RFC 3161 timestamp is attached — with a short note on how to verify integrity;
- the management summary (findings per severity, scope coverage, standards used);
- the MIAUW compliance tally (Voldaan / Openstaand / Uitgesloten);
- the evidence hash table (SHA1 + SHA-256 per evidence image).

Like the normal package export, you can protect the whole dossier with a password
(WinZip **AES-256**), so the report, its evidence and the hash tables travel
together as one encrypted, auditor-ready file.

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

**Finding a setting.** There are around eighty settings across twelve tabs, so the
settings window has a **search box** in its header. Type a word and you get the
matching settings, each with the tab and section it lives in; click one and the
window jumps to that tab, scrolls the section into view and briefly highlights it.
Search also matches **synonyms that aren't printed on screen** — `youtube`,
`vimeo` or `mp4` all lead you to **Online media**, and `lettergrootte` to the
interface text size. You don't need to know what the app calls a thing in order to
find it.

- **Style profiles** control deck colours (including the source-code background,
  text, font and an optional syntax-colouring toggle), fonts, logo, and footer.
  Every colour can be picked from the presets or entered as a custom hex value. The
  Colours and Logo tabs show which profile you're editing. As you edit, a warning
  appears beneath any colour whose contrast the quality panel would flag for a
  presentation — e.g. a white title on a white title background, which would make
  the heading invisible. The check mirrors the deck-level quality report (same
  analyser and contrast threshold), amber for a warning and red for a hard error,
  with the exact contrast ratio shown inline and the full details on hover. The
  bundled Marp theme is `assets/themes/ocideck.css`.
- **Sharing a style profile.** Next to the profile name sit an **export** and an
  **import** button. Export writes the profile you are editing to a
  `.ocideckstyle` file (on the web build it downloads) — so a house style can be
  passed to a colleague or kept in a repository without a deck around it. Import
  reads such a file back, adds it as a new profile and selects it; an existing
  name is never overwritten, the import gets a unique name instead. A **custom
  logo travels inside the file**, so the profile arrives complete; the local path
  to your logo is deliberately left out. Built-in logos stay a reference. On the
  web build a restored custom logo lives only until you reload the page (there is
  no persistent file storage in the browser) — everything else in the profile
  keeps working. Anything that isn't a valid profile file is refused with an
  explanation.
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
