# OciDeck — Agentic Build Plan for the Pentest / AI Feature Set (Design)

> **Status: HISTORICAL — this plan has been executed. Do not run it.**
> It said "nothing implemented yet" long after the work it plans had shipped;
> corrected 2026-07-18.
>
> The capabilities it decomposes are built: the MIAUW pentest module (see
> [`PENTEST_MIAUW.md`](PENTEST_MIAUW.md)) and AI assist Phases 0–3 (see
> [`AI_ASSIST.md`](AI_ASSIST.md), where Phase 4 / MCP is the only open item).
> Running the work packages below would rebuild things that already exist.
>
> **One package is actively wrong to execute: P0-MOD**, which specifies the pack
> fetch / mirror provisioning pipeline. That pipeline was built, tested, never
> went live, and was **removed on 2026-07-16** — see `PENTEST_MIAUW.md` §6, "Why
> the provisioning pipeline went". The module is now a plain on/off toggle over
> built-in catalogues with no network egress. Do not reinstate it.
>
> Kept because the decomposition, the isolation rules and the §7 human decision
> gates are a **reusable pattern** for the next agentic build, and because §7
> records which calls were escalated to a human rather than guessed. Read it as a
> worked example, not as a queue.
>
> Original framing follows.
>
> This document is the **execution plan** for building the capabilities specified
> in [`PENTEST_MIAUW.md`](PENTEST_MIAUW.md) and [`AI_ASSIST.md`](AI_ASSIST.md)
> using **autonomous AI agents** (Claude Code agents / the Workflow orchestrator).
> It does not add new product design — it decomposes the already-validated design
> into agent-executable work packages, orders their dependencies, and defines the
> isolation and verification that make an agentic build safe in this repo.

---

## 1. Why agentic works here (and what makes it safe)

Three properties of this repo make an autonomous multi-agent build viable:

1. **Self-contained specs.** `PENTEST_MIAUW.md` and `AI_ASSIST.md` already spell
   out exact files, data shapes, and round-trip formats — agents get crisp,
   bounded task specs instead of re-deriving intent.
2. **Strong headless verification.** The repo can *prove* correctness without a
   human: `make check` ratchets, `flutter test` (incl. the l10n test that demands
   every `.d(...)` string in ~30 languages and the exhaustive-`switch` guard
   tests), `make mutate-parsers` (0 survivors), `make deps-check`. An agent's work
   is not "done" until these are green — the gate, not the agent's confidence,
   decides.
3. **File-level modularity.** Slide types live in a `slideTypeMeta` map + a widget
   registry; templates and large widgets are split into `part` files. Disjoint
   work packages touch disjoint files, so agents parallelise with few conflicts —
   *except* a handful of choke files (§4).

The corresponding risk: those choke files (the `SlideType` enum + its exhaustive
switches, `app_localizations.dart`, `markdown_service_*`, `slide.dart`) are
merge-conflict magnets. The plan neutralises them with a **scaffold-first** step
and edit serialisation (§4).

---

## 2. The verification contract (definition of done)

Every work package, before it may merge, must pass the **global gate**:

- `flutter analyze` clean; `dart format` clean (run `flutter pub get` first in a
  fresh worktree, or third-party format checks falsely fail).
- `make check` — ratchets: ≤1000 lines/file, ≤150 lines/method, no `catch (_)`,
  no `print`, no bare `writeAs*` (use the atomic-file helpers).
- `flutter test` — including the l10n coverage test and the exhaustive-`switch`
  slide-type guard test.
- For any parser / the CVSS engine: `make mutate-parsers` at **0 survivors**
  (annotate genuinely-equivalent mutants `// mutation: equivalent`).
- For any pinned dependency/data change: `make deps-check`.
- The package's own **new tests** (unit + round-trip) exist and pass.
- The `verify` skill drives the affected flow end-to-end where it is observable.

Each package below adds a **local DoD** on top of this contract.

---

## 3. Orchestration model

Run as a **Workflow** pipeline. Per work package:

```
build (worktree-isolated) → verify (runs the global gate) → review (adversarial)
                                   ↑___________ loop until green ___________|
```

- **`build`** — one agent, `isolation: 'worktree'`, implements the package from
  its spec. Worktrees are mandatory for any package that mutates source in
  parallel (see memory `ocideck-ratchets-parallel`).
- **`verify`** — runs the §2 gate headlessly; returns pass/fail + failing output.
  On fail, the build agent is re-invoked (`SendMessage`) with the failures. Loop
  until green (cap the loop; escalate to a human on repeated failure).
