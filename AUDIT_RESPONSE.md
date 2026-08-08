# Audit response

> **Status:** report; the response to two external audits, with measurements re-taken on 2026-07-22 · **Status last reviewed:** 2026-07-22 · **Published by:** Stichting LibreKAT

A response to the external code audits of OciDeck, point by point. Each item is
weighed against what the codebase actually does, with the measurement that
supports the verdict. Where the audit found something real, the fix and its
commit are named; where the premise did not hold, the counter-evidence is
recorded so the same recommendation does not have to be re-litigated later.

The guiding constraint throughout was that no functionality may be lost. That
rules out several of the proposed changes on its own: a refactor that risks
behaviour to satisfy a metric which is already met is a net loss.

> **The counts in this document are measurements, and measurements go stale.**
> They were re-taken on **2026-07-21** and corrected where the code had moved
> on: `deck_provider.dart` had shrunk from 958 to 744 lines (and gained a
> seventh companion), the direct dependencies had grown from 36 to 37, the files
> using `async`/`await` from 143 to 185, and the tooltips from 198 to 209. None
> of the verdicts changed — every premise the audit got wrong is still wrong —
> but a document that argues from numbers has to keep them true.

# Audit I — code quality and usability

## Summary

| # | Audit point | Verdict |
|---|-------------|---------|
| 1 | Split `deck_provider.dart` (>2000 lines) | Premise incorrect — already 744 lines across 7 files |
| 2A | No media caching; add LRU + lazy loading | Largely present; one real gap, fixed |
| 2B | 100+ dependencies; prune | Premise incorrect — 37 direct dependencies |
| 3A | `lib/` lacks structure | Already structured by domain |
| 3B | async/await vs callbacks inconsistent | No inconsistency found |
| 4 | No performance tests for large decks | **Valid — tests added** |
| 5A | Editor components need a wizard and tooltips | Tooltips present; wizard is a feature request |
| 5B | Missing keyboard shortcuts (Ctrl+S, Ctrl+Z) | Already implemented, plus a command palette |
| 6 | No explicit accessibility tests | **Valid — test added, 3 real defects fixed** |

## 1. State management — splitting `deck_provider.dart`

**Claim:** the file exceeds 2000 lines and should be split into
`slide_deck_provider`, `privacy_deck_provider` and `ai_deck_provider`.

**Measured:** `lib/state/deck_provider.dart` is 744 lines. It is already split
by domain into seven companions (`_ai`, `_auto`, `_checklist`, `_markdown`,
`_miauw`, `_slides`, plus `deck_quality_provider`), together 758 lines.

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

**Measured:** `pubspec.yaml` declares 37 direct dependencies. The 100+ figure
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

**Measured:** 185 files use `async`/`await`. The callbacks that remain are
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

Tooltips are present: 209 across 70 files, including every action in the main
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

The full suite passed when this response was written (3078 tests at that moment;
it has grown since, and `make check` is where the current number lives). The
changes above are additive — two new test files, three tooltip attachments and
one decode hint — so no existing behaviour was modified.

---

# Audit II — security and architecture (2026-07-21)

A four-stream review — architecture, code quality, static security, dynamic
security (DAST) — of `lib/`, the Python fetch-proxy and the web shell. It rated
one finding Critical, three High, thirteen Medium and six Low, and found **zero
exploitable defects** in live testing: the SSRF defence held against all 24
attack variants with a positive control ruling out a false pass.

Every finding was taken up. The table below is the ledger; the sections after it
give the reasoning where the verdict is anything other than "fixed".

## Summary

