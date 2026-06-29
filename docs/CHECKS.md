# OciDeck — Checks & CI

Every automated check OciDeck runs, what it covers, what a failure means, and how
to fix it. The **`Makefile` is the single entry point**: the same targets run
locally and in CI, so "green locally" means "green in CI". Run `make help` for a
one-line summary of every target.

## The one command

```sh
make check        # format-check + analyze + full test suite — the quality gate
```

Run this before every push; it is exactly what the CI gate runs. For the extended
local sweep that also covers licences and dependency health:

```sh
make check-full   # check + licenses + deps-check + deps-outdated
```

---

## Quality gate

These three run on every push and pull request (and as `make check`).

### `make format-check`
- **Runs:** `dart format --output=none --set-exit-if-changed .`
- **Covers:** every Dart source and test file in the workspace.
- **Failure means:** at least one file is not formatted. Fix with `make format`
  (which rewrites files in place), then re-run.
- **Note:** `dart format`'s output is tied to the Dart/Flutter version. The repo
  is pinned to **Flutter 3.44.2** (see [Version pin](#version-pin)); a different
  local version can report spurious drift. Match the pin before reformatting the
  whole tree.

### `make analyze`
- **Runs:** `flutter analyze`
- **Covers:** the analyzer, lints, and type checks for the app and tests, using
  the rules in `analysis_options.yaml`.
- **Failure means:** a warning, lint, or type error. **Zero analyzer warnings is
  the bar** — read the diagnostics above the final summary and resolve each.

### `make test`
- **Runs:** `flutter test` — the full unit/widget suite under `test/`.
- **Covers:** Markdown round-trip, preview/rendering, export, providers/state,
  services, the presenter, localization, and more.
- **Failure means:** inspect the named failing test file and case in the output.

### `make coverage`
- **Runs:** `flutter test --coverage` then `dart run tool/coverage_summary.dart --min=50`.
- **Covers:** line coverage across every `lib/` file a test imports.
- **Failure means:** overall line coverage dropped below the floor (currently
  **50%**). The floor guards against large regressions; raise it as coverage
  improves. This is the coverage form of the gate used in CI.

---

## Security & licence compliance

### `make licenses`
- **Runs:** `dart run tool/check_licenses.dart`
- **Covers:** the licence of every resolved Dart/Flutter package (direct +
  transitive).
- **Failure means:** a dependency uses an unrecognised or non-open-source
  licence — review it. See [`LICENSE_COMPLIANCE.md`](LICENSE_COMPLIANCE.md) for
  the policy and the allow-list.

### `make deps-check`
- **Runs:** `dart run tool/check_bundled_js.dart`
- **Covers:** the **vendored JavaScript bundles** inlined into the HTML export —
  marked, highlight.js, DOMPurify, Mermaid, and MathJax. It verifies two things:
  1. **Integrity** — each file's SHA-256 still matches
     `assets/web_export/MANIFEST.json`.
  2. **Known vulnerabilities** — it queries the [OSV](https://osv.dev) database
     for CVEs in the pinned versions.
- **Failure means:** a bundle drifted from the manifest (re-pin and refresh the
  manifest), or a pinned version now has a known vulnerability (upgrade it and
  refresh the manifest). This is the safe path to upgrade those bundles.

### `make deps-outdated` (advisory)
- **Runs:** `flutter pub outdated`
- **Covers:** dependency freshness only. **Advisory** — it may need network
  access and an outdated package is not in itself a regression. Not part of the
  required gate.

---

## Enforced behaviours worth calling out

- **Localization is enforced by a test.** `test/app_localizations_test.dart`
  fails if any `context.l10n.d('Nederlandse brontekst')` string lacks a
  translation in **every** supported language (Dutch is the source;
  en/it/de/fr/es/fy/pap each need an entry). Add UI strings to
  `lib/l10n/app_localizations.dart` for all languages or `make test` goes red.
- **Path / SSRF guards** are covered by `test/asset_path_guard_test.dart`,
  `test/project_path_security_test.dart`, and the net-guard tests — they keep
  deck-supplied paths and URLs from escaping the project or reaching internal
  hosts.

### Targeted test groups

For focused work, run only the relevant slice instead of the whole suite:

| Target | Covers |
| --- | --- |
| `make test-contracts` | Markdown generation/parsing, save-load round-trips, field migration |
| `make test-preview`   | Slide rendering, footers, TLP, inline Markdown, charts/text styles |
| `make test-export`    | PDF/PPTX export and project file-save behaviour |
| `make test-state`     | Providers, undo/redo, search/replace, settings, recovery |
| `make test-services`  | Image, caption, and description sidecar services |
| `make test-presenter` | Fullscreen presenter navigation and keyboard shortcuts |

---

## Continuous integration

### `.github/workflows/ci.yml` — every push and pull request
- **Gate (Linux)** — `runs-on: ubuntu-latest`: `make format-check`,
  `make analyze`, `make coverage` (with the line-coverage floor), then
  `make licenses` and `make deps-check`. Uploads the coverage report.
- **Test matrix (macOS + Windows)** — runs `flutter test` on the other two
  desktop OSes to catch platform-specific (path, `Platform.isX`) regressions the
  Linux gate would miss. `make` is not reliably present on the Windows runner, so
  this job calls Flutter directly.

CI does **not** build native binaries here; it validates formatting, analysis,
and tests, which are platform-independent.

### `.github/workflows/release.yml` — on a version tag (`v*`) or manual run
Produces distributable artifacts. Desktop bundles cannot be cross-compiled, so
each platform builds on its own runner:

| Job | Runner | Output artifact |
| --- | --- | --- |
| web | ubuntu | `ocideck-web` — hardened bundle (`--no-web-resources-cdn --csp`) |
| macOS | macos | `ocideck-macos` — the `.app` |
| Windows | windows | `ocideck-windows` — the runner `Release` folder |
| Linux | ubuntu | `ocideck-linux` — the `bundle` folder |

See [`BUILD.md`](BUILD.md) for the matching local `make build-*` targets.

---

## Version pin

CI pins **Flutter 3.44.2 (stable)**. The pin matters mainly for **`dart format`**:
its line-wrapping output changes between releases, so an unpinned local toolchain
can disagree with CI on formatting. Keep your local Flutter on the pinned version
(or bump the pin in both `ci.yml` and `release.yml` and reformat the tree in one
mechanical commit).