- **`review`** — an adversarial reviewer (or `/code-review`) checks correctness +
  the design-doc contract before the package is allowed to merge.
- **Barriers** sit at phase boundaries: a phase's packages must land *and* merge
  (via the merge agent) before the next phase's dependents start.
- **Scaffold-alone**: the choke-file packages (§4) run *solo*, before their
  phase's parallel fan-out.
- **Merge agent**: applies the merge recipe (l10n union with de-dup; `make check`
  after every merge — ratchets catch what tests miss; per-coherent-change commits,
  see memories `ocideck-merge-recipe`, `ocideck-commit-granularity`).

A phase is a `parallel([...])` of package pipelines; the run is a sequence of
phases. Human decision gates (§7) pause the relevant phase.

---

## 4. Choke points & isolation strategy

| Choke file / surface | Why it conflicts | Strategy |
|---|---|---|
| `SlideType` enum + `slideTypeMeta` + every exhaustive `switch` | Five new types all touch it; the guard test fails until every switch is covered | **Scaffold agent P1-S** adds all 5 enum values + meta entries + stub editors/previews/serialisers and updates *all* switches so the guard test passes; only then do per-type agents flesh out their type in disjoint files |
| `lib/models/slide.dart` (adds `imageAltText`, report fields) | Multiple packages add fields | Field additions batched into the scaffold agents (P1-S, and P0-F for AI/image) so parallel agents don't all edit the model |
| `lib/l10n/app_localizations.dart` (`.d()` maps, ~30 langs) | Every UI package adds strings; duplicate-key = compile error | Each package adds only its **NL source** `.d()` calls; the **single l10n sweep P4-L** does the 30-language fill via the index-keyed translation pipeline + `assemble.py` (memories `ocideck-add-language`, `ocideck-d-string-*`) |
| `markdown_service_serialize/parse/helpers` | finding/checklist/scopeMatrix + image-alt all round-trip here | One serialize/parse pattern per new token, each in its own helper method (respect the 150-line method ratchet); a shared round-trip test file guards them |

---

## 5. Work breakdown (packages)

IDs: `P<phase>-<pkg>`. "Key surfaces" are the primary files/spec sections.

### Phase 0 — foundations (unblock everything)

| ID | Package | Depends | Key surfaces | Local DoD |
|---|---|---|---|---|
| P0-PICK | `SlideCategory` + tabbed/searchable/sorted picker | — | `slide.dart` (`SlideTypeMeta.category`), `add_slide_dialog.dart` (PENTEST §5) | Picker shows Algemeen/Alle tabs (Informatieveiligheid hidden until module on), search + sort work; wireframes for new types are stubs |
| P0-INTEG | Document integrity A1 (general) | — | new `finalize` front-matter (`ocideck_finalized`), SHA-512 seal (`crypto`), read-only lock (generalise `playOnly`), reusable visual-signature element (PENTEST §8) | Finalise → deck read-only; reopen verifies hash → intact/changed; signature element renders |
| P0-AIBK | AI shared backend | — | new **provider-agnostic** AI client (OpenAI-compatible `/v1` wire format = any model, local/remote — not a vendor dependency), settings toggle, 3-tier backend, guardrail scaffolding (AI_ASSIST §3–4); reuse `consent_provider`, `net_guard`, `flutter_secure_storage`. Optional later: an MCP-server surface so external agents drive OciDeck (AI_ASSIST §10). | Toggle off by default; "test connection" to a local endpoint works; no egress in local mode |
| P0-MOD | Module framework + provisioning skeleton | — | settings module toggle, app-support cache, content-addressed pack fetch + `sha256` verify (reuse `MANIFEST.json`/`check_bundled_js.dart`/`NetGuard`), **build-time pack tooling** (PENTEST §6) | Enable → fetch+verify+cache a pack across a mirror list; offline after; disable hides features |
| P0-CVSS | CVSS 4.0 native Dart engine | — | new engine + MacroVector lookup port (PENTEST §7) | Vector→score→severity matches FIRST fixtures; `make mutate-parsers` 0 survivors |

### Phase 1 — parallel fan-out

