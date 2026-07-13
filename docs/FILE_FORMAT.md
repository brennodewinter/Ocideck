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
- Slides are separated by a line containing exactly `---`. A `---` line **inside
  a fenced code block** (```` ``` ```` or `~~~`) is code content, not a
  separator, so a code sample, diff hunk or embedded YAML document that contains
  `---` no longer splits the slide.
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
| `ocideck_target_seconds` | int | Target duration for the presenter countdown, in seconds. Written only when `> 0`. |
| `ocideck_show_rehearsal_summary` | `false`/absent | Opt-out of the post-presentation timing summary. Default (shown) stays out of the file; only `false` is written. |
| `ocideck_play_only` | `true`/absent | Play-only lock. When `true`, the deck opens locked: no editor, toolbar, menus, or export — only the first slide with a play button, presented full screen. Closing the deck restores normal editing. Default (unlocked) stays out of the file; only `true` is written. Removing this key unlocks the deck. |
| `ocideck_style_profile` | base64url | Complete style profile as JSON (§3.2). |
| `ocideck_miauw_waivers` | base64url | MIAUW compliance exclusions as JSON: EIS id → mandatory reason. Written only when non-empty; a corrupt value is ignored. Drives the compliance overview (PENTEST_MIAUW §9). |
| `ocideck_seal_tsr` | base64url | RFC 3161 trusted-timestamp token (`.tsr`) over `ocideck_seal_hash` (PENTEST_MIAUW §8-A2). Written only when present; excluded from the sealed content hash. Verified in-app on open. |
| `ocideck_finalized` | `true`/absent | Document integrity (§8 A1): the deck is finalised and read-only. Written only when `true`. |
| `ocideck_seal_hash` · `ocideck_seal_algo` · `ocideck_seal_at` | string | The content seal: a SHA-512 hash over the canonical content (styling and the seal fields themselves excluded), the algorithm (`sha-512`), and the ISO-8601 UTC timestamp. Recomputed on open → *intact* / *changed after finalising*. |
| `ocideck_sig_name` · `ocideck_sig_role` · `ocideck_sig_cert` · `ocideck_sig_date` · `ocideck_sig_statement` · `ocideck_sig_typed` · `ocideck_sig_image` | string | The deck-level **visual signature** rendered by the `signOff` slide (§5): signer name, role, certification, date, attested statement, typed signature, and an optional embedded (`data:`) signature image — a **hand-drawn signature** (drawn on the pad in the sign-off editor / seal dialog) is stored here as a self-contained base64 PNG. Written before the seal fields, so the signature is covered by the hash. Each key is written only when non-empty. |

Metadata fields are written only when they are not empty. Text is written as a
YAML scalar and quoted only when needed (empty value, leading/trailing
whitespace, special characters such as `: # "`, or a YAML indicator at the
start). OciDeck does not use a full YAML parser when reading; it uses a simple
line-by-line parser, so keep front matter flat (one key per line).

Only the keys above (plus `marp`) are read; any other front-matter key — a typo,
or a Marp option OciDeck does not implement such as `header`, `footer`, `size` or
`style` — is silently ignored. The in-app markdown checker flags such keys with a
warning so they are not mistaken for having an effect. Likewise, a comment that
looks like a directive (`<!-- _key: … -->` or `<!-- ocideck_key: … -->`) but is
not one OciDeck understands — e.g. Marp's per-slide `_paginate`, `_header`,
`_footer`, `_color` — is dropped and flagged; plain prose comments remain speaker
notes.

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
| `bulletMarker` | `dot` | Default bullet-list marker: `dot` or `paw` (a cat-paw drawn in the accent colour). A slide may override it (see §8). |
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
| `severityCriticalColor` | `#B91C1C` | Finding/CVSS colour for the Critical band. |
| `severityHighColor` | `#EA580C` | Finding/CVSS colour for the High band. |
| `severityMediumColor` | `#D97706` | Finding/CVSS colour for the Medium band. |
| `severityLowColor` | `#15803D` | Finding/CVSS colour for the Low band. |
| `severityNoneColor` | `#475569` | Finding/CVSS colour for the Informational band. |

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
| Video | `video` | a `<video>` tag or an `<iframe class="ocideck-embed">` is present |
| Table | `table` | only a table, no heading/bullets/text |
| Source code | `code` | — |
| Chart | `chart` | — |
| Cockpit | `cockpit` | — |
| Question | `question` | — |
| Timeline | `timeline` | — |
| Finding | `finding` | — |
| Findings summary | `findings-summary` | — |
| Checklist | `checklist` | — |
| Scope matrix | `scope-matrix` | — |
| Sign-off | `sign-off` | — |
| Bullets only | *(none)* | bullets present |
| Two images | *(none)* | two background images |
| Large image | *(none)* | one image, no bullets |
| Free Markdown | *(none)* | no heading/bullets/image/quote |

