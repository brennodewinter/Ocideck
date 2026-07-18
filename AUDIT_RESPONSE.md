# Audit response

A response to an external code audit of OciDeck, point by point. Each item is
weighed against what the codebase actually does, with the measurement that
supports the verdict. Where the audit found something real, the fix and its
commit are named; where the premise did not hold, the counter-evidence is
recorded so the same recommendation does not have to be re-litigated later.

The guiding constraint throughout was that no functionality may be lost. That
rules out several of the proposed changes on its own: a refactor that risks
behaviour to satisfy a metric which is already met is a net loss.

## Summary

| # | Audit point | Verdict |
|---|-------------|---------|
| 1 | Split `deck_provider.dart` (>2000 lines) | Premise incorrect — already 958 lines across 6 parts |
| 2A | No media caching; add LRU + lazy loading | Largely present; one real gap, fixed |
| 2B | 100+ dependencies; prune | Premise incorrect — 36 direct dependencies |
| 3A | `lib/` lacks structure | Already structured by domain |
| 3B | async/await vs callbacks inconsistent | No inconsistency found |
| 4 | No performance tests for large decks | **Valid — tests added** |
| 5A | Editor components need a wizard and tooltips | Tooltips present; wizard is a feature request |
| 5B | Missing keyboard shortcuts (Ctrl+S, Ctrl+Z) | Already implemented, plus a command palette |
| 6 | No explicit accessibility tests | **Valid — test added, 3 real defects fixed** |

## 1. State management — splitting `deck_provider.dart`

**Claim:** the file exceeds 2000 lines and should be split into
`slide_deck_provider`, `privacy_deck_provider` and `ai_deck_provider`.

**Measured:** `lib/state/deck_provider.dart` is 958 lines. It is already split
by domain into six files (`_ai`, `_auto`, `_checklist`, `_markdown`, `_miauw`,
plus `deck_quality_provider`), together 1332 lines.

**Verdict:** the premise does not hold, and the recommendation is already
implemented in substance. `tool/check_conventions.dart` caps files under `lib/`
at 1000 lines, so this is enforced continuously rather than left to review.

Splitting the remaining state across three *separate providers* is a different
proposal from splitting a file, and a costlier one: the deck is a single
consistency domain — undo/redo, the seal hash and the privacy projection all
read and write the same deck. Distributing that over three providers introduces
cross-provider synchronisation where there is currently one source of truth.
That trades a real risk of behavioural regressions for a structural change the
file-size metric does not ask for.

## 2A. Media loading and caching

**Claim:** media is loaded without an adequate caching mechanism; add an LRU
cache and lazy loading.

**Measured:** Flutter ships an LRU `ImageCache` and it is active by default, so
the recommendation is met by the framework. Decode hints — the part that
actually governs memory use — were already applied on the paths that render
many images at once: the picker grid decodes at 360px, the preview at 720px and
the full view at 1000px.

**One real gap, now fixed.** The evidence thumbnail in the findings editor
renders at 44 logical pixels while the underlying screenshot is typically
several thousand pixels wide, and it carried no decode hint — so the full bitmap
was held in memory. In a pentest report with dozens of evidence items this adds
up. It now decodes at 176px, four times its display width and therefore well
above any realistic device pixel ratio.

Signature images (`Image.memory`) were deliberately left alone: they are small
drawn PNGs where a decode hint saves little, and they serve as proof of signing,
so degrading them to save negligible memory would be the wrong trade.

## 2B. Dependency count

**Claim:** 100+ dependencies inflate memory use; analyse the tree and prune.

**Measured:** `pubspec.yaml` declares 36 direct dependencies. The 100+ figure
counts transitive packages, which are not independently removable — pruning them
means removing the direct dependency that pulls them in, along with its feature.

The dependency tree is already under continuous scrutiny: `make sbom` generates
a software bill of materials, `sbom_test` fails the build when a dependency
change is not reflected in it, and `make licenses` and `make trivy` audit the
same set. Dropping packages to lower a count, absent a specific package
identified as unused, would remove functionality — the one thing this work was
asked not to do.