| ID | Package | Depends | Key surfaces | Local DoD |
|---|---|---|---|---|
| P1-S | **Scaffold** the 5 new slide types (enum + meta + switches + stubs) | P0-PICK | `slide.dart`, all exhaustive switches, widget registry | Guard test + l10n test green with stub editors/previews |
| P1-FIND | `finding` **slide group** (header+detail+evidence, shared id) | P1-S, P0-CVSS | `markdown_service_*` (`ocideck_finding_id`), editor/preview, PENTEST §3.1/§4 | Group round-trips Markdown-close; one id/severity across its slides; CVSS badge |
| P1-CHK | `checklist` type (MIAUW tri-state + finding link) | P1-S | `markdown_service_*` (table form), PENTEST §3.2/§6 | Round-trips as MD table; statuses + finding link |
| P1-SCOPE | `scopeMatrix` type | P1-S | editor/preview, serialize | Round-trips; per-object standard mapping |
| P1-SUM | `findingsSummary` type | P1-S | `fl_chart` severity chart | Derives counts from deck findings |
| P1-SIGN | `signOff` type | P1-S, P0-INTEG | signature + attestation binding | Renders MIAUW 1.6 statement; blocks seal until AI-markers cleared |
| P1-IMG | AI image tagging (Consumer B) | P0-AIBK | `slide.dart` (`imageAltText`), `ocideck_image_alt` round-trip, `imageSemanticsLabel`, `description_service`, `image_carousel_picker*`, `_editor_field.dart`, `slide_quality_analyzer` (AI_ASSIST §6) | Suggest alt-text (local vision model); tags fill the search sidecar; never overwrites human alt; decorative→empty alt |
| P1-CWE | CWE offline + CVE opt-in + snippet/finding-template library | P0-MOD | pack CWE JSON, `![…]` CWE/CVE links, importable finding library (PENTEST §5/§10.6/§17) | CWE picker (Mapping-Notes-aware); CVE link + opt-in enrich; snippet autofill |
| P1-THEME | Security theme profile (severity tokens, eye-candy) | P0-PICK | `ThemeProfile`, severity palette (PENTEST §11) | Severity colours/badges applied via the profile |

### Phase 2 — assembly

| ID | Package | Depends | Key surfaces | Local DoD |
|---|---|---|---|---|
| P2-WIZ | Finding wizard + report-setup wizard | P1-FIND, P0-CVSS, P1-CWE | multi-step stepper (PENTEST §4.1) | Finding wizard emits the slide group; report-setup captures CIA per scope object → CIA-weighted CVSS |
| P2-COMP | MIAUW compliance analyzer + waivers panel | P0-MOD, P1-* | `MiauwComplianceAnalyzer` (sibling of `slide_quality_analyzer`), panel (PENTEST §9) | Per-EIS auto/manual status + waiver-with-reason; all 92 waivable |
| P2-AUTO | Automation suite | P1-FIND/CHK/SCOPE | numbering/list/ToC, evidence SHA1+SHA-256, coverage checker, CIA→CVSS, consistency lint (PENTEST §10) | Auto findings list + evidence hash tables + coverage gaps flagged |
| P2-MSUM | Management-summary derivation | P1-SUM, P2-AUTO | derive severity roll-up + standards used (PENTEST §10.3) | Summary regenerates from deck content |

### Phase 3 — finalise & integrate

| ID | Package | Depends | Key surfaces | Local DoD |
|---|---|---|---|---|
| P3-A2 | Document integrity A2 (RFC3161/OpenKAT) | P0-INTEG | `.tsq`/token sidecar, TSA/OpenKAT verify (PENTEST §8-A2) | Hash timestamped + verified in-app |
| P3-AIA | Pentest AI text drafting (Consumer A) | P0-AIBK, P1-FIND | field "Suggest" + `ocideck_ai_assisted` markers (PENTEST §16) | Draft-only; seal blocked until markers cleared |
| P3-TPL | MIAUW report template + eye-candy polish | P1-* | `deck_template*` entry (PENTEST §1) | Template scaffolds all MIAUW chapters |
| P3-EXP | Export / PDF/A + audit dossier | P1-*, P0-INTEG | `pdf` export, AES package (PENTEST §8) | Findings/checklists/summary export deterministically; sealed dossier |

### Phase 4 — cross-cutting closeout

| ID | Package | Depends | Key surfaces | Local DoD |
|---|---|---|---|---|
| P4-L | l10n sweep (all new strings → ~30 langs) | all UI packages | `app_localizations.dart`, translation pipeline + `assemble.py` | l10n test green in all languages |
| P4-DOC | Docs update | all | USER_GUIDE / FILE_FORMAT / CHANGELOG / SOURCE_MAP / ARCHITECTURE / LICENSE_COMPLIANCE / SBOM (memory `keep-docs-updated`) | Docs reflect shipped behaviour |
| P4-V | Full integration verify | all | `make check` + tests + mutation + `verify` skill end-to-end | Whole flow green; a real MIAUW deck authored, sealed, exported |

---

## 6. Dependency graph (phases)