> `code`, `chart`, `cockpit`, and `question` slides contain fenced code blocks
> that would confuse the generic line parser, so they are recognized separately
> through their `_class`.

> **Information-security classes and the module.** `finding`, `findings-summary`,
> `checklist`, `scope-matrix` and `sign-off` are the slide types of the optional
> **Informatieveiligheid** module (§ "Information security module" in the User
> Guide). Their handling in the file format is **unconditional and does not
> depend on the module**: OciDeck always parses these classes, and always renders
> them, whether or not the module is enabled — the file is the source of truth, so
> a report authored elsewhere opens and presents fully on any install. The module
> toggle governs **authoring only**: these types are offered in the add-slide and
> change-type pickers, and the MIAUW template appears in the new-presentation
> dialog, only while the module is enabled. A slide that is already one of these
> types can still be re-typed among them with the module off, so an imported
> report is never a dead-end.

Additional behavior classes:

- `logo-safe` — reserve space so the logo does not overlap content. Added
  automatically when a logo exists **and** the slide shows it.
- `no-logo` — hide the logo on this slide (`showLogo = false`).
- `no-footer` — hide the footer on this slide (`showFooter = false`). If this
  token is absent (older files), the footer remains visible.
- `table-editable` — allow this table to be edited live during a presentation
  (`tableEditable = true`). Only meaningful on `table` slides. If the token is
  absent (older files, or the default), the table is read-only while presenting.

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

The source is a local file, an online `http(s)` URL to a direct video file
(`.mp4`/`.mov`/…), or a YouTube/Vimeo link. Local and remote files use a
`<video>` tag; YouTube/Vimeo use an `<iframe class="ocideck-embed">`.

```markdown
# Optional heading

<video src="media/clip.mp4" controls autoplay muted loop style="..."></video>
```

Online file by URL:
```markdown
<video src="https://example.com/clip.mp4" controls style="..."></video>
```

YouTube/Vimeo embed (`data-src` keeps the original URL; the player `src` is the
embeddable form):
```markdown
<iframe class="ocideck-embed" data-src="https://youtu.be/ID" src="https://www.youtube-nocookie.com/embed/ID?..." style="width:100%; aspect-ratio:16/9; border:0;" allow="autoplay; fullscreen; picture-in-picture" allowfullscreen></iframe>
```

