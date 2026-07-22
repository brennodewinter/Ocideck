# OciDeck — Agentic Build Plan for the Pentest / AI Feature Set (Design)

> **Status:** historical — executed, and shortened on 2026-07-22 to what is still useful · **Status last reviewed:** 2026-07-22 · **Published by:** Stichting LibreKAT

> **HISTORICAL — this plan has been executed. Do not run it.**
> It said "nothing implemented yet" long after the work it plans had shipped;
> corrected 2026-07-18.
>
> The capabilities it decomposes are built: the MIAUW pentest module (see
> [`PENTEST_MIAUW.md`](PENTEST_MIAUW.md)) and AI assist Phases 0–3 (see
> [`AI_ASSIST.md`](AI_ASSIST.md), where Phase 4 / MCP is the only open item).
> Running the work packages below would rebuild things that already exist.
>
> **Shortened on 2026-07-22.** The work-package tables, the dependency graph and
> the 33-step runbook — roughly half the file — were removed; §5 says what they
> were and why they went. A walked queue is not a reference, and one of its
> packages (`P0-MOD`, the pack fetch / mirror provisioning pipeline) was
> **actively wrong to execute**: that pipeline was built, tested, never went
> live, and was **removed on 2026-07-16** — see `PENTEST_MIAUW.md` §6, "Why the
> provisioning pipeline went". The module is now a plain on/off toggle over
> built-in catalogues with no network egress. Do not reinstate it.
>
> What is kept is the part that does not expire: why an agentic build is safe in
> *this* repo (§1), what "done" means (§2), the orchestration shape (§3), the
> choke files that must be edited serially (§4), the §7 decisions that were
> escalated to a human rather than guessed — now with their outcomes — and the
> risk table (§8). Read it as a worked example, not as a queue.
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

## 5. Work breakdown, dependency graph and runbook — removed

This document used to carry the full decomposition: five phases of work-package
tables (`P0-PICK` through `P4-V`), an ASCII dependency graph, and a 33-step
sequential runbook — about half its length. All of it has been executed, and
several of its packages describe things that no longer exist: `P0-MOD` specifies
the pack fetch / mirror provisioning pipeline that was removed on 2026-07-16 and
must not be reinstated, and the MIAUW schema step names 92 EIS where the
catalogue now holds 88 testable ones (`kMiauwFullSchemaSize`).

Kept out rather than corrected, on 2026-07-22, because a work queue that has
been walked is not a reference: correcting it would produce an accurate
description of work nobody should do, at the cost of the pages a reader has to
walk past to reach the parts that are still useful. The package IDs still
referenced in §4, §7 and §8 read as `P<phase>-<package>`; what each one built is
visible in the code and in [`PENTEST_MIAUW.md`](PENTEST_MIAUW.md) and
[`AI_ASSIST.md`](AI_ASSIST.md), which are the specifications, not this.

What survives that decomposition, and is the reason this file exists at all:
the safety properties in §1, the definition of done in §2, the orchestration
shape in §3, the choke-file rules in §4, the decision gates in §7 and the risk
table in §8. Those are about *how* to run an agentic build in this repo, and
they do not expire when a particular build finishes.

The one structural lesson worth carrying forward from the removed §10: the
sequential single-track alternative existed because parallelism costs worktree
coordination and merge work. Its per-step invariant — implement, run the whole
gate green *including* the localisation coverage test in the same step, one
coherent commit, never advance on red — is the part that mattered, and it is
worth more than the order the steps happened to be in.

---

## 7. Human decision gates — and what was decided

These were the open questions an agentic run had to **pause** for rather than
guess. They are the most reusable part of this document: not the answers, but
the fact that these five were recognised in advance as calls a machine should
not make. Where the outcome is readable in the code today it is recorded here;
where it is not, that is said rather than filled in. *(Outcomes added
2026-07-22.)*

- **Before P0-INTEG / P3-A2 — signing approach:** RFC3161/OpenKAT only (no new
  crypto dependency) versus adding an Ed25519/minisign signature dependency
  (also gated the pack signature, PENTEST §14-Q2).
  → **Decided: RFC 3161, no new dependency.** `rfc3161_timestamp.dart` builds a
  `.tsq` and verifies the returned token's message imprint against the seal;
  `pubspec.yaml` carries `crypto` and no signature package. Note the deliberate
  shallowness: the token is checked against *this* hash, not against a
  trustworthy authority (`SECURITY_DESIGN.md` §9).
- **Before P0-MOD — the second mirror host, and whether the pack is signed in
  phase 1** (PENTEST §14-Q1/Q2).
  → **Moot.** The whole pack/provisioning pipeline was removed on 2026-07-16;
  the module is a toggle over built-in catalogues with no network egress. There
  is no pack to mirror or sign (PENTEST_MIAUW §6).
- **Before P1-IMG / P0-AIBK — AI as a separate toggle or inside the module**, and
  the recommended model roster / "install Ollama" help (AI_ASSIST §8).
  → **Decided: separate.** `AiSettings.enabled` is its own setting, off by
  default and independent of the security module.
- **Before P3-EXP — PDF/A strictness for EIS 1.1** (PENTEST §14-Q4).
  → **Still open**, and deliberately so: [`VERIFICATION.md`](VERIFICATION.md)
  §10 carries it as a decision to take before anything is built for it.
- **Before P1-CHK / P1-CWE — additional standards (MASTG/ASVS) now or later, and
  CVSS v3.1 import** (PENTEST §14-Q3/Q5).
  → **Partly decided.** MASTG and MASWE are bundled catalogues today
  (`mastg_catalog.dart`, `maswe_catalog.dart`); there is no ASVS catalogue and
  `lib/services/cvss/` implements v4.0 only, with no v3.1 import. Whether either
  was decided against or simply not reached is not recorded anywhere, so it is
  not claimed here.

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