```
P0-PICK ─┬─ P1-S ─┬─ P1-FIND ─┬─ P2-WIZ ─┐
P0-CVSS ─┘        ├─ P1-CHK   ├─ P2-COMP ├─ P3-TPL ─┐
P0-INTEG ─ P1-SIGN├─ P1-SCOPE ├─ P2-AUTO ┤          ├─ P4-L ─ P4-DOC ─ P4-V
P0-AIBK ─┬ P1-IMG ├─ P1-SUM ──┴─ P2-MSUM ┘          │
         └ P3-AIA                     P3-A2 ─────────┤
P0-MOD ── P1-CWE ───────────────────────── P3-EXP ──┘
P1-THEME ───────────────────────────────────────────┘
```

Phase 0 packages are mutually independent → run all five in parallel first.
Phase 1 fans out after the scaffold (P1-S) and its Phase-0 deps land. Phases 2–3
fan out on their deps. Phase 4 is the closeout barrier.

---

## 7. Human decision gates (resolve before the dependent phase)

These are the still-open questions from the design docs; an agentic run must
**pause** for a human answer, not guess:

- **Before P0-INTEG / P3-A2:** signing approach — RFC3161/OpenKAT only (no new
  crypto dep) vs adding an Ed25519/minisign signature dep (also gates the pack
  signature, PENTEST §14-Q2).
- **Before P0-MOD:** the second mirror host, and whether the pack is signed in
  phase 1 (PENTEST §14-Q1/Q2).
- **Before P1-IMG / P0-AIBK:** AI as a separate toggle vs inside the module; the
  recommended model roster / "install Ollama" help (AI_ASSIST §8).
- **Before P3-EXP:** PDF/A strictness for EIS 1.1 (PENTEST §14-Q4).
- **Before P1-CHK / P1-CWE:** additional standards (MASTG/ASVS) now or later;
  CVSS v3.1 import (PENTEST §14-Q3/Q5).

---

## 8. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Choke-file merge conflicts | Scaffold-first (P1-S, P0 field batching); serialise edits to `slide.dart`/switches/l10n (§4) |
| Agents drift from the spec | The design docs are the contract; the `review` stage checks against them; the gate (§2) is objective |
| l10n test failures across 30 langs | Packages add NL source only; the single P4-L sweep owns translation; duplicate-key checks per memory `ocideck-d-string-duplicate-key` |
| Silent scope/quality regressions | `make check` after every merge; mutation tests on parsers/CVSS; `verify` skill drives real flows |
| Worktree false format failures | `flutter pub get` in each fresh worktree before format checks (memory `ocideck-worktree-pub-get`) |
| Non-deterministic agent output breaking round-trip | A shared round-trip test file is a required deliverable of every serialise package |
| Over-parallelism thrash | Cap concurrency at the Workflow default; keep Phase-0 barrier strict |

---

## 9. Kicking it off (when the human says go)

This plan is executed with the **Workflow** tool: one `parallel([...])` per phase,
each element a `build → verify → review` pipeline with `isolation: 'worktree'`,
`SendMessage` loop-until-green on verify failure, a scaffold-alone step before the
Phase-1 fan-out, and a merge agent between phases. Nothing runs until a human
confirms the §7 decision gates and explicitly authorises the build — this document
is the plan, not the trigger.

---

## 10. Sequential execution order (single-track runbook)

The phased fan-out (§3/§5/§6) is the *fast* path. This section is the **strictly
sequential alternative**: one ordered track, walked top to bottom by a single
agent (or one agent per step, in order), with **no parallelism**. It trades speed
for simplicity and determinism — no worktree coordination, no merge agent, no
cross-package races; the tree is always in one known state.

**Per-step invariant.** Every step ends the same way before the next begins:

1. implement the step from its spec;
2. run the full §2 gate green — *including* the l10n coverage test, so **any step
   that adds `.d(...)` strings must add their ~30-language translations in the
   same step** (via the index-keyed translation pipeline + `assemble.py`); there
   is no deferred translation phase;
3. one coherent commit (memory `ocideck-commit-granularity`);
4. only then move to the next step.

If a step fails the gate, fix it in place — never advance on red.

### The order

