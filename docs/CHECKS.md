# OciDeck — Checks & CI

> **Status:** procedure, current, with a dated result under *Latest result* · **Status last reviewed:** 2026-07-23 · **Published by:** Stichting LibreKAT

Every automated check OciDeck runs, what it covers, what a failure means, and how
to fix it. The **`Makefile` is the single entry point** and the **real gate**:
`make check`, run by the committer before pushing, is what actually enforces
these checks. The Forgejo remote has an Actions runner since 2026-07-23, and
`.forgejo/workflows/ci.yml` runs [`make check-no-coverage`](#make-check-no-coverage)
**on a `v*` tag, on the Mac runner** — not per pull request
(#741/#751/#790/#797). That is `make check`
with the full test suite intact but without the coverage instrumentation —
worth roughly 13 minutes off a 46-minute gate on that runner. Read this literally, twice over:
nothing between your `make check` and `main` runs this gate for you, and the
**coverage floors run nowhere but on your own machine**. CI is the release gate;
you are the merge gate.

**One exception, and it is deliberate:** `.forgejo/workflows/scans.yml` runs the
secret and SAST scans (`make check-secrets`, `make sast`) on **every pull
request** (#778). Those take 17 and 2 seconds locally against the 22 minutes per
pull request that moved the gate to a tag, so the timing argument that moved the
gate to a tag does not reach them — and for a secret the moment is not
interchangeable. Found before the merge it is an edit; found after, it is in the
history and revoking is the only real remedy. It scanned pushes to `main` as
well until the redundant post-merge run — re-reading the same full history the
pull request had just cleared — proved to be the one real source of failure
mail; that trigger was dropped. See
[Continuous integration](#continuous-integration).
Run `make help` for a one-line summary of every target.

## The one command

```sh
make check        # format-check + analyze + conventions + method-length + dead-code + coverage + per-file floor
```

> **Prerequisite: `cmake` on your `PATH`.** Since the move to `dartcv4` for
> on-device face detection (#870), the native OpenCV binding is built through a
> native-assets build hook, and that hook runs on **every** `dart run` and
> `flutter test` — so on every `make check`. Without `cmake` the gate dies before
> the first test with `Failed to find cmake with version=latest` (the Android
> SDK's own cmake is deliberately rejected, so an Android toolchain alone is not
> enough). Install it from your platform's package manager — `brew install cmake`
> on macOS, `apt install cmake` on Debian/Ubuntu (see
> [Development setup](DEVELOPMENT_SETUP_GUIDE.md)) — and confirm with
> `cmake --version` before running the gate.

Run this before every push — it is the enforced gate. For the extended
local sweep that also covers licences and dependency health:

```sh
make check-full   # check + licenses + sbom-verify + deps-check + check-web + deps-outdated
```

### `make check-release`

The **ready-for-tagging** pass. Run it by hand right before `git push origin
v*`, because pushing the tag is what triggers the whole release chain
([`release.yml`](../.forgejo/workflows/release.yml)) — build, publish, live
deploy — and this is the last moment a finding can hold a release back instead
of ending up live.

```sh
make check-release   # check-full (blocking) + an advisory ZAP/DAST scan of the live host
```

It runs everything in `check-full` as a hard gate, then a
[`make dast`](#make-dast-advisory) baseline against the live host
(`DAST_LIVE_URL`, default `https://ocideck.librekat.nl/`) as an **advisory**
step: a ZAP warning is something to weigh and, if real, file as an issue — not
something that reddens the command. Without a container runtime the DAST step
skips itself. Two more things belong in the same pre-tag ritual but are **not**
automated here — run [`make linux-gate`](#continuous-integration) and glance at
open `security`/`privacy` issues on the tracker before you tag.

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
| Automated tests in the suite | **5587** (excluding the `golden` tag) |
| Test files under `test/` | **512** |
| Source files under `lib/` | 613 excl. the 32 translation files (indexed in [`SOURCE_MAP.md`](SOURCE_MAP.md)) |
| Line coverage (enforced floor: 80%) | **86.2%** — 46 761 of 54 264 lines, 545 instrumented files |

*(Corrected 2026-07-22: this table said "~4570 / ~435 / ~564" and called them
"point-in-time figures" without saying which point in time, so there was no way
to tell how far they had drifted. They are now dated, and re-counting them is
part of the procedure under [Latest result](#latest-result).)*

*(Re-counted 2026-07-22, later the same day: the figures above were from an
earlier commit and already read 4852 / 450 / 574 / 82.5%. These counts are
deliberately **not** guarded by a test the way the constants further down are —
they are a snapshot of one moment, and a gate over them would redden the build
on every new test file. The date is the guard: read it, and re-count rather than
believe.)*

Coverage is a floor **and** a census: `make coverage` also fails when a `lib/`
file appears in no test at all. Such a file is not 0% — lcov never records it,
so it sits outside the fraction entirely and the percentage alone can never see
it (see [`make coverage`](#make-coverage)).

`make check` runs the **entire** suite — there is no "smoke subset". The tests
span unit (model/parsing/state), widget (every slide editor, the dialogs, the
panels, the live preview and the fullscreen presenter's keyboard handling) and
service-level (export, file IO, sanitisation) layers, plus the enforced
localization and security guards listed below. The CI runner runs the same gate, but on a `v*` tag rather
than per pull request (#790), so your local run is the answer that matters
before a merge — CI only confirms it again at release time.

---

## Latest result

The sections above and below describe the procedure; this one records what came
out of it, the way [`LICENSE_COMPLIANCE.md`](LICENSE_COMPLIANCE.md) records its
own last run. A dated outcome next to a repeatable command is the difference
between "we check this" and "we checked this".

**Run on 2026-07-23**, on macOS (arm64), on this exact toolchain:

```
Flutter 3.44.7 • channel stable • https://github.com/flutter/flutter.git
Tools • Dart 3.12.2
```

**This is the pinned toolchain, and that is new.** Until 2026-07-23 this section
recorded `3.44.2 • [user-branch] • unknown source` — an unofficial build, with
its binaries under a directory named for a third version again — against
documents that all named a pinned release. Because the gate did not run in CI
until 2026-07-23 (#751), that machine was the only place `make check` had ever
run, so every green gate this
project rested on had been produced by a toolchain nobody else could reproduce.
It is now the official stable SDK, hash-verified before unpacking; see
[Toolchains of record](#toolchains-of-record) for how, and `make check-toolchain`
for what now keeps this paragraph from going stale again (#598).

**The whole gate takes about three minutes.** Measured 2026-07-22 on the machine
above: the test suite (5 768 tests, 2 skipped) finishes in 2:04, and the checks
around it — format, analyze, conventions, method length, dead code, hardcoded
text, and two coverage passes — bring it to roughly three. Worth stating,
because "5 700 tests plus a coverage floor plus eight ratchets" reads like half
an hour, and a contributor who assumes that never runs it.

| Command | Outcome |
| --- | --- |
| `make check` (the whole gate) | pass — exit 0 |
| `flutter test --test-randomize-ordering-seed random --exclude-tags golden` | pass — 5587 tests, 2 skipped |
| `dart run tool/coverage_summary.dart --min=80 --require-instrumented` | pass — 86.2% (46 761/54 264 lines, 545 instrumented files); no `lib/` file outside the census |
| `dart run tool/coverage_summary.dart --per-file-floor` | pass — 0 files below the per-file floor |
| `dart run tool/check_licenses.dart` | pass — 187 packages, all recognised open-source ([`LICENSE_COMPLIANCE.md`](LICENSE_COMPLIANCE.md)) |

**What this run did not cover.** `make check` ran in full, so `format-check`,
`analyze`, `check-conventions`, `check-method-length`, `check-dead-code` and
`check-hardcoded-text` are included above; `check_licenses` was run separately in
the same working copy. The `check-full` extras (`sbom-verify`, `deps-check`,
`check-web`) and the advisory scans (`sast`, `shellcheck`, `dast`, `trivy`,
`check-secrets`) were **not** run here, so this table says nothing about them. It is a snapshot,
not a certificate: the only run that means anything for a given commit is the one
you do yourself before pushing it.

One of these numbers is a floor rather than an achievement: 86.2% sits above an
80% floor that is a ratchet, meant to be raised as coverage improves rather than
treated as a target already met. The per-file floor no longer carries a budget —
until 2026-07-22 this table read "19 files below the floor, against a budget of
21", and that budget was removed the same day (see
[`make coverage-per-file`](#make-coverage-per-file)). Zero below the floor is
now the only passing state.

---

## All checks at a glance

| Check | Verifies | In `make check` | In `check-full` | In CI workflow † |
| --- | --- | :---: | :---: | :---: |
| [`make format-check`](#make-format-check) | Code is `dart format`-clean | ✅ | ✅ | ✅ |
| [`make analyze`](#make-analyze) | No analyzer/lint/type issues (`--fatal-infos`) | ✅ | ✅ | ✅ |
| [`make check-conventions`](#make-check-conventions) | No `print()`; no raw control bytes; bare `catch (_)`, raw-colour, layering, file-size, class-size & FilePicker-gate ratchets | ✅ | ✅ | ✅ |
| [`make check-audience-boundary`](#make-check-audience-boundary) | Every output channel classified: audience surface (needs `AudienceDeck`) or deliberately source-faithful | ✅ | ✅ | ✅ |
| [`make check-method-length`](#make-check-method-length) | Per-method length ratchet (AST, max 150) | ✅ | ✅ | ✅ |
| [`make check-dead-code`](#make-check-dead-code) | No orphaned `lib/` files (unreachable from any entrypoint) | ✅ | ✅ | ✅ |
| [`make check-hardcoded-text`](#make-check-hardcoded-text) | No visible string in `lib/` bypasses `l10n.d()` | ✅ | ✅ | — |
| [`make check-comment-language`](#make-check-comment-language) | No plain comment in `lib/` switches language halfway (`mixedCommentBaseline` ratchet) | ✅ | ✅ | — |
| [`make check-toolchain`](#make-check-toolchain) | The running Flutter is the pinned official stable, and is recorded here | ✅ | ✅ | — |
| [`make test`](#make-test) | Full unit/widget suite passes (randomised order) | ✅ (via `coverage`) | ✅ | ✅ |
| [`make coverage`](#make-coverage) | Line coverage ≥ 80% floor **and** every `lib/` file is in some test | ✅ | ✅ | ✅ (gate) |
| [`make coverage-per-file`](#make-coverage-per-file) | No `lib/` file runs under 20% of its own lines | ✅ | ✅ | — |
| [`make licenses`](#make-licenses) | Every dependency is open-source | — | ✅ | ✅ |
| [`make sbom-verify`](#make-sbom--make-sbom-verify) | Committed SBOM matches the dependency set | — | ✅ | ✅ |
| [`make deps-check`](#make-deps-check) | Vendored export JS: integrity + CVEs | — | ✅ | ✅ |
| [`make check-web`](#make-check-web) | Web bundle keeps its hardening | — | ✅ | ✅ |
| [`make deps-outdated`](#make-deps-outdated-advisory) | Dependency freshness (advisory) | — | ✅ | — |
| [`make catalogs-outdated`](#make-catalogs-outdated-advisory) | Bundled reference data vs upstream (advisory, pre-release) | — | — | — |
| [`make check-secrets`](#make-check-secrets) | No credential-shaped strings in the working tree or in history | — | ✅ | ✅ |
| [`make sast`](#make-sast) | Semgrep rules over shipped Dart (cert validation, subprocesses, weak randomness) | — | ✅ | ✅ |
| [`make shellcheck`](#make-shellcheck) | ShellCheck over the committed shell scripts | — | ✅ | — |
| [`make dast`](#make-dast-advisory) | ZAP baseline over a served build (advisory) | — | — | — |
| [`make trivy`](#make-trivy-advisory) | Dart-dep CVEs + committed secrets (advisory) | — | — | ✅ (advisory) |
| [`make check-pins`](#make-check-pins-advisory) | Exact-pinned CI versions — actions *and* scanner binaries — vs their latest release (advisory) | — | — | — |

† The **In CI workflow** column is what `.github/workflows/ci.yml` *declares* —
not what runs. That workflow does not execute: Forgejo reads
`.forgejo/workflows/` instead of `.github/workflows/` once the former exists
(see [Continuous integration](#continuous-integration)). What *does* run in CI
is [`make check-no-coverage`](#make-check-no-coverage) on the Mac runner, on a
`v*` tag (#790/#796/#797), plus
[`make check-secrets`](#make-check-secrets) and [`make sast`](#make-sast) on
every pull request (#778) — those two are the only checks in
this table that a forge actually runs before a merge.
Note that `make
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
  is pinned to **Flutter 3.44.8** (see [Version pin](#version-pin)); a different
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
    baseline count that may shrink but never grow (`catchUnderscoreBaseline`,
    currently **0**), so every swallow routes a named error through
    `logError`/`logWarning`;
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
    shrink but never grow (`serviceUiImportBaseline`, currently **4**). A
    service is the headless core: usable without a widget tree, testable
    without pumping one. `foundation.dart`/`services.dart` are exempt — they
    carry no widget tree.
    Prefer a semantic `AppTheme` token so a palette change — and a future dark
    mode — touches one place instead of dozens;
  - **file-size ratchet** — no file may exceed the line ceiling
    (`maxFileLines`, currently **1000**), except the
    files listed in `fileSizeBaseline` whose ceiling is their size at ratchet
    time. A ceiling may shrink (split the file) but never grow, so large files
    trend smaller instead of creeping bigger. `lib/l10n/translations/*` is
    exempt (those grow with every UI string).
  - **class-size ratchet** — no *class* may exceed **1000** lines either,
    counted over **all `part` files of its library**: the class itself plus
    every `extension … on` hanging off it. This exists because the file ratchet
    counts files, and a `part` split quiets it without anything getting
    smaller — `TabsNotifier` sits at ~2,400 lines across seven parts and
    `_SettingsDialogState` at ~7,300 across twenty-two, every file neatly under
    a thousand while the class kept growing. The unit that costs you is the one
    you have to hold in your head to change it, which is the class, not the
    file. Same number as the file ceiling on purpose: the promise was "no unit
    over a thousand lines", and this restores it for the unit that counts.
    Fifteen classes were already over when the ratchet went in; they sit in
    `classSizeBaseline` with their current size as their ceiling, which may
    shrink (the run prints a tip) but never grow. The key is
    `<library>#<Name>`, not `<file>#<Name>` — an extension in a part counts
    towards the class it extends, and the library keeps two private
    `_FooState`s in different screens from being added together. A baseline
    entry naming a class that no longer exists is reported as well: a ceiling
    without a class covers nothing. Measured by line scan rather than an AST,
    which holds because `make format-check` fixes the layout: a top-level
    declaration starts at column 0 and closes with a `}` at column 0; only
    `'''` strings are skipped, since they are the one thing that can put a
    false closing line there.
  - **FilePicker paths behind a platform gate** — a *call site* in `lib/` that
    takes a filesystem path from the file picker must have a platform gate
    (`kIsWeb`, `supportsLocalProjectFolders` or `isWebPlatform`) **in the same
    method**. Per call site, not per file: a gate in one method says nothing
    about the next, and `image_service.dart` gates `pickImageDetailed` properly
    while `pickVideo` and `pickAudio` sit ungated right beside it. Two shapes count:
    `FilePicker.getDirectoryPath(`, which has no web implementation and returns
    `null` without a sound, and `FilePicker.pickFiles(` whose `.path` is read
    without `withData: true`, which on web hands back a `blob:` URL that points
    nowhere after a reload. `saveFile(bytes:)` is deliberately excluded — in a
    browser that is a download and does what it promises. This is a **ratchet**:
    `filePickerPathBaseline` lists the files that gate at their *caller* rather
    than in the file itself, and it may only shrink; a stale entry is reported
    too, because a baseline that no longer matches reality reads as "someone
    thought about this" when nobody did. The rule exists because a test cannot:
    `kIsWeb` is always `false` under `flutter test`, the flag arrives through a
    conditional import with no injection point, and there is no
    `--platform chrome` target — so a widget test sits green around the broken
    branch. That is how the buttons in issue #150 came back as #506.
  - **no fixed delay inside `runAsync` in tests** — `runAsync(() =>
    Future.delayed(const Duration(milliseconds: 80)))` waits on a guess about
    how long real work takes on this machine, not on the result. Such a test
    passes in isolation and fails under a loaded `make check`, which is the
    most expensive failure mode there is: it gets re-run, passes, and everyone
    concludes it was a fluke. Four tests were repaired for exactly this reason
    on a single day. Use `pumpUntil` from `test/support/pump_until.dart`, which
    alternates short steps of real time with a `pump` and checks whether the
    result is *there*, with an upper bound so a genuinely stuck future still
    fails with a readable message. Line comments are stripped before matching,
    so the helper's own documentation — which spells the anti-pattern out to
    explain it — does not trip the gate.
  - **suppressed SAST findings ratchet** — `// nosemgrep:` comments in `lib/`
    may shrink but never grow (`nosemgrepBaseline`, currently **1**). One
    suppression is a judgement; ten is a habit, and then a green `make sast`
    means nothing. The count lives here rather than in semgrep itself because
    `make sast` needs an external binary and is not part of `make check`, so a
    suppression would otherwise only be visible to whoever happens to have
    semgrep installed. The single entry today is the `chmod` in
    `lib/services/disk_traces.dart`: the rule guards network traffic that
    NetGuard cannot see, and `chmod` is not network-capable.
- **Failure means:** route the diagnostic through `logError`; **or** replace the
  literal colour with an `AppTheme` token (then lower `rawColorBaseline`); **or**
  split the oversized file (then lower its `fileSizeBaseline` entry — the run
  prints a tip), or deliberately raise the entry with a reason; **or** — for an
  oversized class — move real behaviour out (to a service, a separate class or a
  widget) rather than into another `part`, since a `part` split leaves the class
  the same size and this ratchet says so; **or** — if you removed a
  `catch (_)` — lower `catchUnderscoreBaseline` to lock it in.

### `make check-audience-boundary`
- **Runs:** `dart run tool/check_audience_boundary.dart`
- **Covers:** the **privacy projection boundary** (`docs/design/OCIWACHT.md` §6).
  Only `PrivacyProjection` can mint an `AudienceDeck`, so a surface that demands
  that type cannot be handed unredacted text — the compiler refuses it. The open
  question is *which* surfaces must demand it, and until 2026-07-22 that was a
  list of four hard-coded entry points. A fifth output channel was invisible to
  the gate: exactly the fail-open shape §6.0 warns about.
- **How it measures:** the **`analyzer` package's AST**. It flags every
  declaration that takes slide content (`Deck`, `List<Slide>`, `AudienceDeck`,
  `ExportBundle`) **and** reaches an artefact primitive in its own body —
  `FilePicker.saveFile`, `Clipboard.setData`, `toImage`/`toByteData`, or the
  atomic write helpers. Each hit must appear in `_registry` classified as one of
  two kinds, with a written reason:
  - `audience` — hands content to a **recipient**. Must take an `AudienceDeck`
    or `ExportBundle`; a raw `Deck` here is a leak.
  - `source` — writes the **source** back for the user, verbatim. Redacting here
    would be the bug: a `.ocideck` package is the user's project, and §6.0 says
    in so many words that the deck goes to the `.md` one-to-one.
- **Why it classifies rather than decides:** the two kinds look identical to a
  static rule — same parameter, same primitive, opposite requirement. Inverting
  the naive way (suspect every raw `Deck`) yields 208 parameters across 67 files,
  which is noise, not signal. So the gate does not answer the question; it
  refuses to let the question be skipped. A new output channel breaks the build
  until someone writes down which side it is on.
- **Blind spot, stated plainly:** a surface that delegates the write two layers
  down and itself only passes strings is not seen — the analysis is per
  declaration, not across the call graph. The layer that finally touches the
  primitive *is* seen, as long as it still holds the slide content.
- **Failure means:** classify the new channel in `_registry` (kind **and**
  reason); or give the registered audience surface back its `AudienceDeck`; or
  update a registration that went stale when something was renamed.

### `make check-method-length`
- **Runs:** `dart run tool/check_method_length.dart`
- **Covers:** a **per-method/function-length ratchet** — the per-declaration
  sibling of the file-size ratchet. No method, top-level function or constructor
  body may run longer than `maxMethodLines`
  (currently **150**) lines (signature through closing brace, excluding the
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

### `make check-comment-language`
- **Runs:** `dart run tool/check_comment_language.dart` (`--list` prints each
  block with the words that were counted)
- **Covers:** the CONTRIBUTING rule *"Dutch or English, but never both in one
  comment"* — for plain `//` comments. A block that switches language halfway
  does not read; the codebase being bilingual is a choice, finishing one thought
  in two languages is not.
- **How it measures:** comment tokens from the `analyzer` (not lines that look
  like `//`), grouped into blocks — consecutive lines are one thought, a blank
  line or a switch between `///` and `//` starts a new one. Inside a block,
  backticked spans, quoted strings and URLs are dropped, and the rest is counted
  against two vocabularies of function words that exist in one language only.
  Words that exist in both (`in`, `is`, `of`, `over`, `we`, `was`, `die`, `van`,
  `door`) are deliberately absent from both lists: one of those turns every
  English block into a half hit. A block counts as mixed at **two distinct
  markers of each** language — one English word in a Dutch block is nearly
  always a quoted term, not a language switch.
- **Not covered on purpose — dartdoc.** CONTRIBUTING also prescribes that new
  public types in `lib/models/` and `lib/services/` carry *English* dartdoc,
  while the reasoning below it stays in the working language. An English summary
  line above a Dutch paragraph is therefore the prescribed form, not a
  violation, and it is what 37 of the 47 raw hits were on 2026-07-23. A gate
  that fines the contributor guide is a gate that gets switched off.
- **Why this heuristic and not a language classifier.** CONTRIBUTING notes that
  a language heuristic wrong 5% of the time is worse than no gate. That holds
  for *classifying* ("is this block Dutch or English?"), where every block needs
  an answer and every doubt counts. Mixing detection is the other question: it
  stays silent unless there is hard evidence of both, so doubt produces silence
  rather than a false alarm.
- **`mixedCommentBaseline`, and those blocks are not being cleaned up.** CONTRIBUTING forbids
  rewriting existing comments only to change their language — thousands of lines
  of noise with somebody else's reasoning under your name in `git blame`. They
  fall away as those blocks get edited for other reasons. Every one of them was
  hand-checked when the ratchet was set, and every one is real.

### `make check-hardcoded-text`
- **Runs:** `dart run tool/check_hardcoded_text.dart` (`--list` prints the full
  inventory per area, for clean-up batches)
- **Covers:** the first half of the localisation promise — that every visible
  string actually passes through `l10n.d('…')`. `test/app_localizations_test.dart`
  guards the second half (every `d('…')` exists in all 32 languages), but nothing
  guarded that a string reached `d()` at all. The gap sat in the indirect
  hand-offs: `EditorField` calls `l10n.d(widget.label)`, so
  `EditorField(label: 'Titel (H1)')` at the call site is invisible to a scanner
  that only looks for `d('…')`.
- **How it measures:** an AST dataflow, run backwards from two separate seed
  sets — the parameters of `d()`/`t()`, and the raw Flutter sinks that put text
  on screen unchanged (`Text`, `Tooltip`, `Semantics`, `InputDecoration`, …).
  A parameter that is passed on to a known sink becomes a sink itself, which is
  how `EditorField.label` is found without anyone listing it. A literal that
  reaches only the first set is a **source key** (legitimate: it is a `d()`
  argument, one call further along); one that reaches the second is a violation.
  The *type* decides, not the parameter name — `title:` on a `MastgTest` is
  reference data, not interface text.
- **Not covered on purpose:** `_contentHomes` in the tool is the escape list
  for files that carry deck *content* rather than interface text — strings that
  land in the author's saved file and get typed over, where translating them
  would make a document's text depend on the menu language it was created in.
  It listed the `lib/models/deck_template*.dart` builder files until #622 moved
  that content out of Dart entirely, into a Markdown document per language
  under `assets/templates/`; the list is empty now, and the template register
  that remains in `lib/` carries only l10n source strings and falls under the
  gate like everything else. *(Corrected 2026-07-23.)*
- **Failure means:** route the string through `l10n.d('…')` — and remember the
  translation gate then wants it in every language.

### `make check-toolchain`
- **Runs:** `dart run tool/check_toolchain.dart`
- **Covers:** that the Flutter actually executing the gate — version, channel
  and repository — appears in [Toolchains of record](#toolchains-of-record).
  Every green gate is a statement about the toolchain that produced it; if that
  toolchain is not written down, "make check passes" is not reproducible, which
  is what `COMPLIANCE.md` QA.04 promises and what #598 reported.
- **Why it exists:** the drift was not noticed twice. The machine ran `3.44.2`
  from an unofficial channel while three documents named `3.44.6`; that was
  corrected by hand, and within a day it had drifted back. Nothing was looking.
  The defect is not which number runs — it is that the difference could be
  invisible.
- **What it enforces**, each failing on its own: channel `stable`; repository
  `https://github.com/flutter/flutter.git`; and the version *exactly* equal to
  the pin in `.tool-versions`. All three problems are reported in one run —
  whoever has to replace a toolchain wants the whole list, not one line per run.
  On top of that, once the toolchain is correct, it must also appear in
  [Toolchains of record](#toolchains-of-record), so a pin bump cannot leave this
  document behind.
- **And every place that names the version must agree** (#721). Fifteen version
  claims live across seven files — `.tool-versions`, `README.md`,
  `CONTRIBUTING.md`, `BUILD.md`, this file, and both workflows. Raising the pin
  in one and forgetting another is a silent failure: the documentation then
  promises something the machine does not do, which is how #598 started.
- **A bold version is a requirement; a code-quoted one is a quotation.** That
  distinction is what lets these documents keep telling their own history —
  "the machine ran 3.44.2 while three documents named `3.44.6`" must *not* move
  with the pin, or it becomes untrue. The patterns therefore match the claim
  form (`**Flutter X**`, `flutter-version: X`), never a bare number. A pattern
  that stops matching anything fails the gate too: a check that finds nothing is
  green for the wrong reason.
- **Why exactly, and not "3.44.x":** `dart format` reflows whitespace between
  releases. A green `make format-check` on a neighbouring patch release proves
  something about a different formatter than the one CI runs, which is the one
  symptom the pin exists for.
- **Failure means:** fix the machine, not the tool. Install the latest stable
  from the official archive (verify its SHA-256 against `releases_*.json` before
  unpacking) into `~/flutter`, then move every pin with it. If `~/flutter`
  already exists but does not win, check the `PATH` order in `~/.zshrc` — an
  entry added *before* Homebrew's line loses to it, which is precisely how two
  Flutters disagreed here unnoticed for weeks.

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
- **The native face scan is tested separately, not under `make check`.** The image
  privacy check (recognisable faces on slide images) runs on OpenCV through dartcv4
  2.x's native layer, and that layer does **not** load under a bare `flutter test`
  on the Dart VM (its `@Native` code-assets are not built for the test VM). So under
  `make check` those tests assert the contract and skip the native detection,
  reporting `~2`.

  The real native run is `integration_test/native_face_scan_test.dart`, which drives
  the app on a real desktop platform where the native assets load. Locally:
  `flutter test integration_test/native_face_scan_test.dart -d macos` (needs `cmake`
  on your PATH; the Android SDK's cmake works). In CI it runs on all three desktop
  platforms — Linux in the gate via `xvfb`, macOS and Windows in the matrix (#899) —
  and fails loudly if the detector is unavailable, rather than skipping. That is the
  test that caught the broken `objdetect` build in #898.

### `make coverage`
- **Runs:** `flutter test --coverage --test-randomize-ordering-seed random --exclude-tags golden`
  then `dart run tool/coverage_summary.dart --min=80 --require-instrumented`.
- **Covers:** two things. (1) Line coverage across every `lib/` file a test
  imports. (2) That there **is** such a test for every `lib/` file.
- **Failure means:** coverage dropped below the floor (`--min` in the Makefile
  recipe, currently **80%**), **or** a `lib/` file is in no test at all.
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
  files execute less than `perFileFloorPercent` (currently **20%**) of their own
  lines.
- **Failure means:** at least one file sits below that floor. Write a test for
  it, or — only when it is a platform half or has no executable lines — put it
  in `uncoveredBaseline` with a reason.
- **Why it exists:** being in the denominator is not being executed. A test that
  imports a file without ever calling into it keeps that file in the report at
  0%, and an 80% average absorbs it without a ripple — on 2026-07-21 twenty-two
  `lib/` files were in exactly that state, 1.219 lines between them, and they
  passed both gates above. Neither the floor nor `--require-instrumented` can
  see this: one looks at the mean, the other only at whether a file is mentioned
  anywhere.
- **No budget, and no allow-list.** Until 2026-07-22 this gate carried a
  `filesBelowFloorBudget` counting how many files were allowed below the floor:
  39 at the start, then 21, then 0. A number that reads zero is a number
  somebody can raise; a gate that fails on *every* file below the floor is not.
  So the budget is gone: anything that drops below 20% is a test to write, not a
  number to adjust. The only escape is `uncoveredBaseline`, and that is a list
  with a reason per line — reserved for platform halves and files with no
  executable lines at all.

### `make check-no-coverage`
- **Runs:** every static gate that `make check` runs, then `make test` instead
  of `make coverage` + `make coverage-per-file`. The full suite still runs, in
  randomised order; only the instrumentation is gone.
- **Covers:** exactly `make check` minus the two coverage floors.
- **Where it is used:** `.forgejo/workflows/ci.yml`, on a `v*` tag. Nowhere
  else — **do not use it in place of `make check` in your own working copy.**
- **Why it exists:** `flutter test --coverage` keeps a VM-Service connection
  open per test until the run ends, and that is both the slowest phase and the
  one that parallelises worst. Measured on the runner (task 661): 33 min 49 s of
  a 46-minute gate went to that single phase — on four cores of a 2018 Xeon. On
  a developer machine the same difference is small enough not to notice, which
  is exactly why it had to be measured on the runner rather than guessed at
  here.
- **How much it actually saves — less than that 74% suggests.** The suite still
  has to run; only the instrumentation goes. Measured locally: `make test` is
  112 s wall / 595 s CPU against `make coverage` at 147 s / 971 s — −24% wall,
  −39% CPU. On four cores the run is CPU-bound, so the wall saving approaches
  that −39%: an estimated 33 min 49 s → ~21 min, about **13 minutes off a
  46-minute gate**. Real, but not a step change; the machine itself is the
  factor of ten (see [Continuous integration](#continuous-integration)).
- **What it gives up, stated plainly:** the coverage floor and the per-file
  floor are not enforced in CI at all any more. They are unchanged and still
  mandatory — in `make check`, on the committer's machine, before `main`. This
  is a relocation, not a relaxation, and it only holds because the merge gate
  was already local (see the top of this document).

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
  (volatile timestamp/serial fields are normalised out first). The suite also
  fails if a component ends up in no dependency relation at all, or if a
  resolved Dart package carries no supplier — the two gaps that made the
  document look complete while it was not.
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
- **Runs:** `make build-web`, then `dart run tool/check_web_hardening.dart` and
  `dart run tool/pack_web_release.dart --check`.
- **Covers:** two things about the built `build/web`.

  *Hardening* — a strict CSP in `index.html` (`script-src 'self'
  'wasm-unsafe-eval'`, no `unsafe-inline`/`unsafe-eval`, `connect-src 'self'`,
  `object-src 'none'`, `form-action 'none'` — that last one does *not* fall back
  to `default-src`, so it is asserted separately), CanvasKit **self-hosted**
  (local wasm + the `useLocalCanvasKit` flag), and the UI font **bundled** — so
  the running app pulls zero third-party origins.

  *Release artefacts* — that `LICENSE.md`, `THIRD_PARTY_NOTICES.md` and the
  three SBOM files are in the bundle, and that `SHA256SUMS` describes exactly
  the files that are there. It complains about a file that was **added** after
  packing as loudly as about one that changed, which is the case that actually
  bites: a later build step that drops something in would otherwise fall outside
  the list unnoticed.
- **Failure means:** a change weakened the CSP, re-introduced a CDN/font fetch,
  or moved something in the bundle after it was sealed; the scripts list every
  broken invariant. See [`BUILD.md`](BUILD.md) for the hardened build and for
  what the checksum list does and does not prove.
- **Note:** the packing logic itself is tested in
  `test/pack_web_release_test.dart`, which runs in `make check` — so a broken
  checksum list surfaces without waiting for a web build.

### `make deps-outdated` (advisory)
- **Runs:** `flutter pub outdated`
- **Covers:** dependency freshness only. **Advisory** — it may need network
  access and an outdated package is not in itself a regression. Not part of the
  required gate.

### `make sast`
- **Runs:** `semgrep scan --config semgrep/ocideck.yaml --metrics=off --error`
  over `lib/`, `tool/` and `test/`. Needs the `semgrep` binary
  (`brew install semgrep`).
- **What "SAST" means here, precisely.** Three project-specific rules and no
  vendored community ruleset. That is narrower than the label suggests, and the
  narrowness is the point: a community pack for Dart barely exists, and
  `--config auto` would fetch rules over the network at scan time. Read this as
  "three invariants a parser can check", not as "a general static analysis
  sweep" — the general sweep is `flutter analyze --fatal-infos` plus the
  purpose-built gates above. *(Stated 2026-07-22, because the word SAST reads
  wider than the ruleset is.)*
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

### `make shellcheck`
- **Runs:** `shellcheck scripts/*.sh` at the default severity, so nothing is
  filtered out. Needs the `shellcheck` binary (`brew install shellcheck`).
- **Covers:** every committed shell script — today
  [`scripts/build_release.sh`](../scripts/build_release.sh) and
  [`scripts/regenerate_icons.sh`](../scripts/regenerate_icons.sh). Both are
  clean, which is why the gate could be added with no baseline and no
  exemptions.
- **Why it exists.** Dart in this repository passes a compiler, an analyzer at
  `--fatal-infos`, and eight purpose-built gates. Shell passed nothing. That
  asymmetry was fine while there was one script that only a release manager ran
  by hand; it stopped being fine when a second script started producing
  committed artefacts. ShellCheck catches the classics that only bite on the day
  it matters: an unquoted variable that splits on a path with a space, a glob
  that silently matches nothing, an exit code swallowed by a pipe.
- **Failure means:** ShellCheck found a defect, or the binary is missing. Read
  the finding; it links to a wiki page explaining the case.
- **Wired into `check-full`, deliberately not into `check`** — same reason as
  `sast` and `check-secrets`: the everyday gate cannot assume external binaries.
- **Both directions are tested:** zero findings over both scripts, and a genuine
  failure (exit non-zero, SC2086 reported) on a planted unquoted expansion. That
  second half is not a formality. The first plant tried — a variable assigned a
  literal path and then used unquoted — produced *no* finding, because
  ShellCheck tracks the value and knows the expansion is safe. A gate proven only
  against a plant it was never going to catch proves nothing.

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
- **Advisory, not a gate — but part of the pre-tag pass.** It stays out of
  `check`/`check-full`, but [`make check-release`](#make-check-release) runs it
  once, advisory and non-blocking, against the live host — the quality slag you
  run by hand before `git push origin v*`. That timing is the point: a finding
  before the tag can still hold back a release, whereas a scan after deploy only
  speaks once the site is already live. A finding is for a human to weigh and, if
  real, file as an issue (this is how #849 came to be). Without a container
  runtime the step skips itself with a clear message.
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

### `make check-pins` (advisory)
- **Runs:** `dart run tool/check_pinned_versions.dart` (`--offline` validates the
  manifest without hitting the network).
- **Covers:** every third-party CI version pinned to an **exact** value in
  [`.github/pinned-ci-versions.json`](../.github/pinned-ci-versions.json), in two
  kinds that age identically while looking nothing alike in a workflow:
  - **actions** — `uses: owner/repo@vX.Y.Z` (currently `aquasecurity/trivy-action`);
  - **tools** — a scanner binary a `run:` block downloads by version
    (`gitleaks`, `trufflehog`, `semgrep`), pinned since #799/#800.

  It asks each upstream for its latest version and flags anything behind — the
  CI analogue of `make deps-check`. Two sources, because the three scanners do
  not ship the same way: a GitHub release carries `tag_name`, PyPI carries
  `info.version`. Semgrep is read from PyPI and not from its GitHub release,
  because the workflow installs it with `pip`; "latest" has to mean the latest
  version that install path can actually reach. Actions on a floating major tag
  (`@v4`, `@v2`) auto-update and are intentionally not tracked, and Flutter is
  absent because its version already has one source (`.tool-versions`, guarded by
  [`make check-toolchain`](#make-check-toolchain)).
- **Why the scanners belong here** (#802): a pin without a freshness monitor rots
  silently, and for a secret scanner that is not cosmetic. One that stands still
  keeps exiting 0 while missing the credential shapes invented after it — green
  because it did not know what to look for, the same failure mode as a history
  scan on a shallow clone.
- **Advisory** and not part of the gate (it needs network access and a bump is a
  prompt, not a regression). When it reports a newer release, bump the version in
  **every** workflow that carries it *and* in the manifest, in the same commit.
- **That the manifest still matches the workflows is a separate question, and it
  *is* a hard gate.** `test/pinned_versions_manifest_test.dart` runs in the suite,
  offline, and fails on a version that drifted between the manifest and a
  workflow, on the two workflows disagreeing with each other, and — the one that
  matters most — on any `*_VERSION:` pin appearing in `.github/workflows/` or
  `.forgejo/workflows/` that the manifest does not list. Without that last check
  the manifest could go stale by *omission*: add a fourth scanner, forget the
  manifest, and nothing watches it.

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
  - `test/trademark_notices_test.dart` — every brand OciDeck carries as a
    *feature* sits in an enum (`VideoSourceKind`, `WebdavServerKind`), so the
    test holds those enums against the trademark table in
    `THIRD_PARTY_NOTICES.md`: a new embed provider or WebDAV flavour fails here
    before its brand name can reach the interface unattributed. It also requires
    each branded row to disclaim affiliation, because naming only the owner
    leaves the suggestion of a partnership standing.
  - `test/pinned_versions_manifest_test.dart` — the three scanner versions are
    written out in **two** workflow files, so a bump has three places to land and
    two of them are easy to forget. This holds
    [`.github/pinned-ci-versions.json`](../.github/pinned-ci-versions.json)
    against both workflows in every direction, including the one that has no
    author to remember it: any `*_VERSION:` pin in either workflow directory that
    the manifest does not list fails here. A pin nothing monitors ages silently
    (#802), and for a secret scanner that means green because it did not know
    what to look for.
  - `test/explain_suite_failure_test.dart` — the load-failure explanation
    described under [When the gate fails on something that is not your
    change](#when-the-gate-fails-on-something-that-is-not-your-change) hangs off
    **every** `flutter test` line in the `Makefile`, and nothing but this test
    notices a new line that skips it. Its first duty is the opposite of
    reassurance: a file that fails to load because it does not compile must be
    reported as a *real* failure, never filed under the known one — otherwise
    the explanation sends someone away from a genuine bug while the tests in
    that file quietly do not run. It also holds the two wiring properties that
    would fail expensively and in silence: the `||` branch must still `exit 1`
    (or a red suite turns green because printing the explanation succeeded), and
    `clean-test-cache` must not reach past `build/test_cache` (a `rm -rf build`
    takes the compiled native layer that dartcv4's build hooks produced with it,
    forcing a slow OpenCV recompile on the next platform build).

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
  (`test/golden/`). Renders **every one of the 24 slide types** through
  `SlidePreviewWidget` (the
  widget behind the editor preview, presenter, thumbnails and the PDF/PPTX
  raster) with the default flutter-test font, so the PNGs catch layout /
  structure / colour regressions (elements moving, resizing, disappearing, wrong
  theme colours) without depending on glyph rendering. The PNGs are pixel- and
  **platform-specific**, so they are tagged `golden` and **excluded from the
  default suite** — run them on **one** platform. `make test-golden` compares;
  `make test-golden UPDATE=1` accepts an intentional visual change. (To gate them
  once a CI runner exists, add a single-platform job that runs `make test-golden`
  and regenerate the PNGs on that platform.)

  *Corrected 2026-07-22 (#617): this said "each slide type" while the file
  covered **eight** of the 24. Everything built after the first round — chart,
  cockpit, timeline, scorecard, finding, checklist, scopeMatrix, discoveries,
  findingsSummary, question — had no visual regression test at all, so a theme
  change could shift their layout with nothing turning red. The loop is now over
  `SlideType.values`, which also means a new type gets its golden without anyone
  remembering to add one. Two sentences to keep straight: they are still
  excluded from `make check`, deliberately — a pixel comparison in the default
  gate would fail on any machine but this one — and they are still only as good
  as somebody typing `make test-golden`.*

- **`make clean-test-cache`** — deletes `build/test_cache` and nothing else.
  `flutter test` keeps an incremental kernel cache there
  (`build/test_cache/build/<hash>.cache.dill.track.dill`, around 120 MB on this
  project); this removes it, at the cost of one full recompile on the next
  suite run. Reach for it when a `Failed to load` survives a re-run — see
  [below](#when-the-gate-fails-on-something-that-is-not-your-change).
  Deliberately *not* `flutter clean`: `build/` also holds the compiled native layer
  (dartcv4/OpenCV, built through the native-assets hooks), and a clean forces a slow
  recompile on the next platform build.

---

## When the gate fails on something that is not your change

### `Failed to load "…_test.dart"` followed by a type-cast error

**The signature** (#798) — the named test file differs from run to run:

```
Failed to load "test/<varies>_test.dart":
type '_Map<String, dynamic>' is not a subtype of type 'List<dynamic>' in type cast
```

This is a failure to **load** a test file, not a failure inside it: the tests in
that file never ran, and they are not in the pass count either. The tell is that
the named test is green when you run it on its own.

**What to do:** re-run. If it comes back, `make clean-test-cache && make check`
— and then read the last paragraph of this section, because a persistent one
would be new information.

**Where it actually comes from.** The throwing line is known:

```
stream_channel/lib/src/multi_channel.dart:143
    _inner!.stream.cast<List>().listen(...)
```

`MultiChannel` multiplexes several logical channels over one connection, so
every frame on that connection has to be a `[id, payload]` **list**. A bare
`List` in a cast is `List<dynamic>` to the VM — which is why the message reads
exactly like that, and why the stack is
`CastStreamSubscription._onData` with nothing but `dart:async` frames above it.
So a JSON **object** arrived on a wire that only carries frames. In `flutter
test` that wire is the one between the tool and the test process
(`_pipeHarnessToRemote`, `packages/flutter_tools/lib/src/test/flutter_platform.dart`),
which is JSON over a WebSocket.

**So it has nothing to do with a damaged kernel cache.** That was the first
suspect and it is wrong — see the ruled-out table below. What the two 2026-07-24
incidents and the one reproduced while writing this have in common is *load*:
all three were in the `coverage` phase, the heaviest and most concurrent one,
and the reproduction happened while a second `flutter test` was running on the
same machine. Three occurrences is not a sample either, so that is where the
knowledge currently stops: the failing line is certain, the trigger is not.

Clearing the cache "fixing" it is consistent with this — a full recompile
changes the timing of the whole run — but so is simply running again.

**What is known about the cache itself**, since it was the first suspect and
someone will suspect it again: `flutter test` writes it, nothing in this
repository configures it, and its filename is a hash of **only** the
dart-defines and the extra front-end options
(`getDefaultCachedKernelPath`, `packages/flutter_tools/lib/src/bundle.dart`).
The Flutter version and the package resolution are *not* part of it, so the same
cache file is reused across an SDK upgrade or a dependency change. Worth knowing;
not the cause here.

**What was ruled out.** Three ways of damaging the cache were tried against a
real run of this suite, and `flutter test` shrugged off all three — it fell back
to a full compile and passed:

| Damage | Result |
| --- | --- |
| Truncated to half its length | green |
| ~2,800 bytes flipped mid-file | green |
| Replaced by a valid dill compiled from a different source tree | green |

So the naive reading — "the file got corrupted" — does not hold. Whatever this
is, it is not a broken cache file that the compiler chokes on. Nobody needs to
repeat these three experiments.

**If it happens again, keep the evidence.** The *trigger* is not diagnosed, and
a re-run destroys the state it happened in. Three things, none of which takes a
minute:

1. `cp build/test-report.json /tmp/report-<datum>.json` — the machine-readable
   report of the failed run, which names the file and carries the stack;
2. the full terminal output, not the tail — the suite position and the
   surrounding test names are the load signal;
3. what else was running. The one thread across all three known occurrences is a
   busy machine, so `uptime` and whether a second `flutter test` was going are
   worth more here than anything about the tree.

**Upstream.** Two relevant reports, neither of them this bug:

- [flutter/flutter#49351](https://github.com/flutter/flutter/issues/49351) —
  the same error *shape* (`'…' is not a subtype of type 'List<dynamic>' in type
  cast`), also blamed on a carried-over `.dill.track.dill`. Closed in 2020: the
  cause turned out to be a **package version difference** between two
  environments, not a cache defect. Worth knowing because the cache was the red
  herring there too.
- [flutter/flutter#128563](https://github.com/flutter/flutter/issues/128563) —
  **open**. `flutter test`'s sibling cache under `build/` is not invalidated when
  Flutter changes the format it holds, and the report's own conclusion is that
  the only remedy is to clear it and that it is not obvious that this is what is
  needed. Different cache, same complaint as this section.

**You should not have to remember any of this.** Every `flutter test` in the
`Makefile` carries two things: `$(SUITE_REPORT)`, which writes a machine-readable
report to `build/test-report.json` **alongside** the normal terminal output, and
`$(ON_SUITE_FAILURE)`, which on a red suite runs
[`tool/explain_suite_failure.dart`](../tool/explain_suite_failure.dart) over that
report. It names the files that failed to *load*, and says whether that is the
known channel failure above or a genuine one.

Three properties, in the order they matter:

- **It cannot hide a real problem.** A file that does not compile is also a load
  failure, and it is reported as a real one — with the sentence that otherwise
  goes missing, that the tests in it did not run and are not in the count.
  `test/explain_suite_failure_test.dart` asserts exactly that, for a missing
  `main`, a compilation failure, and an unrelated type-cast error.
- **It cannot swallow the result.** It reads a side channel; the terminal output
  streams past untouched and the exit code is still the suite's.
- **It stays quiet.** No load failure, no output — an ordinary red test gets no
  extra paragraph.

Why a report rather than filtering the output: piping `flutter test` costs it the
single updating progress line and turns a run into thousands of lines. The gate
would be worse to watch in exchange for a message you see twice a year.

`test/explain_suite_failure_test.dart` also holds the wiring: a new `flutter
test` line that skips either variable fails, and so does a `clean-test-cache`
that reaches beyond `build/test_cache`.

---

## Continuous integration

> **A runner exists since 2026-07-23, and since #751 it runs the gate.** The
> Forgejo server has a registered Actions runner (docker-in-docker, on the
> same machine that serves the repository). What it executes comes from
> `.forgejo/workflows/` — Forgejo reads the first workflow directory that
> exists, so that directory shadows `.github/workflows/`, whose files remain
> reference definitions for a GitHub mirror — with one exception: since
> 2026-07-24 `.github/workflows/release.yml` really runs there, because it
> builds the Windows artifact the forge has no machine for. Most of
> `make check-full` (the dependency/web checks) still runs only locally; run it
> before a dependency or web-facing change. Its two *security* scans are the
> exception since #778 —
> see [`scans.yml`](#forgejoworkflowsscansyml--secrets-and-sast-per-pull-request).
> Since #797 the release gate runs on a registered **Mac**
> runner rather than on the server, and the Linux gate moved to an on-demand
> workflow — see below for what that buys and what it costs. The sections below
> describe the workflows that run, then what the remaining GitHub file *declares*.

### `.forgejo/workflows/ci.yml` — the release gate, on a `v*` tag
- **gate** — runs on the registered **Mac** runner (`runs-on: macos`, host
  mode) since #797: `flutter pub get`, then
  [`make check-no-coverage`](#make-check-no-coverage). Host mode means the job
  uses the machine's own pinned toolchain, so nothing is installed and nothing
  is cached here; `check-toolchain` still runs inside the gate and still demands
  channel `stable`, official provenance and equality with the pin — "it is my
  own machine" is not a check.
- **Why the Mac.** Measured (#796): the same gate took 46 minutes in a container
  on the server against 2.5 minutes on the Mac. That factor is the machine, not
  the steps — four physical cores of a 2018 Xeon D-2123IT, 3.8× slower per core
  than an M5 Max. The toolchain cache, dropping coverage and lowering runner
  capacity each took minutes off; this takes off an order of magnitude.
- **What it costs, twice over.** First: the suite no longer runs on Linux
  anywhere by default — and that is a real gap, because `git` 2.43 on Ubuntu
  24.04 does not know `--end-of-options`, and no Mac will ever surface that. The
  Linux gate is not deleted but moved to `linux-gate.yml`, on demand. Second:
  the release gate now depends on one physical machine owned by one person. When
  that Mac is off the run waits — the tag still lands, the gate arrives later.
  Better than a gate nobody waits for, but this is not a server-class
  arrangement and should not be read as one.

### `.forgejo/workflows/scans.yml` — secrets and SAST, per pull request
- **scans** — a bare `ubuntu:24.04` container that installs three pinned
  scanners and then runs [`make check-secrets`](#make-check-secrets) (gitleaks +
  trufflehog, working tree *and* full history) and [`make sast`](#make-sast)
  (semgrep, local rules only). The commands are the Makefile targets, not
  re-typed copies of what they do — a contributor's local run and CI are then
  the same run by construction.
- **Why it is its own workflow rather than a second job in `ci.yml`.** `on:` is
  per workflow, and `ci.yml` fires on a `v*` tag. A job there would first scan
  once the secret was already on `main` with a tag around it.
- **Why it may run per pull request when the gate no longer does.** The reason
  for #790 was the clock — 22 minutes per pull request against a `make check`
  that already ran before every push. These two take 17 and 2 seconds locally,
  so that argument does not reach them, and for a secret the moment is not
  interchangeable.
- **What it actually costs in CI: about three minutes**, measured on the first
  runs (#778). Read that against the 19 seconds above and the difference is the
  point — nearly all of it is *installing* the scanners into a bare image, not
  scanning. The obvious lever would be to cache the two binaries and the semgrep
  venv on the pinned versions, the way `linux-gate.yml` caches the toolchain.
  **That is deliberately not done, and the reason first recorded here — "three
  minutes does not yet justify the staleness" — was the weaker one.** The real
  objection is specific to this job: a cache restore would replace a
  sha256-verified download *of a security scanner* with an artifact written by
  an earlier run. `linux-gate.yml` accepts that trade for the toolchain because
  `check-toolchain` re-checks the restored tree; there is no equivalent re-check
  for a restored scanner binary, so caching here would quietly spend the very
  property #778 was after — that green means the same thing over time.
- **What does get fixed is the network, not the clock.** Three downloads on
  every pull request is three chances per run at a failure that has
  nothing to do with this repository, and on 2026-07-24 that happened twice in
  one afternoon: `curl: (22) … error: 504`, half a second after checkout, with
  `make check-secrets` and `make sast` green locally on the same commit. The
  downloads therefore retry on 5xx with a backoff, and a superseded run cancels
  instead of reporting failure. Both exist for one reason: a red tick on a
  security gate that is not a finding teaches you to ignore the next one.
- **Why on the Linux runner rather than the Mac.** The Mac has all three
  scanners installed already, so nothing would need downloading. But since #797
  that Mac is both the release gate and the committer's own working machine, and
  this is the one workflow that fires on every pull request — it would
  take cores from the machine currently running `make check`. The server has
  been idle since that same move.
- **Two things here are load-bearing and easy to lose.** It checks out with
  `fetch-depth: 0`: `actions/checkout` clones one commit deep by default, and
  both history passes then look at almost nothing and report green. Measured
  rather than asserted — on a repository where a secret was committed and later
  deleted, the full clone exits 1 (gitleaks) and 183 (trufflehog) while the
  shallow clone of that same repository exits 0 twice. And the three scanners
  are pinned in the workflow's `env` block with the download sha256-verified
  against the published manifest, because a scanner that updates itself quietly
  changes what green means. The `test -n "$SHA"` in that verification earns its
  line, though not for the reason first given here (#800): the claim that
  `grep … | sha256sum -c -` passes *silently* on an empty match does not hold on
  GNU coreutils — measured on 9.5, and the image runs 9.4 off the same codebase.
  An empty match ends in "no properly formatted checksum lines found" and exit 1.
  What the line buys is a readable failure: without it, a renamed release asset
  surfaces as a complaint about `sha256sum`'s *input*, and the reader debugs the
  verification instead of the asset name.
- **Counter-tested, because a scan job that sees nothing looks exactly like a
  clean repository.** With a randomly generated AWS-shaped key pair planted in
  the working tree, `make check-secrets` exits non-zero and names the leak; with
  the same pair only in history and the working tree clean, both history passes
  still fail.

### `.forgejo/workflows/linux-gate.yml` — on demand (`workflow_dispatch`)
- **gate-linux** — the gate that `ci.yml` used to be: a bare `ubuntu:24.04`
  container in which the workflow installs the **official** Flutter stable
  release: the version is *read from `.tool-versions`* (so a pin bump has no
  second place to forget) and the tarball is sha256-verified against the
  official release manifest, with `actions/cache` over `/opt/flutter` and
  `~/.pub-cache`. Then `flutter pub get` and `make check-no-coverage`. A
  prebuilt third-party Flutter image was rejected here: the cirruslabs image
  shipped channel `[user-branch]` from an unknown source, exactly what
  `check-toolchain` exists to catch.
- **When to press it:** before a release, and whenever a change touches paths,
  subprocesses or `git` invocations. Nobody presses it automatically — that is
  the deliberate trade for the release gate being fast, not an oversight.

### `.forgejo/workflows/linux-build.yml` — on demand (`workflow_dispatch`)
- **build-linux** — same official pinned toolchain as the gate, plus the GTK
  build dependencies; `flutter build linux --release`, and uploads the bundle
  as the `ocideck-linux-x64` run artifact. This is a build, not a gate: it
  proves the Linux target compiles and packages, nothing more — which is why
  it stopped running on every push to `main` (#790). It cost 17.5 minutes of
  runner time per merge, and `release.yml` on the GitHub mirror already builds
  Linux, macOS and Windows on every `v*` tag. Start it by hand when you want a
  bundle without cutting a tag.

### `.forgejo/workflows/macos-build.yml` — on demand (`workflow_dispatch`)
- **build-macos** — runs on a registered **Mac** runner (`runs-on: macos`,
  host mode), not on the server: Apple licenses macOS for Apple hardware only,
  so there is no macOS job the Linux server could legitimately run. The job
  uses the Mac's own pinned toolchain (the one `check-toolchain` already
  guards), builds `flutter build macos --release`, and uploads the `.app`
  (zipped with `ditto`, which preserves what a plain zip destroys) as the
  `ocideck-macos` run artifact. On demand for the same reason as the Linux
  build (#790). When no Mac runner is online the run waits.

### `.forgejo/workflows/release.yml` — on a version tag (`v*`)
One tag, one release. Not a gate: everything here assumes `make check` was
already green on `main`.

| Job | Runner | Result |
| --- | --- | --- |
| `web` | docker | `make check-web` — hardened bundle **and** its verification |
| `deploy-web` | docker | that same artifact live on the static host, via `scripts/deploy_web.sh` |
| `linux` | docker | `ocideck-linux-x64-<versie>.tar.gz` |
| `macos` | macos | `ocideck-macos-<versie>.zip` (`ditto`, not a plain zip) |
| `windows-ophalen` | docker | waits for the mirror's public release asset and `curl`s it |
| `publiceren` | docker | a Forgejo release with all four, both SBOM formats and `SHA256SUMS` |

`deploy-web` unpacks the *downloaded artifact* rather than rebuilding: what goes
live is then byte-identical to what hangs off the release. It needs the
`DEPLOY_SSH_KEY` and `DEPLOY_KNOWN_HOSTS` secrets ([HOSTING.md](HOSTING.md#automatic-deployment-on-a-tag));
without them that job fails and the release still publishes.

Publishing needs no secret: Forgejo injects a per-run token that may create
releases. A `RELEASE_TOKEN` secret overrides it if that ever changes.

### `.github/workflows/release.yml` — the Windows lane, on a version tag (`v*`)
The only file on the mirror that executes. Builds `flutter build windows
--release` on `windows-2022` (the newest image's MSVC is incompatible with
dartcv4's prebuilt OpenCV pack) and publishes it as a **public GitHub release
asset** — not a build artifact, which would need a token even on a public
repository and would expire after ninety days. The forge picks that URL up with
plain `curl`, so no GitHub credential is stored on the self-hosted runner.

### `.github/workflows/ci.yml` — declared on a version tag (`v*`)
- **On a `v*` tag, or `workflow_dispatch`** (#958) — until 2026-07-29 this
  declared `push: branches: ["**"]` plus `pull_request:`, so the full
  seven-job pipeline below fired on every commit to every branch and every
  pull request on the mirror, regardless of what changed. That made the
  mirror a **second failure-mail source** for work the forge already did: the
  real merge gate is `make check` on the committer's own machine, and
  [`.forgejo/workflows/scans.yml`](#forgejoworkflowsscansyml--secrets-and-sast-per-pull-request)
  already runs `check-secrets`/`sast` on every pull request there. Per PR, this
  mirror added load without adding signal. Brought in line with
  [`.forgejo/workflows/ci.yml`](#forgejoworkflowsciyml--the-release-gate-on-a-v-tag)
  (#790): CI is a release gate, not a merge gate. `workflow_dispatch` stays, so
  a branch can still go through the full pipeline by hand without cutting a
  tag.
- **Gate (Linux)** — `runs-on: ubuntu-latest`: `flutter pub get
  --enforce-lockfile`, then `make format-check`, `make analyze`,
  `make check-conventions`, `make check-audience-boundary`,
  `make check-method-length`, `make check-dead-code`,
  [`make check-secrets`](#make-check-secrets), [`make sast`](#make-sast),
  `make coverage` (with the line-coverage floor), `make licenses`,
  `make sbom-verify`, and `make deps-check`. Uploads the coverage report.
- **The three scanners are pinned, and the checkout is deep** (#800). Until
  2026-07-24 this job installed gitleaks and trufflehog by piping an install
  script fetched from a *branch tip* into `sh`, and semgrep with no version at
  all — unverified code from a moving pointer, setting up tools that silently
  redefined what green meant. They now come from a pinned release, sha256-checked
  against the published manifest, in the same shape the Flutter tarball already
  used in [`linux-gate.yml`](#forgejoworkflowslinux-gateyml--on-demand-workflow_dispatch)
  — `test -n "$SHA"` included, so a renamed release asset fails loudly instead of
  turning the check into a complaint about `sha256sum`'s input. The checkout also
  gained `fetch-depth: 0`: two of the four passes in `make check-secrets` read
  *history*, and a one-commit clone lets them report green on almost nothing.
  Both were already right in
  [`scans.yml`](#forgejoworkflowsscansyml--secrets-and-sast-per-pull-request)
  (#799); only this mirror definition lagged.
- **Test matrix (macOS + Windows)** — runs `flutter test
  --test-randomize-ordering-seed random` on the other two desktop OSes to catch
  platform-specific (path, `Platform.isX`) regressions the Linux gate would miss.
  `make` is not reliably present on the Windows runner, so this job calls Flutter
  directly.
- **Web hardening (Linux)** — `make check-web`: builds the web bundle and asserts
  its hardening invariants, plus that the release artefacts travel with it and
  `SHA256SUMS` still matches.
- **Docs links (Linux)** — `lychee --offline` validates internal Markdown links
  across the repo (external URLs are skipped so it can't flake).
- **Supply-chain (Linux, advisory)** — the [`trivy-action`](https://github.com/aquasecurity/trivy-action)
  runs the same `make trivy` scan (Dart-dep CVEs + committed secrets) with
  `exit-code: 0`, so it surfaces findings without blocking merges.

CI does **not** build native binaries here; it validates formatting, analysis,
tests, and the web bundle's hardening, which are platform-independent.

See [`BUILD.md`](BUILD.md) for the matching local `make build-*` targets, and
[Cutting a release](BUILD.md#cutting-a-release) for the whole tag sequence.

---

## Version pin

CI pins **Flutter 3.44.8 (stable)**, recorded in `.tool-versions` (asdf) and in
both `.github/workflows/*.yml`. The pin matters mainly for **`dart format`**: its
line-wrapping output changes between releases, so an unpinned local toolchain — or
a separately installed standalone Dart used instead of the Flutter-bundled one —
can disagree with CI on formatting. Keep your local Flutter on the pinned version
and use its bundled `dart` (or bump the pin in `.tool-versions` + both workflows
and reformat the tree in one mechanical commit).

### Toolchains of record

A green gate is a statement about the toolchain that produced it. If that
toolchain is not written down, "make check passes" is not reproducible — which
is what [#598](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/598)
reported and what `COMPLIANCE.md` QA.04 promises. So every toolchain the gate
actually runs on is listed here, deviations included.

| Where | `flutter --version` | Against the pin |
| --- | --- | --- |
| Maintainer machine (macOS arm64) | `3.44.8 • stable • https://github.com/flutter/flutter.git` | matches |
| CI (GitHub Actions, all jobs) | `3.44.8 • stable • https://github.com/flutter/flutter.git` | matches |

**The maintainer machine is the one that matters**, because there is no CI
runner: it is the only place the gate has ever run.

**Resolved 2026-07-23 (#598).** Until that day it reported
`3.44.2 • [user-branch] • unknown source`, with binaries under
`/opt/homebrew/Caskroom/flutter/3.29.0/` — a third version number again — while
`.tool-versions`, README, `BUILD.md` and both workflows all named a pinned
release. Every green gate this project rested on was produced by a build from an
unofficial channel that nobody else could reproduce.

It now runs the official stable SDK, installed from the release archive
published by `storage.googleapis.com/flutter_infra_release` and verified against
the SHA-256 in that channel's own release index before unpacking. The Homebrew
cask that used to shadow it is still installed but no longer first on `PATH`:
the line in `~/.zshrc` that adds `~/flutter/bin` now sits last, because a `PATH`
entry added *before* Homebrew's is not a `PATH` entry that wins. That ordering
was the whole reason two Flutters could disagree unnoticed.

**The pin follows the latest stable, not the other way round.** LibreKAT
publishes security tooling, so the toolchain tracks the current stable release
rather than whichever version was pinned first. When a newer stable appears the
pin moves up — `.tool-versions`, `README.md`, `BUILD.md`, `CONTRIBUTING.md` and
both workflows — and the gate is re-run, because `dart format` reflows between
releases and that reflow is the pin's only real symptom.

**`make check-toolchain` keeps this honest.** It fails when the running
toolchain is not in the table above, so the table cannot quietly fall out of
step with reality again — which is exactly what happened twice before it
existed. It deliberately does **not** demand equality with the pin: that would
make the only development machine unable to run the gate at all, and a gate that
blocks everything gets switched off rather than fixed. A deviation is printed
loudly on every run instead.