**Splitting a video across slides (trim window).** A video can be watched in
parts: each slide plays one segment `[start, end]` of the same source. The trim
window is stored in seconds. For `<video>` it rides in a
[media fragment](https://www.w3.org/TR/media-frags/) on the `src`
(`#t=START,END`, or `#t=START` when there is no end). For embeds it rides in
`data-start`/`data-end` attributes (seconds). `start = 0` plays from the
beginning; a missing end plays to the natural end.

```markdown
<video src="media/clip.mp4#t=5,12" controls style="..."></video>
```

> Online media (URL files and embeds) is only loaded live when the
> **Online media** security setting is on (off by default). When off, the slide
> shows a placeholder with the URL instead of fetching anything. On **export**,
> a remote source also gets a clickable literal URL link.

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
Add the `table-editable` behavior class (see §4) to let the table be edited live
while presenting; without it the table is read-only during a presentation.

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
  "type": "bar",            // see the type list below; defaults to bar
  "title": "Revenue",
  "source": "data/revenue.csv",  // optional; otherwise inline x/series
  "x": ["Q1", "Q2"],
  "rowColors": ["#003399", "#FFCC00"],  // optional; color per label (pie/donut/radar)
  "minBound": 0,            // optional; cartesian/radar only
  "maxBound": 20,           // optional; cartesian/radar only
  "series": [ { "name": "2025", "data": [10, 14], "color": "#2563EB" } ]
}
```
````

Fields:

- `type` — defaults to `bar`. One of:
  - `bar`, `stackedBar`, `line`, `area`, `scatter` — cartesian (labels on the
    x-axis, values on the y-axis). `area` is a filled line.
  - `horizontalBar` — bars laid out left-to-right; good for rankings and long
    labels.
  - `combo` — bars for every series except the **last**, which is drawn as a
    line on its own right-hand axis (e.g. revenue bars + growth-% line).
    Falls back to a plain bar chart with a single series.
  - `waterfall` — reads the **first** series only; each value is an up/down
    step floating from the previous running total (green up, red down).
  - `pie`, `donut` — proportional; the labels are the segments. `donut` prints
    the series total in the centre hole. Both show at most the first two series.
  - `radar` — spider chart; needs at least three labels (axes).
  - `heatmap` — a grid: each series is a **row**, each label a **column**, the
    cell colour a light→accent ramp over the data range. Label the axes
    likelihood and impact and it reads as a risk matrix.
- `x` — labels; for `pie`/`donut`/`radar` these are the segments/axes (radar
  requires at least three); for `heatmap` they are the columns.
- `series` — named series with `data` (aligned with `x`) and optionally a
  `color` (hex). `pie`/`donut` show at most the first two series; `waterfall`
  uses only the first; `heatmap` treats each series as a row.
- `rowColors` — optional color per label (used by `pie`/`donut`/`radar`).
- `minBound` / `maxBound` — optional; only for the cartesian types and `radar`.
  On `bar`/`stackedBar`/`line`/`area`/`scatter`/`combo`/`waterfall` they are
  horizontal **reference lines**; for `radar` they set the **scale**
  (inner/outer ring) with even spacing. Ignored for `pie`, `donut`,
  `horizontalBar`, and `heatmap`.

**Question** (`question`) — a fenced ```question``` block with the quiz
specification as **JSON**, optionally preceded by a `# title`, an `![](image)`
with caption, and an `<!-- _style: --image-width: N%; -->` comment when an image
is present. The block is the round-trip source of truth.
````markdown
```question
{
  "kind": "multipleChoice",      // multipleChoice | trueFalse | multipleCorrect | ordering
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
  `trueFalse` (the prompt is a statement; pick true/false), `multipleCorrect`
  (several may be correct; pick all), or `ordering` (put the options in the
  right order). Defaults to `multipleChoice`.
- `prompt` — the question, or the statement for `trueFalse`.
- `answers` — the full pool; each has `text` and `correct`. Ignored for
  `trueFalse`. The presentation draws a random subset from it. For `ordering`
  the **list order is the correct order** and the `correct` flags are ignored;
  the drawn subset keeps its relative order as the right answer and is shown
  shuffled.
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
  (horizontal for ≤ 14 events, vertical otherwise).
- `timeline-steps` — reveal one event per click while presenting; absent = the
  whole timeline draws itself in when the slide opens.
- `timeline-static` — no animation; everything is shown at once.

The draw-in **speed** (only meaningful for the default on-enter animation) is the
one numeric option, so it round-trips in an HTML comment rather than a class
token, and only when it differs from the 1600 ms default:

```markdown
<!-- ocideck_timeline_duration: 2600 -->
```

It is the full draw-in duration in milliseconds, clamped to 400–30000 ms.

One event can be highlighted as the **current point** ("where we are now", e.g.
a project's present phase): its card gets a solid accent border and glow, and
its node grows with a halo ring. It round-trips as an HTML comment holding the
**1-based** event number (the Nth list item), and only when a current point is
set:

```markdown
<!-- ocideck_timeline_current: 2 -->
```

A number that does not point at an existing event is ignored (no highlight).
Without a current point the *last* event carries a subtle emphasis by default;
an explicit current point takes that highlight over, so exactly one "you are
here" shows.

> The reveal step (how many events are currently shown in step mode) is
> **session-only** and never written to the file.

**Finding** (`finding`) — a pentest finding's **header card**, stored as plain,
human-readable Markdown so it reads like a report page rather than a machine
block. All structured fields are inline and re-parsed on load:

```markdown
<!-- _class: finding -->
<!-- ocideck_finding_id: F-03 -->
<!-- ocideck_finding_role: header -->
# F-03 · SQL injection in the login form