## 3A. Directory structure

**Claim:** files under `lib/` are disorganised; create subdirectories for UI,
services and models.

**Measured:** `lib/` is already divided into `models/`, `services/`, `state/`,
`widgets/`, `theme/`, `utils/`, `platform/` and `l10n/`, and `widgets/` is
further divided into `editors/`, `dialogs/`, `panels/`, `slides/`,
`presentation/`, `shell/` and `markdown_editor/`. This is the proposed layout.

## 3B. Async consistency

**Claim:** some services use `async`/`await` while others use callbacks;
standardise on one.

**Measured:** 143 files use `async`/`await`. The callbacks that remain are
Flutter's widget callbacks (`VoidCallback`, `ValueChanged<T>`) — the framework's
own idiom for event handling, not an alternative style of asynchrony. No service
was found returning results through a callback where a `Future` was the
alternative. There is no inconsistency here to standardise, and rewriting widget
callbacks into futures would work against the framework.

## 4. Performance tests for large presentations — valid

No test exercised a deck beyond a handful of slides, and nothing in the suite
would have caught an algorithmic regression in the serialiser or parser.

`test/large_deck_performance_test.dart` now covers this:

- a 150-slide deck must round-trip without losing a single slide, checked on
  types, titles and — sampled at the tail of the deck, where a scaling bug would
  surface first — on bullet, column and table contents;
- serialising and parsing each stay within a generous time budget;
- parsing must not scale quadratically: 50 slides versus 200, with a threshold
  of 10× that sits well between linear (4×) and quadratic (16×).

The budgets carry roughly 70× headroom and each measurement takes the *minimum*
of several runs, which is robust against scheduling noise on a loaded machine. A
slower average means nothing; a slower minimum means something. The tests are
therefore a guard against catastrophic regressions, not a micro-benchmark that
reddens the build on an unlucky day.

## 5A. Editor usability

Tooltips are present: 198 across 67 files, including every action in the main
toolbar.

A wizard mode for new users is a reasonable product idea, but it is a new
feature rather than the correction of a defect, and it sits outside a change set
whose constraint is that no existing behaviour may shift. It belongs on the
roadmap, scoped and designed on its own terms.

## 5B. Keyboard shortcuts

**Measured:** already implemented in `app_shell_main_layout.dart` — save
(Ctrl/Cmd+S), undo (Ctrl/Cmd+Z), redo (Ctrl/Cmd+Shift+Z and Ctrl+Y), each bound
for both the Control and Command modifier. Beyond that the app has a command
palette (`dialogs/command_palette.dart`) and shortcut handling in the markdown
editor, find bar, presenter and slide rail.

## 6. Accessibility — valid, and it found real defects

There was no test asserting accessibility invariants. `test/accessibility_labels_test.dart`
now enforces the most basic and most easily broken one: **every button must have
an accessible name** (WCAG 2.2 SC 4.1.2). It walks the semantics tree of six
editors and fails on any node that reports itself as a button without a label or
tooltip. The test asserts *that* a name exists, not how it is provided, so it
does not constrain implementation. It also includes a self-test against a bare
`IconButton`, so a bug in the check itself cannot silently pass everything.

It immediately found three real defects. The paste, copy and clear buttons in
the image picker bar and the reset button on the zoom slider were wrapped in a
`Tooltip` widget instead of carrying a tooltip. Flutter attaches that tooltip to
a surrounding semantics node, so the button reached the screen reader with no
name at all, while the enclosing row was announced as "Afbeelding plakken uit
klembord". Switching to `IconButton(tooltip:)` attaches the name to the button
itself. Nothing changes visually, and the existing translated strings are reused
unchanged.

The wider WCAG conformance the audit mentions — contrast ratios, focus order,
reading order — is a larger programme than a test file. This establishes the
guard rail and fixes what it caught; it does not claim full conformance.

## Verification

The full suite passes: 3078 tests. The changes above are additive — two new test
files, three tooltip attachments and one decode hint — so no existing behaviour
was modified.
