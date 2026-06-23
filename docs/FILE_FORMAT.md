# OciDeck — File Format

OciDeck stores presentations as **standard [Marp](https://marp.app/) Markdown**
(`.md`). There is no custom binary format: a saved presentation can be processed
directly with the Marp CLI or the VS Code Marp extension. OciDeck-specific
information is written in places Marp ignores (front-matter keys and HTML
comments), so the file remains fully Marp-compatible while still round-tripping
losslessly in OciDeck.

There are also two derived forms:

- a **project folder** around the `.md` file with copied assets, and
- a **portable package** (`.ocideck`, a zip file) for exchanging a presentation as
  a single file.

---

## 1. Project Folder Layout

When saving (`Save` / `Save as...`), OciDeck writes more than the `.md` file: it
also creates a fixed folder structure next to it and copies all used assets
there. Paths in the Markdown are then **relative** to the folder containing the
`.md` file.

```
my_presentation/
├── My_presentation.md              # the presentation (Marp Markdown)
├── My_presentation.ink.json        # annotation-layer sidecar (see §6.2)
├── My_presentation.user-notes.json # user-notes sidecar (see §6.3)
├── images/                         # copied images
│   ├── photo.png
│   └── .ocideck_captions.json      # caption sidecar (see §6.1)
├── data/                           # linked chart CSV files (see §6.4)
│   └── revenue.csv
├── logos/                          # copied logo from the style profile
│   └── logo.png
├── media/                          # video/audio (only in packages, see §7)
└── themes/
    └── ocideck.css                 # generated theme CSS (see §5)
```

> The `.md` filename is derived from the presentation title: non-alphanumeric
> characters are removed and spaces become `_`.

The folders `images/`, `logos/`, `themes/` (and `node_modules/`, `build/`,
`.git/`, `.dart_tool/`) are skipped when OciDeck scans a folder for
presentations.

> **Security — asset paths are confined to the project folder.** Because a
> `.md` may come from an untrusted source, every asset reference
> (`![](…)` images, `logoPath`, video/audio, chart `source`) is resolved
> strictly inside the project folder. Absolute paths and `../` escapes are
> ignored when previewing, presenting, exporting, or analysing a deck — a
> deck cannot read files elsewhere on disk. See `SECURITY.md` →
> *Untrusted deck handling*.

> Next to the `.md` file, OciDeck writes **sidecars** that deliberately are not
> part of the Marp Markdown (so the `.md` stays clean and exchangeable): the
> annotation layer (`<name>.ink.json`, §6.2), user notes
> (`<name>.user-notes.json`, §6.3), captions (`.ocideck_captions.json`, §6.1),
> and linked chart data (`data/*.csv`, §6.4).

---

## 2. Markdown Structure at a Glance

```markdown
---
marp: true
theme: ocideck
paginate: true
... (other metadata) ...
ocideck_style_profile: <base64url(JSON)>
---

<!-- _class: title -->

# First slide

---

<!-- _class: ... -->

(second slide)
```

- The document starts with **YAML front matter** between `---` lines (§3).
- Slides are separated by a line containing exactly `---` (internally split on
  `\n---\n`).
- Each slide can optionally start with a `<!-- _class: ... -->` line that
  determines the slide type and behavior (§4).

---

## 3. Front Matter

| Key | Type | Meaning |
| --- | --- | --- |
| `marp` | `true` | Fixed Marp marker. |
| `theme` | string | Theme name; defaults to `ocideck`. Refers to `themes/<theme>.css`. |
| `paginate` | `true`/absent | Written only when pagination is enabled. |
| `author` | string | Author. |
| `organization` | string | Organization. |
| `version` | string | Version. |
| `date` | string | Date (free text). |
| `description` | string | Description. |
| `keywords` | string | Keywords. |
| `tlp` | enum | Traffic Light Protocol level (§3.1). Written only when not `none`. |
| `ocideck_style_profile` | base64url | Complete style profile as JSON (§3.2). |

Metadata fields are written only when they are not empty. Text is written as a
YAML scalar and quoted only when needed (empty value, leading/trailing
whitespace, special characters such as `: # "`, or a YAML indicator at the
start). OciDeck does not use a full YAML parser when reading; it uses a simple
line-by-line parser, so keep front matter flat (one key per line).

### 3.1 TLP Levels

Stored under the `tlp` key with these stable values:

| `tlp` value | Slide marking |
| --- | --- |
| `none` *(not written)* | — |
| `clear` | `TLP:CLEAR` |
| `green` | `TLP:GREEN` |
| `amber` | `TLP:AMBER` |
| `amber+strict` | `TLP:AMBER+STRICT` |
| `red` | `TLP:RED` |

**Effective marking.** In the app, each slide shows the **strictest** level: the
maximum of the deck-level TLP (`tlp` in front matter) and the per-slide TLP
(`<!-- tlp: ... -->`). That determines the banner, badge, and optional watermark
in preview, presenter, and raster export. It is not stored as extra Markdown; it
is calculated while rendering (`effectiveTlp` in `lib/models/deck.dart`).

**Visibility vs. export gate.** Per-slide TLP determines which slides are held
back during presenting/exporting (`slideVisibleAtTlp`). The **export enforcement**
(ceiling, minimum, mandatory classification) only looks at the deck-wide `tlp`
field in front matter, not at per-slide levels.

### 3.2 `ocideck_style_profile` (Style Profile)

The complete visual profile is serialized as JSON, UTF-8 encoded, and
**base64url** encoded on one line. Decode as base64url -> UTF-8 -> JSON. The JSON
has these fields (with defaults):

| Field | Default | Meaning |
| --- | --- | --- |
| `name` | `"Standaard"` | Profile name. |
| `slideBackgroundColor` | `#FFFFFF` | Background for normal slides. |
| `textColor` | `#222222` | Text color. |
| `accentColor` | `#2E7D64` | Accent (bullet marker, table borders/header). |
| `tableTextColor` | = `textColor` | Text color in tables. |
| `tableHeaderTextColor` | `#FFFFFF` | Table header text color. |
| `titleBackgroundColor` | `#1C2B47` | Title-slide background. |
| `titleTextColor` | `#FFFFFF` | Text on title/section slides. |
| `sectionBackgroundColor` | `#2E7D64` | Section-slide background. |
| `codeBackgroundColor` | `#282C34` | Source-code slide background. |
| `codeTextColor` | `#ABB2BF` | Source-code slide text color. |
| `codeHighlightSyntax` | `true` | Syntax highlighting on/off. Off = everything in one color (for example green on black for a CRT look). |
| `codeFontFamily` | `monospace` | Font family for source-code slides (for example `Courier New`). |
| `logoPath` | `null` | Path to the logo (relative path in `logos/`). |
| `logoPosition` | `bottom-right` | `top-left`/`top-right`/`bottom-left`/`bottom-right`. |
| `logoSize` | `96` | Logo size in px. |
| `fontFamily` | `Arial` | Presentation font family. |
| `footerText` | `""` | Free footer text; tokens: `{page}`, `{total}`, `{date}`, `{title}`. |
| `footerShowPageNumbers` | `false` | Show "page / total" at the bottom right. |
| `footerPosition` | `right` | `left`/`center`/`right`. |
| `closingSlideEnabled` | `false` | Automatically add a closing slide during presenting/exporting. |
| `closingSlideMarkdown` | `"# Bedankt\n\nVragen?"` | Markdown for that closing slide. |

Unknown or missing fields fall back to defaults, so older files migrate cleanly.

> **Cockpit status colours are not part of the style profile or the file.** The
> cockpit instruments use a named *cockpit colour scheme* (good / warning /
> critical / cold) that is an app-level setting, selected globally and applied at
> render time. It is intentionally kept out of the deck `.md` so the file stays
> pure content.

---

## 4. Slide Classes and Behavior

Immediately after a separator, a slide can contain a class comment:

```markdown
<!-- _class: <typeclass> [logo-safe] [no-logo] [no-footer] [custom-classes] -->
```

The first class determines (together with the content) the **slide type**:

| Type | `_class` token | Detection without token |
| --- | --- | --- |
| Title page | `title` | — |
| Section divider | `section` | — |
| Two bullet columns | `two-bullets` | — |
| Bullets + image | `split` | bullets **and** image present |
| Quote | `quote` | a `>` line is present |
| Video | `video` | a `<video>` tag is present |
| Table | `table` | only a table, no heading/bullets/text |
| Source code | `code` | — |
| Chart | `chart` | — |
| Cockpit | `cockpit` | — |
| Question | `question` | — |
| Timeline | `timeline` | — |
| Bullets only | *(none)* | bullets present |
| Two images | *(none)* | two background images |
| Large image | *(none)* | one image, no bullets |
| Free Markdown | *(none)* | no heading/bullets/image/quote |

> `code`, `chart`, `cockpit`, and `question` slides contain fenced code blocks
> that would confuse the generic line parser, so they are recognized separately
> through their `_class`.

Additional behavior classes:

- `logo-safe` — reserve space so the logo does not overlap content. Added
  automatically when a logo exists **and** the slide shows it.
- `no-logo` — hide the logo on this slide (`showLogo = false`).
- `no-footer` — hide the footer on this slide (`showFooter = false`). If this
  token is absent (older files), the footer remains visible.

When reading, OciDeck recognizes and removes the type and behavior classes; what
remains is preserved as the slide's custom `cssClass`.

---

## 5. Per-Slide-Type Markdown Representation

The generated form for each type is shown below. Image captions (§6) are written,
where applicable, as `<div class="image-caption">...</div>` directly below the
image.

**Title** (`title`)
```markdown
![bg 60% opacity:.45](images/background.png)   <!-- optional background -->
# Title
## Subtitle
```

**Section** (`section`)
```markdown
# Section title

Optional explanatory paragraph
```

**Bullets** (no class) — optionally a **subheading** (`## ...`, stored in
`subtitle`), and indentation with tabs in the model -> two spaces per level in
Markdown:
```markdown
# Heading
## Subheading (optional)

- First point
  - Subpoint
```

**Two bullet columns** (`two-bullets`) — besides the visible HTML grid, the two
columns are also stored **canonically** in comments (base64url of a JSON array),
so they can be read back losslessly. Each column can optionally have a
**heading** (`*_title`, base64url of plain text); it is written only when filled
and appears as `<h3>` above the column:
```markdown
<!-- ocideck_two_bullets_left: <base64url(JSON[])> -->
<!-- ocideck_two_bullets_right: <base64url(JSON[])> -->
<!-- ocideck_two_bullets_left_title: <base64url(text)> -->   (optional)
<!-- ocideck_two_bullets_right_title: <base64url(text)> -->  (optional)
<div class="ocideck-two-bullets" style="...">
<div><h3>...</h3><ul>...</ul></div>
<div><h3>...</h3><ul>...</ul></div>
</div>
```

**Bullets + image** (`split`) — panel width and text scale are stored in a
`_style` comment; the image is inside a `split-image` div:
```markdown
<!-- _style: --image-width: 40%; --split-text-scale: 1.85; -->

<div class="split-text" style="font-size: 1.85em">

# Heading

- Point

</div>

<div class="split-image">

![](images/photo.png)

</div>
```

**Two images** (no class) — as left/right backgrounds:
```markdown
![bg left:50%](images/left.png)
![bg right:50%](images/right.png)

# Optional heading
```

**Large image** (no class)
```markdown
![bg 80%](images/photo.png)

# Optional heading
```

**Video** (`video`)
```markdown
# Optional heading

<video src="media/clip.mp4" controls autoplay muted loop style="..."></video>
```

**Quote** (`quote`)
```markdown
![bg 50% opacity:.45](images/background.png)   <!-- optional -->
> The quote text

— Author
```

**Table** (`table`) — GitHub-flavored Markdown; the first row is the header.
Inside cells, `|` is written as `\|` and line endings as `<br>`:
```markdown
# Optional heading

| Header 1 | Header 2 |
| --- | --- |
| a | b |
```

**Free Markdown** (no class) — content is written verbatim.

**Source code** (`code`) — an optional heading plus a fenced code block; the info
string is the programming language (highlight.js id, empty = plain text). The
code itself is stored verbatim in the block:
````markdown
# Optional heading

```dart
void main() => print('hi');
```
````

**Chart** (`chart`) — a fenced ```chart``` block with the chart specification as
**JSON**. Small charts store their data inline; data-driven charts point through
`source` to a CSV in `data/` (see §6.4). When saving, inline data is omitted as
soon as a `source` exists (the CSV is then the source of truth); when opening,
that CSV is read back in.
````markdown
```chart
{
  "type": "bar",            // bar | line | pie | radar
  "title": "Revenue",
  "source": "data/revenue.csv",  // optional; otherwise inline x/series
  "x": ["Q1", "Q2"],
  "rowColors": ["#003399", "#FFCC00"],  // optional; color per label (pie/radar)
  "minBound": 0,            // optional; not for pie
  "maxBound": 20,           // optional; not for pie
  "series": [ { "name": "2025", "data": [10, 14], "color": "#2563EB" } ]
}
```
````

Fields:

- `type` — `bar`, `line`, `pie`, or `radar` (spider). Defaults to `bar`.
- `x` — labels; for `pie`/`radar`, these are the segments/axes (radar requires
  at least three).
- `series` — named series with `data` (aligned with `x`) and optionally a
  `color` (hex). `pie` shows at most the first two series.
- `rowColors` — optional color per label (used by `pie`/`radar`).
- `minBound` / `maxBound` — optional and only for non-`pie`. For `bar`/`line`,
  these are horizontal **reference lines**; for `radar`, they determine the
  **scale** (inner/outer ring) with even spacing. Omitted for `pie`.

**Question** (`question`) — a fenced ```question``` block with the quiz
specification as **JSON**, optionally preceded by a `# title`, an `![](image)`
with caption, and an `<!-- _style: --image-width: N%; -->` comment when an image
is present. The block is the round-trip source of truth.
````markdown
```question
{
  "kind": "multipleChoice",      // multipleChoice | trueFalse | multipleCorrect
  "prompt": "What is the capital of the Netherlands?",
  "optionCount": 4,              // total options shown (random pick)
  "timeLimitSeconds": 0,         // 0 = no limit
  "onWrong": "retry",            // retry | lockAndContinue
  "statementIsTrue": true,       // trueFalse only
  "answers": [
    { "text": "Amsterdam", "correct": true },
    { "text": "Rotterdam", "correct": false }
  ]
}
```
````

Fields:

- `kind` — `multipleChoice` (one correct + a random pick of wrong ones; pick one),
  `trueFalse` (the prompt is a statement; pick true/false), or `multipleCorrect`
  (several may be correct; pick all). Defaults to `multipleChoice`.
- `prompt` — the question, or the statement for `trueFalse`.
- `answers` — the full pool; each has `text` and `correct`. Ignored for
  `trueFalse`. The presentation draws a random subset from it.
- `optionCount` — how many options are shown (2–8, default 4). Not used by
  `trueFalse`.
- `timeLimitSeconds` — optional countdown; running out counts as wrong.
- `onWrong` — `retry` (cannot continue; a fresh set is drawn on the next click) or
  `lockAndContinue` (reveal the answer, lock the slide, allow advancing).
- `statementIsTrue` — for `trueFalse`, whether the statement is true.

> The live answer state (which options were drawn, what the viewer picked,
> correct/wrong) is **session-only** and never written to the file. A static
> export renders the question without interactivity.

**Timeline** (`timeline`) — a normal Markdown list, optionally preceded by a
`# title`. Each list item is one event in the form
`marker :: title :: description`, where `marker` (a date/phase label) and
`description` are optional — a single segment is treated as the title. Because it
is an ordinary list, the slide renders sensibly in plain Marp too.

```markdown
<!-- _class: timeline timeline-vertical timeline-steps -->
# Van idee tot beursgang

- 2019 :: Oprichting :: Drie mensen, één zolderkamer.
- 2021 :: Lancering :: 1.000 gebruikers in zes weken.
- Nu :: Vandaag
```

The layout and animation are **presentation options**, not content, so they
round-trip as extra `_class` tokens alongside the base `timeline` token:

- `timeline-horizontal` / `timeline-vertical` — force a layout; absent = *auto*
  (horizontal for ≤ 5 events, vertical otherwise).
- `timeline-steps` — reveal one event per click while presenting; absent = the
  whole timeline draws itself in when the slide opens.
- `timeline-static` — no animation; everything is shown at once.

The draw-in **speed** (only meaningful for the default on-enter animation) is the
one numeric option, so it round-trips in an HTML comment rather than a class
token, and only when it differs from the 1600 ms default:

```markdown
<!-- ocideck_timeline_duration: 2600 -->
```

It is the full draw-in duration in milliseconds, clamped to 400–6000 ms.

> The reveal step (how many events are currently shown in step mode) is
> **session-only** and never written to the file.

### Image Size (`imageSize`)

One integer field with type-dependent meaning: for `image`/`title`/`quote`, it
is the background percentage (`![bg N%]`); for `split`, it is the panel width
(clamped to 20-70%); for two images, it is the `left:`/`right:` split. `0` =
automatic.

---

## 6. Sidecars and Separate Data

Three kinds of data deliberately live **next to** the `.md` file instead of
inside it, so the Marp Markdown remains clean and exchangeable.

### 6.1 Image Captions

Captions are stored in **two** places:

1. **In the Markdown**, as a visible line below the image:
   ```markdown
   <div class="image-caption">My caption</div>
   ```
   For two images, both captions are joined with ` | `. HTML characters are
   escaped.

2. **As a JSON sidecar** `.ocideck_captions.json` in the image folder, so the
   caption belongs to the *file* (and can be shared between presentations).
   Format: key is the filename, value is the caption:
   ```json
   {
     "photo.png": "My caption",
     "chart.png": "Quarterly revenue"
   }
   ```
   An empty caption removes the key; an empty file is deleted.

Alongside captions, there is a second sidecar with the same shape:
`.ocideck_descriptions.json` for **descriptions/tags**. It stores searchable free
text per image, used by the search box and the "without tags" filter in the
image library (and merged when cleaning up md5-identical duplicates). It uses the
same format and the same empty-cleanup rules as the captions sidecar.

### 6.2 Annotation Layer (`<name>.ink.json`)

Freehand annotations (pen, highlighter) made while presenting are stored in a
separate JSON sidecar next to the `.md` file (and inside the package, §7). The
Marp `.md` is never touched by annotations.

- Coordinates are **normalized** (0-1) inside the 16:9 canvas, so a stroke scales
  identically on a laptop and projector.
- Because slide ids are regenerated every time a file is read, strokes are
  stored **per slide by order + a content fingerprint**. When reopening, they
  are reattached to the slide with the same fingerprint (preferably at the same
  index); strokes for changed/deleted slides are dropped.

```json
{
  "version": 1,
  "slides": [
    {
      "index": 2,
      "fp": "a1b2c3d4",
      "strokes": [
        { "tool": "pen", "color": 4294198070, "width": 0.004,
          "points": [0.1, 0.2, 0.15, 0.22] }
      ]
    }
  ]
}
```

`points` is a flat list `[x0, y0, x1, y1, ...]`; `color` is an ARGB int; `tool`
is `pen` or `highlighter` (laser pointers are transient and are not stored).

### 6.3 User Notes (`<name>.user-notes.json`)

Personal notes for the recipient or learner while following a presentation. They
are fully separate from speaker notes (`Slide.notes` in the `.md`, HTML comments)
and from the annotation layer. They are hidden by default during presenting; the
presenter opens them locally with `Ctrl/Cmd + N` (never on the projector/audience
screen). In the visual editor, speaker notes and user notes each live in a
collapsible block with a header row (title + discard button); slides with user
notes show a blue badge on the thumbnail in the slide list.

Because slide ids are regenerated every time a file is read, notes are stored
**per slide by order + a content fingerprint** (the same hash as in §6.2). When
reopening, they are reattached to the slide with the same fingerprint (preferably
at the same index); notes for changed/deleted slides are dropped. Empty notes are
not stored; when there are no notes, the sidecar file is deleted or not written.

```json
{
  "version": 1,
  "slides": [
    { "index": 1, "fp": "a1b2c3d4", "text": "Ask a question about the diagram" }
  ]
}
```

### 6.4 Chart Data (`data/*.csv`)

A chart slide (§5) can keep its data inline in the `chart` block, or point via
`"source": "data/<name>.csv"` to a CSV in a separate **`data/`** folder next to
the deck. That folder keeps all linked data files together, separate from
`images/`/`media/`. The CSV is then the source of truth: it is edited separately
(for example in a spreadsheet), copied along during save/`Save as...`, and
included in packages (§7). When opening, the CSV is read and attached to the
chart in memory; the `.md` keeps only the `source` reference.

CSV shape: first row = series names (first cell = label column), every next row
is `label, value1, value2, ...`.

---

## 7. Portable Package (`.ocideck`)

`Export package` writes one **zip file** (extension `.ocideck`; `.zip` is also
accepted on import) containing the presentation and all used assets, with
relative paths between them. This also works when the deck has not been saved
yet.

```
<title>.ocideck   (zip)
├── <title>.md                # Marp Markdown
├── <title>.ink.json          # annotation layer (if present, §6.2)
├── <title>.user-notes.json   # user notes (if present, §6.3)
├── images/...                # all used images
├── data/...                  # linked chart CSV files (§6.4)
├── media/...                 # used video/audio
├── logos/...                 # logo from the style profile
└── themes/<theme>.css        # generated theme CSS (usable by Marp/CLI)
```

On import:

- The zip is extracted into a **new**, unique subfolder (name derived from the
  main `.md`; on collision, `name (2)`, `name (3)`, ...).
- The `.md` file with the **shallowest** path is chosen as the main file.
- A package can also be imported from a URL: if the download starts with zip
  magic `PK\x03\x04`, it is treated as a package; otherwise it is saved as plain
  Markdown.

---

## 8. Special Per-Slide Comments (Overview)

Besides `_class`, OciDeck uses these HTML comments (all ignored by Marp, except
for presenter notes):

| Comment | Meaning |
| --- | --- |
| `<!-- _class: ... -->` | Slide type + behavior (§4). |
| `<!-- _style: --image-width: N%; --split-text-scale: x; -->` | Layout of a `split` slide. |
| `<!-- ocideck_two_bullets_left/right: <base64url> -->` | Canonical storage for the two bullet columns. |
| `<!-- advance: N.N -->` | Auto-advance after N.N seconds (0 = off). |
| `<!-- skip -->` | Skip slide during both presenting and export. |
| `<!-- tlp: <key> -->` | Per-slide TLP level (see §3.1). The slide is held back if the presentation TLP is lower. Written only when not `none`. |
| `<!-- ... (free text) ... -->` | **Presenter notes** (any other comment that does not start with `_`). |

---

## 9. Round-Trip and Compatibility

- **Lossless in OciDeck:** everything the editor can set is stored either as real
  Markdown or as OciDeck comments/front-matter keys and read back when opening.
  Parsing is "best effort": if it fails completely, the parser returns `null`;
  an empty document produces one empty title slide.
- **Marp-compatible:** the file remains valid Marp Markdown. External tools see
  normal headings, bullets, tables, background images, and HTML; OciDeck extras
  live in ignored comments and custom front-matter keys.
- **Forward migration:** missing front-matter fields and style-profile fields
  fall back to defaults, and the absence of the `no-footer` token means (for
  older files) "footer visible".

---

## 10. Markdown Mode and Syntax Checking

In the editor, the code icon in the toolbar switches to **Markdown mode**: the
entire presentation is shown as one Marp Markdown document (the same structure as
on disk). **Apply** parses the text back into typed slides; **Cancel** returns
without applying changes.

### Find and Replace

In Markdown mode, an **in-editor find bar** searches the live Markdown text
(including front matter, `---` separators, HTML comments, and unapplied changes).
This differs from the **Find and replace** dialog in visual mode (`Ctrl/Cmd + H`),
which only searches through slide fields.

| Shortcut | Action |
| --- | --- |
| `Ctrl/Cmd + F` | Open find bar |
| `Ctrl/Cmd + H` | Open find bar with replace field |
| `Enter` / `Shift + Enter` (in find field) | Next / previous match |
| `Esc` | Close find bar |

The bar shows a match counter (`1 / 3`), previous/next buttons, a case-sensitive
toggle, **Replace** (current match), and **Replace all**. Each match is selected
in the editor so you can quickly jump to a title, slide separator, or other
part.

### When to Check

- **Check** — at any time while editing; results appear in a summary bar with an
  expandable list. Line numbers on the left are marked red (error) or yellow
  (warning); click a message to jump to that line.
- **Apply** — always runs the check first. If findings exist, a dialog appears
  with **Back to editor**, **Cancel**, or **Apply anyway**.

The check is **structural**: it follows the same rules as `MarkdownService`
(front matter, `\n---\n` as separator, `_class` comments, fenced blocks, and the
HTML fragments OciDeck itself generates). Valid Marp syntax that OciDeck does
not model is not reported.

### Checks Performed

| Area | Severity | Check |
| --- | --- | --- |
| **Document** | warning | Presentation is empty. |
| **Document** | error | No slide content after front matter. |
| **Document** | error | `parseDeck` fails completely (`null`). |
| **Front matter** | error | Opening `---` without a closing `---` line. |
| **Front matter** | warning | Line without `key: value` shape. |
| **Front matter** | error | Unknown `tlp:` value. |
| **Comment** | error | `<!--` without `-->` on the same line. |
| **Comment** | warning | Comment without `_class:`, `_style:`, `ocideck_...`, `skip`, `tlp:`, or `advance:`. |
| **Code blocks** | error | Odd number of ` ``` ` lines (not closed). |
| **`_class`** | error | Malformed `<!-- _class: ... -->`. |
| **`_class`** | warning | Unknown token in `_class` (known: `title`, `section`, `two-bullets`, `split`, `quote`, `video`, `table`, `code`, `chart`, `logo-safe`, `no-logo`, `no-footer`). |
| **Slide metadata** | error | Unknown `<!-- tlp: ... -->`, non-numeric `<!-- advance: ... -->`, or invalid `<!-- ocideck_list_style: ... -->` (`bullets`, `numbered`, `checklist`). |
| **Two columns** | error | Invalid base64/JSON in `ocideck_two_bullets_*` comments. |
| **Images** | error | `![...](...` without closing `)`. |
| **Video/audio** | error | Incomplete `<video>`/`<audio>` tag, or `<video>` without `src="..."`. |
| **`code` slide** | error | No closed fenced ``` block. |
| **`chart` slide** | error | No ` ```chart ` block, not closed, or invalid JSON (not a `{...}` object). |
| **`chart` slide** | warning | Empty JSON in a closed ` ```chart ` block. |
| **`split` slide** | error | Missing or unclosed `<div class="split-text">` / `split-image`. |
| **`two-bullets` slide** | error | Missing or unclosed `<div class="ocideck-two-bullets">`. |
| **`table` slide** | warning | No table rows. |
| **`table` slide** | error | No separator row (`\| --- \|`) or second row is not a valid GFM separator. |
| **HTML** | error | Unbalanced `<div>`/`</div>` inside a slide. |

Implementation: `lib/services/markdown_validator.dart`; tests:
`test/markdown_validator_test.dart`. See also [`USER_GUIDE.md`](USER_GUIDE.md)
(§ Markdown mode).

---

## 11. Export Metadata (Not in `.md`)

For PDF, PPTX, and HTML export, OciDeck writes **document properties** derived
from front matter (`author`, `organization`, `description`, `keywords`, `tlp`,
title). This metadata is **not** stored in the `.md` file and does not change the
round-trip format; it is set only during export (`ExportDocumentMetadata` in
`lib/services/export_metadata.dart`).

| Source (front matter) | PDF / PPTX | HTML |
| --- | --- | --- |
| Title | `Title` | `<title>` |
| `author`, otherwise `organization` | `Author` / `dc:creator` | `<meta name="author">` |
| OciDeck (fixed) | `Creator` | `<meta name="generator">` |
| OciDeck + version (fixed) | `Producer` / `Application` / `lastModifiedBy` | — |
| `description` | — | `<meta name="description">` |
| `keywords` + TLP + `OciDeck` | `Keywords` | `<meta name="keywords">` |
| `tlp` (when not `none`) | `Subject`: `TLP:... — title` | `<meta name="classification">`, `<meta name="tlp">`, fixed `.tlp-export-banner` at the top |

Visual TLP marking (banner, badge, optional watermark) is **rasterized** into
PDF/PPTX slides and is separate from these document properties. See
[`USER_GUIDE.md`](USER_GUIDE.md) (§ Traffic Light Protocol, § Exporting) and
[`ARCHITECTURE.md`](ARCHITECTURE.md) (§ Classification enforcement).
