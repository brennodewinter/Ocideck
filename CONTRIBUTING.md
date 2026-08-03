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

**Sign off every commit.** This project uses the
[Developer Certificate of Origin](dco.txt): a short, standard statement that you
wrote the change, or have the right to submit it, under the project licence. You
certify it per commit by adding a `Signed-off-by` line, which `git` writes for
you:

```bash
git commit -s
```

The line must carry your real name and an email you can be reached at
(`Signed-off-by: Jane Doe <jane@example.org>`). That is the whole ceremony —
no separate agreement to sign, no account, no CLA. Missing the sign-off is the
one thing that will hold a pull request even when the code is fine; `git commit
--amend -s` or `git rebase --signoff` fixes a branch after the fact.

*(Adopted 2026-07-23, #594. A sentence in a document was the weakest contributor
agreement the open-source world recognises and left no per-commit record; the
DCO is the lightest thing that fixes both, and it is what `AUTHORS.md` now
relies on when it says contributors keep copyright in their own work.)*

## Prerequisites

- **Flutter 3.44.8** (stable), from the official channel, using the `dart`
  bundled with it. `.tool-versions` pins it, `make check-toolchain` enforces it,
  and the rule is deliberately strict: the exact version, channel `stable`, and
  the SDK's repository must be `https://github.com/flutter/flutter.git`.

  **One Flutter per machine, not one per project.** Install it in `~/flutter`
  from the archive published by `storage.googleapis.com/flutter_infra_release`,
  and verify the SHA-256 against that channel's own `releases_*.json` before
  unpacking. Do not use the Homebrew cask: it reports a different version number
  in `--version` than in its own install path, and if it sits earlier on `PATH`
  it silently shadows the SDK you meant to use. That is not hypothetical — it is
  what #598 turned out to be.

  **The pin follows the latest stable, not the other way round.** When a newer
  stable is released, the SDK is upgraded and then every pin moves with it:
  `.tool-versions`, `README.md`, [`docs/BUILD.md`](docs/BUILD.md), this file,
  and both workflow files. Then the gate is re-run, because `dart format`
  reflows whitespace between releases — that reflow is the pin's one real
  symptom, and it shows up as `make format-check` failing on files you never
  touched.

  *Tightened 2026-07-23 (#598). Between 22 and 23 July this read "3.44.x", on
  the reasoning that demanding an exact version was stricter than the
  maintainer's own machine met. That was solving the wrong problem: the answer
  to a maintainer machine on an unreproducible build is to fix the machine, not
  to relax the rule for everyone else. The machine now runs the pinned official
  stable, so the rule can be what it should have been.*
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

Run this before every push — it is the enforced quality gate. The Forgejo remote
*has* an Actions runner, but since #790 it runs the *full* gate on a `v*` tag
rather than per pull request: a CI run cost 22 minutes there against 2.5 minutes
here. So the full gate — the test suite and the two coverage floors — runs
nowhere for you between your branch and `main`. If it fails at tag time, the
problem already landed.

Two things *do* run on every pull request. The secret and SAST scans
(`.forgejo/workflows/scans.yml`, #778) take seconds, and for a credential the
moment is not interchangeable — found before the merge it is an edit, found
after it is in the history. And since #1118 the **static gates** run too
(`.forgejo/workflows/static-gate.yml` → `make check-static`, the fast static
half of `make check`), because otherwise those ratchets drift silently red on
`main` between releases. Both are additions to your local run, not a replacement
for it — the coverage floors still run only here.

```sh
make check            # format-check + analyze + conventions + full test suite + coverage floor
```

Individual steps:

| Command | What it does |
| --- | --- |
| `make format` | Rewrites Dart files with `dart format`. |
| `make format-check` | Fails if any file needs formatting. |
| `make analyze` | `flutter analyze --fatal-infos` (analyzer + lints + strict type checks). |
| `make check-conventions` | No `print()`; no raw control bytes; the bare `catch (_)`, raw-colour, layering, file-size and class-size ratchets may not grow. |
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
  the source; all 31 other languages need an entry). Rather than hand-editing 31
  files, write the translations into a small JSON spec and run
  `make add-l10n SPEC=…` — it inserts them into each language's additions overlay,
  `dart format`s the result, skips anything already present, and whitelists any
  `"unchanged"` loanwords (see `tool/add_l10n.dart` for the format). Validate with
  `make l10n-check`. A loanword kept identical in every language (e.g. `Heatmap`)
  goes in the spec's `unchanged` list instead of being translated.

  **If you are not the maintainer, you are not expected to produce 31
  translations.** The list includes Maltese, Irish, Frisian, Papiamento, Latin
  and Klingon; nobody has all of those. **Supply Dutch and English, leave the
  other 30 blank, and say so in the pull request — the maintainer fills them in
  before merge.** The gate is non-negotiable about the *end state*, not about
  who does which part of it. *(Added 2026-07-22: this was the single rule most
  likely to turn a first contribution into a last one, because a contributor met
  it as a failing build rather than as a stated division of labour. The count
  "30 other languages" was also stale since the 32nd language landed.)*

  **Correcting one language is a different job, and it has its own route.**
  Everything above is about *adding* a string. If you are a native speaker who
  wants to fix wording that is wrong, clumsy or machine-flavoured, you do not
  need Dart and you do not need the other 30 languages:

  ```bash
  make l10n-export LANG_=ga OUT=my-irish.json   # 2,261 strings, flat JSON
  # …edit the values in any editor. The keys are the Dutch source sentences,
  # so you always see what you are translating.
  make l10n-import LANG_=ga IN=my-irish.json    # writes them back, formatted
  ```

  (`LANG_`, not `LANG` — make inherits your shell's environment, and `LANG` is
  almost always already set to your locale.)

  A pull request that touches **one** language file and adds no keys is welcome
  on its own; it does not need to wait for anything else. The importer refuses a
  file that introduces an unknown key, on purpose — a new string belongs with
  the code that uses it and must land in all 31 languages at once, which is what
  `add_l10n.dart` enforces. *(Added 2026-07-22, #633: the strings live in 32
  Dart `part` files of roughly 3,000 lines each, and that was the whole barrier
  — it pushed away exactly the contribution this project needs most, native
  review of 31 languages, and toward more machine translation.)*
- **Comment language: Dutch or English, but never both in one comment.**
  *(Gated since 2026-07-23, #518: `make check-comment-language`, a ratchet
  (`mixedCommentBaseline`). It covers plain `//` comments only — see below for
  why dartdoc is out.)*
  The codebase is bilingual and stays that way. Measured over `lib/` (2026-07-22):
  of the ~3,100 comment blocks of three lines or more, 71% are Dutch, 28% are
  English, and **1% mix the two inside a single block**. So the convention the
  code already follows is not "one language for the project" but "one language
  per comment": pick the one that fits, and finish the thought in it.
  - Dutch is the working language and the default for new comments — the
    reasoning, the commit messages and the design documents are Dutch, and a
    *why* is easier to write well in the language you think in.
  - English is equally acceptable, and is the natural choice where the
    surrounding vocabulary is English anyway: a reference to a spec or standard,
    a file whose comments are already English.
  - **New public types in `lib/models/` and `lib/services/` get English
    dartdoc.** That is the layer `dart doc`, pub.dev and the IDE hover show —
    the only part of this codebase an outsider reads without reading the code.
    The rule is deliberately about *new* types and those two directories.
    Measured on 2026-07-22, 278 of the 484 documented public types across
    `lib/` lean Dutch, and translating them is explicitly forbidden by the rule
    below; a clause claiming otherwise would describe an intention rather than a
    practice. *(Corrected 2026-07-22: this said English was "the natural choice"
    for "API doc comments on a public type", which read as a rule the tree does
    not follow. No automated ceiling enforces the new rule yet — a language
    heuristic that is wrong 5% of the time is a worse gate than none.)*
    *(2026-07-23, #518: that judgement stands for this clause and is why
    `check-comment-language` skips dartdoc entirely. Measured over `lib/`, an
    English summary line above Dutch reasoning is 37 of 47 raw hits — it is the
    form this very clause asks for, so a gate that flagged it would be fining
    the guide. The mixing rule above is a different question and is gated: it
    only speaks when both languages are unmistakably present.)*
  - **Do not rewrite existing comments only to change their language.** That is
    thousands of lines of pure noise, it changes no behaviour, and it puts your
    name on every line of `git blame` for reasoning somebody else worked out.
    When you edit a comment, follow the language of the block you are editing.
  - This says nothing about *identifiers*, which are English throughout, or
    about user-visible text, which has its own rule (see localization above).
    *(True since 2026-07-22, #636. `SlideCategory` carried Dutch values —
    `algemeen` and `informatieveiligheid` — forty lines below `SlideType` in
    `lib/models/slide.dart`, the first file anyone opens to understand the data
    model. It was the one place this sentence was demonstrably untrue, which
    cost the rest of an otherwise accurate paragraph its authority. Renaming was
    safe because the enum is never serialised; after publication it would have
    been a breaking change for everyone with a branch open.)*
- **Tests**: add or update tests for behaviour you change — especially the
  Markdown round-trip and any file-format change.
- **New top-level surfaces get an overflow-stress entry.** A `RenderFlex`
  overflow surfaces only when a widget is actually laid out too small, so a
  screen that no test pumps at an extreme size can overflow unseen. When you add
  a top-level screen, dialog or panel, register it in
  [`test/overflow_stress_test.dart`](test/overflow_stress_test.dart): one entry,
  and it is rendered against several demanding viewports (narrow, short) at the
  200% interface-text ceiling (WCAG 1.4.4), failing on the first overflow. *(Added
  2026-08-03: the welcome screen reached `main` overflowing by 266px at 200% text,
  because it slipped in through a direct push that bypassed the pull-request gate.
  The stress gate closes that class of bug — but only for the surfaces that are
  registered, so registering yours is the whole point.)*
- **File format**: if you change how anything is stored, update
  [`docs/FILE_FORMAT.md`](docs/FILE_FORMAT.md) in the same change.

## Proposing changes

1. Fork <https://pawprint.vigilis.online/LibreKAT/Ocideck> and branch from the
   default branch; keep each branch/PR focused on one topic. (Registration on
   the forge is open. If you have push rights you can branch directly, but the
   fork route is the one an outside contributor takes.)
2. Write clear commit messages (imperative subject, a short body explaining the
   *why*).
3. Make sure `make check` is green.
4. Open a pull request describing the change and linking any related issue. Fill
   in the PR template checklist.

## Who reviews this, and who does not

*Added 2026-07-22. Written down because a reader deserves it before relying on
this project, and because a checklist that hides its weakest row teaches you to
distrust the rows that are true.*

**There is one active maintainer.** [`AUTHORS.md`](AUTHORS.md) lists one person
under Contributors, and that is accurate. Changes are merged by their author.
There is no CI runner on the forge, so the checks below run on the maintainer's
machine and nowhere else. That is a bus factor of one, and it is the largest
single risk in this project — larger than anything a scanner has reported.

**What stands in for peer review**, and it is not nothing:

- `make check` must be green before a merge: analysis with `--fatal-infos`, the
  full test suite, conventions, method length, file and class size, dead code,
  the privacy projection boundary, a coverage floor and a per-file coverage
  floor. See [`docs/CHECKS.md`](docs/CHECKS.md).
- The ratchets only move one way. A baseline that is allowed to grow is not a
  baseline, and several of them are at zero.
- `make sast` and `make check-secrets` exist as separate gates.
- **Mutation testing is narrower than the word suggests, so here is its exact
  scope.** `tool/mutation_check.dart` applies **one** operator — it negates each
  `String.startsWith` / `.endsWith` predicate — and `make mutate-parsers` points
  it at **seven files**, the Markdown parsers and serialisers. There are 309
  such predicates across 96 files in `lib/`. There is no condition, boundary-value
  or return-value mutant. It is manual and not part of `make check`. Last run
  2026-07-22: **51 mutants across all seven files, no survivors.** *(Added
  2026-07-22: this line called mutation testing a "gate" without qualification,
  which invites the reader to upgrade the 86.2% line coverage into evidence of
  assertion strength that one operator over seven files does not provide.)*

  *Corrected 2026-07-22 (#660): the previous run reported 26 mutants and one
  survivor. Both numbers were an artefact. The sweep ran one `make` line per
  file and therefore stopped at the first failure, so five of the seven files
  never ran — "26 mutants" was a count of the part that got as far as running.
  The survivor itself was not dead code either: the `ocideck_checklist_scope:`
  predicate is covered, by `test/checklist_spec_test.dart`, which was not in
  the list of tests that sweep re-ran. The target now runs all seven and fails
  at the end, so the number is the whole picture rather than the prefix before
  the first problem.*
- Everything lands through a pull request with a written description, so the
  reasoning is reviewable after the fact even when nobody reviewed it before.

**None of that is four eyes, and it is worth saying so precisely because it is
not the same thing.** A machine reviews what a machine can review. It does not
notice that a design is wrong, that a promise in the interface overstates what
the code does, or that a feature should not exist.

**The gap runs one way.** If *you* send a pull request, it is reviewed by a human
who is not its author — the maintainer. It is only the maintainer's own changes
that go in unreviewed. That asymmetry is worth knowing in both directions.

**What changes with a second maintainer.** Self-merge stops, and every change
needs a review by a non-author. That is not a policy waiting to be written; it is
the point at which the row above becomes tickable, and this section gets
rewritten rather than extended.

## Reporting bugs and requesting features

Use the issue templates in the [Forgejo tracker](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues). For **security issues, do not open a public
issue** — follow [`SECURITY.md`](SECURITY.md).
