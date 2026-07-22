# Contributing to OciDeck

> **Status:** procedure, current — the practical half of contributing · **Status last reviewed:** 2026-07-22 · **Published by:** Stichting LibreKAT

Thanks for your interest in improving OciDeck! This document explains how to set
up the project, the quality bar, and how to propose changes.

> **There are two contributing documents, and this is the practical one.** This
> file covers the commands: the quality gate, the individual `make` targets, the
> localisation tooling, and what to run before a push. Its companion,
> [`docs/CONTRIBUTING_GUIDELINES.md`](docs/CONTRIBUTING_GUIDELINES.md), covers
> the process around them — issue reporting, review, branch naming, the (absent)
> release process, and the Code of Conduct — and is shipped inside the app as a
> readable document, which this file is not. Neither replaces the other.
> *(Noted 2026-07-22: the two had grown apart without either mentioning that the
> other existed.)*

By contributing you agree that your contributions are licensed under the project
licence, the **European Union Public Licence v. 1.2 (EUPL-1.2)** — see
[`LICENSE.md`](LICENSE.md).

## Prerequisites

- **Flutter 3.44.6** (stable), using the `dart` bundled with it. Building
  tolerates 3.44+, but `make format-check` does not: `dart format` reflows
  whitespace between releases, so an unpinned toolchain fails the gate on files
  it never touched. [`docs/BUILD.md`](docs/BUILD.md) is the authority on this and
  explains the difference; `.tool-versions` is the pin itself.
- A desktop target enabled: **macOS**, **Windows**, or **Linux**.
- `make` (the `Makefile` is the entry point for all quality checks).

See [`docs/BUILD.md`](docs/BUILD.md) for platform-specific build notes (including
the macOS CocoaPods locale caveat and the vendored plugin forks).

## Setup

```sh
make setup            # flutter pub get
flutter run -d macos  # or -d windows / -d linux
```

## The quality gate

Run this before every push — it is the enforced quality gate (the remote is
Forgejo with no CI runner, so nothing runs it for you):

```sh
make check            # format-check + analyze + conventions + full test suite + coverage floor
```

Individual steps:

| Command | What it does |
| --- | --- |
| `make format` | Rewrites Dart files with `dart format`. |
| `make format-check` | Fails if any file needs formatting. |
| `make analyze` | `flutter analyze --fatal-infos` (analyzer + lints + strict type checks). |
| `make check-conventions` | No `print()`; no raw control bytes; the bare `catch (_)`, raw-colour, layering and file-size ratchets may not grow. |
| `make test` | The full test suite (randomised order). |
| `make coverage` | The suite with coverage: enforces the 80% floor **and** that every `lib/` file is in some test. Part of `make check`. |
| `make licenses` | Verify every dependency uses an open-source licence. |
| `make deps-check` | Verify the vendored export JS bundles (integrity + known CVEs via OSV). |
| `make check-web` | Build the web bundle and assert its hardening (CSP, self-hosted, fonts). |
| `make check-full` | `check` plus licences, bundled-JS, web hardening, and a freshness report. |

*(Corrected 2026-07-22: the coverage row said "the 78% floor". The `Makefile`
runs `coverage_summary.dart --min=80`, and `docs/CHECKS.md`,
`docs/CONTRIBUTING_GUIDELINES.md` and `docs/DEVELOPMENT_SETUP_GUIDE.md` already
said 80 — this file was the one that had drifted. The floor is a ratchet that
gets raised as coverage improves, so when a document and the `Makefile`
disagree, the `Makefile` is the answer.)*

See [`docs/CHECKS.md`](docs/CHECKS.md) for the full reference — what each check
covers, what a failure means, and how the CI workflows (defined but not currently
running) declare them.

Targeted test groups for focused work:

| Target | Covers |
| --- | --- |
| `make test-contracts` | Markdown generation/parsing, save-load round-trips, migration |
| `make test-preview` | Slide rendering, footers, TLP, inline Markdown, charts |
| `make test-export` | PDF/PPTX export and project file-save behaviour |
| `make test-state` | Providers, undo/redo, search/replace, settings, recovery |
| `make test-services` | Image, caption, description sidecar services |
| `make test-presenter` | Fullscreen presenter navigation and shortcuts |

## Coding guidelines

- **Formatting & analysis must pass clean** (`make check`). No analyzer warnings.
- **Architecture**: skim [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) before
  larger changes. Keep the Marp Markdown the single source of truth; anything
  that isn't plain Marp belongs in a sidecar (see the file format).
- **Localization is enforced.** UI strings go through `context.l10n.d('Nederlandse
  brontekst')`. The test `test/app_localizations_test.dart` fails if a literal
  `.d('…')` string lacks a translation in **every** supported language (Dutch is
  the source; all 30 other languages need an entry). Rather than hand-editing 30
  files, write the translations into a small JSON spec and run
  `make add-l10n SPEC=…` — it inserts them into each language's additions overlay,
  `dart format`s the result, skips anything already present, and whitelists any
  `"unchanged"` loanwords (see `tool/add_l10n.dart` for the format). Validate with
  `make l10n-check`. A loanword kept identical in every language (e.g. `Heatmap`)
  goes in the spec's `unchanged` list instead of being translated.
- **Comment language: Dutch or English, but never both in one comment.** The
  codebase is bilingual and stays that way. Measured over `lib/` (2026-07-22):
  of the ~3,100 comment blocks of three lines or more, 71% are Dutch, 28% are
  English, and **1% mix the two inside a single block**. So the convention the
  code already follows is not "one language for the project" but "one language
  per comment": pick the one that fits, and finish the thought in it.
  - Dutch is the working language and the default for new comments — the
    reasoning, the commit messages and the design documents are Dutch, and a
    *why* is easier to write well in the language you think in.
  - English is equally acceptable, and is the natural choice where the
    surrounding vocabulary is English anyway: API doc comments on a public type,
    a reference to a spec or standard, a file whose comments are already
    English.
  - **Do not rewrite existing comments only to change their language.** That is
    thousands of lines of pure noise, it changes no behaviour, and it puts your
    name on every line of `git blame` for reasoning somebody else worked out.
    When you edit a comment, follow the language of the block you are editing.
  - This says nothing about *identifiers*, which are English throughout, or
    about user-visible text, which has its own rule (see localization above).
- **Tests**: add or update tests for behaviour you change — especially the
  Markdown round-trip and any file-format change.
- **File format**: if you change how anything is stored, update
  [`docs/FILE_FORMAT.md`](docs/FILE_FORMAT.md) in the same change.

## Proposing changes

1. Branch from the default branch; keep each branch/PR focused on one topic.
2. Write clear commit messages (imperative subject, a short body explaining the
   *why*).
3. Make sure `make check` is green.
4. Open a pull request describing the change and linking any related issue. Fill
   in the PR template checklist.

## Reporting bugs and requesting features

Use the issue templates in the Forgejo tracker. For **security issues, do not open a public
issue** — follow [`SECURITY.md`](SECURITY.md).