**Scope object:** `https://app.client.example/login`
**CVSS 4.0:** 9.3 (Critical) · `CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N`
**CWE:** [CWE-89 — Improper Neutralization of SQL](https://cwe.mitre.org/data/definitions/89.html)
**CVE:** [CVE-2024-1234](https://nvd.nist.gov/vuln/detail/CVE-2024-1234)

## Description
…
## Confirmation (reproduction)
…
## Possible impact
…
## Recommendation
…
**Uitvoering testen conform standaard** (`checklist` — the UI label was renamed
from "Checklist"; the class token is unchanged) — a standard-driven test list,
stored as a normal Markdown table so it aligns with the `table` slide and
round-trips losslessly.
The heading is the standard label; the table has a fixed five-column shape:

```markdown
<!-- _class: checklist -->
# Checklist — OWASP WSTG
| ID | Test | Status | Finding | Note |
| --- | --- | --- | --- | --- |
| WSTG-ATHN-07 | Testing for Weak Password Policy | Anomaly | F-03 | |
| WSTG-CRYP-04 | Testing for Weak Encryption | Not testable | — | functionality absent |
| WSTG-SESS-01 | Testing for Session Management |  | — | |
**Scope matrix** (`scope-matrix`) — the scope objects and the extent of testing,
stored as a normal Markdown table (like `checklist`) so it round-trips
losslessly. The heading is the title; the table has a fixed five-column shape:

```markdown
<!-- _class: scope-matrix -->
# Scope
| Object | Type | Standard | Status | Note |
| --- | --- | --- | --- | --- |
| https://app.example | Web | WSTG | Tested | |
| 10.0.0.0/24 | Infra | PTES | Anomaly | one host down |
| firmware.bin | Firmware | FSTM |  | |
```

**Findings summary** (`findings-summary`) — a management overview of how many
findings fall in each CVSS severity band, stored as a normal Markdown table (like
`checklist` / `scope-matrix`) so it round-trips losslessly. The heading is the
title; the table is a fixed two-column count, one row per band:

```markdown
<!-- _class: findings-summary -->
# Bevindingenoverzicht
| Severity | Count |
| --- | --- |
| Critical | 1 |
| High | 2 |
| Medium | 0 |
| Low | 1 |
| None | 0 |
```

- The first column holds the **stable English FIRST band names** (`Critical`,
  `High`, `Medium`, `Low`, `None`) so the table round-trips regardless of
  interface language; the editor and preview localise them (the `None` band is
  presented as "Informational") and colour them per severity.
- The counts are a **deliberate snapshot**: the editor's **Vernieuw uit deck**
  ("refresh from deck") recomputes them from the deck's `finding` header slides
  (each finding's severity is derived from its CVSS vector; an absent vector
  counts as informational), but they remain hand-editable and are stored so the
  slide is self-contained. The **total** shown is derived, never stored.

**Sign-off** (`sign-off`) — the report's truthful-reporting attestation (MIAUW
1.6). The slide itself carries **no body of its own** — only an optional heading;
the attestation is the **deck-level visual signature** (`ocideck_sig_*`) and the
document seal (`ocideck_finalized` / `ocideck_seal_*`), both in the front matter
(§3) and covered by the seal:

```markdown
<!-- _class: sign-off -->
# Ondertekening
```

The editor authors the deck signature (statement, rapporteur name/role,
certification, typed signature) and offers **Afronden & verzegelen**; the preview
renders the signature plus the seal status. Because the signature is deck-level,
one report has one signer, and the sign-off page round-trips as just its class
token and heading — the signer's details live once in the front matter.

Rules:

- The **score and severity band** shown on the `**CVSS 4.0:**` line are always
  **derived** from the vector string by the native CVSS 4.0 engine and rewritten
  on save — they are never a separate stored value. The CWE id/name and the CVE
  ids are likewise parsed back from the inline links; there is no duplicated
  machine block.
- The section headings (`## Description`, `## Confirmation (reproduction)`,
  `## Possible impact`, `## Recommendation`) are **stable English anchors** —
  they are finding *content*, not localised UI, so a finding round-trips
  identically regardless of interface language.
- The whole body rides on the free-Markdown rails in `customMarkdown`, so a
  hand-edited finding is preserved verbatim (file = truth); the structured fields
  are a parsed *view* used by the editor and the severity-card preview.

A finding is authored as a **group**: a header card plus its detail slides
(description, reproduction, impact, recommendation) and evidence slides — a
screenshot (`image`) or a video (`video`), added from the finding editor's
evidence section. Every slide in the group carries the same id and its role — a
`finding`-typed header, plus ordinary `bullets`/`image`/`video` detail and
evidence slides:

```markdown
<!-- ocideck_finding_id: F-03 -->
<!-- ocideck_finding_role: header | detail | evidence -->
```

Both comments are written on any slide with a non-empty finding id (empty = the
slide is not part of a finding). The group carries **one id and one severity**
(derived once from the header's CVSS vector) and moves, deletes and round-trips
as a unit.
- The **Status** column holds the MIAUW tri-state as a **stable English word** —
  `Tested`, `Anomaly`, `Not testable`, or empty (not yet tested) — so the table
  round-trips regardless of interface language; the editor and preview localise
  it for display. Columns are read **by position**, so a translated or reordered
  header never misroutes a value.
- The **Finding** column links a test to a finding id (e.g. `F-03`); `—` means
  none.
- The header line's tested/total count (shown as a progress bar in the app) is
  **derived** from the rows and is not stored.
- The **Type** column drives the **Standard** column: the mapping is fixed
  (Web→WSTG, Infra→PTES, IoT→ISTG, Firmware→FSTM, API→WSTG, Mobile→MASTG, Other→
  none, §10.7), so the standard is **derived from the type** and rewritten on
  save — the type is the source of truth. Type and Status are stable English
  words; columns are read **by position**.
- The **Status** column is the coverage tri-state: `Tested`, `Anomaly`,
  `Unreachable`, or empty (not yet tested).
- The tested/total coverage (shown as a progress bar in the app) is **derived**
  from the rows and is not stored.

### Image Size (`imageSize`)

One integer field with type-dependent meaning: for `image`/`title`/`quote`, it
is the background percentage (`![bg N%]`); for `split`, it is the panel width
(clamped to 20-70%); for two images, it is the `left:`/`right:` split. `0` =
automatic.

For a single **image** slide the percentage controls how the picture fits:

| `imageSize` | Result |
| --- | --- |
| `0` | **Slide-filling (cover)** — fills the whole slide, cropping the overflow. Emitted as a plain `![bg]` with no percentage. |
| `100` | The full image is shown (contain), with letterboxing if the aspect differs. |
| `> 100` | Zoomed in past contain; the excess is cropped. |
| `< 100` (and `> 0`) | Zoomed out, smaller than contain. |

The editor exposes the cover case as an **"Afbeelding slidevullend"**
(slide-filling) checkbox that sets `imageSize` to `0` (ticked) or `100`
(unticked); the zoom control is hidden while it is ticked.

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

### 7.1 Encrypted packages (optional)

When exporting a package you may protect it with a password. Encryption is
**optional** and off by default; an unencrypted package is a plain zip as above.

- **Cipher.** Every file in the zip is encrypted with **AES-256** in the
  **WinZip AES (AE-1)** format (general-purpose-bit-flag bit 0 set, extra field
  `0x9901`). Any AES-zip-aware tool (7-Zip, Keka, WinZip) can open it; the
  built-in macOS Archive Utility cannot.
- **Detection on open.** OciDeck inspects the zip header (no password needed) to
  see whether the package is encrypted, then prompts for the password and
  retries on a wrong one. The central directory (file **names** and structure)
  is *not* encrypted — only file **contents** are.
- **Key derivation.** WinZip AES derives the key with **PBKDF2-HMAC-SHA1, 1000
  iterations**. This iteration count is fixed by the WinZip AES spec and is low
  by modern standards, so a short/guessable password is the weak link. The
  export dialog therefore shows an entropy-based strength meter and offers a
  generator (32 or 256 random characters); with a long or generated password the
  weak KDF is irrelevant.
- **Caveat.** Because file names stay visible and the KDF is weak, ZIP-AES suits
  "keep casual readers out". For strong confidentiality of sensitive material,
  wrap the package in a container with a modern KDF and hidden names (age, GPG,
  or 7-Zip `-mhe=on`).

---

## 8. Special Per-Slide Comments (Overview)

Besides `_class`, OciDeck uses these HTML comments (all ignored by Marp, except
for presenter notes):

| Comment | Meaning |
| --- | --- |
| `<!-- _class: ... -->` | Slide type + behavior (§4). |
| `<!-- _style: --image-width: N%; --split-text-scale: x; -->` | Layout of a `split` slide. |
| `<!-- ocideck_two_bullets_left/right: <base64url> -->` | Canonical storage for the two bullet columns. |
| `<!-- ocideck_bullet_marker: dot\|paw -->` | Per-slide bullet-marker override (bullets/two-bullets/bullets+image). Absent = inherit the theme's `bulletMarker` (§3.2). |
| `<!-- ocideck_image_focus: x,y -->` | Image crop focal point (0..1 per axis, `0.5,0.5` = centre) for the slide's image. Decides which part stays in view when the picture is cropped (fill/zoom, or a fixed image panel). Written only when not centred. |
| `<!-- ocideck_image_focus2: x,y -->` | Same, for the **second** image of a two-images slide. Written only when not centred. |
| `<!-- ocideck_image_alt: text -->` | Per-usage WCAG alt-text (accessibility description) for the slide's image. Preferred over the visible caption as the screen-reader label. Written only when set; `-->` inside is escaped like presenter notes. |
| `<!-- ocideck_image_alt2: text -->` | Same, for the **second** image of a two-images slide. |
| `<!-- ocideck_finding_id: F-03 -->` · `<!-- ocideck_finding_role: header\|detail\|evidence -->` | Finding-group link: ties a header card to its detail/evidence slides (§5). Written on any slide with a non-empty finding id. |
| `<!-- ocideck_ai_assisted: field1, field2 -->` | The slide's fields whose text was drafted by AI and not yet human-reviewed. While any slide carries this marker the deck **cannot be finalised/sealed** (the EIS 1.6 attestation must cover human-verified text). Written only when non-empty; AI drafting sets it and clears it on review. |
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
| **`_class`** | warning | Unknown token in `_class` (known: `title`, `section`, `two-bullets`, `split`, `quote`, `video`, `table`, `code`, `chart`, `finding`, `findings-summary`, `checklist`, `scope-matrix`, `sign-off`, `logo-safe`, `no-logo`, `no-footer`, `table-editable`). |
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