| # | Step | Spec | Done when |
|---|---|---|---|
| **Prep** | | | |
| 1 | Answer decisions #1–#6 | §7; PENTEST §14; AI_ASSIST §8 | All six recorded (human) |
| 2 | MIAUW schema (xlsx) → bundled JSON (92 EIS, NL+EN) | PENTEST §9 | JSON validated against the source |
| 3 | CVSS 4.0 test fixtures from the FIRST reference | PENTEST §7 | Vector→score fixture set committed |
| 4 | Licence/attribution (LICENSE_COMPLIANCE + SBOM) | PENTEST §15 | MIAUW/WSTG/CWE/CVSS entries added |
| 5 | Pack tooling + cut the first data pack | PENTEST §6 | Pack + inner MANIFEST (sha256) built; needs #2 |
| 6 | Model defaults + "install Ollama" help | AI_ASSIST §6 | Recommended models + help text |
| 7 | RFC3161/OpenKAT integration decision | PENTEST §8-A2 | Endpoint + token flow chosen; needs #1 |
| 8 | Verification baseline + worktree strategy | §2/§4 | Gate green on a fresh worktree |
| **Foundations** | | | |
| 9 | P0-PICK — `SlideCategory` + tabbed/searchable picker | PENTEST §5 | Picker tabs/search/sort |
| 10 | P0-CVSS — native CVSS 4.0 engine | PENTEST §7 | Matches #3 fixtures; `make mutate-parsers` 0 |
| 11 | P0-INTEG — Document integrity A1 (finalise+hash+signature) | PENTEST §8; AI_ASSIST §8 | Finalise→read-only; hash verify |
| 12 | P0-AIBK — AI shared backend (`/v1`, 3-tier, guardrails) | AI_ASSIST §3–4 | Local endpoint test works; off by default |
| 13 | P0-MOD — module toggle + provisioning (uses #5 pack) | PENTEST §6 | Enable→fetch+verify+cache; offline after |
| **Slide types & consumers** | | | |
| 14 | P1-S — scaffold all 5 slide types (enum+meta+switches+stubs) | PENTEST §4; §4-choke | Guard + l10n tests green with stubs |
| 15 | P1-FIND — `finding` **slide group** (header+detail+evidence, shared id) | PENTEST §3.1/§4 | Group round-trips; one id/severity; CVSS badge |
| 16 | P1-CHK — `checklist` (MIAUW tri-state + finding link) | PENTEST §3.2/§6 | Round-trips as MD table |
| 17 | P1-SCOPE — `scopeMatrix` | PENTEST §4 | Round-trips; standard mapping |
| 18 | P1-SUM — `findingsSummary` (fl_chart) | PENTEST §11 | Counts derived from findings |
| 19 | P1-SIGN — `signOff` (binds to A1 seal) | PENTEST §7-there/§8 | 1.6 statement; seal blocked until markers cleared |
| 20 | P1-IMG — AI image tagging (alt-text + tags) | AI_ASSIST §6 | Suggest alt-text; tags → search sidecar |
| 21 | P1-CWE — CWE offline + CVE opt-in + finding library | PENTEST §5/§10.6/§17 | CWE picker + CVE link + snippet autofill |
| 22 | P1-THEME — security theme profile (severity tokens) | PENTEST §11 | Severity colours/badges via profile |
| **Assembly** | | | |
| 23 | P2-WIZ — finding + report-setup wizards | PENTEST §4.1 | Wizard emits finding group; CIA captured per scope object → CIA-weighted CVSS |
| 24 | P2-COMP — compliance analyzer + waivers panel | PENTEST §9 | Per-EIS status + waiver; all 92 waivable |
| 25 | P2-AUTO — automation suite | PENTEST §10 | Auto list/numbering + evidence hashes + coverage gaps |
| 26 | P2-MSUM — management-summary derivation | PENTEST §10.3 | Summary regenerates from deck |
| **Finalise** | | | |
| 27 | P3-A2 — RFC3161/OpenKAT timestamp | PENTEST §8-A2 | Hash timestamped + verified |
| 28 | P3-AIA — pentest AI text drafting (Consumer A) | PENTEST §16 | Draft-only; seal-gated markers |
| 29 | P3-TPL — MIAUW report template | PENTEST §1 | Scaffolds all MIAUW chapters |
| 30 | P3-EXP — export / PDF/A + audit dossier | PENTEST §8 | Deterministic export; sealed dossier |
| **Closeout** | | | |
| 31 | l10n consistency audit (dedup, fallback, no orphan keys) | memory `ocideck-add-language` | l10n test + audit clean |
| 32 | Docs update (USER_GUIDE/FILE_FORMAT/CHANGELOG/SOURCE_MAP/…) | memory `keep-docs-updated` | Docs match shipped behaviour |
| 33 | Full integration verify (author→seal→export a real MIAUW deck) | §2 + `verify` skill | End-to-end flow green |

Steps 2–4 are the only ones with no code-under-test dependency and can be done
first in any order; everything from 5 onward follows the table order. Because the
gate runs every step, the build is releasable at every commit — you can stop after
any step with a working tree.
