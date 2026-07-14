# OciDeck

A desktop application for building [Marp](https://marp.app/) presentations through a structured, slide-by-slide editor — no raw Markdown wrangling required. Compose decks from typed slide templates (title, bullets, quotes, tables, images, video, audio, source code, charts, cockpit dashboards, interactive quiz questions), preview them live, present them fullscreen — even across two screens — and export to Marp Markdown, PDF, PPTX, and self-contained HTML.

And because a deck is something you hand to other people, OciDeck also reads it back to you before you do: it flags the personal data it can recognise, and — if you ask it to — removes that data from everything you show and export, while your Markdown keeps the original.

Built with Flutter for macOS, Windows, Linux, and **web**.

> **What's in a name?** *OciDeck* is a small wink: **Oci** is borrowed from the *Ocicats* — the cats of [Brenno de Winter](https://nl.wikipedia.org/wiki/Brenno_de_Winter) — and **Deck** is short for a presentation deck. So: the cats' presentation tool.

## Features

- **Structured slide editors** — dedicated editors per slide type: title, bullets, two-column bullets, bullets + image, single/two images, quote, table, section divider, image-only, video, audio, source code, charts, cockpit dashboards, interactive question (quiz) slides, animated timelines, and free-form Markdown.
- **Source-code slides** — a "code sheet" with per-language syntax highlighting, stored as a fenced code block. Background, text colour and monospace font come from the style profile, with an optional syntax-colouring toggle (turn it off for a single-colour, CRT-terminal look). The code auto-sizes to fill the panel.
- **Charts** — bar, horizontal bar, stacked bar, combo (bars + a line on a second axis), line, area, pie, donut, spider/radar, scatter, waterfall, and heatmap (doubles as a likelihood × impact risk matrix) charts rendered natively (preview, presenter, PDF, PPTX) and as self-contained SVG in the HTML export. Data is entered in an in-app grid or imported from CSV; the spec is stored as JSON in the Markdown, with optional linking to a CSV kept in a tidy `data/` directory. Optional min/max draw reference lines (bar/line/area/combo/waterfall) or fix the scale (radar); legend hover highlights a series, and line tooltips pick the dot under the cursor.
- **Question slides (interactive quiz)** — multiple choice, true/false, multiple-correct, or ordering questions (tap the shuffled options into the right order), with the kind chosen in the editor. The answer pool is unlimited; a configurable number of options (default 4) is drawn at random each run. Optional answer-time countdown, an on-wrong policy (retry until correct, or reveal-and-continue), and an optional image with a pan-and-zoom detail view. Presenting blocks advancing until answered correctly; the audience window is interactive and stays in sync. The spec round-trips as a JSON block; answer state is session-only.
- **Timeline slides** — turn a list of dated events into an animated timeline: a glowing accent spine with nodes and cards that alternate above/below (horizontal) or left/right (vertical), styled from the active profile. Layout is automatic (horizontal for short timelines, vertical for longer ones) or forced; animation is draw-in-on-open, step-by-step (one event per click, synced to the audience window), or none. Events are an ordinary Markdown list (`marker :: title :: description`), so the `.md` stays readable; layout and animation round-trip as `_class` tokens.
- **Live preview** — see each slide rendered as you edit, with inline Markdown, footers, and TLP (Traffic Light Protocol) marking. Free-Markdown slides render fenced code with syntax highlighting, `$…$` / `$$…$$` LaTeX math, and Mermaid diagrams.
- **Traffic Light Protocol** — a deck-wide classification plus an optional **per-slide TLP level**; slides classified stricter than the level the deck is shown at are automatically withheld, both when presenting and exporting. **Visual marking** (banner, badge, optional diagonal watermark) follows FIRST TLP 2.0 colours and is WYSIWYG through preview, presenter, and PDF/PPTX export. Optional **classification enforcement** (release ceiling, required minimum, mandatory classification, watermark toggle) blocks export fail-closed when policy fails; export metadata embeds TLP in PDF/PPTX/HTML.
- **Privacy check & redaction (Privacy Shield)** — OciDeck reads every slide for data that may be privacy-sensitive and reports it in the **quality panel**, right next to the contrast and readability checks: identification numbers (the Dutch BSN plus **national ID numbers across the EU**, each validated by its own checksum), IBANs and payment cards, e-mail addresses, **phone numbers** (E.164 against the assigned ITU calling codes), API keys, tokens, private keys and plain-text passwords, **GDPR art. 9/10 special categories** (health, criminal, religion, trade-union, biometric, genetic notation), bulk personal data in tables, and the structural leaks generic scanners miss — user paths that reveal a name, tokens in URLs, share links with built-in access. False positives are the real enemy here (a scanner that cries wolf gets switched off, and then it detects nothing at all), so checksums, context gates, and an allow-list of values that belong to nobody — test IBANs, the official test-BSN range, `example.com`, the reserved "drama" phone ranges — do the filtering, and a **co-occurrence escalator** keeps a slide *about* privacy law quiet while a slide carrying a name, a BSN and a diagnosis speaks up. It all runs **on this device**, and a finding never shows you the value it found.
- **What you do with a finding is yours to decide** — per slide, or deck-wide: **accept** (a police briefing contains personal data by definition), **accept + warn** (the slide gets a *personal data* badge beside its TLP marking, so whoever receives the deck knows what they are holding), or **leave out of display and export**. That last one means what it says: not a black bar painted over text that is still sitting in the PDF, but data removed at a single **projection boundary** that the type system enforces, so no render surface can forget it — screen, presenter, audience window, PDF, PPTX, HTML, speaker notes, document metadata. Your Markdown keeps the original. And because a pentest report has to be verifiable, export gives you **two versions from one source**: *full* for the client who must be able to check the finding, *redacted* for the wider circle — with a salted-commitment **redaction manifest** so a third party can still prove nothing else was altered. **The check does not guarantee that everything is found; it reduces the chance that personal data leaks out unintentionally.**
- **Information-security reporting (MIAUW pentest module)** — an optional module, **off by default**, for authoring MIAUW-conforming penetration-test reports. It adds dedicated **finding / findings-summary / checklist / scope-matrix / sign-off** slide types, a native **CVSS 4.0** builder with an offline **CWE** picker and CVE fields, a **finding wizard**, and a **compliance overview** that scores the deck against the MIAUW requirements (EIS). Mechanical bookkeeping is automated: **auto-numbering** of findings, **evidence SHA1 + SHA-256** hashing, **scope-coverage** checks, and a derived **management summary**. A report can be **finalised and sealed** (SHA-512 over the canonicalised content, detecting any later change) with an optional **RFC 3161** trusted timestamp, exported as a **MIAUW report template**, and bundled into a **one-click, AES-256-encrypted audit dossier** (report + evidence + hash tables). Everything is offline by default; the optional AI helpers below are privacy-gated.
- **Optional, privacy-first AI assistance** — an entirely optional, **off-by-default** backend (a local model, or a consented outbound endpoint) that drafts free-text **finding fields** grounded only on the tester's own facts (it strips any CWE/CVE/CVSS identifier it invents) and suggests **image alt-text / tags** for accessibility. AI-drafted content is marked and blocks sealing until a human reviews it, so provenance is always explicit.
- **Fullscreen presenter** — keyboard-driven navigation, presenter view, blank screen, auto-advance, and a slide-grid overview.
- **Presentation timer / rehearsal mode** — the presenter view doubles as a rehearsal clock: a countdown against a target time (set in Settings or live with `K`), the time spent on the current slide, and an end-of-run summary (total vs. target and per-slide times, copyable). It measures only — no pacing coaching — and is session-only, never written to disk.
- **Dual-screen presenter** — when a second display is connected, the beamer shows the slide while the laptop shows the presenter view (current/next slide, notes, timer), kept in sync.
- **Annotation layer** — draw on slides while presenting (pen, highlighter, eraser, laser pointer). Kept as a separate layer that never touches the Marp Markdown, mirrored live to the beamer, and saved in a `.ink.json` sidecar.
- **Live table editing** — opt a table into being editable while presenting (off by default) and change it in front of the audience: a subtle pencil toggle, arrow keys moving the cursor inside a cell, `Tab` between cells, mirrored to the beamer.
- **Media handling** — drag-and-drop images, an image carousel picker, captions, and descriptions stored as sidecar metadata. The library can filter images without tags and clean up md5-identical duplicates (merging their tags/captions and repointing every deck — open or on disk — to the kept file).
- **Import / export** — round-trips Marp Markdown, imports existing slides, and exports to PDF, PPTX (with speaker notes), and a self-contained offline HTML deck (code highlighting, math, charts, and mermaid diagrams render in the browser). Decks are saved as a self-contained package with copied assets.
- **Nextcloud (WebDAV) source** — browse a folder on your Nextcloud, open `.ocideck` packages or Marp `.md` decks from it, and save a deck back (as an `.ocideck` package or as a flat `.md` plus assets). The app password is stored encrypted in the OS keychain; a private/LAN server is only reachable after explicitly marking it as trusted, and downloads pass through the same safety gate and size limits as every other import.
- **Productivity** — find & replace, slide finder, undo/redo, skip-slide state, multi-select with bulk copy-to-another-deck / delete / skip, and tabbed multi-deck editing. Paste a spreadsheet selection (or CSV / a markdown table) into a table cell to fill the whole grid. **Markdown mode** edits the whole deck as raw Marp text, with an in-editor find bar (`Ctrl/Cmd+F`, replace via `Ctrl/Cmd+H`) over the live buffer, plus a structural syntax check (line highlights, optional **Apply anyway**) before switching back. `Ctrl/Cmd+O` opens, `Ctrl/Cmd+S` saves.
- **Accessibility** — WCAG 2.1-oriented: interface text scaling up to 200%, keyboard-operable panel divider and dialogs, screen-reader labels for slides and charts (charts read out their data), and slide-change announcements while presenting.
- **Crash recovery** — automatic snapshots so work survives an unexpected exit.
- **Theming** — customizable deck style profiles (deck and source-code colours via presets or custom hex, fonts, logo, footer) and app appearance (including a dark interface), a bundled Marp CSS theme (`assets/themes/ocideck.css`), and a bundled EB Garamond font (no network fetch).
- **Localized** — a fully translated interface in **31 languages**: Dutch, English, German, French, Italian, Spanish, Portuguese, Polish, Czech, Slovak, Slovenian, Croatian, Bulgarian, Romanian, Hungarian, Greek, Danish, Swedish, Finnish, Estonian, Latvian, Lithuanian, Maltese, Irish, Ukrainian, Indonesian, Frisian, Swiss German, Latin, Papiamento, and Klingon. Every interface string is translated in all of them, enforced by tests.

## Requirements

- Flutter SDK `^3.12.0` (Dart 3.12+)
- A desktop target enabled: macOS, Windows, or Linux — or run in a browser via Flutter web

## Getting started

```sh
make setup      # flutter pub get
flutter run -d macos   # or -d windows / -d linux / -d chrome
```

## Development

The `Makefile` is the entry point for all quality checks. Run `make help` for the full list.

```sh
make check        # format check + static analysis + full test suite (the quality gate)
make check-full   # check + dependency freshness report
make format       # auto-format all Dart code
make analyze      # flutter analyze only
make test         # full test suite only
```

Targeted test groups speed up focused work:

| Target | Covers |
| --- | --- |
| `make test-contracts` | Markdown generation/parsing, save-load round-trips, field migration |
| `make test-preview`   | Slide rendering, footers, TLP, inline Markdown, text styles |
| `make test-export`    | PDF/PPTX export and project file-save behavior |
| `make test-state`     | Providers, undo/redo, search/replace, settings, recovery |
| `make test-services`  | Image, caption, and description sidecar services |
| `make test-presenter` | Fullscreen presenter navigation and keyboard shortcuts |

Run `make check` before pushing — it is the same quality gate (format check,
static analysis, full test suite) you would wire into CI. `make check-full` adds
licence compliance (`make licenses`), the vendored-JS security check
(`make deps-check`), and the SBOM freshness gate (`make sbom-verify`). For the
full reference — every check, what it covers, and how CI runs it — see
[`docs/CHECKS.md`](docs/CHECKS.md).

OciDeck ships a machine-readable **Software Bill of Materials** (CycloneDX 1.6 +
SPDX 2.3) covering every component, as required by the EU Cyber Resilience Act —
see [`docs/SBOM.md`](docs/SBOM.md).

## Project layout

```
lib/
  models/     # Deck, Slide, Settings data models
  services/   # Markdown, export, file, image, caption, recovery, rasterizer
  state/      # Riverpod providers (deck, editor, settings, tabs, clipboard)
  widgets/    # UI: app shell, panels, dialogs, per-type editors, presenter
  l10n/       # AppLocalizations (31 languages)
  theme/      # App theming
  utils/      # Small shared helpers (clipboard table parsing, URL launching)
```

State is managed with [Riverpod](https://riverpod.dev/).

## File format

Presentations are saved as standard, Marp-compatible Markdown (`.md`) with a
defined project folder layout and an optional portable `.ocideck` package.
Anything that isn't plain Marp is kept in side files so the `.md` stays pure and
portable: image captions, the annotation layer (`.ink.json`), and linked chart
data (`data/*.csv`). The full specification — front matter, per-slide markup,
style profile, sidecars, and the package format — is documented in
[`docs/FILE_FORMAT.md`](docs/FILE_FORMAT.md).

## Documentation

| Document | What it covers |
| --- | --- |
| [Architecture](docs/ARCHITECTURE.md) | How the code fits together (for contributors) |
| [Build & release](docs/BUILD.md) | Building from source and producing distributables |
| [Changelog](CHANGELOG.md) | Notable changes per version |
| [Checks & CI](docs/CHECKS.md) | Every automated check, what it covers, and how CI runs it |
| [Contributing](CONTRIBUTING.md) | Setup, the quality gate, and how to propose changes |
| [File format](docs/FILE_FORMAT.md) | The Marp Markdown, front matter, sidecars, and `.ocideck` package |
| [Keyboard shortcuts](docs/SHORTCUTS.md) | Editor and presenter shortcuts |
| [Licence compliance](docs/LICENSE_COMPLIANCE.md) | Open-source policy and the `make licenses` check |
| [SBOM](docs/SBOM.md) | The machine-readable Software Bill of Materials and its CRA mapping |
| [Security policy](SECURITY.md) | How to report a vulnerability |
| [Source map](docs/SOURCE_MAP.md) | One-line description of every file under `lib/` |
| [Third-party notices](THIRD_PARTY_NOTICES.md) | Bundled components and their licences |
| [User Guide](docs/USER_GUIDE.md) | Using the app: slide types, charts, presenting, exporting, theming, the privacy check and redaction, and the information-security (pentest) module |

### Design documents

The design rationale and chosen architecture, kept separate from the
current-state docs above. The **Privacy Shield**, **pentest-reporting (MIAUW)**
and **AI-assistance** designs are now **implemented** (see the User Guide and the
Features list); Collaboration and Git storage remain forward-looking proposals.

| Document | Status | What it covers |
| --- | --- | --- |
| [Privacy Shield](docs/design/PRIVACY_SHIELD.md) | **Implemented** | Detecting privacy-sensitive data in a deck, and — where you ask for it — removing it from everything you share, at one enforced boundary |
| [Pentest reporting (MIAUW)](docs/design/PENTEST_MIAUW.md) | **Implemented** | Penetration-test reports with audit value, per the MIAUW methodology |
| [AI assistance](docs/design/AI_ASSIST.md) | **Implemented** | Optional, privacy-first AI assistance (finding text drafting and image tagging) |
| [Agentic build plan](docs/design/AGENTIC_BUILD_PLAN.md) | Executed | How the pentest and AI feature set was built with autonomous agents |
| [Collaboration](docs/design/COLLABORATION.md) | Proposal | Real-time co-authoring, presenting, and calls |
| [Git storage](docs/design/GIT_STORAGE.md) | Proposal | Storing decks in a git repository as versioned storage |

## Contributing

Contributions are welcome! Please read [`CONTRIBUTING.md`](CONTRIBUTING.md) and our
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). In short: `make check` must pass, new
UI strings must be translated in all languages, and file-format changes must be
reflected in `docs/FILE_FORMAT.md`. For security issues, see
[`SECURITY.md`](SECURITY.md).

## License

Copyright © 2026 Stichting LibreKAT.

OciDeck was initiated and conceived by Brenno de Winter and is developed as an
open-source project.

OciDeck is licensed under the **European Union Public Licence v. 1.2 (EUPL-1.2)**.
You may use, study, share, and modify the software under the terms of that
licence. The full text is in [`LICENSE.md`](LICENSE.md); the official versions in
all EU languages are available from the
[EUPL collection](https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12).

SPDX-License-Identifier: `EUPL-1.2`