| ID | Finding | Severity | Verdict |
|---|---|---|---|
| AEG-01 | Redaction bypass on 7 scanned-but-unprojected fields | Critical | **Already closed** before the report landed — with the parity test the audit itself recommended |
| AEG-02 | RFC 3161 TSA signature not verified | High | **Partly fixed** (#1370) — CMS signature now verified against the embedded certificate; full X.509 path validation remains §8-A3 |
| AEG-03 | Fetch-proxy usable as an open relay when misconfigured | High | **Fixed** — release conditions in `docs/HOSTING.md` (#483); found an inverted claim in the proxy README on the way |
| U-01 | New slide type is shotgun surgery over ~56 switch sites | High | **Partly fixed** (#473, #486); the rest is deliberate — see below |
| X-02 | Redaction boundary thins below the entry points | Medium | **Fixed** (#472) — `export()` now takes an `ExportBundle`, `fromDeck` an `AudienceDeck` |
| X-03 | SSRF guard is 7 copies without a build guard | Medium | **Premise stale**; the residual per-file gap fixed (#471) |
| U-02 | Storage backends share no exception shape | Medium | **Deliberately not done** (#492) — no caller catches two; reasoning recorded in the code |
| O-01 | 182 service units, no cluster docs | Medium | **Fixed** (#488) — cluster headers, and four real gaps in SOURCE_MAP closed |
| O-02 | Settings god-provider | Medium | **Deliberately not now** — on the audit's own advice |
| AEG-04 | Media URL gate does not pin the socket | Medium | **Fixed** for images (#485); for video the window is documented, not closed |
| AEG-05 | RFC 3161 request carries no nonce | Medium | **Fixed** (#476), with an honest limit on in-app echo checking |
| AEG-06 | 4-hex commitment id collides | Medium | **Fixed** (#480) — ≥8 chars, growing on collision |
| K1.1 | Git-forge HTTP plumbing duplicated 3× | Medium | **Fixed** (#474) — 162 lines less |
| K1.2 | Hex→Color parser written 6× | Medium | **Fixed** (#487) |
| K1.3 | `PreviewScaffold` boilerplate repeated | Medium | **Fixed** (#479) — 8 previews; 4 deliberately left out |
| K2.1 | Enum `switch` with `default:` disables the compiler net | Medium | **Fixed** (#473) — from 8 to 13 guarded sites |
| AEG-07 | PBKDF2 iteration count is low (1000) | Low | **Already handled** — fixed by the WinZip AES spec, mitigated and documented |
| AEG-10 | AI output must be human-reviewed before sealing | Low | **Already covered** by a real test |
| AEG-11 | Content-Length trusted in the proxy stream | Low | No defect — the proxy counts bytes itself; the audit says so too |
| M-01 | Import direction rests on reviewers | Info | **Fixed** (#489) — hard zero in `check_conventions` |
| M-03 | UI imports inside `lib/services/` | Low | **Fixed** (#481) — ratchet from 8 to 4 |
| K1.4 | `_asFailure` duplicated (WebDAV/S3) | Low | **Fixed** (#490) — one shared transport-error classifier |
| K2.2 | Wide `Slide` value constructor | Low | Not done — the audit advises against it too |

## AEG-01 — the Critical finding was already closed

The audit is right about the mechanism and right that it mattered. It was also
already fixed when the report arrived: `privacy_projection.dart` projects all
seven fields (`version`, `date`, `standardsUsed`, `toolsUsed`, `miauwWaivers`,
`miauwConfirmations`, `checklistScope`).

Worth recording is *how*, because the audit offered two options and the code took
the robust one. `test/privacy_scan_redact_parity_test.dart` puts all three
hand-written field lists — the scanner's fragments, the projection, and the
redaction manifest — side by side. Add a field to the scanner without adding it
to the other two and the test goes red **naming that field**. The audit's
sentence "there is no test that stops this" is the one line of its report that
was already out of date.

## X-03 — the premise was stale, the gap underneath was real

The audit reports "no build guard against a forgotten 8th egress site". There
is one, and it is broader than the proposal: `test/network_sink_guard_test.dart`
scans for `HttpClient`, `package:http`, `dio`, and raw `Socket`/`SecureSocket`/
`WebSocket`/`RawDatagramSocket`.

What the audit's instinct did catch is a blind spot in that guard's *shape*: the
allowlist is per **file**, so once `webdav_service.dart` is on it, a second,
unpinned client inside that same file slips past. The allowlist proves "this file
knows about the gate", not "every client in this file goes through it". Proving
statically that an instance receives a `connectionFactory` is not possible —
`local_cve_database_io.dart` constructs in `getJson` and pins in `_get`, and that
is legitimate. So the *count* per file is now a ratchet (#471), tested in both
directions: zero on the repo, red on a planted extra client.

## U-01 — partly fixed, and the rest is deliberate

Two things the audit could not weigh:

**The silent-failure half is largely gone.** Six enum switches carrying
`default:` were written out (#473). A planted 25th slide type now produces a
compile error in **13** places where it produced 8. What remains is workload, not
risk.

**The registry cannot carry UI behaviour.** `slideTypeMeta` lives in
`lib/models/slide.dart`, and `modelUiImportBaseline = 0` is a hard zero: a model
may not import Flutter. A `buildPreview` hook there is impossible without
breaking a boundary that is worth more than the convenience.

So the work went where the compiler *cannot* see (#486): `backedByTable` replaced
a hand-written set in the parser that duplicated a case group in the serializer —
the silent trap the project's own slide-type checklist warns about — and
`bulletColumns` replaced three copies of "can this bullet slide be split". The
third copy, in `slide_thumbnail.dart`, was a `switch` with `_ => false`: a new
bullet type would have been silently unsplittable there, so the split action
appeared in the panel but not on the card. That was a latent defect, found by
looking where the audit pointed.

The 11 remaining switches are genuinely type-specific — the renderer, the
wireframe drawing, the help text, the writer, three fit-scale functions, contrast
pairs, media fields. Tabulating those yields an equally long table and nothing
safer.

## AEG-02 — CMS signature verified against embedded certificate

The audit offers "verify in full, or degrade the claim explicitly". The claim was
already degraded, and consistently: the seal dialog states that the TSA signature
is not verified in-app and deliberately shows no green "verified" badge; the
audit dossier records `genTime` as a *claim*; `FILE_FORMAT.md` says the check is
an imprint comparison only.

Sinds #1370 verifieert OciDeck de CMS-handtekening van de TSA tegen het
certificaat dat in het token zelf is ingebed (`verifyTimeStampSignature` in
`lib/services/rfc3161_timestamp.dart`). Dit bewijst dat het token niet is
gewijzigd na ondertekening en dat de ondertekenaar de private key bij het
ingebedde certificaat had. Ondersteund: RSA-PKCS#1 v1.5 met SHA-256/384/512.

Wat nog niet is geïmplementeerd: X.509-padvalidatie tegen een vertrouwensanker
— dat vereist een externe CA-lijst die per definitie veroudert, en blijft op
de roadmap als PENTEST_MIAUW §8-A3.

## AEG-04 — closed for images, documented for video

Images now fetch their own bytes over a socket pinned by `NetGuard.connectPinned`
(#485), so `NetworkImage` never re-resolves the host and the TOCTOU window is
gone.

For **video** the window remains, and this is the honest part:
`VideoPlayerController.networkUrl` hands the URL to a platform player that opens
its own connection, and there is no byte-level seam to pin. What is left is an
internal GET whose response never reaches the app — no credentials travel, and
the static-internal and resolves-to-internal cases are still refused. That
residual now sits in the docstring of `isAllowedMediaUrlResolved` instead of a
general remark that read as if it covered images too.

## AEG-05 — the nonce, and what it cannot do here

The request now carries a `Random.secure` nonce (#476). What OciDeck cannot do is
verify the echo on import: the request goes to a TSA out of band and the deck
does not store it, so after a restart the other half is gone. Storing it would
mean a new front-matter key, which would collide with the in-flight move of the
seal to a sidecar. Anyone holding both files can check it
(`openssl ts -reply -in … -text`). That limit is written down rather than left
implied.

## AEG-07 — fixed by the format, mitigated where it counts

The audit is correct that WinZip AES derives its key with PBKDF2-HMAC-SHA1 at
1000 iterations, and that this is low. The count is not ours to raise: it is
fixed by the WinZip AES specification, and `archive` hard-codes it as a `const`.

The proposed alternative — an own AES-256-GCM envelope with Argon2/scrypt —
would trade away the property that makes the package worth having: any
AES-zip-aware tool (7-Zip, Keka, WinZip) can open it. For a project whose stated
purpose is maximal interchangeability, that is the wrong trade.

What is under our control is the passphrase, and that is where the defence
already sits: the export dialog shows an entropy-based strength meter and offers
a generator (32 or 256 random characters) that is on by default. With a generated
password the weak KDF is irrelevant. `FILE_FORMAT.md` §on key derivation states
all of this, including a subtler hazard the audit did not reach — the ZIP-AES
derivation truncates every UTF-16 code unit to its low 8 bits, so a non-ASCII
passphrase silently loses entropy and may not open in other tools.

## AEG-10 — already covered, and not vacuously

`test/ai_assist_marker_test.dart` asserts that `finalizeAndSeal` refuses while a
slide carries an unreviewed AI marker, and — the positive control that makes it
mean something — that it *does* seal once the markers are cleared.

## U-02 — measured, then declined

The audit is right that three parallel exception hierarchies exist, and right to
warn against forcing a fat shared base class. The proposal it *does* make — one
`StorageConflictException` with a `source` field — was measured against the
callers before being built, and it does not pay:

- **No call site catches two of them.** `shell_actions.dart:341` (WebDAV),
  `shell_actions_s3.dart:151` (S3), `tabs_provider_git.dart:490`/`:660` and
  `sync_engine.dart:214` (git). Next to every conflict catch sits an
  `on WebdavException` / `on S3Exception` for the ordinary failures, which stays
  backend-specific either way — so the number of `catch` arms does not drop.
- **"Conflict" means something different per backend.** For WebDAV and S3 it is a
  question to the user (overwrite, or save elsewhere). For git it does not reach
  the shell as a failure at all: it becomes a three-way merge, and only after
  that a `GitSaveStatus.conflict`.
- **The payloads genuinely differ** — an ETag versus `baseSha` + branch. That is
  the same argument `storage_origin.dart` already makes against a shared base
  class, and it applies here too.

The reasoning now sits in the docstring of `WebdavConflictException`, next to the
code it is about.

What the audit's instinct *did* point at, correctly, is real duplication one
level over: the save loop in `shell_actions.dart` and `shell_actions_s3.dart` is
near word-for-word identical, and `_retryRead` exists three times carrying the
same "mirrors the other one" comment that gave `_asFailure` away. That is noted
as follow-up work — it is duplication of behaviour, not of an exception type.

## O-02 — deliberately not now

The audit's own advice: split `AppSettings` "when the file has to take in the
next domain, not preventively". `settings_provider.dart` is not taking one in.
Splitting a 970-line provider that every setting flows through, with no feature
asking for it, is churn that risks behaviour to satisfy a shape. Recorded here so
the recommendation does not have to be re-litigated when it next comes up.

## What the audit got right that no measurement shows

Two of its Medium findings were not really about the code they named. X-02 and
X-03 are the same observation from two directions — *critical invariants are
enforced hard at the top entry points and thin out into convention-over-copies in
the layer below* — and that framing was worth more than either individual fix.
It is why the boundary work went into types and build guards (#471, #472, #489)
rather than into one-off corrections.
