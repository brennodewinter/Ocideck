# Contributing to OciDeck

Thanks for your interest in improving OciDeck! This document explains how to set
up the project, the quality bar, and how to propose changes.

By contributing you agree that your contributions are licensed under the project
licence, the **European Union Public Licence v. 1.2 (EUPL-1.2)** — see
[`LICENSE.md`](LICENSE.md).

## Prerequisites

- **Flutter** 3.44+ (stable channel) with **Dart 3.12+**.
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

Run this before every push — it is exactly what CI runs:

```sh
make check            # format-check + analyze + full test suite
```

Individual steps:

| Command | What it does |
| --- | --- |
| `make format` | Rewrites Dart files with `dart format`. |
| `make format-check` | Fails if any file needs formatting. |
| `make analyze` | `flutter analyze` (analyzer + lints + type checks). |
| `make test` | The full test suite. |
| `make licenses` | Verify every dependency uses an open-source licence. |
| `make check-full` | `check` plus licence compliance and a dependency-freshness report. |

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
  `.d('…')` string lacks a translation in **every** supported language
  (Dutch is the source; en/it/de/fr/es/fy/pap need an entry). Add your strings to
  `lib/l10n/app_localizations.dart` for all languages, or the suite goes red.
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

Use the GitHub issue templates. For **security issues, do not open a public
issue** — follow [`SECURITY.md`](SECURITY.md).
