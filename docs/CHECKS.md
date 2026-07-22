# OciDeck — Checks & CI

Every automated check OciDeck runs, what it covers, what a failure means, and how
to fix it. The **`Makefile` is the single entry point** and the **real gate**:
`make check`, run by the committer before pushing, is what actually enforces
these checks. GitHub Actions workflows are defined under `.github/workflows/`,
but the project's remote is a Forgejo instance with **no CI runner configured**,
so they do not execute — see [Continuous integration](#continuous-integration).
Run `make help` for a one-line summary of every target.

## The one command

```sh
make check        # format-check + analyze + conventions + method-length + dead-code + coverage + per-file floor
```

Run this before every push — it is the enforced gate. For the extended
local sweep that also covers licences and dependency health:

```sh
make check-full   # check + licenses + sbom-verify + deps-check + check-web + deps-outdated
```

## Localisation helpers

Every translatable string must exist in all 32 languages, so adding one used to
mean editing 31 files by hand. Two helpers remove that toil:

```sh
make add-l10n SPEC=strings.json  # insert d('…') strings into every language
make l10n-check                  # fast l10n gate: dup keys + coverage + format
```

`make add-l10n` reads a JSON spec (Dutch source → per-language translations; the
format is documented in `tool/add_l10n.dart`), inserts each string into that
language's additions overlay, `dart format`s the result, skips anything already
present, and whitelists any `unchanged` loanwords. `make l10n-check` runs just
the l10n parts of `make check` (the duplicate-key and per-language coverage
guards plus formatting), handy while iterating on translations.

## How intensively is it tested?

To give a sense of scale. These are counts from one moment, and they only grow,
so read the date with them:

| Metric | Counted on 2026-07-22 |
| --- | ---: |
| Automated tests in the suite | **4852** (excluding the `golden` tag) |
| Test files under `test/` | **450** |
| Source files under `lib/` | 574 excl. the 32 translation files (indexed in [`SOURCE_MAP.md`](SOURCE_MAP.md)) |
| Line coverage (enforced floor: 80%) | **82.5%** — 42 798 of 51 862 lines, 508 instrumented files |

*(Corrected 2026-07-22: this table said "~4570 / ~435 / ~564" and called them
"point-in-time figures" without saying which point in time, so there was no way
to tell how far they had drifted. They are now dated, and re-counting them is
part of the procedure under [Latest result](#latest-result).)*

Coverage is a floor **and** a census: `make coverage` also fails when a `lib/`
file appears in no test at all. Such a file is not 0% — lcov never records it,
so it sits outside the fraction entirely and the percentage alone can never see
it (see [`make coverage`](#make-coverage)).

`make check` runs the **entire** suite — there is no "smoke subset". The tests
span unit (model/parsing/state), widget (every slide editor, the dialogs, the
panels, the live preview and the fullscreen presenter's keyboard handling) and
service-level (export, file IO, sanitisation) layers, plus the enforced
localization and security guards listed below. With no CI runner on the Forgejo
remote, the number you see locally is the number that gates the push.

---

## Latest result

The sections above and below describe the procedure; this one records what came
out of it, the way [`LICENSE_COMPLIANCE.md`](LICENSE_COMPLIANCE.md) records its
own last run. A dated outcome next to a repeatable command is the difference
between "we check this" and "we checked this".

**Run on 2026-07-22**, on macOS (arm64), Flutter 3.44.6, at commit `b98ee072`:

| Command | Outcome |
| --- | --- |
| `flutter test --test-randomize-ordering-seed random --exclude-tags golden` | pass — 4852 tests, 2 skipped |
| `dart run tool/coverage_summary.dart --min=80 --require-instrumented` | pass — 82.5% (42 798/51 862 lines, 508 instrumented files); no `lib/` file outside the census |
| `dart run tool/coverage_summary.dart --per-file-floor` | pass — 19 files below the per-file floor, 5 of them at zero, against a budget of 21 |
| `dart run tool/check_licenses.dart` | pass — 187 packages, all recognised open-source ([`LICENSE_COMPLIANCE.md`](LICENSE_COMPLIANCE.md)) |

**What this run did not cover.** Only the four commands above were executed. The
rest of `make check` — `format-check`, `analyze`, `check-conventions`,
`check-method-length`, `check-dead-code`, `check-hardcoded-text` — and the
`check-full` extras (`sbom-verify`, `deps-check`, `check-web`) were not run here,
so this table says nothing about them. It is a snapshot, not a certificate: the
only run that means anything for a given commit is the one you do yourself
before pushing it.

Two of these numbers are budgets rather than achievements. The per-file floor
allows 21 files below it and 19 are there, so that gate is nearly full; the
overall 82.5% sits above an 80% floor that is a ratchet, meant to be raised as
coverage improves rather than treated as a target already met.

---

## All checks at a glance

| Check | Verifies | In `make check` | In `check-full` | In CI workflow † |
| --- | --- | :---: | :---: | :---: |
| [`make format-check`](#make-format-check) | Code is `dart format`-clean | ✅ | ✅ | ✅ |
| [`make analyze`](#make-analyze) | No analyzer/lint/type issues (`--fatal-infos`) | ✅ | ✅ | ✅ |
| [`make check-conventions`](#make-check-conventions) | No `print()`; no raw control bytes; bare `catch (_)`, raw-colour, layering & file-size ratchets | ✅ | ✅ | ✅ |
| [`make check-method-length`](#make-check-method-length) | Per-method length ratchet (AST, max 150) | ✅ | ✅ | ✅ |
| [`make check-dead-code`](#make-check-dead-code) | No orphaned `lib/` files (unreachable from any entrypoint) | ✅ | ✅ | ✅ |
| [`make test`](#make-test) | Full unit/widget suite passes (randomised order) | ✅ (via `coverage`) | ✅ | ✅ |
| [`make coverage`](#make-coverage) | Line coverage ≥ 80% floor **and** every `lib/` file is in some test | ✅ | ✅ | ✅ (gate) |
| [`make coverage-per-file`](#make-coverage-per-file) | At most `filesBelowFloorBudget` `lib/` files run under 20% of their own lines | ✅ | ✅ | — |
| [`make licenses`](#make-licenses) | Every dependency is open-source | — | ✅ | ✅ |
| [`make sbom-verify`](#make-sbom--make-sbom-verify) | Committed SBOM matches the dependency set | — | ✅ | ✅ |
| [`make deps-check`](#make-deps-check) | Vendored export JS: integrity + CVEs | — | ✅ | ✅ |
| [`make check-web`](#make-check-web) | Web bundle keeps its hardening | — | ✅ | ✅ |
| [`make deps-outdated`](#make-deps-outdated-advisory) | Dependency freshness (advisory) | — | ✅ | — |
| [`make catalogs-outdated`](#make-catalogs-outdated-advisory) | Bundled reference data vs upstream (advisory, pre-release) | — | — | — |
| [`make check-secrets`](#make-check-secrets) | No credential-shaped strings in the working tree or in history | — | ✅ | — |
| [`make sast`](#make-sast) | Semgrep rules over shipped Dart (cert validation, subprocesses, weak randomness) | — | ✅ | — |
| [`make dast`](#make-dast-advisory) | ZAP baseline over a served build (advisory) | — | — | — |
| [`make trivy`](#make-trivy-advisory) | Dart-dep CVEs + committed secrets (advisory) | — | — | ✅ (advisory) |
| [`make check-actions`](#make-check-actions-advisory) | Pinned CI Actions vs their latest release (advisory) | — | — | — |

† The **In CI workflow** column is what `.github/workflows/ci.yml` *declares* —
not what runs. That workflow does not currently execute: the remote is Forgejo
with no runner (see [Continuous integration](#continuous-integration)). Until a
runner exists, only what the committer runs locally gates a push, and `make
check` alone does **not** include `licenses`, `sbom-verify`, `deps-check` or
`check-web` — those live in `check-full`. Run `make check-full` before a
dependency or web-facing change.

The workflow additionally declares `flutter pub get --enforce-lockfile`
(reproducible dependencies) and a **Markdown link check** (`lychee --offline`).

Enforced inside `make test`: **localization in all 32 languages**, the
**path/SSRF guards**, the **HTML-export sanitisation** invariants (strict
export CSP + injected-`</script>` neutralisation; see
[below](#enforced-behaviours-worth-calling-out)), and **documentation
registration** — every `docs/**/*.md` (design docs are their own class) must be
bundled in `pubspec.yaml` and surfaced in the in-app reader, so a new document
cannot ship unreachable. The
[targeted test groups](#targeted-test-groups) (`make test-contracts`,
`test-preview`, `test-export`, `test-state`, `test-services`, `test-presenter`)
are subsets of `make test` for focused work — not separate gates.

---

## Quality gate

These three are the core of `make check` — the enforced gate. (The CI workflow
also declares them, but see the [CI note](#continuous-integration).)

### `make format-check`
- **Runs:** `dart format --output=none --set-exit-if-changed .`
- **Covers:** every Dart source and test file in the workspace.
- **Failure means:** at least one file is not formatted. Fix with `make format`
  (which rewrites files in place), then re-run.
- **Note:** `dart format`'s output is tied to the Dart/Flutter version. The repo
  is pinned to **Flutter 3.44.6** (see [Version pin](#version-pin)); a different
  local version can report spurious drift. Match the pin before reformatting the
  whole tree.

### `make analyze`
- **Runs:** `flutter analyze --fatal-infos`
- **Covers:** the analyzer, lints, and type checks for the app and tests, using
  the rules in `analysis_options.yaml` — which enables `strict-casts`,
  `strict-raw-types`, and `strict-inference`. `--fatal-infos` makes info-level
  diagnostics fail the build, so those strict modes are actually enforced.
- **Failure means:** a warning, lint, info, or type error. **Zero is the bar** —
  read the diagnostics above the final summary and resolve each.

### `make check-conventions`
- **Runs:** `dart run tool/check_conventions.dart`
- **Covers:** these project conventions in `lib/`:
  - **no `print()`** (diagnostics go through the logger in `lib/utils/log.dart`);
  - **no bare `catch (_)`** (silently swallowing errors) — a **ratchet**: a
    baseline count that may shrink but never grow, currently **0**, so every
    swallow routes a named error through `logError`/`logWarning`;
  - **raw-colour ratchet** — literal `Color(0x…)` outside
    `lib/theme/app_theme.dart` may shrink but never grow (`rawColorBaseline`);
  - **no raw control bytes** in any `lib/`, `test/` or `tool/` source. A
    control character written as the *byte* rather than as an escape
    (`\u0000`) makes the whole file read as **binary**: `grep` silently skips
    it — no output at all, not "no matches" — and `git diff` shows
    `Bin … bytes` instead of a reviewable diff. A source file invisible to a
    grep audit and unreadable in review is a real hazard in a security tool,
    and the escape costs nothing: the resulting string is byte-identical;
  - **layering ratchet** — `lib/models/` may not import Flutter's UI layer or
    `lib/widgets/` at all (hard **0**), and the count in `lib/services/` may
    shrink but never grow (`serviceUiImportBaseline`, currently **8**). A
    service is the headless core: usable without a widget tree, testable
    without pumping one. `foundation.dart`/`services.dart` are exempt — they
    carry no widget tree.
    Prefer a semantic `AppTheme` token so a palette change — and a future dark
    mode — touches one place instead of dozens;
  - **file-size ratchet** — no file may exceed **1000** lines, except the
    files listed in `fileSizeBaseline` whose ceiling is their size at ratchet
    time. A ceiling may shrink (split the file) but never grow, so large files
    trend smaller instead of creeping bigger. `lib/l10n/translations/*` is
    exempt (those grow with every UI string).
  - **privacy projection boundary** — every surface that hands slide content to
    a recipient (`SlideRasterizer.rasterize`, `FullscreenPresenter.present`,
    `ExportDialog.show`) must take an `AudienceDeck` and must not accept a raw
    `Deck` or `List<Slide>`. That type can only be minted by `PrivacyProjection`,
    so as long as the entry points hold the line, no unredacted text can escape —
    the compiler refuses it. The risk here is not technical but human: someone
    adds a fourth export format in six months, hands it a `Deck`, and the
    guarantee is quietly gone without a single test going red. A convention in a
    design document does not stop data; a compile error does. See
    `audienceBoundary` in the tool and `docs/design/OCIWACHT.md` §6;
- **Failure means:** route the diagnostic through `logError`; **or** replace the
  literal colour with an `AppTheme` token (then lower `rawColorBaseline`); **or**
  split the oversized file (then lower its `fileSizeBaseline` entry — the run
  prints a tip), or deliberately raise the entry with a reason; **or** — if you
  removed a `catch (_)` — lower `catchUnderscoreBaseline` to lock it in.

### `make check-method-length`
- **Runs:** `dart run tool/check_method_length.dart`
- **Covers:** a **per-method/function-length ratchet** — the per-declaration
  sibling of the file-size ratchet. No method, top-level function or constructor
  body may exceed **150** lines (signature through closing brace, excluding the
  doc comment), except the declarations listed in `methodLengthBaseline` whose
  ceiling is their length at ratchet time. A ceiling may shrink (split the
  method) but never grow.
- **How it measures:** the **`analyzer` package's AST**, not a text heuristic,
  so closures, multi-line signatures and `=>` bodies are counted correctly.
  Keys are `path::Enclosing.name`, stable across line edits. Local functions
  count toward the method that holds them. `lib/l10n/translations/*` is exempt.
- **Failure means:** extract helpers or sub-widgets to shrink the method (then
  lower its `methodLengthBaseline` entry — the run prints a tip), or deliberately
  add/raise the entry with a reason.

### `make check-dead-code`
- **Runs:** `dart run tool/check_dead_code.dart`
- **Covers:** **orphaned files** — the analyzer's blind spot. `flutter analyze
  --fatal-infos` already fails on unreachable statements, unused imports/locals/
  fields and unused *private* elements, but a whole `.dart` file (or a public
  symbol) that nothing imports stays green forever. This check builds the `lib/`
  import graph and walks it from every top-level `main(`; any file reachable via
  `import` / `export` / `part` from none of them is dead.
- **How it measures:** static directive scan — **both** branches of a conditional
  import (`import 'x.dart' if (dart.library.io) 'y.dart'`) count as edges, `part`
  files are pulled in by their parent, and `package:ocideck/…` resolves to `lib/`.
  An unparsed/comment URI can only *add* an edge, so the check errs toward missing
  a dead file, never toward failing on a live one.
- **Failure means:** delete the orphaned file, wire it in, or — for a deliberate
  dynamic entrypoint the static walk can't follow — add it (with a reason) to
  `deadCodeAllowlist` in `tool/check_dead_code.dart`.
- **Not covered:** unused *public symbols* inside a live file (high false-positive
  rate: generated l10n, test-only use). Use `make fix` (`dart fix --apply`) to
  sweep the analyzer-visible kinds; `make analyze` then enforces the result.

### `make test`
- **Runs:** `flutter test --test-randomize-ordering-seed random --exclude-tags golden`
  — the full unit/widget suite under `test/`, in a randomised order so no test can
  silently depend on another running first. The golden (visual-regression) tests
  are excluded here and run separately via `make test-golden`.
- **Covers:** Markdown round-trip, preview/rendering, export, providers/state,
  services, the presenter, localization, and more.
- **Failure means:** inspect the named failing test file and case in the output.
  If it only fails for some seeds, you have an order-dependent test — the seed is
  printed at the top of the run so you can reproduce it.
- **One suite needs a platform build first.** The image privacy check (recognisable
  faces on slide images) runs on OpenCV through FFI, and that native library lives
  in the app bundle — a bare `flutter test` on the Dart VM does not have it, so
  those tests skip themselves and report `~2`.

  If this working copy has ever run `flutter build macos|linux|windows`, the
  Makefile finds the library under `build/` and exports `DARTCV_LIB_PATH`
  automatically; the tests then run for real. No variable to remember — but if you
  are changing the detector, do a platform build first, or you are testing
  nothing. In CI all three desktop jobs build first — Linux in the gate, macOS and
  Windows in the matrix — and each fails loudly if the library is not where it
  expects, rather than falling back to skipping.

### `make coverage`
- **Runs:** `flutter test --coverage --test-randomize-ordering-seed random --exclude-tags golden`
  then `dart run tool/coverage_summary.dart --min=80 --require-instrumented`.
- **Covers:** two things. (1) Line coverage across every `lib/` file a test
  imports. (2) That there **is** such a test for every `lib/` file.
- **Failure means:** coverage dropped below the floor (currently **80%**), **or**
  a `lib/` file is in no test at all.
- **Why (2) exists:** lcov only records files a test imported, so a file no test
  touches is not 0% — it is absent from the denominator altogether. Add a
  brand-new, wholly untested file and the percentage does not move a hair: the
  one case a coverage floor exists to catch is the one case it structurally
  cannot see. `--require-instrumented` enumerates `lib/` from disk instead and
  fails on any file missing from the report. The 60 files legitimately absent
  today are baselined in `uncoveredBaseline` with a reason each — platform
  halves / conditional-import facades (the VM test runner cannot load
  `dart:js_interop` code at all), files with no executable lines (`export`
  barrels, enums, const data tables), and the per-language finding-template data
  tables under `lib/services/finding_templates/`. It is a **ratchet**: it may shrink, and
  the run prints a tip when a baselined file becomes covered.
- Since this supersedes `make test` (same suite, one run, plus the floor),
  `make check` depends on **`coverage`** rather than `test`.

### `make coverage-per-file`
- **Runs:** `dart run tool/coverage_summary.dart --per-file-floor`, over the
  report `make coverage` just wrote — no second test run.
- **Covers:** the worst case *per file* instead of the average: how many `lib/`
  files execute less than **20%** of their own lines.
- **Failure means:** more files sit below that floor than
  `filesBelowFloorBudget` allows (write a test for one of the files the run
  lists), **or** the budget was left standing after an improvement (lower it to
  the number the run prints).
- **Why it exists:** being in the denominator is not being executed. A test that
  imports a file without ever calling into it keeps that file in the report at
  0%, and an 80% average absorbs it without a ripple — on 2026-07-21 twenty-two
  `lib/` files were in exactly that state, 1.219 lines between them, and they
  passed both gates above. Neither the floor nor `--require-instrumented` can
  see this: one looks at the mean, the other only at whether a file is mentioned
  anywhere.
- **A budget, not an allow-list.** A list of blessed files grows quietly — one
  more line per untested file and nobody notices. A number cannot absorb
  anything: a new untested file pushes the count over the budget and the gate
  goes red. It is a **ratchet in both directions** — it may only shrink, and it
  fails when it lags reality by more than a file or two, so the win is locked in
  rather than left as headroom for the next regression. Target: **0**.

---

## Security & licence compliance

### `make licenses`
- **Runs:** `dart run tool/check_licenses.dart`
- **Covers:** the licence of every resolved Dart/Flutter package (direct +
  transitive).
- **Failure means:** a dependency uses an unrecognised or non-open-source
  licence — review it. See [`LICENSE_COMPLIANCE.md`](LICENSE_COMPLIANCE.md) for
  the policy and the allow-list.

### `make sbom` / `make sbom-verify`
- **Runs:** `dart run tool/generate_sbom.dart` (and `--check` for `sbom-verify`).
- **Covers:** the Software Bill of Materials the EU Cyber Resilience Act
  (Reg. (EU) 2024/2847, Annex I Part II §1) requires. `make sbom` regenerates
  `sbom/ocideck.cdx.json` (CycloneDX 1.6) and `sbom/ocideck.spdx.json`
  (SPDX 2.3) from the files that are already the source of truth. `make
  sbom-verify` regenerates in memory and fails if the committed SBOM drifted
  (volatile timestamp/serial fields are normalised out first).
- **Failure means:** dependencies changed but the SBOM wasn't regenerated —
  run `make sbom` and commit the result. See [`SBOM.md`](SBOM.md) for the
  format, the covered components, and the CRA mapping.

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

### `make catalogs-outdated` (advisory)
- **Runs:** `dart run tool/check_reference_data.dart --advisory`
- **Covers:** dezelfde bronnen als de blokkerende variant in `make deps-check` —
  WSTG, MASTG, MASWE, CWE, MIAUW en CVSS — maar dan zonder de build te breken.
- **Waarom apart:** het zijn twee verschillende vragen op twee verschillende
  momenten. De poort in `deps-check` vraagt *mag dit gemerged worden?*, en daar
  is verouderd terecht een blokkade. Dit doel vraagt *weet ik wat ik ga
  inpakken?*, en dat hoort vóór een release-build. Daar zou falen juist verkeerd
  zijn: een nieuwe upstreamversie is geen defect in wat je bouwt, en een controle
  die de release afbreekt wordt binnen twee releases weggevlagd — precies de
  zichtbaarheid kwijt die het doel was.
- **Draait vanzelf** als eerste stap van `scripts/build_release.sh`
  (`make build-release`), vóór de builds, zodat de melding niet onder twintig
  minuten compileruitvoer verdwijnt.
- **Exit 2 (geen netwerk) breekt de release niet**, maar zegt wel dát er niet
  gekeken is. Stilte mag hier niet als goedkeuring lezen.
- **Daarna:** `make refresh-catalogs` haalt de nieuwe versies op, en
  `make refresh-lexicon` het gezondheidslexicon uit Orphanet.
- **Twee soorten bron, twee soorten melding.** Een standaard die verouderd is,
  laat de poort in `deps-check` vallen. Een bron met `advisory: true` in
  `lib/services/reference_standards.dart` meldt zich wél maar blokkeert nooit —
  dat is voor **detectielexicons**. Die brengen maandelijks uit, en bij een
  lexicon *vuurt* elke term, dus een verversing kost een termdiff lezen en de
  vals-positievencorpus opnieuw wegen. Een poort die daarop rood wordt, staat
  binnen twee maanden permanent rood en gaat uit.

### `make check-web`
- **Runs:** `make build-web` then `dart run tool/check_web_hardening.dart`.
- **Covers:** that the built `build/web` keeps its hardening — a strict CSP in
  `index.html` (`script-src 'self' 'wasm-unsafe-eval'`, no `unsafe-inline`/
  `unsafe-eval`, `connect-src 'self'`, `object-src 'none'`, `form-action
  'none'` — that last one does *not* fall back to `default-src`, so it is
  asserted separately), CanvasKit
  **self-hosted** (local wasm + the `useLocalCanvasKit` flag), and the UI font
  **bundled** — so the running app pulls zero third-party origins.
- **Failure means:** a change weakened the CSP or re-introduced a CDN/font fetch;
  the script lists every broken invariant. See [`BUILD.md`](BUILD.md) for the
  hardened build.

### `make deps-outdated` (advisory)
- **Runs:** `flutter pub outdated`
- **Covers:** dependency freshness only. **Advisory** — it may need network
  access and an outdated package is not in itself a regression. Not part of the
  required gate.

### `make sast`
- **Runs:** `semgrep scan --config semgrep/ocideck.yaml --metrics=off --error`
  over `lib/`, `tool/` and `test/`. Needs the `semgrep` binary
  (`brew install semgrep`).
- **Covers:** three invariants that the Dart-specific tools do not check —
  certificate validation being overridden outside `net_guard.dart`, a subprocess
  started outside the git layer (it escapes NetGuard), and a non-cryptographic
  `Random()` bound to a name that says "secret".
- **Rules are local and committed**, in [`semgrep/ocideck.yaml`](../semgrep/ocideck.yaml).
  Deliberately not `--config auto`: that fetches rules over the network at scan
  time and reports metrics. Local rules keep the gate offline and reproducible,
  the same reason `deps-verify-offline` exists.
- **Why Semgrep at all**, given `check_conventions.dart` already knows the AST:
  because it parses, and grep does not. Writing these rules, a grep for
  `badCertificateCallback` returned three hits in `lib/` — all three inside doc
  comments explaining the pinning design. Semgrep returns none, and flags only a
  real assignment. The ruleset is scoped to that difference and does not repeat
  the existing gates.
- **Failure means:** a rule matched. Read it before silencing it; each rule is
  deliberately narrow (the randomness rule keys on the *variable name* so a
  `Random()` for an animation stays quiet).
- **Both directions are tested:** zero findings across 627 files on `main`, and
  three findings on a file with planted violations — with the commented-out
  equivalents correctly ignored.

### `make check-secrets`
- **Runs:** `gitleaks` over the working tree and over all history, then
  `trufflehog` over both, with `--redact` / `--no-verification`. Needs both
  binaries (`brew install gitleaks trufflehog`).
- **Covers:** credential-shaped strings anywhere in the repository, including
  commits that added a secret and later removed it. Two scanners rather than
  one because they disagree usefully: gitleaks matches entropy and rule
  patterns, trufflehog carries per-provider detectors.
- **Failure means:** something outside the allowlist looks like a credential, or
  a scanner binary is missing. Triage by hand — do not silence a finding without
  reading it.
- **Required before a PR.** Wired into `check-full`, deliberately **not** into
  `check`: the everyday gate cannot assume external binaries are installed.
- **Verification is off on purpose.** Trufflehog would otherwise send candidate
  secrets to the issuing service to see whether they are live — outbound traffic
  carrying credentials to third parties, which contradicts the project's own
  premise. Verify a single finding by hand if it ever matters.
- **What is excluded, and the price:** see [`.gitleaks.toml`](../.gitleaks.toml)
  and [`.trufflehogignore`](../.trufflehogignore). Generated output (`build/`,
  `.dart_tool/`) is skipped as noise. The OciWacht detection corpus —
  `lib/services/privacy/privacy_digital_rules.dart` and the `test/privacy_*`
  fixtures — is skipped because those files exist precisely to hold
  credential-shaped values. The price is real and is stated in the config: a
  genuine secret placed in one of those files would not be caught, and would not
  stand out visually either.

### `make dast` (advisory)
- **Runs:** an OWASP ZAP **baseline** (passive) scan in a container against a
  served build. Without arguments it runs `make build-web`, serves `build/web`
  on `DAST_PORT` (default 8091), scans, and tears the server down. Point it at a
  real instance with `make dast DAST_URL=https://…`.
- **Needs** a container runtime. On macOS: `brew install colima docker && colima
  start`. Docker Desktop also works but is proprietary; colima is the
  open-source equivalent and is what this was built against. The ZAP Homebrew
  cask is *not* an option — it fails the macOS Gatekeeper check and is scheduled
  for removal.
- **Advisory, in no aggregate target.** Findings are for a human to read.
- **Be honest about what it can see.** The CSP is already pinned exactly by
  [`make check-web`](#make-check-web) from the meta tag, so ZAP does not improve
  on that. Its spider cannot traverse the UI — CanvasKit paints into a canvas,
  so there are no links or forms to follow and only the initial load is
  observed. Against the local server, most header findings are about *that
  server*.
- **What it silences, and nothing more:** [`zap/baseline.conf`](../zap/baseline.conf)
  ignores exactly three rules, all pure artefacts of `python3 -m http.server`
  (leaked `Server` version, its cache headers, and the "Modern Web Application"
  observation). Everything a real host would have to answer for — CSP delivered
  as a header, `Permissions-Policy`, `Cross-Origin-Embedder-Policy`,
  anti-clickjacking, `X-Content-Type-Options` — stays visible on purpose, so the
  list still says something the day this is published somewhere.
- **Known noisy:** rule 10027 (*Information Disclosure — Suspicious Comments*)
  fires on the vendored export libraries, not on our own `index.html`. It is
  left visible rather than silenced, because silencing a rule nobody has read is
  how a scanner stops being worth running.
- **Its first run earned its keep:** it found that the CSP has no `form-action`
  directive, which does *not* fall back to `default-src`. `frame-ancestors` is a
  different matter — it is present but browsers ignore it in a `<meta>` tag, and
  `web/index.html` already documents exactly that.

### `make trivy` (advisory)
- **Runs:** `trivy fs --config trivy.yaml .` (needs the external
  [`trivy`](https://trivy.dev) binary; `brew install trivy` on macOS).
- **Covers:** known **CVEs in the resolved Dart packages** (`pubspec.lock`) —
  which `make licenses` checks for licence but not for vulnerabilities — plus a
  **committed-secret sweep** over the repo. Scanners and scope are pinned in
  [`trivy.yaml`](../trivy.yaml).
- **Advisory** and deliberately **not** wired into `check`/`check-full`: the
  gate can't assume the `trivy` binary is installed, and Dart/pub advisory
  coverage is still thin, so a finding is a prompt to review rather than a build
  break. Container/IaC scanners are omitted — OciDeck ships no images or IaC.

### `make check-actions` (advisory)
- **Runs:** `dart run tool/check_pinned_actions.dart` (`--offline` validates the
  manifest without hitting the network).
- **Covers:** every third-party CI Action pinned to an **exact** version in
  [`.github/pinned-actions.json`](../.github/pinned-actions.json) (currently
  `aquasecurity/trivy-action`). It queries each Action's release API and flags
  any that have fallen behind, so a stale pin stands out — the Action analogue
  of `make deps-check`. Actions on a floating major tag (`@v4`, `@v2`)
  auto-update and are intentionally not tracked.
- **Advisory** and not part of the gate (it needs network access and a bump is a
  prompt, not a regression). When it reports a newer release, bump the `uses:`
  in the workflow **and** the version in the manifest in the same commit.

---

## Enforced behaviours worth calling out

- **Localization is enforced by a test.** `test/app_localizations_test.dart`
  fails if any `context.l10n.d('Nederlandse brontekst')` string lacks a
  translation in **every** supported language (Dutch is the source, so each of
  the other **30** languages needs an entry). Use `make add-l10n SPEC=…` to insert
  a string into every per-language file in `lib/l10n/translations/` at once, or
  `make test` goes red.
- **Path / SSRF guards** are covered by `test/asset_path_guard_test.dart`,
  `test/project_path_security_test.dart`, and the net-guard tests — they keep
  deck-supplied paths and URLs from escaping the project or reaching internal
  hosts.
- **HTML-export sanitisation** is covered by `test/export_sanitization_test.dart`:
  the export carries a strict, nonce-based CSP (no `unsafe-inline`/`unsafe-eval`,
  `object-src 'none'`) and any `</script>` an untrusted deck injects is escaped
  so it can't break out of the inert markdown data holder.
- **Class-level guards** catch whole bug *families*, not just known cases:
  - `test/network_sink_guard_test.dart` — a source scan that fails if any
    egress primitive appears outside the files that apply `NetGuard`, so a new
    sink cannot reintroduce SSRF. It covers `NetworkImage` /
    `VideoPlayerController.networkUrl`, raw `HttpClient`, **and** the other ways
    to open a socket: `package:http`, `package:dio`, `Socket`, `SecureSocket`,
    `WebSocket`, `RawDatagramSocket`. That last group was added after the guard
    was found to scan for `HttpClient(` alone — which made its own promise
    ("a new raw client fails this test") untrue for every other primitive: an
    `http.get(deckSuppliedUrl)` anywhere in `lib/` passed every gate untouched.
  - `test/markdown_roundtrip_fuzz_test.dart` — an adversarial corpus (pipe,
    `-->`, `<br>`, backslash, HTML metachars, newlines) through every lossless
    field, so a new escaping bug fails instead of silently losing author text.
  - the `ThemeProfile.fromJson` fuzz in `test/settings_provider_test.dart` —
    every style colour must read back as `#RRGGBB` and every font as a
    whitelisted family, blocking CSS/HTML injection via an imported theme.
  - `test/style_profile_export_test.dart` — the standalone `.ocideckstyle`
    carrier of that same profile: a file without the format marker, with an
    unsupported version, or over the size cap is refused rather than half-read;
    an embedded logo is accepted only on its magic bytes (a declared MIME type
    is ignored); a bare `logoPath` from someone else's disk is dropped; and a
    crafted colour in a file still comes back neutralised — so the hardened gate
    is proven on the carrier that actually crosses machines.
  - `test/privacy_scan_redact_parity_test.dart` — the privacy scanner, the
    projection and the redaction manifest each name their fields by hand, in
    three files the compiler never connects. This test holds the three lists
    against each other, so a field that is scanned but not redacted (which
    leaves the user a finding that *Redact* cannot clear, while the value still
    exports) fails by name instead of shipping.
  - `test/privacy_region_coverage_test.dart` — every country pack you can switch
    on has at least one rule, and every rule hangs on a pack you can switch on.
    Both directions matter: a pack with no rules lets "nobody looked" read as
    "nothing found", and a rule outside every pack never runs at all.
  - `test/log_no_content_test.dart` — a source scan of `lib/` for the shapes
    that put deck or file *contents* into a log message (a collection joined,
    taken from, or sliced into the text). It cannot judge a lone variable that
    happens to hold a cell value; it does catch the pattern that actually did it.

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

### Manual tools (not gates)

- **`make mutate`** — a lightweight mutation check for the *dead/untested
  boolean-operand* bug class that `dart analyze` and line coverage both miss
  (an `||`/`&&` operand that can never be true — the line is still hit via
  another operand). It forces each `String.startsWith`/`endsWith` predicate in a
  target file to false and reruns the given tests; a **surviving** mutant is a
  dead or untested predicate to review. Slow and triage-heavy, so it stays out of
  `make check`. Override the target: `make mutate FILE=lib/services/markdown_service.dart TESTS="test/markdown_round_trip_test.dart"`.
- **`make test-golden`** — visual-regression goldens for the slide renderer
  (`test/golden/`). Renders each slide type through `SlidePreviewWidget` (the
  widget behind the editor preview, presenter, thumbnails and the PDF/PPTX
  raster) with the default flutter-test font, so the PNGs catch layout /
  structure / colour regressions (elements moving, resizing, disappearing, wrong
  theme colours) without depending on glyph rendering. The PNGs are pixel- and
  **platform-specific**, so they are tagged `golden` and **excluded from the
  default suite** — run them on **one** platform. `make test-golden` compares;
  `make test-golden UPDATE=1` accepts an intentional visual change. (To gate them
  once a CI runner exists, add a single-platform job that runs `make test-golden`
  and regenerate the PNGs on that platform.)

---

## Continuous integration

> **These workflows are defined but do not currently run.** OciDeck's remote is a
> Forgejo instance with no CI runner configured, so GitHub Actions never fires on
> push or tag. The files are kept ready for a GitHub mirror or a future Forgejo
> runner; until then, **`make check` (plus `make check-full` for the
> dependency/web checks), run by the committer before pushing, is the only
> enforcement.** The sections below describe what the workflow files *declare*.

### `.github/workflows/ci.yml` — declared for every push and pull request
- **Gate (Linux)** — `runs-on: ubuntu-latest`: `flutter pub get
  --enforce-lockfile`, then `make format-check`, `make analyze`,
  `make check-conventions`, `make check-method-length`, `make check-dead-code`,
  `make coverage` (with the line-coverage floor), `make licenses`,
  `make sbom-verify`, and `make deps-check`. Uploads the coverage report.
- **Test matrix (macOS + Windows)** — runs `flutter test
  --test-randomize-ordering-seed random` on the other two desktop OSes to catch
  platform-specific (path, `Platform.isX`) regressions the Linux gate would miss.
  `make` is not reliably present on the Windows runner, so this job calls Flutter
  directly.
- **Web hardening (Linux)** — `make check-web`: builds the web bundle and asserts
  its hardening invariants.
- **Docs links (Linux)** — `lychee --offline` validates internal Markdown links
  across the repo (external URLs are skipped so it can't flake).
- **Supply-chain (Linux, advisory)** — the [`trivy-action`](https://github.com/aquasecurity/trivy-action)
  runs the same `make trivy` scan (Dart-dep CVEs + committed secrets) with
  `exit-code: 0`, so it surfaces findings without blocking merges.

CI does **not** build native binaries here; it validates formatting, analysis,
tests, and the web bundle's hardening, which are platform-independent.

### `.github/workflows/release.yml` — on a version tag (`v*`) or manual run
Produces distributable artifacts. Desktop bundles cannot be cross-compiled, so
each platform builds on its own runner:

| Job | Runner | Output artifact |
| --- | --- | --- |
| SBOM | ubuntu | `ocideck-sbom` — the `sbom/` directory (runs `make sbom-verify` then `make sbom`) |
| web | ubuntu | `ocideck-web` — hardened bundle (`--no-web-resources-cdn --csp`) |
| macOS | macos | `ocideck-macos` — `build/macos/Build/Products/Release` |
| Windows | windows | `ocideck-windows` — the runner `Release` folder |
| Linux | ubuntu | `ocideck-linux` — the `bundle` folder |

See [`BUILD.md`](BUILD.md) for the matching local `make build-*` targets.

---

## Version pin

CI pins **Flutter 3.44.6 (stable)**, recorded in `.tool-versions` (asdf) and in
both `.github/workflows/*.yml`. The pin matters mainly for **`dart format`**: its
line-wrapping output changes between releases, so an unpinned local toolchain — or
a separately installed standalone Dart used instead of the Flutter-bundled one —
can disagree with CI on formatting. Keep your local Flutter on the pinned version
and use its bundled `dart` (or bump the pin in `.tool-versions` + both workflows
and reformat the tree in one mechanical commit).
