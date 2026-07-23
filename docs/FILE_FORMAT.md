# OciDeck — File Format

> **Status:** specification of the on-disk format — the stable contract · **Status last reviewed:** 2026-07-22 · **Published by:** Stichting LibreKAT

## Contents

- [1. Project Folder Layout](#1-project-folder-layout)
- [2. Markdown Structure at a Glance](#2-markdown-structure-at-a-glance)
- [3. Front Matter](#3-front-matter)
- [4. Slide Classes and Behavior](#4-slide-classes-and-behavior)
- [5. Per-Slide-Type Markdown Representation](#5-per-slide-type-markdown-representation)
- [6. Sidecars and Separate Data](#6-sidecars-and-separate-data)
- [7. Portable Package (`.ocideck`)](#7-portable-package-ocideck)
- [8. Special Per-Slide Comments (Overview)](#8-special-per-slide-comments-overview)
- [9. Round-Trip and Compatibility](#9-round-trip-and-compatibility)
- [10. Markdown Mode and Syntax Checking](#10-markdown-mode-and-syntax-checking)
- [11. Export Metadata (Not in `.md`)](#11-export-metadata-not-in-md)
- [12. Redaction Manifest Files (Beside an Export)](#12-redaction-manifest-files-beside-an-export)
- [13. Accepted Files and Their Limits](#13-accepted-files-and-their-limits)

*(Added 2026-07-22: this document is around 2,253 lines and had no way in other than scrolling. In the app the documentation reader has full search; on the repository page it did not.)*

OciDeck stores presentations as **standard [Marp](https://marp.app/) Markdown**
(`.md`). There is no custom binary format: a saved presentation is *designed* to
be processed directly with the Marp CLI or the VS Code Marp extension. **That has
not been verified against the real tools** — there is no Node tooling in this
repository and no test that runs one, so treat it as a design goal rather than a
tested guarantee, and tell us if a deck fails in real Marp. *(Corrected
2026-07-22: this promised the round-trip outright. OciDeck has its own renderer
built on `marked` and does not embed Marp Core, which is exactly why the promise
needed testing rather than asserting.)* OciDeck-specific
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
├── My_presentation.miauw.json      # MIAUW-disposition sidecar (see §6.5)
├── My_presentation.seal.json       # seal + signature sidecar (see §6.6)
├── images/                         # copied images
│   ├── photo.png
│   └── .ocideck_captions.json      # caption sidecar (see §6.1)
├── data/                           # linked chart data files (see §6.4)
│   └── revenue.json
├── logos/                          # copied logo from the style profile
│   └── logo.png
├── media/                          # video/audio, created on save (see §7)
└── themes/
    └── ocideck.css                 # generated theme CSS (see §5)
```

> The `.md` filename is derived from the presentation title: non-alphanumeric
> characters are removed and spaces become `_`.

**Before the first save** there is no project folder yet, so an inserted image
or video is copied to a per-session **staging folder** under the OS temp
directory, laid out the same way (`images/`, `media/`). The bytes are therefore
safe from the moment you insert them — moving or renaming the original no longer
breaks the deck — and the ordinary save-time copy moves them into the project
folder because the layout already matches. Until then the editor marks such an
asset as *not yet saved*.

The staging folder is housekeeping, not storage: at startup OciDeck deletes
session folders nothing has touched for the same period recovery files are kept
(7 days), so heavy use without saving does not quietly pile up. The two periods
share one constant on purpose — a recovered draft points at its old session
folder, so staging must never be cleared before recovery is.

When a copy would land on a name that is already taken, the existing file is
reused only if its contents are byte-identical; otherwise the newcomer gets a
numbered suffix (`screenshot_2.png`). Two different pictures that happen to
share a filename therefore stay two pictures.

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
> linked chart data (`data/*.json`, `data/*.csv`, §6.4), the MIAUW
> disposition (`<name>.miauw.json`, §6.5) and the document seal plus visible
> signature (`<name>.seal.json`, §6.6).

> **No base64 in the `.md`.** As of 0.1.0 nothing OciDeck writes into a
> presentation file is opaque. Whatever is unreadable to a human, or is *about*
> the document rather than part of it, lives in a sidecar next to it. What
> remains in the Markdown as an HTML comment is plain text a reader can
> understand and edit (`tlp`, `skip`, `advance`, `ocideck_bullet_marker`,
> `ocideck_image_focus`, `ocideck_title_text_color`, …). The promise this
> upholds: someone with only a text editor and Marp can keep working. See §3.6
> for what moved, and where it went.

---

## 2. Markdown Structure at a Glance

```markdown
---
marp: true
theme: ocideck
paginate: true
... (other metadata) ...
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

### 3.0 The format contract

Four rules govern the front matter. They are written down because a file
outlives the build that wrote it, and because the last of them is a promise made
to future versions of OciDeck rather than to the reader.

**1. Keys OciDeck does not know are kept.** On save, OciDeck does not
regenerate the front matter — it updates the lines that were already there. The
keys it owns (every key in the table below, `marp` included) are replaced,
removed or appended; **every other line stays exactly where it was**, including
`#` comments, blank lines, indented blocks, the original order and the original
quoting. A hand-written `header:`, `footer:`, `size:` or `style:` therefore
survives an OciDeck save unchanged. The implementation is in
`lib/services/front_matter_merge.dart`; the owned keys live there in one list,
which the markdown checker (§10) reads as well.

Two boundaries are worth knowing. Only keys at column 0 count as keys — an
indented `key: value` is read as the inside of the block above it, which is what
keeps a nested `style: |` block intact. And a key OciDeck *does* own is replaced
together with any lines indented underneath it, because leaving those behind
would produce front matter that is no longer valid YAML.

**2. `ocideck_format` is the format version.** One monotonically increasing
integer, not `major.minor`: the only question to answer is "is this file older
than I am?". A file **without** the key is version 1 — that is the normal state
of every hand-written Marp file, never an error, and an unreadable value is read
as version 1 for the same reason.

**3. A reader never lowers the version, and never upgrades on open.** If this
build reads `ocideck_format: 2` it writes `2` back, not `1` — otherwise the file
would lie about itself after one save. That is only safe because rule 1 keeps
the keys of that newer version in place. Upgrading happens **on save, never on
open**: looking at someone else's file must not change it. This is the existing
"migrate on read, persist on first write" policy — see
[MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) and §6.4. An older file always opens
and is never made read-only.

**4. The meaning of an existing key never changes.** A changed meaning gets a
new key. This is the precondition that makes "skip what you do not know" safe
forever: a reader that ignores an unknown key must be able to trust that the
keys it *does* recognise still mean what they meant. Renaming or repurposing a
key would break every older build silently, which is the worst way to break
something.

**The version line is inside the seal, because the seal is over the file.**
Since 0.1.0 the seal hashes the `.md`'s bytes (§6.6), and `ocideck_format` is
one of those bytes. A build that writes a higher version therefore changes the
file and breaks the seal. That is strict on purpose and it is the honest
answer — the file *did* change — but it only bites if something rewrites a
sealed deck, and OciDeck does not: a finalised deck is read-only, so nothing in
the app produces a save. A future format upgrade must skip sealed decks, or
accept that it re-issues them; silently rewriting one and calling the result
intact is the thing this design refuses to do. (Before 0.1.0 the version was
excluded from the hash, because the hash was over a canonicalisation instead of
over the file. See §6.6 for why that changed.)

| Key | Type | Meaning |
| --- | --- | --- |
| `marp` | `true` | Fixed Marp marker. |
| `ocideck_format` | int | The format version of this file (§3.0). Absent means version 1. Written on save; never lowered. |
| `title` | string | Deck title. Written and parsed; also used as the export document title. |
| `theme` | string | Theme name; defaults to `ocideck`. Refers to `themes/<theme>.css`. |
| `paginate` | `true`/absent | Written only when pagination is enabled. |
| `author` | string | Author. |
| `organization` | string | Organization. |
| `version` | string | Version. |
| `date` | string | Date (free text). |
| `description` | string | Description. |
| `keywords` | string | Keywords. |
| `language` | string | The language the report is written in, as a language code (`nl`, `en`, …). This is the **report's** language, not the interface language: a Dutch tester writing for an international client produces an English report from a Dutch UI. Written only when recorded. Findings render their section headings in it while the Markdown keeps its stable English anchors (§4.x / PENTEST_MIAUW §12.3), and recording it satisfies MIAUW EIS 2.3. |
| `standards` | string | Standards the test was carried out against, comma-separated as `name@version` (e.g. `OWASP WSTG@4.2`). MIAUW EIS 4.3.2. The **version is frozen here on purpose**: a report is a record of what was actually used, so reopening it in a build that bundles a newer standard must not silently restate the new version. |
| `tool` | string | One **per line, repeated**, as `name@version \| url \| description` (e.g. `Burp Suite@2026.4 \| https://portswigger.net \| Web proxy`). The tools used during the test — MIAUW EIS 4.8.2 (.1 description, .2 version, .3 public reference). A different list from `standards`: these are the tester's tools, not the standards tested against. Only the name is required; the rest may be filled in later. |
| `tlp` | enum | Traffic Light Protocol level (§3.1). Written only when not `none`. |
| `ocideck_target_seconds` | int | Target duration for the presenter countdown, in seconds. Written only when `> 0`. |
| `ocideck_show_rehearsal_summary` | `false`/absent | Opt-out of the post-presentation timing summary. Default (shown) stays out of the file; only `false` is written. Overruled by `ocideck_play_only`: a play-only deck never shows the summary, whatever this key says. |
| `ocideck_play_only` | `true`/absent | Play-only lock. When `true`, the deck opens locked: no editor, toolbar, menus, or export — only the first slide with a play button, presented full screen. Closing the deck restores normal editing. Default (unlocked) stays out of the file; only `true` is written. Removing this key unlocks the deck. |
| `ocideck_style_profile` · `ocideck_miauw_waivers` · `ocideck_miauw_confirmations` · `ocideck_finalized` · `ocideck_seal_hash` · `ocideck_seal_algo` · `ocideck_seal_at` · `ocideck_seal_tsr` · `ocideck_sig_name` · `ocideck_sig_role` · `ocideck_sig_cert` · `ocideck_sig_date` · `ocideck_sig_statement` · `ocideck_sig_typed` · `ocideck_sig_image` | *retired* | **No longer written** as of 0.1.0 (§3.6). Still read, so an older file opens correctly; removed from the file on the next save. The seal and signature blocks now live in `<name>.seal.json` (§6.6). |

Metadata fields are written only when they are not empty. Text is written as a
YAML scalar and quoted only when needed (empty value, leading/trailing
whitespace, special characters such as `: # "`, or a YAML indicator at the
start). OciDeck does not use a full YAML parser when reading; it uses a simple
line-by-line parser, so keep front matter flat (one key per line).

Only the keys above (plus `marp`) are read; any other front-matter key — a typo,
or a Marp option OciDeck does not implement such as `header`, `footer`, `size` or
`style` — has no effect inside OciDeck, but it is **kept on save** (§3.0, rule
1). The in-app markdown checker flags such keys with a warning so they are not
mistaken for having an effect. Likewise, a comment that
looks like a directive (`<!-- _key: … -->` or `<!-- ocideck_key: … -->`) but is
not one OciDeck understands — e.g. Marp's per-slide `_paginate`, `_header`,
`_footer`, `_color` — is dropped and flagged; plain prose comments remain speaker
notes.

### 3.6 Retired keys — what moved out of the front matter, and where it went

Fifteen keys left the front matter in 0.1.0. None of them are written any more.
They are still **read**, so an existing file opens exactly as before, and they
are **removed from the file on the next save** — the deck is written back in the
new shape without the author doing anything.

| Retired key | Where it lives now |
| --- | --- |
| `ocideck_style_profile` | Never on disk to begin with; only in the transient beamer stream. Now travels beside that markdown as plain JSON (§3.2). |
| `ocideck_miauw_waivers` | `<name>.miauw.json`, key `waivers` (§6.5). |
| `ocideck_miauw_confirmations` | `<name>.miauw.json`, key `confirmations` (§6.5). |
| `ocideck_finalized` · `ocideck_seal_hash` · `ocideck_seal_algo` · `ocideck_seal_at` · `ocideck_seal_tsr` | `<name>.seal.json` (§6.6). |
| `ocideck_sig_name` · `ocideck_sig_role` · `ocideck_sig_cert` · `ocideck_sig_date` · `ocideck_sig_statement` · `ocideck_sig_typed` · `ocideck_sig_image` | `<name>.seal.json`, key `signature` (§6.6). |

Two of these carried base64 (`ocideck_seal_tsr` is a DER timestamp token,
`ocideck_sig_image` a PNG), which is reason enough on its own. But the seal
block had a second, larger reason to move: as long as the seal lived *inside*
the file, the hash could not be a hash *of* the file. Moving it out is what made
the integrity check reproducible by a third party — see §6.6.

**Migrating a sealed deck.** A deck sealed before 0.1.0 opens normally, its seal
still verifies, and its seal block moves into `<name>.seal.json` on the first
save. What does **not** happen is a recomputation: the sidecar records the old
hash together with `"form": "canonical-v1"`, and OciDeck keeps verifying it the
old way. Re-issuing that hash would invalidate any RFC 3161 token the report
carries — the token timestamps that exact value — and a real notarisation is
worth more than the convenience of one uniform format.

The removal is what makes this a migration rather than a rename. In
`front_matter_merge.dart` these keys did not simply disappear from the owned
list — they moved to a second list, `kRetiredFrontMatterKeys`. A key on
*neither* list falls under rule 1 above ("keys OciDeck does not know are kept")
and would sit in the file forever. Being on the retired list means the opposite:
the line is dropped on save and never written back. The markdown checker (§10)
knows them too, so it does not report them as unknown keys.

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

### 3.1b Privacy disposition — `privacy:` / `<!-- ocideck_privacy: … -->`

What happens to privacy findings. Four stable values: `warn` (the default, never
written), `accept`, `shield`, `redact`.

```markdown
---
marp: true
theme: ocideck
privacy: accept
---

# Suspect

<!-- ocideck_privacy: redact -->
```

**A slide overrides the deck** — deliberately unlike `tlp`, where the stricter
level wins. A deck on `accept` (the whole briefing is known) with one slide on
`redact` (this one detail is for nobody) must work; the author of that slide knows
best. `effectivePrivacyDisposition` in `lib/models/privacy_disposition.dart`.

`shield` shows a **PERSONAL DATA** badge on the slide, next to the TLP marking,
and it rasterises into PDF/PPTX like any other overlay. `redact` replaces every
detected value with blocks in everything rendered or exported — see §3.1a; the
Markdown on disk is untouched either way.

Note that `redact` is honoured **regardless of the "warn about possible personal
data" setting**. That setting governs warnings, not redaction: otherwise silencing
the messages would silently stop the redaction too.

### 3.1c Quality disposition — `<!-- ocideck_quality: … -->`

What happens to the quality findings on a slide. Two stable values: `warn` (the
default, never written) and `accept`.

```markdown
# Cover image

<!-- ocideck_quality: accept -->
```

`accept` says *this is how the slide is meant to be*: a title image that
deliberately contrasts softly, a table that genuinely has that many rows. The
findings do not disappear — the thumbnail badge turns grey and the export gate
stops counting them, but they stay readable. Accepting must not become a way of
hiding.

**Slide-level only; there is no deck-wide counterpart.** Unlike `privacy:`, a
deck that accepts every contrast error in one go is not a judgement about the
content but a switch, and that switch already exists under *Settings → General*.
A quality verdict is about *this* slide.

An unrecognised value falls back to `warn`, not to `accept`. A deck written by a
newer OciDeck must never cause an older one to silently suppress findings it does
not understand; at worst the author makes the choice again.

### 3.1a Redaction markers — `[[…]]`

Text between double square brackets is **redacted**: replaced by a fixed run of
`█` in everything the deck renders or exports.

```markdown
The suspect, [[Jan de Vries]], was arrested at [[Kalverstraat 12]].
```

It is inline body text, not a directive, so it needs no escaping rule and
round-trips through parse/generate untouched. The regex is
`\[\[([^\[\]]*)\]\]` — no nested brackets, so an ordinary Markdown link
(`[text](url)`) never matches.

**The marker stays in the file.** Redaction is applied by `PrivacyProjection`
(`lib/services/privacy/privacy_projection.dart`) at the boundary between the
source deck and every receiving surface — preview, presenter, audience window,
rasteriser (PDF/PPTX), HTML, speaker notes, and document metadata. The Markdown
on disk is never rewritten, so the same source can produce a full version and a
redacted one.

**The replacement has a fixed width** (8 blocks) regardless of the original
length. Mirroring the length would tell the reader what kind of value was
removed and how long it was, which for short structured values (a BSN, a phone
number) comes uncomfortably close to reconstructable.

Two consequences worth knowing about:

- A slide containing a redaction has `tableEditable` forced off in the
  projection. The presenter writes a live table edit back as a whole slide, and
  it only ever saw the blocks.
- Redaction covers slide fields (title, subtitle, bullets, column titles,
  captions, alt text, quotes, free Markdown, table cells, the checklist scope,
  **speaker notes**) and every deck field the scanner reads: title, author,
  organisation, description, keywords, version, date, standards used, tools used,
  and the two MIAUW justification maps (waivers and confirmations). The last six
  were scanned but not redacted until 2026-07-21, which meant the export gate
  reported a finding that *Redact* could not clear while the value still
  travelled. Media is handled differently: on a redacted slide the whole image,
  video or audio reference is dropped rather than blacked out, because a path
  with blocks in it is a broken reference.
- Redaction deliberately does **not** cover `userNotes` — those are the
  recipient's own sidecar notes, they reach no export artefact, and projecting
  them would let the presenter write blocks over someone's own annotations.

### 3.2 The Style Profile

**No file ever contains the style profile.** Styling is deliberately kept out of
the `.md`: the file holds content, and the app applies the active style profile
when it opens the deck. Styling travels as `themes/<theme>.css` and the app's
own profile; a standalone profile can be exchanged as `.ocideckstyle` (§9).

Until 0.1.0 there was one exception: the transient markdown streamed to the
audience (beamer) window carried the profile as `ocideck_style_profile`,
base64url-encoded, because that window has no other way to learn the styling.
It now travels **next to** that markdown, as plain JSON in the `styleProfile`
field of the window's opening message. That was the last thing in OciDeck that
could put base64 into a Markdown document.

A file that still carries the old key opens fine — the key is simply ignored,
and it is removed on the next save (§3.6). The profile itself is JSON with
these fields (with defaults):

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

### 3.3 Standalone Style Profile (`.ocideckstyle`)

A style profile also travels on its own, so a profile can be shared without a
deck around it. The settings dialog exports the profile currently in the editor
and imports one back (the buttons next to the profile name).

The file is plain UTF-8 JSON — an envelope around the same profile JSON as
§3.2:

```json
{
  "ocideck": "style-profile",
  "version": 1,
  "profile": { "name": "…", "accentColor": "#2E7D64", "…": "…" },
  "logo": { "mime": "image/png", "data": "<base64>" }
}
```

| Key | Meaning |
| --- | --- |
| `ocideck` | Format marker; must be `style-profile`. Import refuses anything else, so an arbitrary `.json` cannot be mistaken for a profile. |
| `version` | Envelope version (currently `1`). A higher number is refused rather than half-read. |
| `profile` | The profile, exactly the §3.2 field set. Unknown/missing fields fall back to defaults. |
| `logo` | **Optional.** An embedded custom logo. `mime` is informational — the importer re-derives the type from the bytes themselves. |

Import accepts the `.ocideckstyle` and `.json` extensions. Caps: 16 MiB per
file, 8 MiB per embedded logo.

**How the logo travels.** `logoPath` is a local path and means nothing to the
receiver, so it is handled by kind:

- **No logo** (`null`) — nothing to do.
- **Built-in logo** (`asset:…`) — stays a reference; every install carries the
  same bundle.
- **Custom logo** — the image bytes are embedded as base64 in `logo` and
  `profile.logoPath` is written as `null`. This keeps the file portable and
  avoids leaking the sender's local path (which contains their user name).

On import the embedded bytes are written back to a real file and `logoPath`
points at it: a `data:` URI is never left in `logoPath`, because none of the
consumers (slide preview, rasterizer, presenter) resolve one.

> **Web caveat.** On desktop the restored logo lands in a `style_logos/` folder
> under the app-support directory and survives a restart. On web there is no
> persistent byte store, so the logo goes into the in-memory store and is gone
> after a reload — the profile itself (all colours, fonts, footer, …) stays
> intact and only the logo falls back to a placeholder.

**Security.** An imported profile is untrusted input and goes through the same
hardened `ThemeProfile.fromJson` gate as a profile from a deck: colours are
validated to strict `#RRGGBB` and font families are whitelisted, because these
values are interpolated into a `<style>` block on export. A profile without an
embedded image but *with* a bare `logoPath` has that path dropped — it points at
the sender's disk and would not resolve anyway.

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
| Scorecard | `scorecard` | — |
| Asset overview | `assets` | — |
| Discoveries | `discoveries` | — |
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

A bullet list can be broken into visually separated groups with **group
headings** ("tussenkoppen"): a labelled break, or an empty one that renders as
just a divider rule. Like the redaction marker (§3.1a), it is an inline sentinel,
not a comment: a heading is an ordinary `bullets` entry whose text starts with
the private-use marker `U+E010`, so it rides the normal list
read/write path and keeps its position in the list; it never carries a checkbox
or a number and never consumes a list number. It is written as a plain list item
(`- ␀Ochtend`, where `␀` is the marker) — valid Marp, and in OciDeck's own
rendering/exports it draws as an accent-coloured label above a thin rule:

```markdown
- ␀Ochtend
- Inloop
- Keynote
- ␀Middag        (a second group)
- Workshops
- ␀             (an empty heading = a wordless divider)
- Borrel
```

**Rich text** (`<!-- ocideck_list_style: richText -->`) — a bullets or
bullets-with-image slide whose body is free Markdown instead of a list. After the
heading lines the comment is written, then a blank line, then the body as it was
typed:
```markdown
# Heading
<!-- ocideck_list_style: richText -->

A paragraph, **bold**, a `- list` if you want one, all of it ordinary Markdown.
```

**An `![alt](path)` alone on a line in such a body is an image**, drawn in the
flow of the text rather than left as literal Markdown (since 2026-07-22). It is
written and read back verbatim — there is no OciDeck marker around it — so this
costs the format nothing; what changed is that OciDeck now looks at it. Two
reading rules:

- The image must be the **whole line**. A `![…](…)` inside a paragraph stays part
  of that paragraph's text, so a sentence is never broken in half.
- `w:` and `h:` **inside the alt text** set its size, following Marp's own
  convention: `![Login screen w:600 h:400](images/login.png)`. They count against
  a slide 1280 wide — Marp's measure, and the width the HTML export uses — not
  against OciDeck's internal 960 layout unit, so the same directive means the
  same thing in the app and in the export. Without `w:` the image spans the text
  column; without `h:` it gets a fixed box of `kMarkdownImageDefaultHeightFraction`
  (a quarter) of the reference width, and is scaled to fit inside it. A value that
  is not a positive finite number is ignored rather than honoured. To any other
  Markdown reader the whole of `Login screen w:600 h:400` is just alt text.

The box is derived from the Markdown alone and never from the image file:
pagination is synchronous and cannot wait for a decode, so the height a line
reserves must be readable off the text. `lib/services/markdown_body_blocks.dart`
holds both the parse and the box, and the paginator and the renderer call the
same function — the reserved and the drawn height cannot drift apart.

An empty path (`![alt]()`) is deliberately kept as an image block: that is what
the privacy projection leaves behind when it removes the picture of a redacted
slide, and keeping the block keeps the layout from shifting.

**The page split of such a body is not in the file.** Text that would have to
shrink below the readable floor to fit one slide is broken into pages while
rendering, worked out from the theme (the font, and the reserve a logo or footer
claims) at the reference 16:9 geometry — `lib/services/rich_text_layout.dart`. The
same file can therefore be one page under one theme and three under another, and
there is no page marker to hand-edit. `Slide.renderPage`, which says which page a
rendered copy draws, exists only for surfaces that enumerate slides instead of
paging through them (the export; see ARCHITECTURE § *Render-time pagination*). It
is never written and never read: a slide that came from a file always has it at 0.

**Two bullet columns** (`two-bullets`) — **the visible HTML is the content.**
Until 0.1.0 both columns were also stored as base64 in four comments above the
grid, and those comments won; the `<ul><li>` below them was decoration. Worse:
the parser skipped every non-heading line on a `two-bullets` slide, so a
hand-written two-column slide did not lose to the comments — it was never read
at all, and arrived as two empty columns. Both are gone. What you see is what is
stored:

```markdown
<!-- _class: two-bullets -->

# Heading
## Subheading (optional)

<div class="ocideck-two-bullets">
<div>
<h3>Left column heading</h3>
<ul>
<li>First point</li>
<li style="margin-left:1.4em;">Subpoint</li>
</ul>
</div>
<div>
<h3>Right column heading</h3>
<ul><li>Other point</li></ul>
</div>
</div>
```

Reading rules, all of them tolerant of hand-written markup (the style
attributes OciDeck writes are optional):

| What you write | What it means |
| --- | --- |
| `<ul>` / `<ol>` | Starts a column. The first is the left column, the second the right; a third is ignored. |
| `<ol>`, or `<li value="…">` | The list is **numbered**. |
| `<h3>…</h3>` before a list | The heading above that column. Written only when filled. |
| `<li>…</li>` | One list item, in the column it sits in. |
| `<li style="margin-left:1.4em;">` | One indentation level (`1.4em` per level). |
| `<li>☑ …` / `<li>☐ …` | A **checklist** item, ticked or not. Stored as `[x] …` / `[ ] …`. |
| `<li style="list-style:none; …">Label</li>` | A group heading (§ above). With no text: a wordless divider. |

Text inside an `<li>` or `<h3>` is HTML-escaped on write and unescaped on read,
so a bullet may contain `<`, `>`, `&`, `"` **and a pipe** — the very cases the
base64 was introduced for. `&lt;b&gt;bold&lt;/b&gt;` reads back as the literal
text `<b>bold</b>`.

The list style follows the visible markup in **both** directions. `<ol>`/`value=`
makes it numbered, a `☑`/`☐` makes it a checklist, and items carrying neither
make it a plain bullet list — so deleting the tick boxes by hand actually turns
the checklist off. `<!-- ocideck_list_style: … -->` is still written and read,
but only as the starting value; the markup overrules it. (The same downgrade
applies to a single-column bullet list: a `checklist` comment with no `[x]`/`[ ]`
items left reads as plain bullets.)

For a file written by an older OciDeck the old comments are still read, but only
as a fallback for when there is no visible list at all — a file whose grid was
cut out by hand. When both are present the visible markup wins, and on the next
save the comments are gone.

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

**The `split-image` div decides which image is the side image.** On a slide whose
body is rich text (§ *Rich text*), only a `![…](…)` **inside** that div becomes
`imagePath`; one in the `split-text` half is an image in the running text and
stays in the body. The rule used to be "the first `![…]` on a split slide is the
side image"; since a body may hold pictures of its own (2026-07-22) that rule
would swallow one the author put in the text. Leaning on the scaffolding is safe
here because this branch only runs for a
body carrying `<!-- ocideck_list_style: richText -->`, a marker only OciDeck
writes — so the div is there too; a hand-written Marp split slide has no rich-text
body and is read down the bullet path.

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

Add `table-overdue` (see §4) to mark expired dates: a body cell whose entire
content is an ISO `yyyy-mm-dd` date earlier than the day the deck is shown
renders red and bold. Nothing on disk records *that* a cell is late — only the
date is stored, and lateness is judged at render time, so a deck presented months
later marks itself. Only the strict ISO form is recognised; a cell that is not a
bare date is never marked. Absent by default, so an existing table never changes
appearance.

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
**JSON**. The data may sit inline, or in a data file in `data/` that `source`
points at (see §6.4). When saving, the values move out as soon as a `source`
exists; when opening, that file is read back in. Styling — colours, title,
bounds — always stays in the block, never in the data file.
````markdown
```chart
{
  "type": "bar",            // see the type list below; defaults to bar
  "title": "Revenue",
  "source": "data/revenue.json",  // optional; otherwise inline x/series
  "x": ["Q1", "Q2"],
  "rowColors": ["#003399", "#FFCC00"],  // optional; color per label (pie/donut/radar)
  "minBound": 0,            // optional; cartesian/radar only
  "maxBound": 20,           // optional; cartesian/radar only
  "animateOnEnter": false,  // optional; only written when false
  "animationDurationMs": 600,  // optional; omitted = inherit the theme
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
  - `horizontalStackedBar` — a `stackedBar` on its side: one bar per label with
    the series stacked left-to-right; part-to-whole with long labels.
  - `combo` — bars for every series except the **last**, which is drawn as a
    line on its own right-hand axis (e.g. revenue bars + growth-% line).
    Falls back to a plain bar chart with a single series.
  - `waterfall` — reads the **first** series only; each value is an up/down
    step floating from the previous running total (green up, red down).
  - `pie`, `donut` — proportional; the labels are the segments. `donut` prints
    the series total in the centre hole. Both show at most the first two series.
  - `radar` — spider chart; needs at least three labels (axes).
  - `bullet` — target-and-actual: one row per label with grey background bands
    for the scale you judge against, a thin measure bar for the actual value,
    and a tick where the agreed target sits. Reads the **first** series only.
    The point is that the target is drawn *as a target* — a mark on the ruler —
    rather than as a second bar; for an SLA story that is the difference between
    "two numbers" and "met or not met". Without `targets` it degrades to a plain
    horizontal bar, so a half-filled chart still says something.
  - `heatmap` — a grid: each series is a **row**, each label a **column**, the
    cell colour a ramp over the data range. Label the axes likelihood and
    impact and it reads as a risk matrix. Unlike every other type, a heatmap
    is *not* tinted with the deck's accent: it uses a fixed, theme-independent
    heat ramp (pale→red on a light slide, dark→bright on a dark one), so a
    heatmap reads as magnitude rather than as the theme. `rowColors` and the
    per-series `color` are therefore ignored for this type.
- `x` — labels; for `pie`/`donut`/`radar` these are the segments/axes (radar
  requires at least three); for `heatmap` they are the columns.
- `series` — named series with `data` (aligned with `x`) and optionally a
  `color` (hex). `pie`/`donut` show at most the first two series; `waterfall`
  uses only the first; `heatmap` treats each series as a row.
- `targets` — **`bullet` only**: the agreed norm per label, parallel to `x`.
  A target belongs to an x position rather than to a series, which is why it is
  its own list and not a `ChartSeries` — the one thing this chart type needed
  the model widened for. A shorter list simply leaves the later rows without a
  marker; not every row has an agreed norm.
- `bands` — **`bullet` only**: qualitative thresholds shared by every row, drawn
  as background bands. `[60, 80]` reads as poor below 60, satisfactory 60–80,
  good above. Shared rather than per row on purpose: bands express the scale you
  judge against, and a scale that changes per row is not a scale.
  Both are written to the block **only** for `bullet`, so switching a chart to
  another type does not leave a stray target behind.
- `rowColors` — optional color per label (used by `pie`/`donut`/`radar`).
- `minBound` / `maxBound` — optional; only for the cartesian types and `radar`.
  On `bar`/`stackedBar`/`line`/`area`/`scatter`/`combo`/`waterfall` they are
  horizontal **reference lines**; for `radar` they set the **scale**
  (inner/outer ring) with even spacing; for `bullet` `maxBound` pins the axis
  (e.g. to 100 for a percentage) instead of letting it follow the data. Ignored
  for `pie`, `donut`, `horizontalBar`, `horizontalStackedBar`, and `heatmap`.
- `animateOnEnter` — whether the chart draws itself in (values growing from the
  baseline) when the slide comes up in presentation mode. Defaults to `true` and
  is only written to the block when turned **off**, so a clean chart stays clean.
- `animationDurationMs` — per-slide override of that draw-in duration. Omitted
  means inherit the theme's `animationDurationMs`; it is only written when set.
- `source` — optional path to a data file holding `x` and `series` (§6.4). When
  present, the values are omitted from the block on save. `x` disappears
  entirely; `series` disappears too *unless* a series carries a `color`, in
  which case the block keeps a stripped `series` array of names and colours
  (no `data`) — the colours are styling and have nowhere else to live.

**Question** (`question`) — a fenced ```question``` block with the quiz
specification as **JSON**, optionally preceded by a `# title`, an `![](image)`
with caption, and an `<!-- _style: --image-width: N%; -->` comment when an image
is present. The block is the round-trip source of truth.
````markdown
```question
{
  "kind": "multipleChoice",      // see the six kinds below
  "prompt": "What is the capital of the Netherlands?",
  "optionCount": 4,              // multipleChoice + ordering only
  "timeLimitSeconds": 0,         // 0 = no limit
  "onWrong": "retry",            // retry | lockAndContinue
  "statementIsTrue": true,       // trueFalse only
  "similarityThreshold": 0.85,   // openText only
  "answers": [
    { "text": "Amsterdam", "correct": true },
    { "text": "Rotterdam", "correct": false }
  ]
}
```
````

Fields:

- `kind` — one of six values, defaulting to `multipleChoice`:
  - `multipleChoice` — one correct answer plus a random pick of wrong ones; pick one.
  - `trueFalse` — the prompt is a statement; pick true/false.
  - `multipleCorrect` — several may be correct; pick all. **Every** filled-in
    answer is shown, in random order (*corrected 2026-07-21: this used to be a
    random subset, and this section described it as one*).
  - `ordering` — put the options in the right order.
  - `imagePair` — two pictures side by side, pick the right one. Which picture
    lands left and which right is redrawn every round.
  - `openText` — the viewer types the answer; it counts as right when it is
    close enough to one of the answers marked `correct`.
- `prompt` — the question, or the statement for `trueFalse`.
- `answers` — the full pool; each has `text`, `correct` and optionally `image`.
  Ignored for `trueFalse`. For `multipleChoice` and `ordering` the presentation
  draws a random subset of `optionCount` from it; `multipleCorrect` shows every
  filled-in answer, shuffled. For `ordering` the **list order is the correct
  order** and the `correct` flags are ignored; the drawn subset keeps its relative
  order as the right answer and is shown shuffled. For `imagePair` each round
  draws **one** `correct: true` and **one** `correct: false` answer and shuffles
  the pair, so the editor's two slots are the common case but a longer pool in the
  file gives a fresh pair every round. For `openText` the entries with
  `correct: true` are the accepted answers and the rest are ignored.
- `answers[].image` — a deck-relative image path, for `imagePair`: there the
  picture *is* the answer and `text` is only its caption. **Written only when it
  has a value**, so a text-only question keeps the two-key answer objects it
  always had. An `imagePair` question counts an answer as filled in when it has an
  image, not when it has text; every other kind still goes by `text`.
- `optionCount` — how many options are shown (2–8, default 4). Only used by
  `multipleChoice` and `ordering`; the other kinds show every filled-in answer or
  no option list at all. Always written.
- `timeLimitSeconds` — optional countdown; running out counts as wrong.
- `onWrong` — `retry` (cannot continue; a fresh set is drawn on the next click) or
  `lockAndContinue` (reveal the answer, lock the slide, allow advancing).
- `statementIsTrue` — for `trueFalse`, whether the statement is true. Written for
  that kind only.
- `similarityThreshold` — for `openText`, how much a typed answer must resemble an
  accepted one (Jaro-Winkler over the normalised strings, `0.5`–`1.0`, default
  `0.85`). Written for that kind only; a value outside the range is clamped when
  the block is read.

> The live answer state (which options were drawn, what the viewer picked, what
> was typed, correct/wrong) is **session-only** and never written to the file. A
> static export renders the question without interactivity; in the HTML export an
> `imagePair` question emits its two pictures as ordinary Markdown images after
> the question card (so their paths resolve like any other deck image) and an
> `openText` question emits no options at all, because its accepted answers are
> the answer key.

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

**Scorecard** (`scorecard`) — a handful of headline figures, each with the figure
from the previous report beside it, so a recurring report leads with what
changed. Stored as a normal Markdown table (like `checklist` / `scope-matrix`) so
it round-trips losslessly and a generator can write one without the app. The
heading is the title:

```markdown
<!-- _class: scorecard -->
# Sinds de vorige rapportage
| Label | Value | Previous | Unit | Polarity |
| --- | --- | --- | --- | --- |
| Assets in beeld | 412 | 375 |  | neutral |
| Open bevindingen | 96 | 120 |  | lower-better |
| Gemiddeld openstaand | 62 | 73 | dagen | lower-better |
```

- **`Value` / `Previous`** are the figure now and the figure it replaces. The
  *previous value* is stored rather than a computed delta, so the difference
  always agrees with the two numbers and the file stays verifiable. `Previous` is
  written as an **empty cell** when there is no earlier measurement — distinct
  from a zero — and the slide then shows no change at all, rather than claiming a
  figure held steady when it was never measured before.
- **`Polarity`** is one of the stable English tokens `lower-better`,
  `higher-better` or `neutral` (an unrecognised value reads as `neutral`). It
  decides only the **colour** of a change; the direction of the arrow always
  follows the numbers. The deck cannot derive this — more assets in view is good
  news when you are inventorying and bad news when you are decommissioning.
- **`Unit`** is optional free text shown beside the figure.
- At most **five** rows are kept, on both read and write. Numbers accept a comma
  as the decimal mark when unambiguous (one comma, no dot); thousands separators
  are refused rather than guessed at. A row that is entirely blank is dropped at
  both ends, so writing and reading agree.

**Asset overview** (`assets`) — the attack surface broken into the kinds of
object it consists of. Stored as a normal Markdown table, like `scorecard`:

```markdown
<!-- _class: assets -->
# Ons aanvalsoppervlak
| Group | Total | AtRisk | New | Unowned |
| --- | --- | --- | --- | --- |
| Webapplicaties | 182 | 12 | 7 | 3 |
| Mailservers | 24 | 1 | 0 | 0 |
| VPN-endpoints | 3 | 2 | 0 | 0 |
```

- A row is a **kind** of exposed object, not one object. A scan returns hundreds
  and a management slide carries eight lines; listing individual hosts turns the
  slide into an appendix. The per-object detail belongs in the tool that produced
  it.
- **`Total`** is how many were found; **`AtRisk`**, **`New`** and **`Unowned`**
  are subsets of it — carrying an open finding, first seen in this scan, and
  having nobody's name against them. That last one is a governance figure rather
  than a technical one: an object without an owner has nobody to fix it.
- Deck-wide totals are **derived, never stored**, so they cannot disagree with
  the rows above them. Same rule as the findings summary's total.
- A count that exceeds its group's total is **shown as given**; only the drawn
  bar is clamped so it cannot overrun its row. Silently correcting it would hide
  the fault in whatever produced the number. The editor flags it.
- Counts are whole numbers; a negative or unreadable value reads as zero. At most
  **eight** rows are kept, on both read and write, and an entirely blank row is
  dropped at both ends.
- Note that "asset" here means an exposed object. Elsewhere in the format (the
  `.ocideck` package, `data/`, image paths) "asset" means a media file.

**Discoveries** (`discoveries`) — the named objects a scan turned up that were
not in any inventory beforehand. Stored as a normal Markdown table, like
`assets` and `scorecard`:

```markdown
<!-- _class: discoveries -->
# Wat we niet wisten te hebben
| Discovery | Kind | DaysUnnoticed | Owner |
| --- | --- | --- | --- |
| betaalportaal-acc.example.nl | Webapplicatie | 412 | Team Betalen |
| oud-intranet.example.nl | Webapplicatie | 280 |  |
| mail-relay-03.example.nl | Mailserver | 190 | Infrastructuur |
```

- Deliberately narrower than "new asset". The asset overview already counts what
  is new per category; this is the **named list** of the ones nobody knew about
  — shadow IT, a forgotten acceptance environment, a certificate issued by a team
  that has since been reorganised away.
- **`DaysUnnoticed`** is how long the object was reachable before anyone noticed.
  Written as an **empty cell** when it is not known — distinct from a zero, which
  would claim the object was found the day it appeared. An unknown exposure draws
  no bar and the row reads "onbekend"; that is the common case for a first scan,
  which has no history to measure against. A negative or unreadable figure reads
  as unknown for the same reason.
- **`Owner`** is who owns it now that it is known. An empty cell means nobody
  does, and the slide says so in red — the governance problem, and the reason a
  discovery can still be a discovery next quarter.
- The **longest exposure** is the headline the slide leads with, and the scale
  every bar is drawn to. Both are **derived, never stored**: a stored headline is
  a second number that can disagree with the rows under it, and per-row bar
  scaling would draw three days the width of four hundred.
- The slide is not simply a `table` because of that derivation. A table can hold
  the same four columns; it cannot say which row is the problem.
- At most **six** rows are kept, on both read and write — more names make an
  appendix rather than a slide, and the generator picks the ones worth naming.
  An entirely blank row is dropped at both ends, so writing and reading agree.

**Actions** (`actions`) — **retired.** This was a `table` with a fixed header
row and a typed editor over it; the rows always lived on disk as an ordinary
Markdown table. A file carrying the token still opens: the parser reads `actions`
as `table` and the rows come through unchanged, so no conversion step exists or
is needed. New decks write `table`.

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
`**MASWE:** [MASWE-0005 — API Keys Hardcoded in the App Package](https://mas.owasp.org/MASWE/MASVS-AUTH/MASWE-0005/)` — the mobile weakness (OWASP MASWE), written alongside `**CWE:**` rather than instead of it. Only the **id** is authoritative: the title and the category in the URL are resolved from the bundled catalogue when writing, so a weakness whose title OWASP later adjusts is not frozen in the report. An id the bundled catalogue does not know is kept verbatim, without a link.
**CVE:** [CVE-2024-1234](https://nvd.nist.gov/vuln/detail/CVE-2024-1234)
**Test:** `WSTG-ATHN-07`
**Retest:** Resolved — hertest 2026-07-20, patch toegepast

## Description
…
## Confirmation (reproduction)
…
## Possible impact
…
## Recommendation
…
```

**Uitvoering testen conform standaard** (`checklist` — the UI label was renamed
from "Checklist"; the class token is unchanged) — a standard-driven test list,
stored as a normal Markdown table so it aligns with the `table` slide and
round-trips losslessly.
The heading is the standard label; the table has a fixed five-column shape:

A checklist may be **linked to a scope object** (the scope element it covers) via
an `<!-- ocideck_checklist_scope: … -->` comment carrying the plain object string
(matched to the scope matrix by the same normalisation as the finding↔scope link).
It is written only for `checklist` slides and only when set:

```markdown
<!-- _class: checklist -->
<!-- ocideck_checklist_scope: https://app.example/login -->
# Checklist — OWASP WSTG
| ID | Test | Status | Finding | Note |
| --- | --- | --- | --- | --- |
| WSTG-ATHN-07 | Testing for Weak Password Policy | Anomaly | F-03 | |
| WSTG-CRYP-04 | Testing for Weak Encryption | Not testable | — | functionality absent |
| WSTG-SESS-01 | Testing for Session Management |  | — | |
```

**Scope matrix** (`scope-matrix`) — the scope objects and the extent of testing,
stored as a normal Markdown table (like `checklist`) so it round-trips
losslessly. The heading is the title; the table has a fixed eight-column shape:

```markdown
<!-- _class: scope-matrix -->
# Scope
| Object | Type | Standard | Status | Note | C | I | A |
| --- | --- | --- | --- | --- | --- | --- | --- |
| https://app.example | Web | WSTG | Tested | | H | M | L |
| 10.0.0.0/24 | Infra | PTES | Deviation | one host down | | | |
| firmware.bin | Firmware | FSTM |  | | | | |
```

The last three columns are the object's **CIA rating** — how important it is on
Confidentiality (`C`), Integrity (`I`) and Availability (`A`) — each `H`/`M`/`L`
or empty (not rated). They map to the CVSS 4.0 Environmental Security
Requirements (`CR`/`IR`/`AR`) and give every finding on this object a **context
(environmental) score** derived from its base vector — the weighting lives here,
not in the finding. The `C`/`I`/`A` columns are **appended after `Note`**, so a
matrix written by an older version (five columns, no rating) still parses: the
missing cells simply read as "not rated".

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
| Resolved | 1 |
```

The last `Resolved` row is the **retest-resolved total** ("x opgelost na
hertest") — a separate figure from the bands (resolved findings still count as
found). It is appended after the five bands; a table without it reads `0`. Each
finding's own retest outcome lives on its header via a `**Retest:**` meta line
(`Resolved` / `NotResolved` / `PartiallyResolved`, optionally `— <note>`; absent
when not retested). A finding may also carry a `**Test:**` meta line with the
checklist test id it evidences (e.g. `` `WSTG-ATHN-07` ``, backtick-wrapped); it
mirrors the `Finding` column of that test's row in the scope object's checklist.

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
the attestation is the **deck-level visual signature** and the document seal,
which live together in `<name>.seal.json` beside the file (§6.6):

```markdown
<!-- _class: sign-off -->
# Ondertekening
```

The editor authors the deck signature (statement, rapporteur name/role,
certification, typed signature) and offers **Afronden & verzegelen**; the preview
renders the signature plus the seal status. Because the signature is deck-level,
one report has one signer, and the sign-off page round-trips as just its class
token and heading — the signer's details live once, in the seal sidecar. The
HTML export therefore gets them handed to it rather than reading them back out
of the front matter, which is where they used to be.

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
- The **Status** column holds the MIAUW status as a **stable English word** —
  one of `Tested`, `Anomaly`, `Not testable`, or empty (not yet tested) — so the table
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
- The **Status** column holds one of four values: `Tested`, `Deviation`,
  `Unreachable`, or empty (not yet tested). Note that this is **not** the same
  vocabulary as the checklist slide, which uses `Anomaly` and `Not testable`;
  `ScopeStatus.fromToken` silently falls back to *not tested* for anything it
  does not recognise, so a copied `Anomaly` loses the status without a warning.
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

### View limit (`ocideck_view_*`) — non-destructive display windows

A data-driven slide (bullets, table, chart, and the table-backed specials) may
carry an optional **view limit** (#672): show only part of the data without
discarding any of it. A generator importing thousands of rows can make a
readable slide while the full dataset stays in the file; opening, saving and
reopening never drops hidden items. The limit is applied at render and export
time only — preview, presenter, PDF, PPTX and HTML all show the same
selection.

Stored as plain, readable per-slide HTML comments; absent comments mean the
existing behaviour (show everything):

```markdown
<!-- ocideck_view_limit: 8 -->
<!-- ocideck_view_mode: top -->
<!-- ocideck_view_key: 2 -->
<!-- ocideck_view_remainder: other -->
<!-- ocideck_view_show_count: true -->
```

- `limit` — maximum number of visible items; `0` or absent = show everything.
- `mode` — `first` | `last` (source order) or `top` | `bottom` (by value).
  Bullets support only `first`/`last`; a line/time-series chart uses `last`
  rather than value-sorting, so chronology is never silently destroyed.
- `key` — for tables the column index (or stable column name) to rank on; for
  charts the series name. Not applicable to bullets.
- `remainder` — `hide` (keep but do not show) or `other` (aggregate the hidden
  values into one *Overig* bucket; only where values can honestly be summed —
  bar/pie/donut-style charts and numeric table columns).
- `show_count` — whether the slide renders an "N of total" indicator, in the
  app language. The indicator is ordinary slide content, so it travels into
  every export the same way the rest of the slide does.

Ties are broken deterministically: value, then original source position, so a
deck shows the same top-N on every reopen. The **saved** markdown always
carries the full data plus these comments; only the **export** path writes the
projected selection, and it strips the `ocideck_view_*` comments while doing
so — an already-applied projection must not carry a live directive, or
reopening the exported file would apply the limit a second time, over the
baked-in caption and *Overig* row. A malformed comment (say, a key without a
value) is ignored; it never makes the file unreadable.

---

## 6. Sidecars and Separate Data

Four kinds of data deliberately live **next to** the `.md` file instead of
inside it, so the Marp Markdown remains clean and exchangeable. (The redaction
manifests of §12 are not among them: those sit beside an *export*, not beside the
deck.)

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
  "version": 2,
  "slides": [
    {
      "index": 2,
      "fp": "a1b2c3d4",
      "strokes": [
        { "id": "9f2c1a84-…", "tool": "pen", "color": 4294198070,
          "width": 0.004, "points": [0.1, 0.2, 0.15, 0.22] },
        { "id": "b7e03d51-…", "tool": "pen", "color": 4294198070,
          "width": 0.004, "points": [0.4, 0.5, 0.45, 0.52],
          "erased": true }
      ]
    }
  ]
}
```

`points` is a flat list `[x0, y0, x1, y1, ...]`; `color` is an ARGB int; `tool`
is `pen` or `highlighter` (laser pointers are transient and are not stored).

Since version 2 (#541) every stroke carries a stable **`id`**, and an erased
stroke stays in the file marked **`"erased": true`** — a tombstone, not a
deletion. Both exist for the merge: when two copies of a deck come together the
stroke sets are **unioned by id** (two people drawing did not disagree), and a
tombstone wins over the same stroke un-erased, so an erasure survives a merge
with someone who still had the stroke. `erased` is only written when true. A
version-1 file still reads — every stroke is dealt a fresh id — and a tool that
writes this sidecar should write version 2 with ids, or its strokes will union
into duplicates.

`version` is a single increasing integer, and every sidecar in this chapter
handles it the same way (`lib/services/sidecar_format.dart`): **a file declaring
a higher version than this build understands is not loaded, and not
overwritten.** Both halves matter. Reading half of a file you do not understand
and then writing back what you did understand deletes the rest; and refusing to
read it while still saving over it deletes all of it — the deck would hold no
strokes in memory, and the save would take that as "there is nothing here".
A missing `version` is version 1.

The same payload rides along in an **autosave/recovery snapshot**, since drawing
marks a deck as changed and the strokes are not in the markdown: without it a
deck that had only been drawn on came back after a crash with the drawings gone.
A snapshot that carries an unreadable ink payload still restores the text.

**A commit to a git repository carries this sidecar** (since #541, part 2): it
is written as `deck.ink.json` next to `deck.md`, indented so line-based diffs
and merges stay readable. Inside OciDeck a merge unions the stroke sets as
described above; a clone made by another tool has no merge driver and falls
back to git's ordinary text merge, which OciDeck's read side treats as
untouchable when it left conflict markers behind — it will not load half a
file, and it will not delete or overwrite what it could not read. See
`design/GIT_STORAGE.md` §9.1 and §9.7.

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

Like the annotation layer, user notes ride along in an autosave/recovery
snapshot. Unlike it, they **are** carried by a commit to a git repository — see
below. *(Corrected 2026-07-22: this said they were not, and that the warning
before the commit counted them. Both stopped being true with #541.)*

#### 6.3.1 In a git repository

A deck in a repository keeps its notes at **`<deckDir>/deck.user-notes.json`** —
the same file name as on disk, on a stable path next to `deck.md`, deliberately
not in the content-addressed asset pool (a pool path *is* the hash of the
contents, so every typed character would mint a new blob and orphan the last).

**The repository copy is written indented, one field per line.** Same schema,
same `version`, and it decodes identically — `jq .` makes the two forms equal.
The difference exists because the storage design has git's ordinary text merge
resolve this file (`design/GIT_STORAGE.md` D7), and a line-based merge over a
single line makes every edit a collision. If you write this file from another
tool, either form is read; write the indented one if you expect anyone to merge
it.

Two consequences worth knowing if you build on this format:

- **A conflicted file is not valid JSON.** Git leaves conflict markers, which
  no JSON parser accepts. OciDeck then opens the deck *without* its notes rather
  than with mangled ones — and deliberately leaves the file alone instead of
  rewriting or deleting it, so the markers stay there for a human to resolve.
- **Notes in a repository are as readable as the repository.** On disk they sit
  next to your own file; in a shared repo everyone with read access has them,
  under your name in the commit log. See §6.3 above for what the layer is meant
  to hold.

### 6.4 Chart Data (`data/*.json`, `data/*.csv`)

A chart slide (§5) can keep its data inline in the `chart` block, or point via
`"source": "data/<name>.json"` to a data file in a separate **`data/`** folder
next to the deck. That folder keeps all linked data files together, separate
from `images/`/`media/`. When opening, the file is read and attached to the
chart in memory; the `.md` keeps the `source` reference and the styling, so the
markdown stays about the *shape* of the chart while the file holds the values.

The `data/` prefix is a convention for files OciDeck creates, not a rule it
enforces: any project-relative path is read and written, and the reader is
chosen purely on the extension — `.json` is parsed as JSON, everything else as
CSV. A `source` that points outside the project folder is refused rather than
followed (§1); it is never read and never written, and the reference is left in
the deck untouched.

The file is copied along during save/`Save as...` and included in packages
(§7). A package is written from the deck **in memory**, not by copying the file
from disk, so an export made before saving carries the numbers you see on
screen rather than the older ones still in the file. Anywhere there is no
folder to resolve a reference against, the data is inlined instead: HTML/PDF
export, the browser's "download as `.md`", the presenter/beamer hand-off, and
the HTML preview.

**Two forms.** New data files are written as **JSON**; **CSV** is still read,
and a deck that already links a `.csv` keeps getting CSV on save — silently
rewriting it as JSON would break whatever points at it from outside. The reader
is chosen on the extension.

```json
{
  "x": ["Jan", "Feb", "Mrt"],
  "series": [
    { "name": "Omzet", "data": [120.0, 138.0, 95.0] }
  ]
}
```

Values are read as `double` and written back as such, so a whole number comes
out of the app as `120.0` even when it was typed as `120`. A hand-written
`120` reads back identically; the form only matters if something outside
compares the file byte for byte.

That the *extension* survives a rewrite does not mean the file comes back
byte-for-byte in its original dialect. A CSV that OciDeck rewrites is written
with a `,` separator and a dot decimal, whatever it used before — so a
semicolon-and-comma file from a Dutch spreadsheet stays a `.csv`, but its
dialect flips on the first save that changes a value. If something outside
reads that file with a fixed separator, link it as JSON instead.

CSV shape: first row = series names (first cell = label column), every next row
is `label, value1, value2, ...`.

**What the CSV reader accepts.** The separator is detected per file — `,`, `;`
or tab — so a spreadsheet that exports semicolons (which every locale with a
decimal comma does) loads without conversion. Fields follow RFC 4180: a value in
double quotes may hold the separator, and `""` inside it is one literal quote,
so `"Amsterdam, NL"` is a single label. A line break *inside* a quoted field is
deliberately **not** supported: rows are split on newlines before fields are
parsed, which keeps a stray quote from swallowing the rest of the file.

How numbers are written is deduced from the file as a whole rather than per
cell: `1.234,56` settles itself (the last mark is the decimal one), and a `10,5`
elsewhere settles a bare `1,234` in the same file. Nothing is assumed from the
reader's locale. A file that genuinely does not say — every comma followed by
exactly three digits — is asked about when the file is **imported** in the chart
editor. On deck open there is no one to ask, so the same file is read with the
fallback convention and no question: a `,`-separated file is read dot-decimal,
a `;`- or tab-separated one comma-decimal, on the reasoning that a file that
uses `;` to separate had a reason to. Ambiguity is therefore only ever raised
on import, never on open.

A cell that is no number at all (`12%`, `€ 1.000`) is charted as 0 and named
after the import. An empty cell is also charted as 0 — it is simply not
reported as unreadable, because blank is a normal thing for a spreadsheet to
contain. There is no separate "missing value": a gap in a series and a zero in
a series are the same thing to the chart.

New files are still written as JSON: it needs no such reading rules, and it
round-trips a `double` exactly.

**Values only.** The data file carries `x` and `series` and nothing else. Row
and series colours, the title and the bounds stay in the `chart` block, because
they are styling rather than data. That split is what lets the data file be
regenerated wholesale — from a spreadsheet, a script, an export — without the
chart losing its look.

**In a git repository** the data file sits next to `deck.md` at the path the
`source` names, deliberately *not* in the content-addressed asset pool that
images use. A pool path is the hash of its contents, so every changed cell would
produce a new file and orphan the old one — no diff to read. On a fixed path, a
change reads as what it is.

That fixed path is where the git route's involvement ends. A commit only ever
*writes* data files; it does not delete the orphans a local save would clean up,
and it does not compare against a baseline first, so the housekeeping described
above is specific to saving a project folder on disk. OciDeck's own three-way
merge and version comparison do not look inside `data/*` either: a data file is
carried along as a file, and a conflicting edit to one is settled by git's own
line-based merge on the raw JSON rather than by anything chart-aware.

**Automatic.** A chart that still carries its data inline is moved to a data
file **on save**, and the block is left with the reference. Decks written before
data files existed therefore convert on their next save, with nothing for the
user to do. The conversion runs on save and never on open — opening must not
rewrite a deck that was only looked at.

The file is named after the chart title, slugged down to letters, digits,
spaces and hyphens with the rest collapsed to `_` (`Omzet 2025` →
`data/Omzet_2025.json`), or `grafiek.json` when the chart has no title. A name
already taken — by another chart in the deck or by a file already on disk —
gets a numeric suffix: `Omzet_2025-2.json`, `-3`, and so on. Once assigned, a
`source` never changes again, even if the title does: renaming on every title
edit would churn the file and its history for no gain. A chart with no data yet
gets no file. Copying a chart slide copies its `source` too, so on the next save
the copy is given a file of its own rather than overwriting its twin's.

Writing a **package** (§7) is the one exception to "a `source` never changes".
Package members are re-slugged into `data/` and collide under a different
scheme (`Omzet_2025 (2).json`), and the slide's `source` in the packaged `.md`
is rewritten to match. A deck that is exported and imported again can therefore
come back with different data filenames than it left with. The values ride
along unchanged; only the paths move.

On save, data files that nothing references any more — from a deleted chart,
say — are removed. Eligibility is deliberately narrow: only a `.json` that
**this deck** read or wrote in this session, and only inside its own folder.
Anything else in `data/`, and every `.csv`, is left alone. A file OciDeck has
never touched is never deleted, so a folder shared with other tooling survives
a save — and so does the data file of another deck that happens to live in the
same folder, which is why the bookkeeping is per deck rather than per folder.

**Editing.** Both directions work. The grid in the app edits a linked chart just
like an inline one and writes the file back on save; the file can equally be
edited outside the app. To keep those from fighting, a save only rewrites a data
file whose values actually changed in the app: an untouched chart leaves its
file completely alone, so an edit made elsewhere while the deck was open
survives.

If **both** sides changed, neither wins: the file on disk is left as it became
outside the app, and the save reports the clash. Until 21-07-2026 the app
overwrote it and only wrote a line to the log — a lost update, which is exactly
the failure this comparison exists to prevent. Nothing in the editor is lost by
refusing; the numbers are simply not on disk yet, and the user can save elsewhere
or reopen the deck. The recorded baseline is deliberately *not* advanced on a
refusal, so the next save meets the same clash instead of silently resolving it.

**A data file that cannot be written at all** — a `source` outside the project
folder, a full disk, missing permissions — is reported the same way, and it
matters more than it looks: the conversion described under *Automatic* has just
taken the values out of the `.md`, so at that point they exist only in memory.
Both cases come back from `saveDeckDetailed`/`saveDeckAsDetailed` as
`chartWarnings` and are shown as an error, mirroring the warning the *open* path
already gave. *(Before 21-07-2026 the save path only logged this.)*

Two shapes fall outside that baseline comparison. A chart that arrives with inline data
*and* a `source` is not hydrated from the file — the block already has values —
so there is nothing to compare against and its file is overwritten on save. And
a chart whose rows are all deleted stops counting as having data at all, so its
file is left as it was rather than emptied; the old numbers come back on the
next open. Clear a chart by deleting the slide, not by clearing the grid.

A missing or unparseable data file leaves the chart's data empty rather than
failing the open, and never causes the reference to be dropped. A missing file
is reported to the user; a file that is present but malformed leaves the chart
untouched without a warning.

---

### 6.5 MIAUW Disposition (`<name>.miauw.json`)

The compliance decisions made **about** a report: requirements the client
excluded (with a mandatory reason) and requirements the client confirmed. They
drive the compliance overview (PENTEST_MIAUW §9).

Until 0.1.0 both maps lived in the front matter as base64 (§3.6). They are two
things at once that the `.md` should not carry: unreadable to anyone opening the
file in an editor, and *about* the document rather than part of it — the same
argument that already put annotations and user notes beside the file.

Keyed by EIS id; a key is written only when its map is non-empty, and the file
is deleted when everything is. Same `version` rule as §6.2.

```json
{
  "version": 2,
  "waivers": {
    "1.3": { "text": "Certification not required by the client",
             "at": "2026-07-23T16:41:00.000Z" }
  },
  "confirmations": {
    "2.1": { "text": "Intake held on 2026-07-01",
             "at": "2026-07-23T16:42:30.000Z" }
  },
  "revoked": {
    "waivers": { "1.6": "2026-07-23T17:02:11.000Z" },
    "confirmations": {}
  }
}
```

Version 2 *(2026-07-23, #756)* adds two things version 1 lacked, both needed
the moment the file travels to a git repository (§9.7 of GIT_STORAGE) where two
reviewers can edit it independently:

- **A timestamp per entry** (`at`, ISO-8601 UTC): the merge keeps, per EIS id,
  the decision taken last.
- **Tombstones** (`revoked`): withdrawing a waiver or confirmation is itself a
  review decision and must survive a merge. Without it, a plain union would
  silently resurrect an exclusion a reviewer had just undone — for a waiver
  that is a security-relevant wrong answer. A tombstone records *when* the
  entry was withdrawn; on a timestamp tie the tombstone wins, because the
  strict reading (no waiver without a standing decision) is the safe one.

**Tombstones count as content**: a disposition holding only `revoked` entries
still writes a file — "withdraw everything" must not delete the sidecar, or
the withdrawn waiver returns from the other side at the next merge, which is
the exact failure version 2 exists to prevent. The copy that lives in a git
repository is written indented, one field per line, so git's own text merge
can work line-wise (the same deal as the notes and the set-asides). And the
entries deliberately carry **no author**: this file rides along in git
history, packages, the bin and autosave — a name in it would be a second copy
of personal data with its own lifetime. The audit trail lives where it
belongs: git commits carry authorship once the deck lives in a repository,
and the attested artefact is the seal with its signer (§6.6).

Version 1 files (plain `{ "id": "text" }` maps, no `revoked`) are still read;
their entries carry no timestamp and are treated as older than any version-2
decision. The app writes version 2.

The sidecar travels with the deck wherever the `.md` alone would not be enough:
it is a member of the `.ocideck` package (§7), it moves along to the bin with
the deck, and it rides in the autosave/recovery snapshot. A web download of a
bare `.md` (§1) does not carry it, exactly as it does not carry annotations or
user notes; export the deck as a package to take everything.

---

### 6.6 Document Seal and Signature (`<name>.seal.json`)

Everything that is *about* the report rather than part of it: the read-only
lock, the seal, an optional RFC 3161 timestamp token, and the visible signature
of whoever attested to it. Until 0.1.0 all of this sat in the front matter
(§3.6).

```json
{
  "version": 1,
  "finalized": true,
  "hash": "76f87f10…5c8936f",
  "algo": "sha-512",
  "form": "file-bytes-v1",
  "at": "2026-07-22T09:12:33.000Z",
  "timestamp_token": "MIIF…",
  "signature": {
    "name": "Jan Jansen",
    "role": "Onderzoeker",
    "certification": "OSCP",
    "date": "2026-07-10",
    "statement": "Naar waarheid opgesteld.",
    "typed": "J. Jansen",
    "image": "data:image/png;base64,…"
  }
}
```

The file is written when there is something to record and deleted when there is
not. Same `version` rule as §6.2. It travels with the deck the way the other
sidecars do: as a member of the `.ocideck` package (§7), into the bin, in
the autosave/recovery snapshot, and — since #541 — in a commit to a git
repository, as `deck.seal.json` next to `deck.md`. A web download of a bare
`.md` (§1) does not carry it.

**In a git repository the seal is metadata, not a verification that succeeds
there.** The hash covers the bytes of the original `.md` (see below), and the
repo copy of the deck rewrites asset references, so verifying against the repo
copy would cry tamper on an honest file. A deck opened from git therefore
reports its seal as present but not verifiable *here* — the same behaviour as
an `.ocideck` package. Verify against the original `.md` file. The file is
written compact (one line), unlike the other repo sidecars: a seal is set in
one act and never merged, so there is no per-line diff to keep readable, and
two versions of one seal is a mistake rather than a conflict (GIT_STORAGE
§9.7, D13).

**Seal and signature share one file on purpose.** They are one act — *I attest
to this, and this is the fixing of what I attested to* — and a recipient needs
them together: a signature with no seal has nothing to anchor it, and a seal
with no signer does not say who stands behind it. Two files would mainly mean
one of them can go missing.

#### How to verify the seal yourself

For `"form": "file-bytes-v1"` the hash is a plain SHA-512 over the **bytes of
the `.md` file**. No canonicalisation, no line-ending conversion, no field
selection, no BOM handling, no OciDeck:

```console
$ sha512sum rapport.md
76f87f10…5c8936f  rapport.md
```

Compare that to `hash` in `rapport.seal.json`. Equal means the report is
byte-for-byte what was sealed; different means it changed. `shasum -a 512`,
`openssl dgst -sha512`, `certutil -hashfile … SHA512` and any other SHA-512
implementation give the same answer, because there is nothing to reproduce
beyond the hash function itself.

That absence of steps is the design. Every normalisation step would be a step
the recipient has to replay, and therefore a step where an honest file can be
declared tampered with. There are none.

**Test vector.** This is the smallest deck OciDeck writes — a single title
slide, no metadata beyond the title. `test/document_integrity_test.dart` asserts
both halves, so if this ever stops being true the build fails.

`rapport.md` (118 bytes, LF line endings, no trailing whitespace, final blank
line included):

```markdown
---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Rapport
---

<!-- _class: title -->

# Rapport

```

SHA-512:

```
76f87f10084f69911d3742e2e64eb9b9f2ac99d90686e1f24e3c6c3d14e34ed7
d637fefa0252f49ece0e3fb9bbccd0803877c9d050ab87a616ae4af9d5c8936f
```

(one line in the file; wrapped here for width).

#### What the seal does and does not prove

- It proves the `.md` is unchanged since sealing — **tamper-evidence**, relative
  to a hash you obtained by another route (the audit dossier, an email, the
  timestamp token). It is not tamper-*proof*: there is no signing key, so anyone
  who edits the `.md` can also rewrite the sidecar. That was equally true when
  the seal lived in the front matter.
- It covers the `.md` only. Images, chart data files, annotations and notes are
  separate files and are not in the hash. Evidence images have their own hash
  table in the audit dossier (PENTEST_MIAUW §10.11).
- It no longer covers the visible signature, which moved out of the `.md` in the
  same step. The signature now sits next to the hash in this file rather than
  under it. That is a real narrowing of the seal's reach: what the hash proves
  is that the *report* is unchanged, and the attestation beside it is worth
  what the channel that delivered it is worth.
- Any change to the `.md` breaks it, including one that changes no content —
  converting line endings, adding a trailing newline, or a future OciDeck
  writing a higher `ocideck_format` (§3.0). **A sealed deck is frozen**, and
  OciDeck enforces that by making a finalised deck read-only, so it never
  rewrites one on its own.
- **Your own front-matter lines are inside the hash again**, and this reverses a
  deliberate exemption made a day earlier. When the seal still lived in the
  front matter it skipped the lines OciDeck does not own — your `style:` block,
  your comments, a hand-placed `header:` — because editing your own CSS in a
  sealed deck raised a tamper alarm that was simply wrong (*fixed 2026-07-21*).

  A hash over the file cannot make that exemption: the recipient runs
  `sha512sum` over the whole file, so any line the app excluded would make the
  app's verdict disagree with theirs — and a verdict only OciDeck can reproduce
  is the thing this change exists to eliminate. The exemption is not lost so
  much as made unnecessary: a finalised deck is read-only, so there is no way to
  adjust your CSS inside a sealed report and be surprised afterwards. Edit it
  outside the app and you no longer hold the sealed artefact — which is the
  literal truth, and now the recipient sees exactly what you see.

For `"form": "canonical-v1"` — only ever produced before 0.1.0 — the hash is
over OciDeck's own serialiser output instead, and **cannot** be recomputed
outside the application. Such a seal is kept as it is rather than converted; see
§3.6.

#### The RFC 3161 timestamp

`timestamp_token` is a base64url DER token from an external TSA (obtained
out-of-band; OciDeck makes no network connection). OciDeck checks **one** thing
about it: that its message imprint equals `hash` — does this token belong to
this document?

It does **not** verify the token's CMS signature and does **not** validate the
TSA's certificate chain or its timestamping EKU. So `genTime` is a *claim made
by the token*, not an established fact: whoever holds the deck can mint a token
with an arbitrary time and a matching imprint. The interface says so and shows
no "verified" badge, and the audit dossier repeats it. For non-repudiable time
anchoring, verify the token against the TSA; OciDeck stores it unaltered so that
stays possible.

The exported `.tsq` **does** carry a random RFC 3161 nonce, and §2.4.2 obliges
the TSA to echo it back in the token. That echo is what binds one request to one
token — without it, any valid token for the same imprint is interchangeable with
any other, and re-submitting an old one goes unnoticed. Anyone holding both
files can check the echo (`openssl ts -reply -in … -text`, or
`timeStampEchoesNonce`).

**OciDeck cannot check it on import**, because it does not keep the nonce: the
request travels to the TSA outside the app, and after a restart the other half
is gone. A token whose imprint matches is therefore accepted whatever its nonce
says. The original reason for not storing it — that an extra front-matter key
would clash with the ongoing move of the seal into a sidecar — no longer holds:
that move is done, and this file is exactly where such a nonce belongs (it is
opaque, and it is *about* the document rather than part of it). What remains is
the decision to build it.

---

### 6.7 Set-aside Privacy Findings (`<name>.dismissals.json`)

*Designed for [#651](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/651)
before the build, because it changes the file format and this project settles a
format on paper first. Built since: the codec and store, the set-aside action on
the finding card, the undo list in Settings → Security, and — last — the git
write path, so the sidecar travels with the deck into a repository
(`deck.dismissals.json` next to `deck.md`, merged as described under *Merging*
below).*

Today a privacy finding offers one action: **never report this rule again**. That
is a global switch for a local judgement. Someone who has looked at one hit and
decided it is fine — a colleague's name that belongs on the slide, an address
that is the client's own — must choose between living with the warning forever
and turning the rule off for every deck they will ever make. Turning a rule off
is the loudest possible answer to the quietest possible problem, and it fails in
the direction that matters: the next real hit of that class never appears.

**Per deck, not per user.** A set-aside is a judgement about *this* document, so
it belongs to the document. Move the deck to another machine or hand it to a
second reviewer and the judgement travels with it; leave it in preferences and
the second reviewer re-litigates every hit the first one already settled, while
the first reviewer sees hits suppressed on *other* decks they never looked at.

**In a sidecar, not in the `.md`.** Same boundary as the annotations, the notes
and the seal: the markdown stays maximally interchangeable, and what is *about*
the document sits beside it.

```json
{
  "version": 1,
  "salt": "9f8a3c2e1b7d4056",
  "dismissals": [
    {
      "rule": "nl.name",
      "commitment": "f1a2…b9c0",
      "at": "2026-07-23T11:42:07.000Z",
      "seen_at": { "slide": 4, "field": "bullets", "fragment": 2 }
    }
  ],
  "revocations": [
    { "rule": "fin.iban", "commitment": "77de…12ab", "at": "2026-07-23T12:03:00.000Z" }
  ]
}
```

#### What identifies a set-aside

`rule` plus a **commitment over the matched text**: `SHA-256(salt ‖ text)`, hex.
The salt is per deck and lives in this same file.

**Not the position.** `PrivacyFinding` carries `slideIndex`, `field`,
`fragmentIndex`, `start` and `end`, and every one of them moves when the author
types a word above it. A set-aside keyed to a position would quietly expire on
the next edit. `seen_at` is therefore written for the undo list to say *where you
judged this*, and is explicitly **not** part of the identity: a reader that
matches on it is wrong.

Keying on the value instead means a name judged fine on slide 4 stays quiet if it
also appears on slide 9. That is the intent, not a side effect — the judgement
was about the name in this deck, not about one paragraph.

#### Why a commitment, when the value is in the `.md` anyway

The redaction manifest (§ `redaction_manifest.dart`) hides values because they
have been *removed* from the artefact. Here they have not: anyone holding this
sidecar holds the deck as well, so the commitment buys no confidentiality
against them, and this section must not pretend otherwise.

It earns its place for two other reasons, and they are the honest ones:

1. **A privacy tool must not create a second copy of a personal datum.** The
   `.md` is the document the author manages, backs up and eventually cleans.
   This file is machinery. Writing `Jan Jansen` into it makes a second copy with
   its own lifetime — one that follows the deck into git history, sync folders
   and package exports, and that keeps the name **after the author has removed
   it from the slide**. A value that outlives its own deletion is the failure
   this project exists to prevent.
2. **The salt stops cross-deck correlation.** Per deck, so the same name in two
   decks yields two unrelated commitments. Nobody can line up a stack of
   sidecars and see which decks mention the same person.

The salt is *not* a secret and this file does not pretend it is: it sits right
here, so anyone with the file can test a guess. Against a holder of the deck
that costs nothing, because they can read the slide. State it plainly rather
than implying a protection that is not there.

#### Two points settled on 23-07-2026 (#651)

**A set-aside does not expire when the *rule* changes.** The commitment is over
the matched text, not over the rule's version, so tightening a rule until it no
longer fires simply means the set-aside is never consulted, and widening one so
it matches a longer span means the commitment misses and the finding returns.
Returning is the safe direction and it costs one click; the alternative —
anchoring on a rule version so every catalogue refresh expires every set-aside —
was considered and rejected. Somebody will propose it again; this is the answer.

**Still open: what the export gate does with a set-aside.** "Hidden in the panel"
and "not resolved" are settled above. Whether the *export* gate lets a deck
through whose only outstanding findings are set aside is not, and it is a real
fork: treat it as unresolved and an author faces a permanently blocked export
whose only escape is the global rule switch — the very thing this feature
replaces; treat it as resolved and the gate reports a cleanliness that the
compliance count deliberately refuses to report. Decide before wiring the gate.

#### The scan must keep finding it

A set-aside **hides**, it does not unscan. `privacyRawScanProvider` keeps
returning the full set, and the compliance count that MIAUW EIS 1.1 reads keeps
counting it. Only the panel filters. A dismissed finding is also not "resolved":
the two must stay distinguishable, or the quality panel starts reporting a
cleanliness the deck does not have.

**The export gate is a second reader, and forgetting that was a bug (#740).**
The first build filtered set-asides in the panel provider only. The gate read
the same findings by another route, still counted them as unresolved, and
interrupted the export over something the panel no longer showed — a block with
no way to find what it was about, which is exactly the kind of prompt people
learn to click away.

The resolution is not "count it as resolved". The gate and the compliance
counter answer different questions, and both answers are correct:

| Asks | Set-aside counts as |
| --- | --- |
| Export gate: *did you look at this?* | looked at — it does not block |
| MIAUW EIS 1.1: *how much is in this document?* | still there — it counts |

So the gate lets it through, `PrivacyExportSummary.setAside` counts it
separately (not folded into `accepted`, which is a whole-slide decision), and
the export message names it. Both readers now share one predicate,
`setAsidePredicate` in `privacy_scanner_dismissals.dart`: a third reader must
use it rather than restate it.

#### Undoing

`revocations` exists because a set-aside you cannot find again is a deletion.
The panel gets a *set aside* list with an undo, and undoing writes a revocation
rather than dropping the entry — which is what makes merging work.

#### Merging (git, and the same deck edited twice)

Both lists are merged as a **union keyed by `rule` + `commitment`**, and where an
id appears in both lists the **later `at` wins**. That gives one rule for every
case: two reviewers setting aside different findings keep both; one setting aside
what the other revoked resolves by clock, and re-revoking is always possible.

**Diverging salts do not merge.** The salt is per deck, and two sides of the
same deck are expected to carry the same one; when they do not, *ours* wins and
the other side's lists are dropped entirely. That is deliberate, not an
oversight: a commitment is `SHA-256(salt ‖ text)`, so entries under another
salt can never match anything in this deck — carrying them along would be
carrying judgements that can no longer be checked. The way to get there is for
two reviewers to each set aside their *first* finding on copies that had no
sidecar yet, minting two fresh salts; the failure direction is the safe one
(the dropped side's findings become visible again and can be re-set-aside).
A second implementation of this format should do the same rather than attempt
a two-salt union.

Since #651's git write path this is running behaviour, not only design: the
sidecar is committed next to `deck.md` (indented, so line-based merges outside
OciDeck stay readable), `mergeDeckVersions` applies exactly this union when two
copies of a deck come together, and the repository read side refuses to load or
overwrite a file it cannot read — conflict markers or a newer version leave the
file untouched, the same rule every sidecar in this chapter follows.

Timestamps are UTC, ISO 8601, millisecond precision — same as §6.6.

Dropping the tombstones and merging only the set-asides would be simpler and
wrong: a revocation would vanish on the next merge and the finding would stay
hidden, which is the quiet failure direction. See `design/GIT_STORAGE.md` §D7
for the same question on notes.

#### Reading an older or newer file

Same rule as every sidecar in this chapter (`lib/services/sidecar_format.dart`):
a file declaring a higher `version` than this build understands is **not loaded
and not overwritten**. A missing `version` is 1. A deck written before this
section existed simply has no such file, which reads as "nothing set aside" —
there is no migration, and the format version in the front matter does not move.

#### Where it travels

With the deck wherever the `.md` alone would not be enough: a member of the
`.ocideck` package (§7), along to the bin, and in the autosave/recovery snapshot.
A bare `.md` download on the web carries it no more than it carries annotations
or notes.

**Unlike the annotation layer, this one does belong in a git commit.** Ink is a
personal mark on a copy; a set-aside is a review decision about the report, and a
reviewer pulling the deck should not be shown findings a colleague has already
judged. That is a deliberate difference from §6.2 and needs its write path in
`services/git/`.

#### Cost, before anyone starts

Two new interface strings — which means 31 translations beside the Dutch
source, 32 languages in all — one new sidecar reader/writer, a second
action on the finding card plus the set-aside list, the git write path, and the
merge. The scanner itself does not change.

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
├── <title>.miauw.json        # MIAUW disposition (if present, §6.5)
├── <title>.seal.json         # seal + signature (if present, §6.6)
├── images/...                # all used images
├── data/...                  # linked chart data files (§6.4)
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
  is *not* encrypted — only file **contents** are. Worth knowing when the names
  themselves are telling: image filenames come along as they were, and a chart's
  data file is named after the chart's **title** (§6.4), so `Omzet_2025.json` is
  readable from an encrypted package without the password. Retitle a chart
  before exporting if its title is the sensitive part.
- **Key derivation.** WinZip AES derives the key with **PBKDF2-HMAC-SHA1, 1000
  iterations**. This iteration count is fixed by the WinZip AES spec and is low
  by modern standards, so a short/guessable password is the weak link. The
  export dialog therefore shows an entropy-based strength meter and offers a
  generator (32 or 256 random characters); with a long or generated password the
  weak KDF is irrelevant.
- **Keep the password to ASCII if you type it yourself.** *(Added 2026-07-22;
  this was documented nowhere.)* The ZIP-AES key derivation takes the password's
  bytes as `Uint8List.fromList(password.codeUnits)` — it truncates every UTF-16
  code unit to its low 8 bits. For plain ASCII that is exact and nothing is lost.
  For anything above U+00FF it is not: Cyrillic, Greek, Hebrew, Arabic, CJK and
  emoji characters are silently folded onto whichever byte their low half
  happens to be, and different characters collapse onto the same byte. Two
  consequences, both quiet. You lose entropy you thought you had — a
  twelve-character Cyrillic passphrase is not worth what its length suggests —
  and the derived key depends on a truncation rule that other tools need not
  share, so 7-Zip or WinZip may refuse a password OciDeck accepted, or the
  reverse. Nothing warns you; the package simply will not open.

  This is a property of the format's key derivation as implemented, not of
  OciDeck's own code, and it cannot be fixed from here without producing
  packages other tools cannot read. **A generated password is unaffected**:
  `passwordAlphabet` is printable ASCII by construction, so the generator route
  never meets this at all.
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
| `<!-- ocideck_two_bullets_left/right[_title]: <base64url> -->` | **Retired (0.1.0).** Was the canonical storage for the two bullet columns; the visible `<ul><li>` now carries them (§5). Still read from older files, dropped on save. |
| `<!-- ocideck_bullet_marker: dot\|paw -->` | Per-slide bullet-marker override (bullets/two-bullets/bullets+image). Absent = inherit the theme's `bulletMarker` (§3.2). |
| `<!-- ocideck_image_focus: x,y -->` | Image crop focal point (0..1 per axis, `0.5,0.5` = centre) for the slide's image. Decides which part stays in view when the picture is cropped (fill/zoom, or a fixed image panel). Written only when not centred. |
| `<!-- ocideck_image_focus2: x,y -->` | Same, for the **second** image of a two-images slide. Written only when not centred. |
| `<!-- ocideck_image_alt: text -->` | Per-usage WCAG alt-text (accessibility description) for the slide's image. Preferred over the visible caption as the screen-reader label. Written only when set; `-->` inside is escaped like presenter notes. |
| `<!-- ocideck_image_alt2: text -->` | Same, for the **second** image of a two-images slide. |
| `<!-- ocideck_finding_id: F-03 -->` · `<!-- ocideck_finding_role: header\|detail\|evidence -->` | Finding-group link: ties a header card to its detail/evidence slides (§5). Written on any slide with a non-empty finding id. |
| `<!-- ocideck_ai_assisted: field1, field2 -->` | The slide's fields whose text was drafted by AI and not yet human-reviewed. While any slide carries this marker the deck **cannot be finalised/sealed** (the EIS 1.6 attestation must cover human-verified text), and any PDF/PPTX/HTML export declares it in its document properties, its filename, and — in HTML — a banner (§11). Written only when non-empty; AI drafting sets it and clears it on review. |
| `<!-- advance: N.N -->` | Auto-advance after N.N seconds (0 = off). |
| `<!-- ocideck_detail -->` | Verdiepingsslide: valt weg in de beknopte export, blijft in de volledige. Alleen geschreven als de vlag aanstaat. |
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
- **Marp-compatible the other way round too:** front-matter keys OciDeck does
  not know — Marp options it has not implemented, or a note the author put
  there — survive an open-and-save unchanged (§3.0). What is *not* covered is
  the slide body: everything outside the front matter is parsed into typed
  slides and written back from them, so markup OciDeck cannot represent is not
  passed through.
- **Forward migration:** missing front-matter fields and style-profile fields
  fall back to defaults, and the absence of the `no-footer` token means (for
  older files) "footer visible". A file that declares a *newer* format version
  (§3.0) still opens: the keys of that version are unknown but preserved, and
  the version is written back unchanged rather than lowered.
- **Chart data:** inline `x`/`series` in a `chart` block stays valid and is
  read unchanged — it is still the only possible form where there is no project
  folder (web). A `source` pointing at a `.csv` keeps being read *and written*
  as CSV; only newly linked data files are JSON (§6.4).
- **What left the file in 0.1.0** still reads: the three retired front-matter
  keys (§3.6) and the four `ocideck_two_bullets_*` comments (§5). None of them
  is written any more, and all of them are dropped from the file on the first
  save — a one-way migration that needs no action from the author. For the two
  columns the visible `<ul><li>` wins over the old comment when both are
  present, which is the whole point: what is on screen is what is stored.
- **Hand-writing works.** A two-column slide typed by hand, with plain
  `<ul><li>` and no style attributes, now reads correctly. Before 0.1.0 it
  parsed as two empty columns.

---

## 10. Markdown Mode and Syntax Checking

In the editor, the code icon in the toolbar switches to **Markdown mode**: the
entire presentation is shown as one Marp Markdown document (the same structure as
on disk). **Apply** parses the text back into typed slides; **Cancel** returns
without applying changes.

One deliberate difference from the file on disk: a chart with a linked data file
(§6.4) is shown here with its `x` and `series` **inline**, so the numbers can be
read and edited in place instead of pointing at a file the text editor cannot
open. The `source` stays in the block, and applying the text writes the values
back to the data file on the next save.

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
| **Front matter** | warning | Key OciDeck does not know: it has no effect, but it is kept on save (§3.0). |
| **Front matter** | error | Unknown `tlp:` value. |
| **Comment** | error | `<!--` without `-->` on the same line. |
| **Comment** | warning | Comment without `_class:`, `_style:`, `ocideck_...`, `skip`, `tlp:`, or `advance:`. |
| **Code blocks** | error | Odd number of ` ``` ` lines (not closed). |
| **`_class`** | error | Malformed `<!-- _class: ... -->`. |
| **`_class`** | warning | Unknown token in `_class` (known: `title`, `section`, `two-bullets`, `split`, `quote`, `video`, `table`, `code`, `chart`, `scorecard`, `actions` (read-only, migrates to `table`), `assets`, `discoveries`, `finding`, `findings-summary`, `checklist`, `scope-matrix`, `sign-off`, `logo-safe`, `no-logo`, `no-footer`, `table-editable`, `table-overdue`). |
| **Slide metadata** | error | Unknown `<!-- tlp: ... -->`, non-numeric `<!-- advance: ... -->`, or invalid `<!-- ocideck_list_style: ... -->` (`bullets`, `numbered`, `checklist`, `richText`). |
| **Two columns** | error | Invalid base64/JSON in a legacy `ocideck_two_bullets_*` comment (retired; §5). |
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
from the deck — mostly from front matter (`author`, `organization`,
`description`, `keywords`, `tlp`, title), plus one property counted over the
slides (§8, the unreviewed-AI markers). This metadata is **not** stored in the
`.md` file and does not change the round-trip format; it is set only during
export (`ExportDocumentMetadata` in `lib/services/export_metadata.dart`).

| Source | PDF / PPTX | HTML |
| --- | --- | --- |
| Title | `Title` | `<title>` |
| `author`, otherwise `organization` | `Author` / `dc:creator` | `<meta name="author">` |
| OciDeck (fixed) | `Creator` | `<meta name="generator">` |
| OciDeck + version (fixed) | `Producer` / `Application` / `lastModifiedBy` | — |
| `description` | — | `<meta name="description">` |
| `keywords` + TLP + AI marking + `OciDeck` | `Keywords` / `cp:keywords` | `<meta name="keywords">` |
| `tlp` (when not `none`) | `Subject`: `TLP:... — title` | `<meta name="classification">`, `<meta name="tlp">`, fixed `.tlp-export-banner` at the top |
| any slide carrying `<!-- ocideck_ai_assisted: … -->` (§8) | `Subject` gains ` — contains AI-drafted text that no human has checked`; `Keywords` gains `AI-generated (unreviewed)` | `<meta name="ai-generated">`, `<meta name="ai-generated-slides">` (the count), fixed `.ai-export-banner` — at `top:2.4em` under the TLP banner, at `top:0` when there is none |

The AI keyword and Subject note are fixed English strings, like `Creator` and the
TLP labels: they are read by tools, and a value that varied with the interface
language would not be findable. The `.ai-export-banner` is a sentence for a
reader and is written in Dutch, as is the rest of the text the HTML export
generates itself.

The AI marking also reaches the **filename**: the export is written as
`…-ai-concept.<ext>`, after the redaction-profile suffix (`-geredigeerd`) and the
depth suffix (`-beknopt`). All of it is absent once every AI-drafted field has
been reviewed and the markers are gone from the `.md`. *(Added 22-07-2026; before
that the marker existed in the `.md` and blocked sealing, but nothing about it
survived into an exported file.)*

Visual TLP marking (banner, badge, optional watermark) is **rasterized** into
PDF/PPTX slides and is separate from these document properties. There is no
equivalent rasterized AI marking: the PDF and PPTX carry the declaration in the
document properties and the filename only. See
[`USER_GUIDE.md`](USER_GUIDE.md) (§ Traffic Light Protocol, § Exporting) and
[`ARCHITECTURE.md`](ARCHITECTURE.md) (§ Classification enforcement).

---

## 12. Redaction Manifest Files (Beside an Export)

When an export actually removes something (§3.1a), OciDeck writes two JSON files
into the same folder as the export — on the web, into the same download folder.
They are export artefacts, not deck sidecars: nothing reads them back in, and
they never appear next to the `.md`.

| File | Contains | Travels with the report |
| --- | --- | --- |
| `<name>-redactions.json` | One entry per redaction, without salts | Yes |
| `<name>-redaction-keys.json` | The same entries **plus the salts** | **No** — it stays with the source |

The second file is only written when there is something to protect (a manifest
carrying salts). Both suffixes are constants in
`lib/models/redaction_manifest.dart`; they are English on purpose, because the
whole point is that a recipient in any language can tell the two apart. They were
`-redacties.json` and `-redacties-verificatiesleutels.json` until 2026-07-21 —
two Dutch names that look alike while needing opposite handling.

```json
{
  "format": "ocideck-redaction-manifest/1",
  "notice": "This file lists what was redacted in the accompanying document, without the values. It carries no salts and reverses nothing.",
  "derived_from": "9f1c…",
  "algorithm": "sha-256(salt || value)",
  "redactions": [
    { "id": "a3f1e2b7", "commitment": "a3f1e2b7…", "rule": "nl.bsn", "slide": 4, "field": "bullets" },
    { "id": "77bd", "commitment": "77bd…", "rule": "contact.email", "slide": -1, "field": "author" }
  ]
}
```

- `notice` is the one-line statement of what the file is and whether it may be
  sent on. It is there because a filename does not survive being renamed, zipped
  or forwarded, and the keys file is the one you must not attach.
- `derived_from` is the seal hash (§6.6) of the source deck, empty
  when the deck is not sealed. It pins provenance; it does **not** put the
  manifest under the seal, which is impossible — the manifest is made at export,
  after the seal, with fresh random salts.
- `id` is a prefix of the commitment — at least **eight** hex characters, and
  longer whenever eight would not tell two entries in the same manifest apart.
  Enough to name one redaction in a conversation ("I dispute a3f1e2b7"), too
  little to reveal anything. Every entry in one manifest uses the same length,
  the way git abbreviates its hashes. *(Corrected 2026-07-22: this was four
  characters — 16 bits, so by the birthday bound a document with ~300 redactions
  had an even chance of two entries sharing an id, and a dispute then pointed at
  both.)* Older manifests keep their shorter ids; nothing verifies against the
  id, only against the full `commitment`.
- `commitment` is `SHA-256(salt ‖ value)` in hex. The values themselves are never
  in either file.
- `salt` appears only in the keys file. Without it a commitment over a short,
  structured value is trivially reversible, which is exactly why the two files
  are separate.
- `slide` is the slide index, or `-1` for a redaction in the deck-wide fields
  (the front matter that feeds document metadata). Deck-wide entries come first
  and in the order the projection applies them, because verification compares
  entry by entry against a fresh projection of the source.
- `field` is the field the redaction fell in. There is no free-text reason field:
  a reason written by the author could describe the value that was just removed.

An entry exists for a redaction that is actually in the document, and for no
other. Findings that are not redactable (an *indicator* such as the word
"diagnosis" with nobody attached to it) and findings with an empty span (a
notice that *something* is in the speaker notes, pointing nowhere) produce no
entry — before 2026-07-21 they did, which sent recipients looking for blocks
that were not there. See [`design/OCIWACHT.md`](design/OCIWACHT.md) §6.6 for the
reasoning and [`USER_GUIDE.md`](USER_GUIDE.md) (*The two manifest files*) for
what to do with them.

---

## 13. Accepted Files and Their Limits

*Added 2026-07-22.* Every number here was already enforced by the code and stated
somewhere — scattered across §7, `SECURITY.md` under *Untrusted deck handling*,
and the constants themselves. What was missing was the one place a reader can
check "will OciDeck take this file, and how big may it be" without reading three
documents. The constant name is given for each so a changed limit can be found
rather than guessed.

Every limit is a **refusal**, not a truncation: a file over its cap is rejected
whole, with a reason, and nothing partial is ever read into a deck.

### Files you open or import

| What | Accepted as | Cap | Constant |
|---|---|---:|---|
| Deck | `.md` | 32 MiB | `FileService.maxDeckMarkdownBytes` |
| Package | `.ocideck` (`.zip` also accepted on import) | 512 MiB, 10 000 entries, path ≤ 512 chars | `maxPackageBytes`, `maxPackageEntries`, `maxZipEntryPathLength` |
| Package, **unpacked** | — | 512 MiB total across all entries | same `maxPackageBytes`, applied to the running total |
| Style profile | `.ocideckstyle` | 16 MiB | `maxStyleProfileBytes` |
| Logo embedded in a style profile | PNG/JPEG/GIF/BMP/WebP by magic bytes | 8 MiB | `maxStyleProfileLogoBytes` |

The unpacked cap deserves its own row because it is the one a crafted archive
attacks. A zip bomb understates its declared size, so the declared figure is only
a cheap early reject; the real guard inflates each entry into a capped stream
that aborts mid-decompression the moment the running total would exceed the
budget. An encrypted package is the exception — WinZip-AES members must be
decrypted whole before they can be measured, so there the guard falls back to the
declared size plus the running total. That is accepted deliberately: the user
encrypted and unlocked that package themselves.

### Assets you add to a deck

| What | Accepted as | Cap | Constant |
|---|---|---:|---|
| Image (picked or pasted) | PNG, JPEG, GIF, BMP, WebP — validated by **magic bytes**, not by the file extension | 64 MiB | `ImageService.maxImageBytes` |
| Video / audio | Size-checked only; no magic-byte validation | 1 GiB | `ImageService.maxMediaBytes` |
| Image offered to the face scan | As above | 24 MiB | `kFaceScanMaxBytes` |

Every image is additionally decoded with its dimensions capped
(`cappedFileImage` / `kMaxImageDecodeDimension`), so a small file that declares
enormous dimensions cannot exhaust memory on display or export.

### Files that arrive over the network

| Route | What it accepts | Cap | Constant |
|---|---|---:|---|
| URL import | Sniffs the bytes: zip magic `PK\x03\x04` → package, otherwise plain Markdown | 512 MiB on the download (checked on `Content-Length` **and** while streaming), then the `.md` or package cap above | `maxPackageBytes`, then `maxDeckMarkdownBytes` |
| WebDAV / Nextcloud | Deck or package, through the same gate as a local import | 512 MiB per file; PROPFIND listing capped at 16 MiB and by entry count | `WebdavService.maxDownloadBytes`, `maxListingBytes` |
| S3 | As WebDAV | 512 MiB per object; listing capped at 16 MiB across **all** pages together | `S3Service.maxDownloadBytes`, `maxListingBytes` |
| Git (REST) | Deck files from a forge | Listing responses capped at 16 MiB per forge adapter | `maxListingBytes` in `gitea_forge.dart`, `github_forge.dart`, `gitlab_forge.dart` |
| Git (native subprocess) | As above | Subprocess output capped at 8 MiB | `_maxOutputBytes` in `git_cli_io.dart` |
| AI backend response | JSON from an OpenAI-compatible `/v1` endpoint | 8 MiB | `AiClientService.maxResponseBytes` |
| CVE lookup | JSON | 2 MiB | `_maxBytes` in `cve_transport_io.dart` |

Note what the first row means in practice: extension does not decide anything on
the URL route. A file served as `deck.md` that begins with zip magic is treated
as a package, and one served as `deck.ocideck` that does not is treated as
Markdown. The bytes decide, which is the safer way round — but it is worth
knowing if you are the one serving the file.

A deck arriving by any of these routes passes the same `MarkdownSafetyScanner`
gate as a local one; none of them is a shortcut past it.
