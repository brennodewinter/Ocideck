# OciDeck — Checks & CI

> **Status:** procedure, current, with a dated result under *Latest result* · **Status last reviewed:** 2026-08-30 · **Published by:** Stichting LibreKAT

Every automated check OciDeck runs, what it covers, what a failure means, and how
to fix it. The **`Makefile` is the single entry point** and the **real gate**:
`make check`, run by the committer before pushing, is what actually enforces
these checks. The Forgejo remote has an Actions runner since 2026-07-23, and
`.forgejo/workflows/ci.yml` runs [`make check-no-coverage`](#make-check-no-coverage)
**on a `v*` tag, on the Mac runner** — not per pull request
(#741/#751/#790/#797). That is `make check`
with the full test suite intact but without the coverage instrumentation —
worth roughly 13 minutes off a 46-minute gate on that runner. Since #1118 the
**static gates** — `$(STATIC_GATES)`, seconds each — run on **every pull
request** (`.forgejo/workflows/static-gate.yml`, [`make check-static`](#make-check-static)),
and since #1123 that same per-PR job also runs `make check-registrations` — the
fast registration/invariant tests (`SOURCE_MAP`, docs, SBOM, l10n, and the
Windows installer) that are *tests* and so escaped the static subset. **Since #1123 that `static-gate` check
is a required status check** (branch protection on `main`): a PR does not merge
until it passes, via the web UI or the REST/`tea` merge API. That is the
prevention layer — drift is stopped at the PR instead of landing. Two things it
still does **not** hard-block, on purpose: the **coverage floors** and the
**full test suite**. The full test suite runs **once a night on the tip of
`main`** — `linux-gate.yml`, `make check-no-coverage` — as a detection smoke
alarm: a Linux-specific or load-sensitive test (path separators, subprocess
timeouts, I/O races) can be green on the fast maintainer Mac and red only on
the Linux runner. It is **detection, not prevention**: the merge is not
blocked, and a red night points at a handful of commits rather than at one
merge.

That trigger has moved twice, both times because this gate is the most
expensive tenant of the slowest runner. #1123 also ran it per PR; that doubled
the suite per change and was reverted. What remained was one full run per merge,
and measured over 24 days that did not earn its keep either — see
[`linux-gate.yml`](#forgejoworkflowslinux-gateyml--nightly-schedule-and-on-demand-workflow_dispatch)
for the numbers and what was given up. The per-PR prevention layer is
`static-gate`, the required check, which also runs on `push` to `main` and
catches merge drift within minutes on the capacity-4 lane.

The heavy gate is **serialized**: it runs on a dedicated **`linux-serial` runner
with capacity 1**, so a manual dispatch and the nightly run never run at once,
while `static-gate`/`scans` keep the capacity-4 lane. The coverage floors still
run nowhere but in `make check` on your own machine. So: the per-PR static gate
blocks, the nightly run alarms, the tag is the release gate, and you are still
the coverage gate.

> **Escape hatch.** If the runner is down or saturated and a green PR cannot
> merge because its required `static-gate` check never ran, a repo admin removes
> or edits the branch-protection rule (Settings → Branches, or the
> `branch_protections` API) — the rule is server state, not in a commit, so
> lifting it is immediate and reversible.

**Three workflows run per pull request, each for its own deliberate
reason** — two unconditionally, one only when the change can reach the web
bundle. The oldest is `.forgejo/workflows/scans.yml`, which runs the
secret and SAST scans (`make check-secrets`, `make sast`) on **every pull
request** (#778). Those take 17 and 2 seconds locally against the 22 minutes per
pull request that moved the gate to a tag, so the timing argument that moved the
gate to a tag does not reach them — and for a secret the moment is not
interchangeable. Found before the merge it is an edit; found after, it is in the
history and revoking is the only real remedy. It scanned pushes to `main` as
well until the redundant post-merge run — re-reading the same full history the
pull request had just cleared — proved to be the one real source of failure
mail; that trigger was dropped. The third is
`.forgejo/workflows/web-gate.yml` (#1888-tail), which *builds* the web bundle
and runs [`make check-web`](#make-check-web) on it — but only on a pull request
that touches something able to break it. It is the one per-PR workflow with a
**path filter**, and therefore deliberately **not** a required check: a required
context that stays silent on an unrelated PR would leave that PR pending
forever. See
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

> **Running the gate in more than one worktree at once? It queues.** Since
> 2026-08-17 `make check` and `make check-full` run under a gate lock
> (`scripts/gate_lock.sh`): a second run waits for the first instead of
> starting alongside it. It prints which worktree holds the lock and for how
> long.
>
> **Why.** Every worktree of this repo points `.dart_tool/hooks_runner/shared`
> at the same directory, so a fresh worktree does not have to rebuild the
> native OpenCV layer — and cannot, while GitHub answers the archive download
> with an HTTP 429. The price of sharing is that concurrent runs also share one
> native-assets lock and one CMake build directory. Run four at once and you
> get CMake refusing (*"The current CMakeCache.txt directory … is different
> than the directory … where CMakeCache.txt was created"*), a full OpenCV
> rebuild, and then other runs dying on *"Could not acquire the lock …
> TimeoutException after 0:05:00"*. `make check` then fails on a **random**
> gate — dead-code, method-length, coverage — with nothing wrong in the change.
> A gate that points at the wrong place is worse than a slow one.
>
> **The CMake stamp.** An earlier version of this note claimed a worktree
> switch merely re-stamps the CMake cache — "slow but correct". That was
> wrong. Each worktree names the same physical build directory by a different
> path (through the `shared` symlink), and CMake refuses outright: *"The
> current CMakeCache.txt directory … is different than the directory … where
> CMakeCache.txt was created"*. Serialising made it **predictable** rather than
> occasional — every run stamps its own path, so the next one fails for
> certain. The lock therefore clears a cache stamped by another worktree while
> it holds the lock, so nobody is interrupted mid-build. Only `CMakeCache.txt`
> and `CMakeFiles/` go; `_deps` stays, so there is no re-download (GitHub would
> answer it with a 429 anyway). A rebuild after a switch is still slow — that
> part was true.
>
> **The brake.** Left alone, CMake builds with one job per core and
> `flutter test` starts one worker per core. On a laptop that drew more power
> than the adapter could supply: the battery ran down while plugged in. The
> lock therefore sets `CMAKE_BUILD_PARALLEL_LEVEL` to four below the core
> count, and the suite targets pass `--concurrency=$(TEST_JOBS)` with the same
> default. Both are overridable — `make test TEST_JOBS=18` on a machine that is
> doing nothing else, or your own `CMAKE_BUILD_PARALLEL_LEVEL`. Deliberately
> *not* `nice`: priority redistributes CPU time, it does not lower power draw.
>
> **Writing the output to a file? Make the name unique.** Three separate gate
> runs in this repo have written to the same `check1.log` in a shared scratch
> directory and read each other's results — one nearly reported another
> worktree's green as its own, another nearly "fixed" a failure from a
> different branch. Put the worktree name or `$$` in the filename.
>
> **What it still does not fix.** A worktree switch rebuilds OpenCV. To avoid
> that, give a worktree its own `.dart_tool/hooks_runner` (roughly 2 GB, and it
> needs the download to work) instead of the shared symlink — the lock notices:
> with a real directory instead of a symlink, the scope is that worktree alone
> and nobody waits.
>
> **Escape hatches.** `OCIDECK_NO_GATE_LOCK=1` skips the lock (a CI runner has
> one worktree, so there is nothing to queue for);
> `OCIDECK_GATE_LOCK_TIMEOUT=<seconds>` bounds the wait (default 5400, and it
> exits 75 with the path of the lock to remove if you are sure it is stale). A
> lock whose holder process is gone is released automatically — an aborted run
> does not block the machine.

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
something that reddens the command. If `colima` is installed but stopped, this
starts it rather than requiring a separate step before every tag (it's
idempotent — a no-op if already running); only if no container runtime is
reachable even after that does the DAST step skip itself. Two more things
belong in the same pre-tag ritual but are **not** automated here — run
[`make linux-gate`](#continuous-integration) and glance at open
`security`/`privacy` issues on the tracker before you tag.

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

### `make check-l10n-orphans`
- **Runs:** `dart run tool/check_l10n_orphans.dart` (`--list` prints every
  finding with its line in `lib/l10n/translations/en.dart`)
- **Covers:** the *other* direction of the translation promise. `l10n-check` and
  `app_localizations_test.dart` guard that every key in use exists in all 32
  languages; nothing asked whether a key is still looked up at all. Each orphan
  costs 32 lines of upkeep for text no one ever sees.
- **How it measures:** the keys come from the three maps in
  `lib/l10n/translations/en.dart`, read via the AST. A key counts as *in use*
  when it appears either as a Dart string literal (AST again, so adjacent
  literals split across lines and escaped quotes count) or as literal text
  anywhere in `lib/`, `test/`, `tool/`, `assets/` or `web/`. That second rule is
  what catches the third lookup route: `AppLocalizations.sourceFor(lang,
  labelNl)`, used by the improvement module for labels that live in
  `assets/improvement/templates/` and in the baked
  `improvement_templates_floor.g.dart` — "Bedreigingen" is in no Dart literal
  and is very much in use.
- **Not evidence on purpose:** `docs/`, the README and the CHANGELOG (prose
  *describes* the app, it does not look a key up — two of the three
  hand-confirmed orphans are quoted in the CHANGELOG); `tool/*_l10n_spec.json`
  (the *input* to `make add-l10n`, which created the key); the translation
  tables themselves; and the gate's own two files, which name keys in comments
  and expectations.
- **Deliberately silent about:** a key that happens to occur as a *substring* of
  another string ("treffer(s)" inside "meer treffer(s)"). The textual rule is
  coarse on purpose — this gate may miss an orphan, but it must never send
  someone hunting for a key that is actually in use.
- **Why `check-full` and not `check`:** the evidence is textual, not a type
  check — the gate knows a key occurs somewhere, not that it is executed. A
  judgement like that does not belong in the gate that stops every commit, where
  a false finding costs everyone time over something that is not a defect (an
  unused key breaks nothing; it only dilutes upkeep). The part that *does* touch
  every commit is the ratchet: `orphanBaseline` may fall, never rise, so a key
  added and never called fails the check.
- **Failure means:** a key was added that nothing calls — call it or leave it
  out. If it *is* used along a route the gate cannot see, widen `useRoots` /
  `textExtensions` in `tool/check_l10n_orphans.dart`; do not raise the baseline.

### `make check-l10n-parity`
- **Runs:** `dart run tool/check_l10n_table_parity.dart` (`--list` prints every
  gap with the languages that miss the key and the ones that carry it)
- **Covers:** the only translation gate that compares the tables *with each
  other* instead of against usage in `lib/`. Every key present in one language
  must exist in all of them, whether or not anything looks it up right now.
- **Why it was needed:** `l10n-check` and `app_localizations_test.dart` reason
  from `d('…')` literals found in `lib/`, and `check-l10n-orphans` asks whether a
  key is still fetched. A key that sits in the tables but is momentarily looked
  up nowhere slips through both, and may then exist in one language and be
  absent in another with nothing complaining. That is exactly what #1520 turned
  up: six languages (de, es, fr, fy, it, pap) had been missing four source keys
  for a while and nobody noticed.
- **How it measures:** the keys of the three top-level maps per language file,
  read via the AST. They form **two** families, not three:
  `_strings<Lang>` (the `t()` table) on one side, and `_dutchSource<Lang>` plus
  `_dutchSourceAdd<Lang>` on the other — those two are one namespace, because
  `make add-l10n` writes into the additions overlay while `d()` reads from both,
  and where the cut between them falls differs per language purely by history
  (most sit at 1266/2014, de/es/fr/it at 501/2777, tr at 1949/1331). Comparing
  them separately would report over a thousand meaningless differences per
  language.
- **The `nl` exception:** Dutch is the source language. `d('Opslaan')` returns
  `'Opslaan'` for `nl` without consulting a table, so `nl.dart` carries no
  Dutch-source tables at all and is left out of that family. It does take part in
  the `_strings*` family, where `t()` genuinely needs a Dutch value.
- **Why `check` and not `check-full`,** unlike its sibling
  `check-l10n-orphans`: this is an exact set comparison, not a textual
  heuristic. There is nothing to interpret, so no false finding is possible and
  no baseline is needed — zero is the only state. It reads 32 files and is done
  in a second, which is affordable in the gate that stops every commit.
- **Failure means:** a language drifted out of line. Fill the gap with the
  translation from a language that does have the key, or remove the key
  everywhere if it is a leftover — if it still sits in only one language, that is
  the likelier reading.

### `make check-l10n-passthrough`
- **Runs:** `dart run tool/check_l10n_dutch_passthrough.dart` (`--list` groups
  every finding by key, `--by-lang` counts them per language)
- **Covers:** the *third* direction. `l10n-check` asks whether a value is
  present, `check-l10n-parity` whether the key exists everywhere, and
  `test/l10n_untranslated_test.dart` whether that value is not simply the
  **English** sentence. Nothing asked whether it is the **Dutch source**. #1524
  found 44 such keys in `tlh.dart` alone — including a whole LibrePlan-connector
  block of full sentences — and that same block sits untranslated in thirty
  languages.
- **How it measures:** two families, read via the AST. In the `d()` tables
  (`_dutchSource*` plus `_dutchSourceAdd*`) the key *is* the Dutch source, so a
  pass-through is `key == value`. In the `t()` table (`_strings*`) the key is a
  name, so the source comes from `_stringsNl` and a pass-through is
  `value == _stringsNl[key]`. `nl` itself never counts: there the value *is* the
  source.
- **Only from three words up:** exactly the trade-off in
  `test/l10n_untranslated_test.dart`, for the same reason. Single words are
  identical wholesale without anything being wrong — `Logo`, `Audio`, `Mermaid`,
  `Gantt`, `OK`. Without the threshold the gate finds 1,800 and is wrong about
  most of them; that is not a gate but noise, and noise gets clicked away. The
  price is stated plainly: an untranslated source string of one or two words
  slips through.
- **Exceptions go per key, never per language:** see `loanKeys`. The criterion
  is strict — the Dutch source sentence contains no translatable Dutch word at
  all: a proper name, a fixed technical term, a formatting placeholder, or an
  English phrase Dutch itself borrowed untranslated (`Access key ID`,
  `Sprint review / demo`, `P {pitch}  B {bank}`). Only then is equality evidence
  that the translator picked the right term rather than evidence that he did
  nothing. An exception phrased per language ("tlh may have this") says something
  about the translator and covers up the next mistake in that same language; an
  exception per key says something about the *source sentence*, and that stays
  true. What that costs is stated too: a key listed there is silent for every
  language, including ones in another script that would transliterate it.
- **Why `check-full` and not `check`,** like its sibling `check-l10n-orphans`
  and unlike `check-l10n-parity`: the judgement is a textual heuristic, and at
  introduction it finds 394 — a gate that is red on arrival cannot go into
  `check` without a baseline. So: a `passthroughBaseline` ratchet that may fall
  and never rise, with zero as the goal. The strictest part still touches every
  commit, because the same ratchet is asserted in
  `test/l10n_dutch_passthrough_test.dart`, which runs in the suite.
- **Failure means:** another language or another block started passing the Dutch
  source through. Translate it. If there is genuinely nothing to translate, add
  the **key** to `loanKeys` with its reason — not the baseline.

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
Tools • Dart 3.13.0
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

**The whole gate takes about five minutes.** Measured 2026-09-01 on the machine
above: the test suite (11 041 tests, 1 skipped) finishes in 4:00, and the checks
around it — format, analyze, conventions, method length, dead code, hardcoded
text, two coverage passes, and (on macOS) the golden visual-regression suite —
bring it to roughly five. Worth stating, because "11 000 tests plus a coverage
floor plus eight ratchets plus goldens" reads like half an hour, and a
contributor who assumes that never runs it.

| Command | Outcome |
| --- | --- |
| `make check` (the whole gate) | pass — exit 0 |
| `flutter test --test-randomize-ordering-seed random --exclude-tags golden` | pass — 11 041 tests, 1 skipped |
| `dart run tool/coverage_summary.dart --min=80 --require-instrumented` | pass — 87.1% (87 721/100 751 lines, 1026 instrumented files); no `lib/` file outside the census |
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

| Check | Verifies | In `make check` | In `check-full` | In CI workflow † | Blocks merge? |
| --- | --- | :---: | :---: | :---: | --- |
| [`make format-check`](#make-format-check) | Code is `dart format`-clean | ✅ | ✅ | ✅ | required (via `static-gate`) |
| [`make analyze`](#make-analyze) | No analyzer/lint/type issues (`--fatal-infos`) | ✅ | ✅ | ✅ | required (via `static-gate`) |
| [`make check-conventions`](#make-check-conventions) | No `print()`; no raw control bytes; bare `catch (_)`, raw-colour, layering, file-size, class-size, FilePicker-gate & fixed-delay ratchets | ✅ | ✅ | ✅ | required (via `static-gate`) |
| [`make check-audience-boundary`](#make-check-audience-boundary) | Every output channel classified: audience surface (needs `AudienceDeck`) or deliberately source-faithful | ✅ | ✅ | ✅ | required (via `static-gate`) |
| [`make check-method-length`](#make-check-method-length) | Per-method length ratchet (AST, max 150) | ✅ | ✅ | ✅ | required (via `static-gate`) |
| [`make check-dead-code`](#make-check-dead-code) | No orphaned `lib/` files (unreachable from any entrypoint) | ✅ | ✅ | ✅ | required (via `static-gate`) |
| [`make check-hardcoded-text`](#make-check-hardcoded-text) | No visible string in `lib/` bypasses `l10n.d()` | ✅ | ✅ | — | required (via `static-gate`) |
| [`make check-comment-language`](#make-check-comment-language) | No plain comment in `lib/` switches language halfway (`mixedCommentBaseline` ratchet) | ✅ | ✅ | — | required (via `static-gate`) |
| [`make check-dated-claims`](#make-check-dated-claims) | Every registered measurement in the docs still has its anchor, and no unregistered duration claim was added (`looptijdBasislijn` ratchet). Staleness itself runs daily, not here | ✅ | ✅ | — | required (via `static-gate`) |
| [`make check-toolchain`](#make-check-toolchain) | The running Flutter is the pinned official stable, and is recorded here | ✅ | ✅ | — | required (via `static-gate`) |
| [`make check-linux-deps`](#make-check-linux-deps) | Every pkg-config module a plugin requires on Linux has a package that every build environment installs, and the linked ones are runtime dependencies of the `.deb`/PKGBUILD | ✅ | ✅ | — | required (via `static-gate`) |
| [`make check-version-bump`](#make-check-version-bump) | The version in `pubspec.yaml` is at most one canonical semver step above the last release tag | ✅ | ✅ | ✅ | required (via `static-gate`) |
| [`make check-sbom-version`](#make-check-sbom-version) | Every committed SBOM file names the current `pubspec.yaml` version (`X.Y.Z+B`) | ✅ | ✅ | ✅ | required (via `static-gate`) |
| [`make check-collab-field-parity`](#make-check-collab-field-parity) | Every field on `Slide` is accounted for in the collaboration surface — synced, deliberately excluded with a reason, or on the shrink-only debt baseline | ✅ | ✅ | ✅ | required (via `static-gate`) |
| [`make check-translated-mermaid`](#make-check-translated-mermaid) | No machine-translated `docs/NAME.<lang>.md` carries a `mermaid` diagram byte-identical to the English base | ✅ | ✅ | ✅ | required (via `static-gate`) |
| [`make check-untranslated-templates`](#make-check-untranslated-templates) | No `assets/templates/<id>.<lang>.md` carries a line that stands in the English base and not in the Dutch source (two-word threshold, `allowedCognates` exemptions) | ✅ | ✅ | ✅ | required (via `static-gate`) |
| [`make translate-docs-check`](#make-translate-docs-check) | Every shipped doc variant (`shippedDocLanguages`) exists, is registered and carries the same section structure as its English source; no variant drifts or dangles, and no excluded document was translated | ✅ | ✅ | ✅ | required (via `static-gate`) |
| [`make test`](#make-test) | Full unit/widget suite passes (randomised order) | ✅ (via `coverage`) | ✅ | ✅ | local only (nightly on `main`) |
| [`make coverage`](#make-coverage) | Line coverage ≥ 80% floor **and** every `lib/` file is in some test | ✅ | ✅ | ✅ (gate) | local only |
| [`make coverage-per-file`](#make-coverage-per-file) | No `lib/` file runs under 34% of its own lines | ✅ | ✅ | — | local only |
| [`make check-l10n-parity`](#make-check-l10n-parity) | Every key present in one language table exists in all of them (no baseline) | ✅ | ✅ | — | required (via `static-gate`) |
| [`make check-l10n-orphans`](#make-check-l10n-orphans) | No growth in translation keys nothing looks up any more (`orphanBaseline` ratchet) | — | ✅ | — | local only (`check-full`) |
| [`make check-l10n-passthrough`](#make-check-l10n-passthrough) | No growth in translations that pass the Dutch source through verbatim (`passthroughBaseline` ratchet) | — | ✅ | — | local only (`check-full`) |
| [`make licenses`](#make-licenses) | Every dependency is open-source | — | ✅ | ✅ | local only (`check-full`) |
| [`make sbom-verify`](#make-sbom--make-sbom-verify) | Committed SBOM matches the dependency set | — | ✅ | ✅ | local only (`check-full`) |
| [`make deps-check`](#make-deps-check) | Vendored export JS: integrity + CVEs | — | ✅ | ✅ | local only (`check-full`) |
| [`make check-web`](#make-check-web) | Web bundle keeps its hardening | — | ✅ | ✅ | conditional (via `web-gate`, #1888-tail) |
| [`make deps-outdated`](#make-deps-outdated-advisory) | Dependency freshness (advisory) | — | ✅ | — | advisory |
| [`make catalogs-outdated`](#make-catalogs-outdated-advisory) | Bundled reference data vs upstream (advisory, pre-release) | — | — | — | advisory |
| [`make check-secrets`](#make-check-secrets) | No credential-shaped strings in the working tree or in history | — | ✅ | ✅ | required (via `scans`, #1891) |
| [`make sast`](#make-sast) | Semgrep rules over shipped Dart (cert validation, subprocesses, weak randomness) | — | ✅ | ✅ | required (via `scans`, #1891) |
| [`make shellcheck`](#make-shellcheck) | ShellCheck over the committed shell scripts | — | ✅ | — | local only (`check-full`) |
| [`make dast`](#make-dast-advisory) | ZAP baseline over a served build (advisory) | — | — | — | advisory |
| [`make trivy`](#make-trivy-advisory) | Dart-dep CVEs + committed secrets (advisory) | — | — | ✅ (advisory) | advisory |
| [`make check-pins`](#make-check-pins-advisory) | Exact-pinned CI versions — actions *and* scanner binaries — vs their latest release (advisory) | — | — | — | advisory |

† The **In CI workflow** column is what `.github/workflows/ci.yml` *declares* —
not what runs. That workflow does not execute: Forgejo reads
`.forgejo/workflows/` instead of `.github/workflows/` once the former exists
(see [Continuous integration](#continuous-integration)). What *does* run in CI
is [`make check-no-coverage`](#make-check-no-coverage) on the Mac runner, on a
`v*` tag (#790/#796/#797), plus
[`make check-secrets`](#make-check-secrets) and [`make sast`](#make-sast) on
every pull request (#778), and — since #1118 — the static gates
(`$(STATIC_GATES)`) via [`make check-static`](#make-check-static) on every pull
request too (`.forgejo/workflows/static-gate.yml`), plus — since #1888-tail —
[`make check-web`](#make-check-web) on a pull request that can reach the web
bundle (`.forgejo/workflows/web-gate.yml`, path-filtered). Those are the checks in this
table that a forge actually runs before a merge; the full test suite and the two
coverage floors still run only in your local `make check`.

‡ The **Blocks merge?** column says whether a failing check prevents a PR from
merging into `main`. **required** = a required status check on branch protection
(`static-gate` since #1118, `scans` since #1891). **conditional** = runs on a
pull request, but only when the change touches the paths that can break it, and
so cannot be a required context — a filtered check that never reports would hang
every unrelated PR on a status that never arrives. Red still stops a merge in
practice; it is simply not the mechanism branch protection waits for.
**local only** = runs in
`make check` on the committer's machine, not on the forge. **post-merge** = runs
after the merge, as detection not prevention. **advisory** = never blocks.

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
registration** — the deliberate split between the docs the app *bundles* and the
docs that live *only in the repository*. A bundled doc must be declared in
`pubspec.yaml` **and** surfaced in the in-app reader (so it cannot ship
unreachable); a repo-only doc — the developer-internal set (architecture, build,
checks, source map, API, contributing, dev setup) and every `docs/design/**`
spec — must be in neither. A new `docs/*.md` defaults to *must be bundled*, so
dropping one in fails the gate until it is either registered or listed as
repo-only; the decision is forced, never silent. The
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
  is pinned to **Flutter 3.47.1** (see [Version pin](#version-pin)); a different
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
  - **fixed-delay ratchet for tests** (`fixedDelayBaseline`) — `runAsync(() =>
    Future.delayed(const Duration(milliseconds: 80)))` waits on a guess about
    how long real work takes on this machine, not on the result. Such a test
    passes in isolation and fails under a loaded `make check`, which is the
    most expensive failure mode there is: it gets re-run, passes, and everyone
    concludes it was a fluke. Use `pumpUntil` from
    `test/support/pump_until.dart`, which alternates short steps of real time
    with a `pump` and checks whether the result is *there*, with an upper bound
    so a genuinely stuck future still fails with a readable message.

    The baseline is a per-file count of the wait points that still exist; it
    may shrink but never grow, and a file that drops below its entry is
    reported so the win gets locked in. Two kinds of entry live in it and the
    comments keep them apart: deliberate exceptions (a queue draining, an
    isolate that must start inside `runAsync` — the reasons are written out in
    `pump_until.dart`) and debt still to be converted.

    **This gate measured almost nothing between 2026-07 and 2026-09-01.** It
    was a regular expression looking for the bare spelling `Future.delayed(`
    and reading 400 characters past the `runAsync(`. Three blind spots followed
    from that, and all three had already cost red gates:

    1. **the type argument** — 126 of the 129 wait points in `test/` are written
       `Future<void>.delayed(`. The gate saw 3 of 129 and reported green while
       `image_carousel_delete_test` failed the linux gate nine times in twelve
       days;
    2. **the reach** — one `pumpWidget` with a widget tree in it is longer than
       400 characters, and that is exactly where the failing wait point sat;
    3. **the detour** — a wait point inside a helper *called* from a `runAsync`
       block is not lexically inside it. `callout_reveal_test._pumpOverlay` had
       that shape and was never seen.

    The measurement therefore runs over the AST (the `analyzer` package, as
    `check_method_length` already did), with a call graph within the file: a
    `runAsync` counts when it reaches a fixed wait directly, or through a helper
    declared in the same file. Comments and string literals fall away by
    construction — the parser makes no call nodes out of them — so the two text
    filters this used to need are gone, and so is the risk that the gate trips
    over its own documentation. A file that fails to parse is reported rather
    than skipped: "silently measuring nothing" is the failure mode that made
    this gate useless for six weeks, and it must not recur quietly.
    `test/fixed_delay_ratchet_test.dart` holds all three blind spots as cases.

    What the gate still does *not* cover is a guess measured in **frames**
    rather than wall-clock — two bare `pump()` calls and then an assertion that
    an async fallback has happened. That shape failed the gate five times in
    `document_editor_screen_test`; it is fixed there, but no gate would catch
    the next one.
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

### `make check-dated-claims`
- **Runs:** `dart run tool/check_dated_claims.dart`, and with
  `--tegen-de-klok` the staleness half on top
- **Covers:** claims about a *measured* quantity — how long something of ours
  takes. This document promised on two lines that a red `main` surfaces well
  under the time it actually takes; on 2026-09-03 the measured median from merge
  to verdict was 54 minutes. The claim was true when it was written and stepped
  up around 2026-08-23 without this repository changing. Nothing saw it, and
  nothing could: there was no date to check against.
- **Why this is its own class.** The gates on the code are strong, and
  `docs_claims_match_code_test.dart` holds the numbers that have a constant
  behind them. A duration has no constant. It decays while the tree stands
  still, which makes it the documentation counterpart of
  `check_reference_data.dart` — the same question, asked about our own
  measurements instead of somebody else's releases.
- **How it measures — two halves, and the second keeps the first honest.**
  `gemetenBeweringen` is the register of live claims: where each one sits, what
  was measured, when, and how to measure it again. Each entry carries a literal
  anchor that must still appear in the document, and that anchor contains the
  measurement date, so the register and the prose cannot drift apart on the one
  number that matters. `looptijdBasislijn` then counts *every* duration
  expression in `docs/CHECKS.md`, `CONTRIBUTING.md` and `docs/BUILD.md`. Without
  that second half the register would only guard what somebody remembered to add
  to it, and the next undated promise would be exactly as invisible as the last.
  A new expression fails the gate with a choice: measure it and register it, or
  put it on the baseline because it is history.
- **Word forms count too.** The claim that caused this gate carried no digit at
  all. A pattern that only looks for `\d+ minutes` would never have seen it, so
  `half an hour`, `about an hour`, `an hour or so` and `a few minutes` are in
  the pattern by name.
- **Not covered on purpose — placement.** The baseline is a multiset of
  expressions, not a set of locations. Removing one `22 minutes` from a file and
  adding another elsewhere in the same file passes silently. That is the price
  of a counter that does not sit on line numbers, which would fail on every
  reflow of a paragraph and get switched off within a week. The limit is written
  down here because a gate whose blind spot nobody knows gets taken for more
  proof than it delivers.
- **Not covered on purpose — staleness, per PR.** Whether a measurement is past
  its shelf life changes without a commit, so it runs daily in
  `.forgejo/workflows/time-degrading-checks.yml` and not in this gate. Were it
  here, some unrelated pull request would one day fail on a claim its author
  never touched, and the answer to that is always to disable the gate.

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
- **And every place that names the version must agree** (#721). The claims live
  in `.tool-versions`, `README.md`, `CONTRIBUTING.md`, `BUILD.md`, this file,
  the setup and troubleshooting guides, and the mirror workflows that pin
  `flutter-version:`; `versionClaimPatterns` in `tool/check_toolchain.dart` is
  the list, and the gate prints how many claims in how many files it compared —
  repeating those counts here would be a number this document does not own.
  Raising the pin in one place and forgetting another is a silent failure: the
  documentation then promises something the machine does not do, which is how
  #598 started.
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

### `make check-linux-deps`
- **Runs:** `dart run tool/check_linux_pkgconfig.dart`
- **Covers:** every pkg-config module a Flutter plugin demands on Linux with
  `pkg_check_modules(... REQUIRED ...)`, re-derived from the resolved sources in
  `.dart_tool/package_config.json`, against the promises in
  `.github/linux-pkgconfig-modules.json`: which apt package provides it, which
  build environments must install it, and which runtime package the `.deb` and
  the AUR PKGBUILD must depend on.
- **Why it exists:** because v0.4.9 has no release. The nativeapi migration
  (#1741) brought in `cnativeapi`, which requires `ayatana-appindicator3-0.1` —
  the one of its four modules that `libgtk-3-dev` does not pull in. No gate
  builds the Linux desktop: they all run `flutter test`, and `flutter build
  linux` first appears in the release chain. So CMake failed there, before
  compiling a single file, the `linux` job failed, `publiceren` needs it, and the
  tag produced nothing. Every gate was green from the merge to the tag.
- **Both directions are fatal.** A module nobody installs is the failure above. A
  package nobody requires any more is a system library we still make our users
  install for a reason that no longer exists.
- **Comments do not count.** The prose that *explains* a package is not the line
  that installs it, so the comment half of every line is dropped before matching
  — otherwise deleting an apt argument while leaving its comment keeps the gate
  green.
- **A build environment is a composition.** The Forgejo release job installs part
  of what it needs and inherits the rest from the prebaked CI image, so each
  environment lists every file that may carry the package and one of them naming
  it is enough.
- **Ceiling:** pkg-config is how Flutter's Linux plugins ask for system
  libraries, not the only way anything can. `find_library`, `find_package`, a
  bare `#include` or a build script shelling out to a tool are invisible here.
  That half is covered by actually building: `.forgejo/workflows/linux-build.yml`
  now also runs after a merge to `main` when `pubspec.lock`, `pubspec.yaml`,
  `.tool-versions`, `linux/`, `third_party/` or the CI image changed — the
  inputs that can break a native build — instead of on every push, which is what
  #790 switched off for costing 17.5 minutes a time. That list is itself
  guarded: `test/linux_pkgconfig_manifest_test.dart` fails if one of those
  inputs disappears from the path filter, because a build that does not fire
  guards nothing. `.tool-versions` is in it because a *bare* Flutter pin bump
  touches neither pubspec file, and a new Flutter is a new compiler, engine and
  generated CMake.
- **Failure means:** add the module to the manifest with the package that
  provides it, install that package in the build environments the manifest
  lists, and — if the bundle links the library — name its runtime package in
  `scripts/package_linux.sh` and `packaging/aur/PKGBUILD`. The offline half of
  this invariant also runs inside the suite
  (`test/linux_pkgconfig_manifest_test.dart`), so a stale manifest fails with a
  readable message even where the pub cache is not populated.

### `make check-version-bump`
- **Runs:** `dart run tool/check_version_bump.dart`
- **Covers:** the `version:` in `pubspec.yaml` against the last release tag
  reachable from HEAD (`git describe --tags --abbrev=0 --match 'v*'`). From a
  released `X.Y.Z` the only legal next versions are the patch `X.Y.(Z+1)`, the
  minor `X.(Y+1).0` (patch reset) or the major `(X+1).0.0` (minor and patch
  reset). Anything else — carrying an old minor or patch across a major bump,
  jumping two axes at once — is refused.
- **Why it exists:** the version was once bumped `0.2.0 → 1.2.1` in a release
  commit, and the `v1.2.1` tag fired the whole release chain (four platforms, a
  published release, the live web) before anyone noticed it was meant to be
  `0.2.2`. `1.2.1` is not a step any release process produces; it is the
  signature of a typo or a stray find-replace. A single-axis rule catches
  exactly that class of mistake.
- **A no-op between releases.** When the pubspec version equals the baseline
  there is no bump in progress, so normal development and feature branches never
  trip it — it fires only on the commit that actually changes the version.
- **Deliberate exceptions are written down.** A conscious, one-off transition the
  canonical rule forbids (say, a correction that goes back down past a bad
  release) goes in `sanctionedTransitions` in `tool/check_version_bump.dart`, in
  the diff, with a reason. The one current entry is `1.2.1->0.3.0`: the
  accidental `v1.2.1` release is abandoned and the project deliberately returns
  below 1.0, continuing its 0.x line at 0.3.0. An accident has no entry there and
  fails; a decision does.
- **A shallow clone is skipped, not failed.** With no reachable tag the gate
  cannot know the baseline, so it prints a note and passes rather than fail a
  machine that simply lacks the history; a full clone and the release runner both
  carry the tags.
- **Failure means:** correct the version in `pubspec.yaml` (and
  `kOciDeckVersion` in `lib/services/export_metadata.dart` — see
  `version_consistency_test`), or, for a deliberate one-off, add the transition
  to `sanctionedTransitions` with a reason.

### `make check-sbom-version`
- **Runs:** `dart run tool/check_sbom_version.dart`
- **Covers:** that every committed SBOM file (`sbom/ocideck.cdx.json`,
  `sbom/ocideck.spdx.json`, `sbom/ocideck.sbom.md`) contains the current
  `pubspec.yaml` version *including the build number* (`X.Y.Z+B`). `make sbom`
  writes that string into all three at once, so a file that lacks it was not
  regenerated.
- **Why it exists:** the SBOM records the project version (the CRA wants "which
  version is this inventory for"), so a version bump makes it stale.
  `sbom_test` already catches that — but only as a full regenerate-and-diff
  flutter test in `make check-registrations`, which
  is outside the fast `make check-static` subset. The `1.2.1 → 0.3.0` bump
  therefore passed the fast static gate green while the SBOM was still a version
  behind, and the drift only surfaced in the slower gate. This closes that gap
  with a cheap string check at the same fast tier; `sbom_test` still owns the
  full dependency-set freshness.
- **Why the build number too:** `make sbom` writes `X.Y.Z+B`, and the build
  number moves on a re-release even when `X.Y.Z` does not — so matching only the
  three-part version would let a stale SBOM through.
- **Failure means:** regenerate the SBOM and commit it — `make sbom` then
  `git add sbom/`.

### `make check-collab-field-parity`
- **Runs:** `dart run tool/check_collab_field_parity.dart`
- **Covers:** that every `final` field declared on `class Slide` is in exactly
  one of three places — the `SlideField` enum (it syncs on edit), the
  `deliberatelyNotSynced` map (a written decision, with its reason beside it),
  or `unsyncedBaseline` (known debt, a ratchet that may shrink but never grow).
  It also refuses a `SlideField` entry that no `Slide` field backs, and an entry
  in either list for a field that no longer exists.
- **Why it exists:** two parity tests already guard the collaboration surface —
  `deck_op_test` asserts every `SlideField` has a case, `collab_codec_test`
  asserts the codec maps every `SlideField` — and **both look the same way**.
  They answer "is everything *in* the enum handled?"; neither answers "is every
  syncable field *in* the enum?". Adding a field to `Slide` therefore lowered no
  gate at all. That is how `imageZoom` was missed for two weeks (#1803): the op
  model landed on 2026-07-30 with `imageSize` and all four focal fields, the
  zoom was added to `Slide` on 2026-08-12, and a changed panel zoom silently
  never reached the other client while a *newly inserted* slide carried it
  fine — an asymmetry that makes the bug hard to reproduce on purpose.
- **Failure means:** classify the field. Sync it (`SlideField` +
  `slideFieldValue` + `applyOp` + the codec kind map + a case in
  `test/deck_op_test.dart`), or record in `tool/check_collab_field_parity.dart`
  why it is excluded. Choosing to leave debt is allowed; leaving the choice
  unmade is not.

### `make check-translated-mermaid`
- **Runs:** `dart run tool/check_translated_mermaid.dart`
- **Covers:** every generated `docs/NAME.<lang>.md` variant — for each
  ` ```mermaid ` block it compares the body byte-for-byte against the same block
  in the English base `docs/NAME.md`, and fails on an identical (untranslated)
  one. Genuinely language-neutral diagrams (only node IDs, numbers, arrows) are
  exempted through the explicit `languageNeutralMermaidBlocks` whitelist, which is
  empty today.
- **Why it exists:** the translated docs are generated by
  `tool/translate_docs.dart`, which hands the whole
  Markdown body to an external translator. Like every sane translator it leaves
  fenced code blocks untouched so it cannot break their syntax — and a `mermaid`
  block *is* a code block, so its label text stays in the source language while
  the prose around it is translated. A Dutch reader then saw an English diagram in
  the middle of the Dutch guide (#1278). This gate catches that whole class, for
  every current and future language.
- **Why not machine-translate the labels instead:** mermaid has a dozen node
  shapes and a different text syntax per diagram type, interleaved with lines that
  must *not* be touched (`classDef`, `style`, `click`, `linkStyle`). A partial
  extractor would be exactly the fragile parser that corrupts a diagram — the risk
  the translator sidesteps by skipping code blocks. So the labels are translated by
  hand and this gate forces that pass.
- **Failure means:** translate the diagram's label text by hand in the named
  variant, keeping the node IDs and mermaid syntax intact; or, if the diagram
  genuinely carries no prose, add its body to `languageNeutralMermaidBlocks` in
  `tool/check_translated_mermaid.dart`.

### `make check-untranslated-templates`
- **Runs:** `dart run tool/check_untranslated_templates.dart`
- **Covers:** every `assets/templates/<id>.<lang>.md`. A line counts as
  untranslated when it stands verbatim in the English base **and** does not stand
  verbatim in the Dutch source, and carries at least `minimumWords` (currently
  **2**) words of three or more Latin letters. Klingon is skipped
  (`skippedLanguages`): `TemplateContentService.languagesWithContent` deliberately
  keeps it on the English fallback. Ratchet: `untranslatedBaseline` (currently
  **0**).
- **Why it exists:** `tool/template_l10n_po.dart` peels only five things out of a
  template — `title:`, `# `, `## `, bullets and table rows. Everything else
  travels along as a `raw` segment, so whatever the English base said the
  translation kept saying. That was not theory: 47 raw lines in twelve templates
  stood in English in every translated language but Spanish and Greek, nine
  templates carried English answers,
  chart series and meter labels inside their ` ```question `, ` ```chart ` and
  ` ```cockpit ` blocks, and four templates carried English text inside embedded
  HTML. The three l10n gates never saw any of it — they watch
  `lib/l10n/translations/`, not `assets/`.
- **Why Dutch is the yardstick and not English alone:** Dutch is the source
  language of the content, so a line that is identical in Dutch is the authored
  form rather than a gap. That one rule silences the SIPOC table head (which
  spells the acronym), `Destination METAR/TAF`, `ATIS / QNH`, `Sterile cockpit`,
  `Check-out`, the language-neutral mermaid diagram in `technical`, and
  `**Scope object:**` — which `FindingSpec` parses as a key and must stay English.
- **Failure means:** translate the named line in place, or — if the English words
  genuinely are that language's words — add the `(language, line)` pair to
  `allowedCognates` in `tool/check_untranslated_templates.dart` with the reason.
  `--list` prints every hit.

### `make translate-docs-check`
- **Runs:** `dart run tool/translate_docs.dart --check`
- **Covers:** the bundled user docs are shipped only in the languages listed in
  `shippedDocLanguages` (the English base plus Dutch today), not machine-translated
  into every interface language. The gate does *not* demand the other languages
  exist; it enforces that what is shipped stays coherent — every
  `shippedDocLanguages` variant exists and is registered in `pubspec.yaml`, no
  variant file sits on disk for an unlisted language, no `pubspec.yaml`
  registration dangles after its file is gone, and no excluded document
  (`PRIVACY.md`, `SECURITY_DESIGN.md`) was translated. Since 2026-08-19 it also
  checks that a shipped variant is *current*: it must carry the same number of
  headings per level as its English source, and every numbered section
  (`14.11`, `6.3.1`) must be present under the same number. There is no
  baseline and no allowance: the Dutch variants were brought level with their
  sources in the same change that added this rule, so any drift the gate reports
  is drift introduced today.
- **Why it exists:** the docs are *content*, and OciDeck ships content in Dutch +
  English while translating only the interface into every language. The generator
  (`tool/translate_docs.dart`) can machine-translate the manuals into any interface
  language (#1181), but that is opt-in — a maintainer adds a language by generating
  its variants (`make translate-docs`) and listing its code in `shippedDocLanguages`.
  Until then the gate keeps the shipped set honest without forcing hundreds of
  unreviewed machine translations, and it still fails on the real regressions: an
  unbundled variant the app cannot load, a dangling registration, or a translated
  privacy/security promise. The check also used to exit 0 silently — `main`
  returned an `int` the Dart VM discards — until #1341 propagated it through
  `exitCode` so the gate can actually fail. The structure half was added after
  the same hole showed twice in two days: §14.9 of FILE_FORMAT existed only in
  English for a day (#1568), and §14.11 landed with its feature in English only
  (#1571, repaired in #1573). Both times every gate was green, because
  "the variant exists" was the whole question the gate asked. Dutch is what the
  in-app reader shows, so a variant that exists but is a section behind is a
  reader who is told less than the English reader.
- **Failure means:** for a missing or unregistered shipped variant, run
  `make translate-docs` and commit the result; for a variant on disk in an unlisted
  language, either add that language to `shippedDocLanguages` or delete the file;
  for a dangling registration, drop the `pubspec.yaml` line; for a translated
  excluded document, remove the translation. For structure drift — a variant
  missing a heading, or a section number the variant does not carry — translate
  the new section into the variant *in the same change*; that is the whole point
  of the rule, and there is deliberately no number to raise to get past it.

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

  In dezelfde geest draait `integration_test/document_pdf_graphics_test.dart` de échte renderers achter de tekeningen in een document-PDF: mermaid en MathJax wonen in een verborgen WebView, en die bestaat onder `flutter test` niet — daar valt alles stil terug op de bron, dus een groene suite zegt daar niets over de functie zelf. Draaien met `flutter test integration_test/document_pdf_graphics_test.dart -d macos`. Hij schrijft de PDF naar de tijdelijke map, zodat er ook met eigen ogen naar te kijken valt.

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
  fails on any file missing from the report. The 92 files legitimately absent
  (counted 2026-08-30) are baselined in `uncoveredBaseline` with a reason each
  — platform halves / conditional-import facades (the VM test runner cannot load
  `dart:js_interop` code at all), files with no executable lines (`export`
  barrels, enums, const data tables), the per-language finding-template data
  tables under `lib/services/finding_templates/`, and one user-approved native
  binding (`meeting_media_core_webrtc.dart`, which needs a real device).
  *(Corrected 2026-08-15: this page still carried 60, the count from an earlier
  stand of the list.)* It is a **ratchet**: it may shrink, and the run prints a
  tip when a baselined file becomes covered — but only when that file also
  clears the per-file floor. A baselined file can sit in the report and still
  run almost none of its own lines; dropping *that* one from the list would trip
  `--per-file-floor` on the next run, so the run names it separately as
  something a test has to fix first.
- Since this supersedes `make test` (same suite, one run, plus the floor),
  `make check` depends on **`coverage`** rather than `test`.

### `make coverage-per-file`
- **Runs:** `dart run tool/coverage_summary.dart --per-file-floor`, over the
  report `make coverage` just wrote — no second test run.
- **Covers:** the worst case *per file* instead of the average: how many `lib/`
  files execute less than `perFileFloorPercent` (currently **34%**) of their own
  lines. The floor is a ratchet: it was raised on 2026-07-29, after tests were
  written for every file that sat below the new bar. *(Corrected 2026-07-30:
  this page still carried the starting value from 2026-07-21 after that
  raise.)*
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
  So the budget is gone: anything that drops below the floor is a test to
  write, not a number to adjust. The only escape is `uncoveredBaseline`, and that is a list
  with a reason per line — reserved for platform halves, files with no
  executable lines at all, and the one user-approved native binding that cannot
  run in a headless VM. This gate skips that list, so a file on it is not
  floored; that is also why the leave-the-list tip refuses to recommend dropping
  a baselined file that would land below the floor the moment it left.

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

### `make check-static`
- **Runs:** exactly `$(STATIC_GATES)` — the same static gates `make check` runs,
  and nothing else: no `make test`, no coverage.
- **Covers:** formatting, static analysis, the toolchain, conventions, the
  privacy projection boundary, method length, dead-code, hardcoded visible text,
  comment language and improvement templates. Seconds each; no test-suite compile.
- **Where it is used:** `.forgejo/workflows/static-gate.yml`, on **every pull
  request** (#1118). It is the part of the gate fast enough to run per pull
  request on the server without the clock argument that moved the full gate to a
  tag.
- **Why it exists:** while the full gate runs only on a `v*` tag and the Linux
  gate only on demand, these static ratchets ran nowhere between releases — so
  `main` drifted silently red (files, classes, a method and registrations over
  their ceiling, uncaught until someone tried to land a fix on top, #1118). This
  target puts the fast half of the gate back on the pull request, where an
  overrun is still an edit rather than history.
- **What it gives up, stated plainly:** the full test suite, the coverage floor
  and the per-file floor. Those are unchanged and still mandatory — in
  `make check`, on the committer's machine, before `main`. It is a safety net in
  front of that gate, not a replacement for it.

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
- **Daarna:** `make refresh-catalogs` (→ `scripts/refresh_catalogs.sh`) haalt op
  wat upstream nú heeft — de doelversie komt uit dezelfde probes als deze
  controle, dus verversing en poort praten nooit over verschillende versies — en
  legt die versie meteen vast in de catalogus én in `docs/LICENSE_COMPLIANCE.md`
  (`tool/record_catalog_version.dart`). Eén commando maakt de melding dus weg.
  Dat was niet altijd zo: de Makefile haalde de bron op met een vastgezette
  versie en liet het bijschrijven aan jou, waardoor "werk bij met
  `make refresh-catalogs`" een advies was dat de melding niet kón wegnemen.
  `make refresh-lexicon` doet hetzelfde voor het gezondheidslexicon uit Orphanet.
- **In een release rijdt een verschoven momentopname vanzelf mee.**
  `scripts/release_auto.sh` ververst in fase 1 zelf wanneer upstream bewoog zónder
  dat de gegenereerde catalogus verandert — dan is het administratie, en het wordt
  een eigen commit op de release-branch. Raakt de verversing wél een gegenereerd
  deel, dan stopt de keten: dat verandert waar een rapport naar verwijst.
- **Meet wat je meedraagt.** Een bron met een commitdatum-probe krijgt een
  `probePath`: het pad waar onze generator uit leest. Zonder dat pad telt elke
  commit in andermans repository als veroudering — MASWE stond zo een release in
  de weg om een build-workflow die geen enkele zwakheid raakte.
  `reference_standards_test` dwingt het pad nu in beide richtingen af.
- **Twee soorten bron, twee soorten melding.** Een standaard die verouderd is,
  laat de poort in `deps-check` vallen. Een bron met `advisory: true` in
  `lib/services/reference_standards.dart` meldt zich wél maar blokkeert nooit —
  dat is voor **detectielexicons**. Die brengen maandelijks uit, en bij een
  lexicon *vuurt* elke term, dus een verversing kost een termdiff lezen en de
  vals-positievencorpus opnieuw wegen. Een poort die daarop rood wordt, staat
  binnen twee maanden permanent rood en gaat uit.

### `make check-web`
- **Runs:** `make build-web`, then `dart run tool/check_web_hardening.dart`,
  `dart run tool/pack_web_release.dart --check` and
  `dart run tool/check_bundled_docs_fresh.dart build/web`.
- **Covers:** three things about the built `build/web`.

  *Hardening* — a strict CSP in `index.html` (`script-src 'self'
  'wasm-unsafe-eval'`, no `unsafe-inline`/`unsafe-eval`, `connect-src 'self'`,
  `object-src 'none'`, `form-action 'none'` — that last one does *not* fall back
  to `default-src`, so it is asserted separately), CanvasKit **self-hosted**
  (local wasm + the `useLocalCanvasKit` flag), and the UI font **bundled** — so
  the running app pulls zero third-party origins. It also walks `web/` and
  asserts that **every** entry reached `build/web`, minus what `nietUitleveren`
  deliberately drops. Those files are copied by `flutter build web` rather than
  placed by the packing step, so a test on the source file cannot see whether
  they survived — and #1888's dotfile sweep proved they might not: it removed
  `.htaccess` (header-form hardening, #849) and `.well-known/security.txt` (the
  RFC 9116 disclosure address) from the bundle, and only the first was pinned by
  name, so the reporting address vanished with no gate going red. Deriving the
  list from `web/` instead of naming files covers whatever is added there next.

  *Release artefacts* — that `LICENSE.md`, `THIRD_PARTY_NOTICES.md` and the
  three SBOM files are in the bundle, and that `SHA256SUMS` describes exactly
  the files that are there. It complains about a file that was **added** after
  packing as loudly as about one that changed, which is the case that actually
  bites: a later build step that drops something in would otherwise fall outside
  the list unnoticed.

  *Bundled docs fresh* — every Markdown asset declared in `pubspec.yaml` (the
  in-app documentation) matches its `docs/`/root source **byte for byte** in the
  built bundle. The docs are plain assets, so a *clean* build always carries the
  current text; but the project deliberately avoids `flutter clean` and the
  forge's macOS runner is persistent, so an *incremental* build could ship stale
  documentation while everything else is current. `check_bundled_docs_fresh.dart`
  closes that gap by construction, naming any file that is stale or missing. It
  rewrites nothing — the fix is a clean rebuild.
- **Failure means:** a change weakened the CSP, re-introduced a CDN/font fetch,
  dropped `.htaccess` or `security.txt` from the bundle, moved something in the
  bundle after it was sealed, or an incremental build shipped documentation
  older than `docs/`; the scripts list every broken invariant. See [`BUILD.md`](BUILD.md) for the hardened build and for what the
  checksum list does and does not prove.
- **Note:** the packing logic itself is tested in
  `test/pack_web_release_test.dart`, which runs in `make check` — so a broken
  checksum list surfaces without waiting for a web build. That file also mirrors
  the real `web/` tree into a stand-in bundle and asserts nothing from it is
  swept away, which puts the invariant above on the **per-PR** gate: no web
  build runs there, and #1888 merged green precisely because its own test used a
  hand-built bundle that happened to contain none of the files it broke.
  Since #1888-tail there is a second, higher layer:
  [`web-gate.yml`](#forgejoworkflowsweb-gateyml--the-web-bundle-per-pull-request-that-can-break-it)
  runs this whole target — a real `flutter build web` — on a pull request that
  touches the source, the packing step or the toolchain. The test stays the
  cheap per-commit layer; the workflow is the one that actually builds.

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
- **Both directions are tested:** zero findings across the whole of `lib/`,
  `tool/` and `test/` on `main`, and three findings on a file with planted
  violations — with the commented-out equivalents correctly ignored.

  *(Corrected 2026-08-30: this read "627 files", undated, while the three
  directories held 2,211 Dart files. A file count that moves with every commit
  says nothing a reader can use — the scope does, so the scope is what is stated.
  The `uncoveredBaseline` count above kept its number because a reader compares
  it against the list in `coverage_summary.dart`, but it now carries the date it
  was counted.)*

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
  for removal. If colima is installed but its VM is stopped, both this target
  and `make check-release` start it automatically (`colima start` is
  idempotent — a no-op with a warning if it's already running) rather than
  requiring a separate step before every tag.
- **Advisory, not a gate — but part of the pre-tag pass.** It stays out of
  `check`/`check-full`, but [`make check-release`](#make-check-release) runs it
  once, advisory and non-blocking, against the live host — the quality slag you
  run by hand before `git push origin v*`. That timing is the point: a finding
  before the tag can still hold back a release, whereas a scan after deploy only
  speaks once the site is already live. A finding is for a human to weigh and, if
  real, file as an issue (this is how #849 came to be). Only if no container
  runtime is reachable even after the auto-start attempt does the step skip
  itself, with a clear message.
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
  (`test/golden/`). Renders **every slide type** through
  `SlidePreviewWidget` (the
  widget behind the editor preview, presenter, thumbnails and the PDF/PPTX
  raster) with the default flutter-test font, so the PNGs catch layout /
  structure / colour regressions (elements moving, resizing, disappearing, wrong
  theme colours) without depending on glyph rendering. The PNGs are pixel- and
  **platform-specific**, so they are tagged `golden` and **excluded from the
  default suite** — run them on **one** platform. `make test-golden` compares;
  `make test-golden UPDATE=1` accepts an intentional visual change. (Gated in CI
  since #1988: `macos-gate.yml` runs `make test-golden` on every push to `main`
  on the Mac-runner — a post-merge vangnet that een sub-promille renderlaag-
  verschuiving binnen minuten ziet in plaats van pas wanneer iemand lokaal `make
  check` draait. Geen required PR-check, want de Mac-runner staat niet altijd
  aan en de goldens zijn machine-specifiek.)

  *Corrected 2026-07-22 (#617): this said "each slide type" while the file
  covered **eight** of the 24 types there were then. Everything built after the
  first round — chart, cockpit, timeline, scorecard, finding, checklist, scopeMatrix, discoveries,
  findingsSummary, question — had no visual regression test at all, so a theme
  change could shift their layout with nothing turning red. The loop is now over
  `SlideType.values`, which also means a new type gets its golden without anyone
  remembering to add one. (Corrected again 2026-08-30: the sentence above still
  read "every one of the 24 slide types" while the enum had reached 32. A loop
  over `SlideType.values` needs no count beside it, so the number is gone rather
  than raised — it would only rot again.) Two sentences to keep straight: they
  are still excluded from `make check`, deliberately — a pixel comparison in the default
  gate would fail on any machine but this one — and they are still only as good
  as somebody typing `make test-golden`. Sinds #1988 draait `macos-gate.yml` ze
  op `push: main` op de Mac-runner, dus een vergeten handmatige run is niet meer
  de enige vangst.*

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
> Since #1118 the **static gates** run per pull request as well — see
> [`static-gate.yml`](#forgejoworkflowsstatic-gateyml--the-static-gate-per-pull-request).
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
- **scans** — runs on the prebaked scan image
  (`pawprint.vigilis.online/librekat/ocideck-scans:<pins>`, see the
  `ci-image-scans.yml` section) with the three scanners baked in, then runs
  [`make check-secrets`](#make-check-secrets) (gitleaks + trufflehog, working
  tree *and* full history) and [`make sast`](#make-sast) (semgrep, local rules
  only). The commands are the Makefile targets, not re-typed copies of what they
  do — a contributor's local run and CI are then the same run by construction.
- **Why it is its own workflow rather than a second job in `ci.yml`.** `on:` is
  per workflow, and `ci.yml` fires on a `v*` tag. A job there would first scan
  once the secret was already on `main` with a tag around it.
- **Why it may run per pull request when the gate no longer does.** The reason
  for #790 was the clock — 22 minutes per pull request against a `make check`
  that already ran before every push. These two take 17 and 2 seconds locally,
  so that argument does not reach them, and for a secret the moment is not
  interchangeable.
- **What it used to cost, and why it is now prebaked.** The first runs (#778)
  measured about three minutes, against 19 seconds of actual scanning — nearly
  all of it *installing* the scanners into a bare image. The obvious lever, an
  `actions/cache` on the two binaries and the semgrep venv the way
  `linux-gate.yml` caches the toolchain, was **deliberately refused** for a reason
  specific to this job: a cache restore would replace a sha256-verified download
  *of a security scanner* with an artifact written by an earlier run.
  `linux-gate.yml` accepts that trade for the toolchain because `check-toolchain`
  re-checks the restored tree; there was no equivalent re-check for a restored
  scanner binary, so caching would quietly spend the very property #778 was after
  — that green means the same thing over time.
- **The prebaked scan image answers that objection instead of dodging it.** The
  scanners now come baked into
  `pawprint.vigilis.online/librekat/ocideck-scans:<pins>` (see the
  `ci-image-scans.yml` section), which removes the per-run install *and* the
  three network fetches. It is defensible only because it closes the exact gap the
  cache left open, on two points: (1) the sha256 verification is not gone but
  moved to **build time** (in `scans.Dockerfile`), and (2) the workflow regains
  the missing re-check — a first step, *"baked scanner versions == the pins"*,
  asserts fail-closed that the image carries what the pins say, the precise
  equivalent of `check-toolchain` for Flutter. A lagging or mistagged image falls
  over there, before anything is scanned, so green still means the same thing over
  time. The image tag *is* the three pins, so a bump cannot ride an old image
  silently; `ci-image-scans.yml` republishes on a pin change.
- **The network problem this also removes.** Three downloads on every pull request
  were three chances per run at a failure that had nothing to do with this
  repository, and on 2026-07-24 that happened twice in one afternoon: `curl: (22)
  … error: 504`, half a second after checkout, with `make check-secrets` and `make
  sast` green locally on the same commit. With the scanners baked in there is no
  per-run download to fail; a superseded run still cancels rather than reporting
  failure. Both matter for one reason: a red tick on a security gate that is not a
  finding teaches you to ignore the next one.
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
  shallow clone of that same repository exits 0 twice. And the three scanner pins
  still live in the workflow's `env` block — no longer as download parameters (the
  download, sha256-verified against the published manifest, now happens once at
  image-build time in `scans.Dockerfile`) but as the *expected values* the
  fail-closed re-check asserts the baked binaries against. That `test -n "$SHA"` in
  the build-time verification earns its line, though not for the reason first given
  here (#800): the claim that `grep … | sha256sum -c -` passes *silently* on an
  empty match does not hold on GNU coreutils — measured on 9.5, and the image runs
  9.4 off the same codebase. An empty match ends in "no properly formatted checksum
  lines found" and exit 1. What the line buys is a readable failure: without it, a
  renamed release asset surfaces as a complaint about `sha256sum`'s *input*, and
  the reader debugs the verification instead of the asset name.
- **Counter-tested, because a scan job that sees nothing looks exactly like a
  clean repository.** With a randomly generated AWS-shaped key pair planted in
  the working tree, `make check-secrets` exits non-zero and names the leak; with
  the same pair only in history and the working tree clean, both history passes
  still fail.

### `.forgejo/workflows/static-gate.yml` — the static gate, per pull request
- **static-gate** — runs on the prebaked CI image
  (`pawprint.vigilis.online/librekat/ocideck-ci:flutter-<pin>`, same as
  `linux-gate.yml`), so the OS, node, build-toolchain and the pinned,
  sha256-verified Flutter (+ precache) are baked in — no per-run install. Only the
  repo-coupled artifacts (`~/.pub-cache` and the dartcv OpenCV build) stay on
  `actions/cache`. Then `flutter pub get`, [`make check-static`](#make-check-static)
  (`$(STATIC_GATES)`) **and `make check-registrations`** — the handful of *fast*
  registration/invariant tests (#1123). The image tag *is* the pin, so a stale
  image fails `check-toolchain` (fail-closed) rather than drifting silently — see
  the `ci-image.yml` section.
- **Why `check-registrations` too (#1123).** `check-static` catches the *static*
  drift (file/class/method size, formatting, hardcoded text) but the
  registration gates — new lib file in `SOURCE_MAP`, new docs registered, SBOM
  fresh vs `pubspec`, new `l10n.d` string translated, and (since #1208) the
  Windows installer still packaging what it claims to — **are tests**, so they
  ran nowhere before the merge and that class (e.g. `source_map_coverage_test`)
  could still land red. These five are plain tests (no widget render), seconds
  each, in the same job — so the required-check context stays
  `static-gate / static-gate`.
  The list in `REGISTRATION_TESTS` is hand-maintained: a new invariant *test*
  must be added there or it is a silent gap again. The full suite and the
  coverage floors still stay in `make check`.
- **Why it exists (#1118).** The release gate runs on a `v*` tag and the Linux
  gate only on demand, so between releases nothing held the static ratchets on a
  pull request. `main` drifted silently red — a run of merges pushed files,
  classes, a method and doc/coverage registrations past their ceilings, and it
  only surfaced when a later fix could not land on a green gate. This puts the
  fast half of the gate on the pull request, where an overrun is still an edit
  rather than history.
- **Why only the static subset.** The full suite and the coverage floors cost
  tens of minutes on this container — the very reason the gate moved to a tag
  (#796) — while the static gates are seconds each. The coverage floor and the
  per-file floor stay in `make check` on the committer's machine, before `main`;
  this workflow deliberately does not run them, and says so in its own header.
- **Why the Linux container, not the Mac.** Same trade as `scans.yml`: it fires
  on every pull request, and since #797 the Mac is both the release gate and the
  committer's working machine. In a container on the otherwise-idle server it
  takes no cores from a `make check` running on the Mac. `check-toolchain` runs
  unchanged inside `make check-static`, so the pinned official stable is enforced
  here too — a prebuilt Flutter image with channel `[user-branch]` would fail it,
  exactly as in `linux-gate.yml`.
- **A superseded run cancels** (`concurrency`, `cancel-in-progress`): the gate
  reads the whole tree at the newest commit, so a later run covers everything an
  aborted one would have seen.

### `.forgejo/workflows/web-gate.yml` — the web bundle, per pull request that can break it
- **web-gate** — on the prebaked CI image, same container and same two caches as
  `static-gate.yml`: `flutter pub get`, then [`make check-web`](#make-check-web).
  That is a real `flutter build web --release --no-web-resources-cdn --csp`
  followed by the three checks on the built bundle. The web engine artifacts are
  *not* baked into the image (`--no-web`) and are fetched during the build; that
  is a small download.
- **Why it exists (#1888-tail).** `make check-web` is the only check that looks
  at a *built* bundle, and it lived in `check-full` on the committer's machine
  and in `release.yml` on a `v*` tag. Between those two, nothing ever built the
  web. #1888's dotfile sweep kept only what `releaseArtefacten` names — a list
  describing what the packing step *adds*, not what the bundle *contains* — and
  the two dotfiles that belong there come from `web/`, copied by `flutter build
  web`. So `build/web/.htaccess` (header-form hardening, #849) and
  `build/web/.well-known/security.txt` (the RFC 9116 reporting address) stopped
  being shipped. The first machine to notice was phase 1 of the release chain,
  weeks after the merge, and it aborted the v0.5.0 release. Every gate was green
  the whole time.
- **Two layers, on purpose.** `test/pack_web_release_test.dart` mirrors the real
  `web/` tree into a stand-in bundle and runs in `make check` — cheap, per
  commit, but still a simulation of building. This workflow does the real thing
  once, on the changes that can break it, with the same command the tag will
  run. Neither replaces the other: the test catches the logic, the workflow
  catches what only a build shows (an asset that does not survive, a plugin with
  no web implementation, a loader the pin changed).
- **Why a path filter, and what is on it.** The build costs minutes and an
  ordinary Dart change cannot reach the bundle. It fires on `web/**`, the three
  `tool/` scripts `check-web` runs, the `Makefile` (it holds the hardening
  flags), `pubspec.yaml`/`pubspec.lock`, `.tool-versions` and
  `.forgejo/ci-image/**` — and on itself, so a change to the gate re-runs it.
  `docs/**` is deliberately **absent**: the bundled-docs check exists for
  *incremental* builds, and CI always builds clean.
- **The filter is itself guarded.** `test/web_gate_triggers_test.dart` parses
  this file and asserts, per trigger, that every input is on the list — with the
  reason for each one, so a later reader can judge before removing it. A gate
  that no longer fires guards nothing, and that is exactly how `.tool-versions`
  once fell off `linux-build.yml`'s filter. It checks `pull_request` and `push`
  **separately**, and that the two lists have not drifted apart: a substring
  search over the file would pass while one trigger had quietly lost an entry.
- **Deliberately not a required check.** Branch protection waits for every
  context it requires. A required check with a path filter never reports on a
  pull request that does not match it, so that PR hangs pending forever. Keep
  `web-gate` out of `status_check_contexts`; `static-gate` and `scans` are the
  required, unfiltered gates. Red here still stops a merge in practice — it is
  simply not the mechanism branch protection blocks on.
- **It also fires on `push` to `main`**, for the same reason `static-gate` does:
  a PR run tests the *preview* of one merge, and two bundle-touching PRs landing
  together can each be green while the result is not.
- **A superseded run cancels** (`concurrency`, `cancel-in-progress`): it builds
  the whole bundle at the newest commit, so a later run covers everything an
  aborted one would have seen.

### `.forgejo/workflows/linux-gate.yml` — nightly `schedule` **and on demand** (`workflow_dispatch`)
- **gate-linux** — the gate that `ci.yml` used to be, now on the prebaked CI
  image (`pawprint.vigilis.online/librekat/ocideck-ci:flutter-<pin>`, same as
  `static-gate.yml`): the OS, node, build-toolchain and the **official**,
  sha256-verified pinned Flutter (+ precache) are baked in, so there is no per-run
  install. `~/.pub-cache` and the dartcv OpenCV build stay on `actions/cache`. Then
  `flutter pub get` and `make check-no-coverage`. Provenance is unchanged — the
  sha256 check moved to image-build time — and `check-toolchain` still runs on the
  baked Flutter, so a *prebuilt third-party* image (the cirruslabs one shipped
  channel `[user-branch]`) still falls over on it; our own image carries only the
  pinned stable release. The tag *is* the pin, so a stale image fails fail-closed.
- **When to press it:** before a release, and whenever a change touches paths,
  subprocesses or `git` invocations.
- **Why it runs at all:** `static-gate.yml` runs the static gates per PR but
  **not** the test suite, so a registration gate that is *a test*
  (`source_map_coverage_test`, the docs-registration, SBOM and l10n invariants)
  could land red on `main` — and between releases nothing else runs the full
  suite. One scheduled run on the tip keeps `main` from sitting **silently**
  red. It is a **detection** net, not prevention: no merge is blocked. The
  coverage floor still stays out (`check-no-coverage`); it belongs on the
  committer's machine (see above).
- **Why nightly and not per merge, measured 2026-09-03.** This trigger has moved
  twice and both times for the same reason: this gate is the most expensive
  tenant of the slowest runner. #1123 also ran it per PR — the suite twice per
  change, the PR run being the expensive one — and that was reverted. What
  remained was `push: [main]`, one full run per merge, and the numbers do not
  carry it. At 7.6 merges a day against a median of 51 minutes it cost about
  **6.5 hours of runner time a day** on a capacity-1 runner. What it returned
  over 24 days: **zero** product regressions; **one** genuinely red `main` (a
  test left stale by #1777, which also failed on macOS and Windows, so a local
  `make check` caught it just as well); and **twelve** alarms about tests that
  guessed at time instead of waiting for a condition. That last class was real
  and only visible because this machine is slow — but #1911 put a ratchet on
  `Future.delayed` in `test/` over it, so it is now stopped at the source.
- **What the change costs, hardop.** Attribution. A red night points at the
  commits of that night instead of at one merge. That is cheap to recover — the
  failing test names itself and there are only a handful of commits — and it
  buys back the queue: this gate shares one host with the capacity-4 lane, so
  while it runs the `static-gate` runs that *are* needed per PR wait behind it,
  and with `block_on_outdated_branch` on, a green PR base ages faster the longer
  that queue is.
- **Concurrency.** Scoped by event, so a manual dispatch and the nightly run
  never cancel each other. `cancel-in-progress: false` (#1890) stays: an aborted
  run reports as "failure / Has been cancelled" rather than "skipped", and those
  hide real failures. Since the trigger moved off `push`, runs no longer stack
  in the first place.
- **How long the run itself takes, measured 2026-09-03** against `action_run` on
  the forge, over the 61 runs of the ten days before the trigger moved: a median
  of **51 minutes**, **66** at the 90th percentile. That is roughly double what
  it was — over the ten days before those, the median was 29 minutes — and it
  stepped up around 2026-08-23 without this workflow changing. CI run volume *fell* over
  the same period, so host contention does not explain it; the cause is in the
  tree and has not been traced to a commit. **This claim decays while the tree
  stands still**: the suite grows, the runner does not, and no gate measures the
  duration itself. `make check-dated-claims` guards that the claim carries a
  date and that this paragraph has not been rewritten out from under the
  register — it cannot tell you the number is still true. Re-measure rather than
  trust it.

### `.forgejo/workflows/ci-image.yml` — the prebaked Linux CI image (`workflow_dispatch` + on pin/Dockerfile change)

The three Linux workflows above each run in a bare `ubuntu:24.04` and rebuild
the same environment every run: install the apt build-tools, fetch and unpack
the official Flutter, precache the Linux desktop artifacts. That is identical
work with an identical result — so it is baked once instead of repeated. This
workflow builds `.forgejo/ci-image/Dockerfile` and pushes it to the project's
own Forgejo registry as
`pawprint.vigilis.online/librekat/ocideck-ci:flutter-<pin>`.

- **What the image carries:** the *slow-changing* toolchain — the OS, the fixed
  apt `.deb` list, the pinned Flutter (official stable, sha256-verified **at
  build time** against the release manifest), and `flutter precache --linux`.
  What it deliberately does **not** carry: the repo-coupled artifacts (pub
  packages, the dartcv OpenCV build), which move with `pubspec.lock` and stay on
  `actions/cache` in the gate workflows — a toolchain image must not need a
  rebuild on every dependency change.
- **Provenance is unchanged.** The sha256 verification the gates did at download
  time moved into the image build; `check-toolchain` still runs *in the gate* on
  the baked Flutter and still demands channel `stable`, official origin and
  equality with the pin. An image carrying anything else falls over on the same
  gate that once rejected the cirruslabs image.
- **Pin coupling.** The Flutter version is a build-arg read from `.tool-versions`,
  and the image tag *is* that version (`flutter-<pin>`). A pin bump publishes a
  new tag; the workflow fires automatically on a change to the Dockerfile or
  `.tool-versions`, so the image cannot silently lag the pin. The gate workflows
  reference that same tag (see the follow-up that switches them over).
- **Trust boundary.** Same as the runner and the existing `actions/cache`: our
  own job builds the image on our own runner and pushes it to our own registry —
  no new party.
- **One-time setup** (either route): for the workflow, a repo secret
  `CI_IMAGE_TOKEN` (a Forgejo token with `write:package`) **and** a repo variable
  `CI_IMAGE_USER` (the token owner's login — the workflow logs in as that user,
  not as whoever triggered the run); **or** `make ci-image-publish` from a machine
  with docker/colima (it uses your own `docker login` and cross-builds
  `linux/amd64`, since the runner is amd64). Then set the published package to
  **public** so the gate workflows can pull it without credentials (fase 2 may
  instead configure pull-credentials on the runner — see below). Until the image
  exists and the gates are switched over (a separate PR), the gates keep
  installing the toolchain per run as before — introducing the image cannot break
  CI on its own.
- **Reaching the daemon from inside the job.** These publish jobs run *inside*
  the dind sidecar, on a per-run `WORKFLOW-<hash>` network whose gateway **is** the
  dind daemon (it listens on all interfaces). That address differs per run, so it
  cannot be written down in advance — and `DOCKER_HOST` is not a usable channel
  either: the runner config injects
  `runner.envs.DOCKER_HOST=tcp://docker-in-docker:2375`, and that injection
  **overrides** a job-level `env:`. The alias itself only exists on the *outer*
  compose network, so every docker call died on
  `lookup docker-in-docker … no such host`. That is why this workflow had never
  once gone green and both images have always been published by hand — a gap that
  only surfaced when a release stalled on it. The job now reads its own default
  gateway (`ip route`) into a step output and passes it as `-H` on every docker
  call: a CLI flag beats the environment, whatever the runner injects.
  `test/ci_image_docker_host_test.dart` keeps a bare `docker` call from creeping
  back in.
- **Two conditions the follow-up (fase 2) must honour** (raised by the
  kernwaardenbewaker on #1141): (1) **continuity** — a `container: image:` pointing
  at the registry is a hard dependency; a registry outage or an accidentally
  *private* package would stop the gate job from starting, where fase 1 needs no
  registry. Fase 2 must degrade to per-run install (or configure runner
  pull-credentials so *private* still works), not to a blocked CI. (2)
  **single-source pin↔tag** — an `image:` field cannot interpolate the pin at
  runtime, so the tag is hardcoded in the gate workflow; a pin bump must update
  `.tool-versions` **and** the gate tag in the same commit, and the ordering must
  ensure `ci-image` has published the new tag before a gate tries to pull it, so a
  bump cannot race `main` red.

### `.forgejo/workflows/ci-image-scans.yml` — the prebaked scan image (`workflow_dispatch` + on pin/Dockerfile change)

The sibling of `ci-image.yml`, for the *scanner* image rather than the Flutter
toolchain. `scans.yml` ran on a bare `ubuntu:24.04` and rebuilt its environment
every pull request — apt tools plus three scanners fetched from the net. This
workflow bakes those into
`pawprint.vigilis.online/librekat/ocideck-scans:<pins>` and pushes it to the
project's own Forgejo registry from `.forgejo/ci-image/scans.Dockerfile`.

- **Why a second image and workflow, not a job added to `ci-image.yml`.** `on.push.paths`
  is per workflow, not per job. One workflow carrying both images would rebuild the
  scanner image on every Flutter bump and the toolchain image on every scanner bump.
  Two files keep each trigger sharp: an image rebuilds only when *that* image changes.
- **What the image carries:** the three scanners — gitleaks and trufflehog
  (release tarballs, sha256-verified **at build time** against their published
  manifests) and semgrep (a pinned pip venv). No repo-coupled artifacts, so a
  dependency change never rebuilds it.
- **Why baking is defensible here where an `actions/cache` was refused.** See the
  `scans.yml` section: the cache objection was that it removed the sha256
  verification with no re-check. Baking keeps the verification (moved to build
  time) *and* adds the re-check `scans.yml` runs in the gate — *"baked scanner
  versions == the pins"*, fail-closed, the equivalent of `check-toolchain`.
- **Pin coupling, single-source.** The three versions are read at build time from
  `.github/pinned-ci-versions.json` — the one manifest `check-pins` monitors for
  staleness and `pinned_versions_manifest_test` keeps equal to the `env` block in
  `scans.yml`. They are **not** written into this workflow as `*_VERSION:` lines
  (that would be an unmonitored second copy); it reads them with `jq`. The image
  tag *is* the three pins (`gl<gitleaks>-th<trufflehog>-sg<semgrep>`), so a bump
  publishes a new tag, and the workflow fires automatically on a change to the
  Dockerfile or the manifest — the image cannot silently lag the pins.
- **Trust boundary and one-time setup** are identical to `ci-image.yml`: our own
  job builds on our own runner and pushes to our own registry; it needs the same
  `CI_IMAGE_TOKEN` secret and `CI_IMAGE_USER` variable, or the manual route
  `make ci-image-scans-publish` from a machine with docker/colima. Set the
  published package to **public** so `scans.yml` can pull it without credentials.
  The publish guard skips green when the token is absent, so adding this cannot
  turn `main` red before the one-time setup is done.
- **Publish the image once by hand when you introduce or re-point it — Forgejo
  will not do it for you (#1168).** A newly added `push`-triggered workflow does
  **not** run on the commit that introduces it, so merging the PR that adds this
  image (or bumps the pin so the tag changes) does not build the image. Until you
  **dispatch `ci-image-scans.yml` manually** (or run `make ci-image-scans-publish`),
  the tag `scans.yml` references does not exist, and every pull request built on
  that `main` fails in seconds with `docker pull … not found`. This is exactly how
  #1150 left the scan gate red for a day — branches predating it still ran the old
  per-run install and passed, which disguised a hard breakage as a ~50% flake
  (#1168). After the first publish, pin bumps *do* rebuild automatically, because
  the `push` trigger covers `.github/pinned-ci-versions.json`. The same one-time
  dispatch applies to `ci-image.yml`.

### `.forgejo/workflows/linux-build.yml` — on demand, **and after a merge that can break the native build**
- **build-linux** — same official pinned toolchain as the gate, plus the GTK
  build dependencies; `flutter build linux --release`, then
  `check_bundled_docs_fresh.dart build/linux` (the same freshness gate
  `check-web` runs — a persistent runner's incremental build must not ship docs
  older than `docs/`), and uploads the bundle as the `ocideck-linux-x64` run
  artifact. This is a build, not a gate: it proves the Linux target compiles and
  packages, nothing more. #790 took it off every push to `main` — 17.5 minutes
  of runner time per merge, while `release.yml` on the mirror builds all three
  platforms on every `v*` tag anyway. That argument held for the *packaging* and
  not for the *building*: no gate builds a desktop app, so a native break first
  surfaced at tag time, which is exactly how `v0.4.9` ended up with no release
  (see [`make check-linux-deps`](#make-check-linux-deps)). It therefore runs
  again after a merge to `main`, but only when `pubspec.yaml`, `pubspec.lock`,
  `.tool-versions`, `linux/`, `third_party/` or the CI image changed — the
  inputs that can break a native build. Ordinary Dart work does not trigger it.
  Start it by hand when you want a bundle without cutting a tag.

### `.forgejo/workflows/macos-build.yml` — on demand, **and after a merge that can break the native build**
- **build-macos** — runs on a registered **Mac** runner (`runs-on: macos`,
  host mode), not on the server: Apple licenses macOS for Apple hardware only,
  so there is no macOS job the Linux server could legitimately run. The job
  uses the Mac's own pinned toolchain (the one `check-toolchain` already
  guards), builds `flutter build macos --release`, then runs
  `check_bundled_docs_fresh.dart build/macos` (the persistent Mac runner is
  exactly where an incremental build could carry stale docs), and uploads the
  `.app` (zipped with `ditto`, which preserves what a plain zip destroys) as the
  `ocideck-macos` run artifact. Like the Linux build it also runs after a merge
  to `main` that touched `pubspec.yaml`, `pubspec.lock`, `.tool-versions`,
  `macos/` or `third_party/` — the same reasoning, the same failure it prevents.
  When no Mac runner is online the run waits.

### `.forgejo/workflows/toolchain-rehearsal.yml` — on a pull request that changes `.tool-versions`
- **rehearsal** — dispatches the mirror's full `ci.yml` against *this branch*
  and waits for it, so a Flutter bump is rehearsed on all three platforms
  **before** the merge instead of discovered at tag time. The forge's own gates
  run `flutter test` on Linux and macOS; they build nothing and they never see
  Windows. A toolchain bump is the one change that can break the build on all
  three at once — a different compiler, a different engine, different generated
  build files — so it is the one change worth an hour of mirror CI up front.
- It uses the same `GH_DISPATCH_TOKEN` the release chain uses to start the
  Windows build. A pull request from a fork has no secrets: the job then warns
  and exits 0 rather than turning red for something the contributor cannot fix.
- **Advisory, not a lock.** Branch protection on `main` requires
  `static-gate` and `scans` (#1891). This run shows up as its own status and
  fails visibly.

### `.github/workflows/windows-native-check.yml` — after a merge that can break the native build
- **build** — `flutter build windows --release` on the mirror, with the pinned
  toolchain, when `pubspec.yaml`, `pubspec.lock`, `.tool-versions`, `windows/`
  or `third_party/` changed. Windows is the platform with no machine on this
  forge, so without this the first Windows build of a change was the release
  chain — and Windows has the same history as Linux here (an MSVC clash with
  dartcv4's prebuilt OpenCV once forced a `windows-2022` pin, #870).
- It builds and throws the result away: this is a check, not a delivery. The
  bundle users get still comes from `release.yml`, on a tag.

The three path filters are themselves guarded by
`test/native_build_triggers_test.dart`: a build that no longer fires guards
nothing, and that must not be able to happen quietly. `.tool-versions` is on
every list because a *bare* pin bump touches neither pubspec file.

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
  used in [`linux-gate.yml`](#forgejoworkflowslinux-gateyml--nightly-schedule-and-on-demand-workflow_dispatch)
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
  its hardening invariants, that the release artefacts travel with it and
  `SHA256SUMS` still matches, and that the bundled documentation in the build is
  byte-for-byte fresh against `docs/`.
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

CI pins **Flutter 3.47.1 (stable)**, recorded in `.tool-versions` (asdf) and in
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
| Maintainer machine (macOS arm64) | `3.47.1 • stable • https://github.com/flutter/flutter.git` | matches |
| CI (GitHub Actions, all jobs) | `3.47.1 • stable • https://github.com/flutter/flutter.git` | matches |

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
