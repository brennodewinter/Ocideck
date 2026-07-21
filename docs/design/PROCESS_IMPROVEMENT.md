# OciDeck — Procesverbetering (Design)

*The module that supports Lean Six Sigma methods — DMAIC, DMADV, Kaizen, A3, 8D.
The neutral name is deliberate; see §19.*

> **Status: design proposal — not yet implemented.**
> This document describes a *future* capability (a Lean Six Sigma authoring
> module) and the architecture chosen for it. It is deliberately kept separate
> from the current-state contributor docs
> ([`ARCHITECTURE.md`](../ARCHITECTURE.md), [`SOURCE_MAP.md`](../SOURCE_MAP.md),
> [`FILE_FORMAT.md`](../FILE_FORMAT.md)) so that those keep describing what
> exists. When (parts of) this lands, fold the relevant sections into those docs
> and the [`USER_GUIDE.md`](../USER_GUIDE.md), and update the
> [`CHANGELOG.md`](../../CHANGELOG.md).
>
> It is written to be **picked up cold**: exact file paths, integration points,
> data shapes, invariants and open questions are spelled out so a later
> implementation session has everything it needs without re-deriving context.
>
> Sibling design docs: [`PENTEST_MIAUW.md`](PENTEST_MIAUW.md) (the module this
> one deliberately mirrors), [`AI_ASSIST.md`](AI_ASSIST.md),
> [`OCIWACHT.md`](OCIWACHT.md).

---

## 1. Purpose & scope

OciDeck should be able to author **Lean Six Sigma work** — the full range: the
Lean side (VSM, 5S, kanban, waste analysis), the Six Sigma side (capability,
control charts, MSA, hypothesis testing, DOE), and the frameworks that bind them
(DMAIC, DMADV/DFSS, Kaizen, A3, 8D, PDCA) — while keeping OciDeck's principles
intact: *file = truth*, storage stays as close to plain Markdown as possible, and
nothing leaves the machine.

The fit is better than it first looks. **An LSS project's deliverable is already
a deck.** A tollgate review *is* a presentation; an A3 *is* one page; a Kaizen
report-out *is* a slide sequence. OciDeck does not need to become a project
tracker — it needs to make the artefacts authorable, correct, and internally
consistent.

Delivered as an **opt-in module** ("Procesverbetering"), mirroring the
Informatieveiligheid module, so the majority of users who never run a DMAIC
project see none of it.

### The two audiences, one core

Confirmed scope: **both**, sharing one engine set.

| Audience | What they need | Same engines? |
|---|---|---|
| **Practitioner** — project deck *is* the deliverable | Depth: real numbers, derived limits, a golden thread, tollgate gap analysis | yes |
| **Belt trainer** — teaching material | Breadth: many artefacts, worked examples, clean visuals | yes |

They differ only in **templates and seed content**, not in code. That is the
whole reason the architecture below is *engines × templates*: a second audience
costs template data, not Dart.

### Where this differs sharply from MIAUW

MIAUW gave us a free, normative, machine-readable artefact (EUPL 1.2, a 92-EIS
schema we could bundle verbatim). **Lean Six Sigma has no such thing.**

- **ISO 13053-1/-2:2011** (*Quantitative methods in process improvement — Six
  Sigma*; part 1 DMAIC, part 2 tools & techniques) and **ISO 18404** are
  paywalled ISO standards. We cannot bundle, quote at length, or reproduce their
  factsheets.
- The certification **Bodies of Knowledge** (ASQ, IASSC, CSSC) are copyrighted.
- The **trademark position is mixed**: the bare terms are unowned in the EU (the
  "LEAN SIX SIGMA" EUTM is *Ended*; no live EU mark containing "six sigma" covers
  software), while a live but narrow US registration survives and a cluster of
  live Dutch/Belgian composite marks sits in classes 35/41/42 — see §19.

**Consequence, and it is load-bearing:** the methodology schema (which artefacts
exist, which phase they belong to, what a tollgate expects) must be **authored
in-house** from uncontroversial, widely-published practice, and be **editable
data** rather than a normative claim. OciDeck's phase-gate panel says *"your
deck is missing a SIPOC"*, never *"this is not ISO 13053 conformant"*. This is
the single biggest scoping difference from the MIAUW module, and it is why §12's
analyzer is framed as a **checklist you can edit**, not a compliance engine.

### Goals

- Author every mainstream LSS artefact, with the tool understanding what it is.
- **Compute, don't ask.** Control limits, Cp/Cpk, RPN, PCE, takt, sigma level are
  *derived from data*, never typed by the user and never stored.
- One **golden thread** (VOC → CTQ → Y → X → solution → control) that the tool
  can lint for contradictions.
- Markdown that is readable, diffable and useful **without OciDeck**.

### Non-goals

- Not a project portfolio tracker, time-tracker, or PPM tool.
- Not a Minitab replacement for exploratory analysis. We compute what an LSS
  *report* needs, correctly; we are not a general statistics workbench.
- No certification claims, no ISO-conformance claims (§19).
- No database. No server. (Unchanged from the rest of OciDeck.)

---

## 2. The central decision: engines × templates

This is the architectural heart, and it is where this module departs from the
MIAUW playbook.

**The problem.** MIAUW added five `SlideType`s. "All LSS methodologies" is
**~45 artefacts** — and the list never closes; every LSS text ships a different
tool set. The measured cost of a chart-class structured slide type in this
codebase is **≈7,000–7,500 lines** (§16). Naïvely, 45 artefacts is not a project,
it is a decade.

### The options, weighed

| # | Option | Cost | Verdict |
|---|---|---|---|
| **A** | **One `SlideType` per tool** (the MIAUW way, scaled) | `SlideType` 16 → ~60. ~45 × 7,000 ≈ **300k lines**. Every one of the 16 add-a-type sites (§16.2) × 45. Picker becomes a phone book. l10n × 31 languages × 45. | **Rejected.** Cost is linear in an unbounded list. |
| **B** | **Engines × templates** — few *rendering primitives* as slide types; each artefact is declarative **data** | ~5 slide types + ~10 chart types. A new artefact ("add Kano") = a template file. **Zero Dart, zero l10n.** | **Recommended.** Cost is linear in primitives (bounded ≈7), constant in artefacts. |
| **C** | **Free Markdown + a CSS theme** | ~0 | **Rejected as the answer**, kept as the **escape hatch**: any artefact no engine covers stays authorable as free Markdown/Mermaid. But it cannot compute Cpk, cannot derive limits, cannot lint. Fails the brief. |
| **D** | **Extend the existing chart engine** for the statistical plots | Reuses `ChartSpec`, CSV linking, the data grid, the SVG exporter, chart a11y read-out | **Recommended as a sub-decision** — this is option B applied to charts, and it is the cheapest real value in the whole plan. |

**Decision: B + D, with C as the escape hatch.**

### Why it works: artefacts collapse onto primitives

Classify LSS artefacts by *how they render*, not by what they are called. ~45
artefacts collapse onto **four canvas engines + the chart engine + one derived
overview**:

| Engine (`SlideType`) | Rendering primitive | Artefacts it covers |
|---|---|---|
| **`matrix`** | typed grid + derived columns | SIPOC · FMEA (RPN derived) · Control Plan · Data Collection Plan · RACI · Stakeholder analysis · Pugh / solution-selection matrix · Cause-&-Effect (XY) matrix · Waste analysis (TIMWOODS) · 8D · Check sheet · Gage R&R worksheet · Kaizen newspaper · Risk register · Is/Is-Not · House of Quality (`layout: hoq`) |
| **`canvas`** | fixed regions of Markdown | A3 · Project charter · Problem-statement frame · In/Out-of-scope frame · VOC→CTQ card · Impact/Effort 2×2 · PICK chart · SWOT · Affinity diagram · Kanban board (`layout: board`) · 5S audit · Standard work · Lessons learned · Benefit tracking |
| **`tree`** | hierarchy | CTQ tree · 5× Why · **Ishikawa/fishbone** (`layout: fishbone`) · Fault tree · Driver tree · Tree diagram |
| **`flow`** | directed steps | Process flowchart · Swimlane/deployment (`layout: swimlane`) · **VSM** (`layout: vsm`) · Makigami · Value-add analysis |
| **`chart`** *(existing, extended)* | data plot | Control charts (I-MR, X̄-R, X̄-S, p, np, c, u) · Histogram + capability · Pareto · Run chart · Box plot · Probability plot · Main-effects · Interaction · Multi-vari |
| **`phaseGate`** | derived overview | DMAIC/DMADV storyboard, tollgate status |

**Fishbone is a layout, not a type.** Ishikawa and a 5× Why hold the *same data*
(categories → causes → sub-causes) and differ only in painter. This mirrors the
existing precedent exactly: `TimelineLayout` / `TimelineReveal` are **fields** on
`Slide` that round-trip as extra `_class` tokens, not separate types
(`ARCHITECTURE.md`, "Timeline slides"). Same for VSM vs. flowchart, board vs.
canvas.

**Net: 5 new `SlideType`s — the same order of magnitude as MIAUW's five — cover
~45 artefacts.**

### The template is a Markdown file (the proven pattern)

This is not a new invention; it already exists in the repo and works.
`lib/services/finding_template_library.dart` and
`lib/models/finding_template.dart` store a reusable finding as **plain Markdown
with YAML front matter**, precisely so it is *"git-friendly, diffable, importable,
and survives tool abandonment"*. An LSS artefact template is the same thing:

```markdown
---
id: sipoc
engine: matrix
phase: define
label:
  nl: SIPOC
  en: SIPOC
columns:
  - { key: supplier, label: { nl: Leverancier, en: Supplier } }
  - { key: input,    label: { nl: Input,       en: Input } }
  - { key: process,  label: { nl: Processtap,  en: Process } }
  - { key: output,   label: { nl: Output,      en: Output } }
  - { key: customer, label: { nl: Klant,       en: Customer } }
guidance:
  nl: Vul rechts naar links in — begin bij de klant.
  en: Fill right-to-left — start at the customer.
---
| Supplier | Input | Process | Output | Customer |
|---|---|---|---|---|
| Sales | Signed order | Enter order | Order confirmation | Customer |
```

Consequences, all good:

- Adding **Kano** later = drop in a file. No Dart, no rebuild of the picker.
- Template labels/guidance are **data with `nl`/`en` fields — not `d()`
  strings**, so they do **not** hit the 31-language l10n test. This is explicitly
  the MIAUW precedent (*"Bundled standard content … is data, not `d(...)`
  strings"*, PENTEST_MIAUW §12) and it saves an enormous amount of work. The
  honest cost: template content ships NL+EN only, while the *chrome* around it is
  translated in all 31.
- Users can **export, edit, share and re-import** their own templates — which is
  exactly what a Belt trainer or a consultancy with a house method wants. The
  "second audience" is a template pack, not a fork.

---

## 3. Storage — Markdown-close, per engine

The rule, inherited from MIAUW §3: **the body is readable Markdown; only what
cannot round-trip losslessly goes in an `<!-- ocideck_* -->` comment; anything
derivable is never stored.**

### 3.1 `matrix` — a real Markdown table

```markdown
<!-- _class: matrix -->
<!-- ocideck_template: fmea -->
# FMEA — Order intake

| # | Process step | Failure mode | Effect | S | Cause | O | Control | D |
|---|---|---|---|---|---|---|---|---|
| 1 | Enter order | Wrong article no. | Wrong delivery | 7 | **X-03** Manual retyping | 6 | Visual check | 5 |
| 2 | Credit check | Check skipped | Bad debt | 9 | **X-07** No hard stop | 3 | Monthly audit | 8 |
```

Invariants:
- **RPN is derived** (S×O×D = 210 / 216) and rendered — **never stored**. Exactly
  mirrors *"Severity is derived from the CVSS score → never stored"* (MIAUW §3.1).
- Rows re-rank by RPN in the preview; the file keeps author order (stable diffs).
- `X-03` is the golden thread (§5), **parsed back from the inline text** — no
  duplicated machine block. Mirrors MIAUW: *"the CVSS vector string, CWE id and
  CVE ids are parsed back from the inline text"*.
- Reuses the existing table rails: a `matrix` renders as a normal Markdown
  table to any other tool.

### 3.2 `canvas` — Markdown headings as regions

```markdown
<!-- _class: canvas -->
<!-- ocideck_template: a3 -->
# A3 — Lead time order intake

## Background
Customers complain about confirmation speed.

## Current situation
Lead time 14 days (**Y-01**), Cpk 0.42 against USL 7.

## Goal
7 days by Q4 2026.

## Root cause analysis
Manual retyping (**X-03**) drives 60% of the variation.

## Countermeasures
...

## Plan
...

## Follow-up
...
```

**On disk, an A3 simply *is* an A3 document.** Open it in any editor and it reads
correctly. The engine's only job is to *lay the regions out* on a slide. This is
the strongest expression of "Markdown where it can be" in the whole module: the
region layout lives in the template, the content lives in ordinary headings.

Quadrant artefacts (Impact/Effort, PICK) use `layout: quadrant` — each region is
a quadrant holding a **list**. Coordinate-placed variants are a `scatter` chart
instead; we do not invent a third thing.

### 3.3 `tree` — a nested Markdown list

```markdown
<!-- _class: tree -->
<!-- ocideck_template: five-whys -->
# 5× Why — Order entered late

- Order entered late
	- Approval is awaited
		- The approval limit is unclear
			- Two policies contradict each other
				- Policy never merged after the merger
					- No owner was assigned — **X-03**
```

Depth is **leading tabs**, which is already the repo's convention: `bulletLevel()`
/ `bulletText()` in `lib/models/slide.dart:63-71` count exactly that. So a tree
reuses `Slide.bullets` verbatim, exactly as timeline slides do — *no
`customMarkdown`, the `.md` stays a readable list*.

Fishbone is the same data under `<!-- ocideck_layout: fishbone -->`, with the
top-level bullets being the 6M categories.

### 3.4 `flow` — a step list with typed attributes

```markdown
<!-- _class: flow -->
<!-- ocideck_template: vsm -->
<!-- ocideck_layout: vsm -->
# VSM — Order to delivery (current state)

- Enter order :: process :: pt=12m; lt=2d; fte=2; fpy=0.92
- :: inventory :: wip=45
- Credit check :: process :: pt=4m; lt=1d; fte=1
- Pick & pack :: process :: pt=35m; lt=3d; fte=4; fpy=0.88
```

The `a :: b :: c` separator is the established timeline convention (`marker ::
title :: description`), reused rather than reinvented. Derived and rendered,
never stored: **total lead time, total process time, PCE = PT/LT, takt, the
bottleneck** (§11).

### 3.5 Statistical plots — the chart engine, extended

Reuses `ChartSpec` (`lib/models/chart.dart:33` `ChartType`, `:309` `toBlock`)
verbatim, including the CSV mechanism:

````markdown
<!-- _class: chart -->
# I-MR — Cycle time

```chart
{
  "type": "controlChart",
  "controlChart": { "kind": "imr", "stages": [ {"from": 0, "label": "Baseline"}, {"from": 24, "label": "After pilot"} ] },
  "metric": "Y-01",
  "source": "data/cycle_time.csv"
}
```
````

**Control limits are absent from the file by design** — they are computed from the
data (§4). A stored UCL is a lie waiting to happen when the CSV changes.

The `source` → `data/*.csv` link is the existing "strip on save, hydrate on open"
model and it is a perfect fit for LSS measurement data:
`ChartSpec.toBlock(forStorage: true)` (`chart.dart:309`, `dropData` at `:323`) drops the cached values
when a `source` is set, `_hydrateCharts` (`lib/services/parts/file_service_open.dart:56`)
re-reads them on open. **The CSV is the living truth; the deck holds no copy of
the numbers.** No database — a folder of CSVs and a Markdown file.

> Two existing guards apply and must not be lost: `resolveProjectRelative`
> (`file_service_open.dart:70`, `:120`) rejects `../../../secret.csv` on Save As,
> and `parseCsv` (`chart.dart`) reads quoted fields per RFC 4180 since the
> pre-cursor fix (§18.8) — so a `"Amsterdam, NL"` from Excel survives. It also
> detects the separator per file, so a `;`-delimited Dutch export loads, and in
> that case reads `10,5` as a decimal. What it still refuses is a genuinely
> ambiguous number, and it no longer decides that alone: the convention is
> deduced from every value in the file (`1.234,56` settles itself; a `10,5`
> nearby settles `1,234`), and a file that truly cannot say is asked about at
> import. LSS inherits no open number-locale decision — see §17.

### 3.6 Deck-level metadata (front matter)

Namespaced `ocideck_improvement_*`, alongside `ocideck_miauw_*`:

```yaml
ocideck_improvement_framework: dmaic          # dmaic | dmadv | kaizen | a3 | eight_d | pdca
ocideck_improvement_project: Order intake lead time
ocideck_improvement_metrics:
  Y-01:
    name: Lead time order intake
    unit: days
    usl: 7
    target: 3.5
    baseline: 14
    goal: 7
ocideck_improvement_gates:
  define:  { passed: 2026-03-04, by: J. Jansen }
  measure: { passed: 2026-04-11, by: J. Jansen }
ocideck_improvement_waivers:
  msa: Client accepted the existing gauge study
```

**A Y is defined once.** The histogram, the capability analysis and the control
chart all resolve their spec limits *through the `Y-01` reference*, so LSL/USL
cannot drift between slides. This is the direct analogue of MIAUW's CIA → CVSS
environmental propagation (PENTEST_MIAUW §10.5): ask once, up front, propagate
everywhere.

---

## 4. The statistics core

**Decision: a native Dart engine, no new dependency.** This follows the CVSS 4.0
precedent verbatim (`lib/services/cvss/`; PENTEST_MIAUW §7 — *"a native Dart
port … not a bundled JS calculator in a webview. Rationale: offline,
isolate-safe, unit- and mutation-testable"*). It also avoids the SBOM gate: any
`pubspec.yaml` dependency change forces `make sbom`, and there is no Dart
statistics package worth taking the supply-chain surface for.

Lives in `lib/services/improvement/stats/` — pure, network-free, no Flutter imports
(`modelUiImportBaseline = 0` is a hard zero; keep services clean too).

| Area | Contents |
|---|---|
| `distributions.dart` | Normal (CDF + inverse), Student-t, χ², F — CDF and quantile |
| `descriptives.dart` | mean, median, sd (n−1), quartiles (state the hinge method), skew, kurtosis |
| `constants.dart` | **Control-chart constants** d2, d3, A2, A3, D3, D4, c4, B3, B4 by subgroup size — a lookup table, exactly like the CVSS MacroVector table |
| `control_charts.dart` | I-MR, X̄-R, X̄-S, p, np, c, u; limits, stages/recalculation boundaries |
| `rules.dart` | Nelson 1–8 and Western Electric — selectable, off by default beyond rule 1 |
| `capability.dart` | Cp, Cpk, Pp, Ppk, Cpm; DPMO; yield; **sigma level** |
| `inference.dart` | 1/2-sample t, paired t, ANOVA, χ², proportions, F, Levene, Anderson-Darling |
| `regression.dart` | simple + multiple linear, R², adj-R², coefficient p-values, residuals |
| `msa.dart` | Gage R&R (**ANOVA method**), %study variation, ndc |
| `doe.dart` | full factorial, 2^(k−p) fractional, main effects, interactions |
| `sampling.dart` | sample-size / power calculators |

### The rules that keep it honest

1. **The 1.5σ shift is explicit, never silent.** "Sigma level" is ambiguous in the
   field and the shift is the single most common source of two people getting two
   answers. It is a stored, visible flag per metric, and every rendered sigma
   value states which convention it used.
2. **Cp/Cpk (within) vs Pp/Ppk (overall) are both reported**, never conflated.
3. **Capability requires a normality verdict.** Reporting Cpk on
   visibly non-normal data is the classic Six Sigma malpractice. The engine
   returns the Anderson-Darling result alongside, and the panel warns.
4. **Never present more digits than are justified.**
5. **Refuse rather than guess.** n too small for a limit → a stated refusal, not a
   number.

### Validation strategy — this is the credibility of the whole module

If Cpk is wrong, everything above it is worthless. Therefore:

- **NIST StRD** (Statistical Reference Datasets) — certified values for univariate
  summaries, ANOVA and linear regression, public and freely usable. These become
  the primary test corpus, including the deliberately ill-conditioned sets
  (`Longley`, `Wampler`, `NumAcc`) that catch naïve one-pass algorithms. Use
  **Welford** for variance, QR for regression.
- **Known-answer tests** for control-chart constants against the published
  factor tables.
- **Property tests**: scale/shift invariance, permutation invariance,
  monotonicity of Cpk in the spec width.
- **Round-trip** DPMO ↔ yield ↔ sigma.

This phase ships **headless, before any UI** (§17, Phase 1) precisely so it can be
proven correct in isolation.

---

## 5. The golden thread

The centrepiece of user-friendliness, and the direct analogue of MIAUW's
`ocideck_finding_id` grouping.

DMAIC's actual logic is a chain: **VOC → CTQ → Y → X → hypothesis → solution →
control**. Every LSS review asks the same question — *"you proved X-03 causes
Y-01; where is it in the control plan?"* — and no drawing tool can answer it.
OciDeck can, because it holds the whole deck.

Two id families, auto-numbered from deck order (mirroring finding numbering,
`lib/services/finding_numbering.dart`):

- **`Y-01`** — a measurable output, defined once in front matter (§3.6), born in
  the CTQ tree or the charter.
- **`X-03`** — a candidate cause / input, born in the fishbone or the process map.

They travel as **inline Markdown text** (`**X-03** Manual retyping`) and are
parsed back — no parallel machine block, no id-to-slide table. Ids stay
meaningful in a plain-text diff.

**What it buys (the lint, §12):**

- `X-03` is a *proven* root cause but appears in **no control plan row**.
- `Y-01` has spec limits but **no capability analysis**.
- The charter promises "lead time −50%" but **no `Y` measures lead time**.
- A Pugh matrix solution addresses **no `X`** at all.
- `X-07` is in the FMEA with RPN 216 and was **never tested**.

That list is the difference between a tool that draws fishbones and a tool that
knows what a fishbone is *for*.

---

## 6. Slide types & registration

Added to `SlideType` (`lib/models/slide.dart:15`) and `slideTypeMeta` (`:152`),
all tagged `SlideCategory.procesverbetering` (§8):

| Type | `marpClass` | Layouts |
|---|---|---|
| `matrix` | `matrix` | `grid` · `hoq` |
| `canvas` | `canvas` | `regions` · `quadrant` · `board` |
| `tree` | `tree` | `tree` · `fishbone` |
| `flow` | `flow` | `flow` · `swimlane` · `vsm` |
| `phaseGate` | `phase-gate` | derived from the deck |

**The names are deliberately domain-neutral, and that is the design, not caution.**
A `matrix` engine is a typed grid; nothing about it is Lean Six Sigma. The
methodology lives **entirely in the template data** (§2) — which is exactly what
makes ~45 artefacts affordable. Three consequences worth stating:

- The `_class` token lands in the **user's Markdown** and is a permanent
  file-format commitment. `matrix` describes what the slide *is*; `lss-matrix`
  would have branded a generic primitive with a methodology it does not depend on
  — and with a trademark-adjacent abbreviation (§19).
- A **future module can reuse these engines** with its own template pack, paying
  only for templates. That is the module framework (§8) actually earning its name,
  rather than claiming it.
- They are nonetheless tagged `SlideCategory.procesverbetering` and gated with the
  module: an empty `matrix` with no templates behind it would only confuse. The
  *code* is domain-neutral; the *offer* is not.

Plus `ChartType` additions (`lib/models/chart.dart:33`): `controlChart`,
`histogram`, `pareto`, `runChart`, `boxPlot`, `probabilityPlot`, `mainEffects`,
`interaction`, `multiVari`.

The add-a-type checklist is **16 sites** (§16.2); 8 are compiler-enforced, and
`test/slide_type_meta_test.dart:11,21` guards the four map registries. Two sites
fail *silently* and must be done by hand — see §18.

---

## 7. Rendering — one scene, two backends

### The problem, measured

There is **no shared scene model today**, and the cost is visible. `_maxY` is
duplicated near-verbatim between the in-app painter
(`lib/widgets/slides/previews/chart_preview.dart:517`) and the SVG serializer
(`lib/services/parts/marp_html_service_charts.dart:149`) — same stacked sum, same
clamp, same `return m <= 0 ? 1 : m * 1.15;`. Both carry a parallel 13-branch
`ChartType` switch. Nothing links them but two test suites.

The good news, also measured: **the in-app painter is free across five surfaces.**
`SlideRasterizer` (`lib/services/slide_rasterizer.dart:334`) wraps
`SlidePreviewWidget` in a `RepaintBoundary` and PNGs it, so preview + thumbnail +
presenter + **PDF + PPTX** all come from one painter. Only the HTML export is a
genuinely second world, dispatching on the **markdown fence**
(`marp_html_service.dart:262`), invisible to `SlideType`.

### The proposal

Four engines × two renderers would mean eight painters and eight copies of the
layout maths. Instead:

```
lib/services/scene/scene.dart      # pure Dart. No Flutter.
  class Scene { double width, height; List<SceneNode> nodes; }
  sealed class SceneNode = SceneRect | ScenePath | SceneLine | SceneText | SceneImageRef
```

- **Engines produce scenes**, not pixels: `SipocLayout.build(spec, measurer) →
  Scene`. Pure functions. Unit-testable with no widget test, no golden.
- **Two thin, generic backends**, written **once** and shared by all four engines:
  - `lib/widgets/slides/previews/scene_painter.dart` — a `CustomPainter`
  - `lib/services/parts/marp_html_service_scene.dart` — an SVG serializer
- **Text measurement is injected** (`TextMeasurer`), so layout maths is
  identical in both worlds. The HTML export runs in-process, so it can use the
  same Flutter-backed measurer the painter uses — the existing
  `services/text_measurement` is already the (baselined) precedent for a service
  reaching into UI for exactly this.

**Honest caveat:** parity is *near*, not identical. The browser re-lays out text
from its own font metrics; we pin `font-size`/`font-family` and emit explicit
positions, and accept the residue. `ARCHITECTURE.md` already states HTML export
*"fidelity differs from the in-app renderer by design"*. A scene-level golden test
(assert the scene, not pixels) catches divergence in the *layout*, which is where
`_maxY` actually went wrong.

This turns a ~36% SVG surcharge with duplicated maths into a one-time ~800-line
investment. It is also the piece most worth back-porting to charts later — but
that is **out of scope here** (do not refactor charts as part of this module).

---

## 8. Module framework — the Phase 0 that is not optional

**Honest finding from the codebase, and it contradicts the code's own comments.**
`info_safety_provider.dart:11-12` claims *"This is deliberately reusable: a future
domain extension can reuse the same enable → provision → reveal pattern."* The
claim outruns the implementation.

What **is** genuinely reusable:
- `SecModuleProvisioner` / `SecPackTransport` / `SecPackStore`
  (`lib/services/info_safety/`) — cleanly injected, pure Dart, version/hash/mirrors
  are constructor params. Instantiable for a second pack today.
- `sec_pack_codec.dart` — fully domain-agnostic.
- The picker's tab bar is **derived** from categories present
  (`add_slide_dialog.dart:118-134`), so it generalises for free.

What is **hardcoded to one module** and must be generalised first:

| Site | Today | Needs |
|---|---|---|
| `infoSafetyRevealProvider` (`info_safety_provider.dart:56`) | a single global `Provider<bool>` | `moduleRevealProvider(ModuleId)` family |
| 7 consumer call sites | each names the sec module | read by `ModuleId` |
| `AddSlideDialog` (`:19`) | `bool revealInfoSafety` | `Set<ModuleId> revealed` |
| `SlideCategory` (`slide.dart:49`) | closed 2-value enum | + `procesverbetering` |
| `DeckTemplate.requiresInfoSafety` (`deck_template.dart:45`) | `bool` | `ModuleId? requiresModule` |
| `_infoSafetyCommands` (`command_palette_actions.dart:127`) | hand-spliced at `:61` | contribution list keyed by module |
| `settings_dialog_modules.dart:23` | one hardcoded card | list of module descriptors |
| prefs keys | 2 module-specific constants | namespaced per module |

**Phase 0 is a pure refactor with zero user-visible change** — which makes it
ideal for small, reviewable commits, and it de-risks everything after it.
Widening `SlideCategory` deliberately breaks the exhaustive `_categoryLabel`
switch (`add_slide_dialog.dart:136-143`) — that is a *feature*: a compile error is
a guided migration.

Behaviour is inherited unchanged from the sec module, and it is already right:
- Reveal is **enabled AND provisioned** (`info_safety_provider.dart:86`).
- **The gate is authoring-only.** Slides always render — `app_shell.dart:470` calls
  this the MODUS-REGEL. An LSS deck opened without the module still presents.
- **Auto-discovery**: opening a deck containing `matrix`/`canvas`/`tree`/`flow` classes offers to enable
  the module (`app_shell.dart:480-493`, `deck.hasSecuritySlides` analogue).

### Provisioning: do *not* cargo-cult the pack

**Honest finding:** the sec pack is **write-only**. `sec_pack_codec.dart:6-9` says
so plainly — *"the shipped pack is still a placeholder skeleton, the module's live
data … is compiled into the base app, and nothing reads the pack's contents back
yet"*. `SecPackStore.read()` is implemented and has **no production caller**;
`secPackMirrors` is labelled *"no live host serves the pack yet"*. What actually
works is far simpler: a bundled JSON asset with a loader
(`lib/services/cwe_catalog.dart:21`, `assets/cwe/cwe_full.json`) or `const` Dart
data (`miauw_eis_catalog.dart:8`).

**Recommendation: follow what works, not what was designed.** LSS reference data
is small — templates + guidance + constant tables in NL/EN ≈ **150–400 KB**, an
order of magnitude below the CWE catalog that already ships as a plain asset. So:

- Ship `assets/improvement/templates.json` (built from the Markdown template sources
  by `tool/build_improvement_templates.dart`) + a loader mirroring `CweCatalog`.
- **Do not** build a second mirror/provisioning apparatus. Enabling the module is
  then instant, offline, and needs no consent — which is *better* UX than the sec
  module's path.
- If a real mirror host ever exists, LSS can adopt the generalised pack **and be
  its first real consumer**. That is a fine follow-up; it is not a prerequisite,
  and pretending otherwise would buy ~1,000 lines of ceremony for zero user value.

---

## 9. User-friendliness

The brief asks for maximum user-friendliness. Concretely:

1. **Project wizard** — pick a framework (DMAIC / DMADV / Kaizen / A3 / 8D), name
   the project, define `Y-01` (unit, baseline, goal, spec limits), and OciDeck
   **scaffolds the whole deck**: phase sections, placeholder artefacts, the
   charter pre-filled from what you just typed. Reuses the wizard precedent
   (`lib/widgets/dialogs/finding_wizard.dart`, 324 lines) and the deck-template
   registry (`deck_template.dart:535`).
2. **Artefact picker with guidance** — inserting a SIPOC shows the template's
   `guidance` inline ("fill right-to-left — start at the customer"). Offline,
   data-driven, no LLM. This is where a Belt trainer's knowledge lives.
3. **Paste from a spreadsheet.** `parseClipboardTable`
   (`lib/utils/table_clipboard.dart:17`) is generic and already tested, but is
   wired only into `table_editor.dart:143` — **the chart grid has no paste
   handler at all**. LSS data entry starts in Excel, always. Wiring
   `parseClipboardTable` into the chart grid and `matrix` is a small, unclaimed,
   high-value win.
4. **Never ask for a derivable number.** RPN, control limits, Cpk, PCE, takt and
   sigma are computed and shown read-only, with the formula on hover.
5. **The thread is visible.** Clicking `X-03` jumps to where it is defined and
   lists everywhere it is used, reusing the existing slide-navigation rails.
6. **The escape hatch is honest.** Anything the engines do not cover stays free
   Markdown/Mermaid — no dead end.
7. **Worked examples** ship as deck templates for the training audience.

### Optional AI — a sharper guardrail than MIAUW's

Reuses the off-by-default, consent-gated backend (`services/ai_*`,
[`AI_ASSIST.md`](AI_ASSIST.md)) with the marking that blocks sealing until a human
reviews. But the LSS guardrail must be **stricter**, and the reason is
methodological, not privacy:

> **AI may draft wording. It may never produce a cause, a conclusion, or a
> number.**

An LLM asked to "brainstorm causes" will emit fluent, plausible, evidence-free
causes — and Six Sigma exists precisely to stop people acting on plausible
guesses. This mirrors MIAUW's rule that the AI *"strips any CWE/CVE/CVSS
identifier it invents"*: same shape, different noun. AI polishes a problem
statement; it does not fill in a fishbone.

---

## 10. Theming

A built-in `ThemeProfile` with LSS tokens: phase colours (D/M/A/I/C), a
value-add / non-value-add / waste triad for VSM and flow steps, and a
severity ramp reused for RPN and Pareto's vital few. The `finding_severity_palette`
(`lib/theme/finding_severity_palette.dart`) is the pattern; note
`check_conventions.dart:93` — raw `Color(0x…)` is baselined at **zero** outside
the three palette homes, so a new palette file must be registered there.

All rendering must be deterministic and isolate-safe so it flows through the
rasterizer to PDF/PPTX unchanged.

---

## 11. Derivations

Everything below is derivable from the deck + its CSVs, and all of it is offline.

| # | Derivation | From |
|---|---|---|
| 1 | **RPN** = S×O×D, re-ranking, vital few | `matrix` (fmea) |
| 2 | **Control limits** + Nelson/WE rule violations, per stage | chart + CSV |
| 3 | **Cp/Cpk/Pp/Ppk, DPMO, sigma, yield** + normality verdict | chart + `Y` spec limits |
| 4 | **Pareto**: sort, cumulative %, 80% line, vital-few callout | chart |
| 5 | **VSM roll-up**: total LT, total PT, **PCE = PT/LT**, bottleneck | `flow` (vsm) |
| 6 | **Takt** = available time / demand | front matter + VSM |
| 7 | **Little's Law** cross-check (WIP = throughput × LT) → flag contradiction | VSM |
| 8 | **SIPOC → process map → VSM** seeding | `matrix` → `flow` |
| 9 | **CTQ → data collection plan** rows | `tree` → `matrix` |
| 10 | **Charter**: gap = baseline − goal; benefit tracking | front matter |
| 11 | **X/Y auto-numbering** from deck order | golden thread |
| 12 | **Phase-gate completeness** | §12 |
| 13 | **Golden-thread lint** | §12 |
| 14 | **DPMO ↔ yield ↔ sigma converter** (a small, beloved utility) | stats core |

Mirrors PENTEST_MIAUW §10 in spirit: mechanical bookkeeping is the tool's job.

---

## 12. Two analyzers, two surfaces — and the repo already tells us which is which

The codebase has both precedents, and the choice between them is not a matter of
taste:

- **Issue-shaped output → plug into the existing quality panel.**
  `combinedSlideQualityResult` (`lib/widgets/panels/slide_quality_panel.dart:27`)
  already merges three sources (sync analyzer + async image contrast + privacy).
  The bridge pattern is `lib/services/privacy/privacy_quality_bridge.dart` — **69
  lines**. The panel's own doc comment states the rule: *"een eigen paneel zou een
  tweede plek zijn om te kijken, en de gebruiker kijkt hier al."*
- **Gap-shaped output → its own surface.** `MiauwComplianceAnalyzer` deliberately
  did **not** plug in — it produces `EisStatus`, not issues, so it got
  `miauw_compliance_panel.dart`.

Therefore:

| Analyzer | Output | Surface |
|---|---|---|
| **Golden-thread lint** (§5) | issue-shaped (slide index + severity + category) | **Plugs into the quality panel** — ~70-line bridge, one `SlideQualityCategory`, a handful of `SlideQualityIssueKind`s |
| **Phase-gate / tollgate** | gap-shaped (per artefact: present / missing / waived) | **Own panel**, modelled on `MiauwCompliancePanel` |

Two rules carried over from the privacy bridge, both learned the hard way:
- **One issue *kind* per family, not per rule** (`slide_quality.dart:34`) — because
  `formatSlideQualityIssue` is an exhaustive switch
  (`lib/l10n/slide_quality_localization.dart:210`), and every kind costs 31
  translations.
- The phase-gate panel is a **gap analysis, never a gate**. Every item is
  waivable with a reason (`ocideck_improvement_waivers`), the framework checklist is
  user-editable data (§1), and nothing ever blocks export. OciDeck has no
  standing to tell someone their DMAIC is wrong.

---

## 13. Localisation

- UI chrome: `d('Nederlandse brontekst')` — all 31 languages, enforced by
  `test/app_localizations_test.dart`. On `main`, use `make add-l10n SPEC=…`.
- **Template labels, guidance, catalog terms: data with `nl`/`en` fields, not
  `d()` strings** (§2). This is the MIAUW precedent and it is what makes ~45
  artefacts affordable.
- Watch the homograph trap (`ARCHITECTURE.md`, "Homographs — use `t()`, not
  `d()`"). LSS is full of them: *"Control"* the DMAIC phase vs. *"control"* the
  FMEA column vs. *"Beheersing"*; *"Meten"* the phase vs. the verb. Use keyed
  `t()` for every phase name.

---

## 14. Cost model — honest numbers

Measured against this codebase, not guessed. A chart-class structured type costs
**≈7,000–7,500 lines** across model, painter, SVG serializer, editor, registries
and tests (§16 breakdown below). The engines pattern plus the shared scene model
(§7) is what makes the module affordable:

| Component | Est. lines (incl. tests) |
|---|---|
| Phase 0 — module framework generalisation | ~600 |
| Stats core + NIST validation | ~3,000 + ~2,000 tests |
| Chart extensions (9 new `ChartType`s, reusing everything) | ~3,500 |
| Scene model + 2 backends (one-time) | ~1,200 |
| 4 engines × (spec/parse + layout + editor + tests ≈ 1,900) | ~7,600 |
| Templates + library + loader + asset build tool | ~1,000 |
| Golden thread + quality-panel bridge | ~500 |
| Phase-gate analyzer + panel | ~600 |
| Wizards + deck templates | ~1,400 |
| **Total** | **≈22,000–28,000** |

**Calibration:** the existing MIAUW module measures **≈14,100 lib lines + ≈7,500
test lines ≈ 21,600**. So this module is **≈1.2–1.4× MIAUW** — a large but proven
shape for this codebase, and *one order of magnitude* below option A's ~300k.

### The ratchets are not negotiable

- `maxFileLines = 1000`, `fileSizeBaseline = {}` — **empty**
  (`tool/check_conventions.dart:67`, `:74`). Every one of the 426 `lib/` files
  complies today, and the biggest are at ~97% (`cockpit_preview.dart` 967,
  `marp_html_service_charts.dart` 893, `slide_preview.dart` 889). The
  `chart_preview` split into `_cartesian`/`_extra`/`_radar` is the ratchet's
  fingerprint, not style. **Budget the `part`/`part of` split from day one.**
- `maxMethodLines = 150`, baseline also **empty** (`tool/check_method_length.dart:26`, `:32`), AST-measured.
- `make check` runs `coverage --min=79 --require-instrumented` (Makefile) —
  every `lib/` file must appear in at least one test, and `check-dead-code` fails
  on any file not reachable from an entrypoint. **A painter that is not yet wired
  into `_buildContent` fails the build.** Land each engine end-to-end, never
  half.
- No new `pubspec.yaml` dependency without `make sbom` (§4 says: don't).
- CI has no runner; **local `make check` is the real gate.**

---

## 15. Phased implementation plan

Ordered so that risk is retired early and each phase is independently useful.

| Phase | Content | Ships value? |
|---|---|---|
| **0 · Module framework** | `ModuleId` registry; migrate the 7 sec gate sites; widen `SlideCategory`; `requiresModule`; module-keyed commands + settings. **No user-visible change.** | no (de-risking) |
| **1 · Stats core** | `lib/services/improvement/stats/` headless + NIST StRD validation. No UI at all. | no (de-risking) |
| **2 · Chart extensions** | Pareto, histogram+capability, run chart, box plot, control charts. Reuses `ChartSpec`, CSV, grid, SVG. **+ wire `parseClipboardTable` into the chart grid.** | **yes — earliest real value** |
| **3 · Scene + `matrix`** | Scene model + both backends; the grid engine; templates SIPOC / FMEA / control plan / RACI / Pugh / data collection plan | yes |
| **4 · `canvas`** | Regions engine; A3, charter, quadrant, SWOT, board | yes |
| **5 · `tree`** | Tree + fishbone layouts; CTQ, 5× Why, Ishikawa. **Golden-thread ids appear here.** | yes |
| **6 · `flow`** | Flow + swimlane; then VSM layout + roll-ups (PCE, takt, Little) | yes |
| **7 · Thread & gates** | Golden-thread lint → quality panel; `phaseGate`; tollgate panel; project wizard; deck templates | yes |
| **8 · MSA / inference** | Gage R&R, hypothesis tests, regression — UI over the Phase-1 engine | yes |
| **9 · DOE** | Full/fractional factorial, main-effects & interaction plots | yes |
| **10 · AI (optional)** | Wording only, never causes/conclusions/numbers (§9) | yes |

Phases 0–1 deliberately ship nothing a user can see. That is the point: the
module framework and the arithmetic are the two things that are expensive to fix
later and cheap to get right first. Docs (USER_GUIDE + SOURCE_MAP + FILE_FORMAT +
CHANGELOG) are updated **per phase**, not at the end.

---

## 16. Reference: the add-a-type checklist (measured)

### 16.1 What the painter buys you for free

`SlidePreviewWidget` (`lib/widgets/slides/slide_preview.dart:301`) feeds preview,
thumbnail, presenter, audience window, play-only, diff/finder/import dialogs
**and** PDF + PPTX (via `slide_rasterizer.dart:334`). One painter, seven
surfaces, zero incremental cost.

### 16.2 The 16 sites

Map registries (guarded by `test/slide_type_meta_test.dart`):
1. `lib/models/slide.dart:15` — the enum
2. `lib/models/slide.dart:152` — `slideTypeMeta`
3. `lib/widgets/editors/slide_editor_registry.dart:80` — `slideEditorBuilders`
4. `lib/widgets/panels/editor_panel.dart:345` — `slideTypeIcons`

Compiler-enforced switches:
5. `slide_preview.dart:626` — `_buildContent`
6. `lib/services/markdown_service.dart:392` — serialize
7. `lib/services/slide_quality_analyzer.dart:389` — alt-text
8. `lib/services/slide_quality_analyzer.dart:538` — missing media
9. `lib/services/parts/slide_quality_analyzer_density.dart:69` — density
10. `lib/widgets/editors/slide_type_help.dart:16` — help text
11. `lib/widgets/dialogs/add_slide_dialog.dart:388` — picker wireframe painter

**Silent sites — no compiler help, no guard:**
12. `slide_preview.dart:864` — `_contentLeftInset` has a `default:` → silently wrong
13. `lib/services/markdown_service_parse.dart:560` — the class-token if/else chain
14. `lib/services/markdown_service_fenced.dart` — a `_parseXBlock` per structured type
15. `add_slide_dialog.dart:49` — picker ordering
16. `lib/models/deck_template.dart:535` — template registry

**And the HTML/SVG path is invisible to all of it** — it dispatches on a fence
regex (`marp_html_service.dart:262`) and never sees a `SlideType`. No registry,
no guard, no compile error. That is where the honest risk sits, and it is exactly
what §7's scene model is for.

---

## 17. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| **Wrong statistics** | fatal — the module's whole credibility | NIST StRD, known-answer tables, property tests, Phase 1 headless before any UI (§4) |
| **Scope creep** — the artefact list never closes | high | Engines × templates: a new artefact is data, not code (§2) |
| **SVG/painter divergence** | high — precedent: `_maxY` duplicated verbatim | Shared scene model, injected measurer, scene-level goldens (§7) |
| **File-size ratchet** | medium — biggest files at 97% of cap, baseline empty | `part`/`part of` split from day one; budget it (§14) |
| ~~**`parseCsv` is naïve** — no quoted fields~~ | ~~medium~~ — **retired in full** ahead of this module (§18.8): RFC 4180 quoting, per-file separator detection (`,` `;` tab), and number conventions deduced from evidence across the whole file (`utils/number_convention.dart`) | Nothing outstanding for LSS to decide. `1.234,56` and `10,5` read correctly; a file that genuinely cannot say (only three-digit comma groups) is asked about at import rather than guessed. Locale is deliberately *not* used as a tiebreak — a colleague's export does not follow the reader's region |
| **Cpk on non-normal data** | medium — methodological malpractice | Normality verdict is mandatory alongside every capability figure (§4) |
| **Standards/trademark** | medium | §19 — no bundled normative text, no conformance claims, naming reviewed |
| **VSM painter complexity** | medium | Last of the engines (Phase 6), after the scene model has proven itself twice |
| **l10n explosion** | contained | Template content is data (NL/EN), not `d()` (§13) |
| **Concurrent branches on l10n maps** | low but recurring | Known: use a `merge=union` rebase |

---

## 18. Non-goals & explicit exclusions

- **Spaghetti diagram** — an image with coordinate-placed polylines. It fits no
  engine; it is closest to the ink/annotation layer, which is presentation-time
  and deliberately *not* in the `.md`. **Deferred** — see §20.
- **Response-surface / optimal DOE designs**, mixture designs — out. Full and
  fractional factorial only (§4).
- **Time-series forecasting**, SPC alarming, live data feeds — out. Decks are not
  dashboards; the `cockpit` slide type already exists for that.
- **AIAG-VDA Action Priority tables** — copyrighted. RPN (public arithmetic) only.
- **Refactoring the chart engine onto the scene model** — tempting, out of scope.

---

## 19. Licensing, naming & standing

The MIAUW module could bundle its standard (EUPL 1.2). **This one cannot**, and
the plan is built around that. Register evidence below was gathered on
**2026-07-16**; re-check before a public release.

> **This is research, not legal advice.** It is recorded so a decision can be
> made with the facts visible, not so the decision is already made.

### 19.1 Copyright

| Artefact | Status | Consequence |
|---|---|---|
| **ISO 13053-1/-2:2011**, ISO 18404 | paywalled ISO standards | ISO's prohibition reaches reproduction of the **document** — expressly including *"using parts of it … in software"* — but **not implementation of the method it describes**. So: may cite by number, may implement DMAIC; may **not** embed ISO wording, tables or factsheets verbatim; must never republish. |
| **ASQ / IASSC / CSSC Bodies of Knowledge** | copyrighted | Not copied. Our framework checklist is authored in-house from widely-published practice, and is **editable data** (§1). |
| **NIST StRD** | US government work, freely usable | Bundled as **test fixtures only**, not shipped in the app. |

The idea/expression line is what saves this: DMAIC as a *method* is unprotectable;
ISO's *prose about* DMAIC is not.

### 19.2 Trademarks — United States

| Mark | Reg. | Owner | Status | Classes |
|---|---|---|---|---|
| SIX SIGMA (stylised) | **1813630** | Motorola Trademark Holdings, LLC | **LIVE**, renewed **2024-04-18** (3rd renewal) | **16 + 41 only**, both field-limited to *electronics and communications equipment* |
| SIX SIGMA | 1647704 | Motorola | **DEAD** — cancelled **2016-01-29**, §8 failure | 41, *no* field limit |

Two corrections to the received wisdom, both material:

- The live mark is **not "limited to electronics/communications goods"** — it never
  covered goods at all. It covers *printed publications* (cl. 16) and *educational
  services* (cl. 41) in that field. It does **not** reach class 9 (software) or
  class 42.
- The registration that *could* have read broadly onto quality methodology — the
  unlimited 1991 class-41 service mark — **is gone**. The survivor is the narrow
  one. It is nonetheless live and actively maintained, so it cannot be waved away
  as abandoned.

### 19.3 Trademarks — EU & Benelux (the operative jurisdiction)

This is the register that matters for a Dutch publisher, and it had to be queried
directly (TMview, EUIPO + BOIP; TMview is *not* an official register and has no
legal effect — verify at EUIPO/BOIP before relying on it).

**The bare terms are unowned in the EU:**

| Mark | No. | Owner | Status | Classes |
|---|---|---|---|---|
| **LEAN SIX SIGMA** | EM 002663938 | George Group Consulting, L.P. | **Ended** | 41 |
| **SIX SIGMA** | EM 002589489 | Six Sigma Ranch, LLC *(a winery)* | **Ended** | 36 |
| SIX SIGMA | BX 989402 | Six Sigma Ranch, LLC | Registered | 25, 33 *(clothing, wine)* |
| SixSigma | EM 002346427 | GKN Sinter Metals GmbH | Ended | 25,26,35,41,42 |

**No live EU/Benelux mark containing "six sigma" covers class 9 (software).** The
only two that ever did are dead: POWER SIX SIGMA (EM 004130324, Power Steering
Software, cl. 9) **Expired**, and ONESIXSIGMA (EM 003879905, cl. 9…42) **Expired**.

**What *is* live is a cluster of composite marks owned by training providers**, in
classes 35/41/42 — and several are Dutch or Belgian, i.e. this module's own
neighbourhood:

| Mark | No. | Owner | Classes |
|---|---|---|---|
| THE LEAN SIX SIGMA COMPANY | EM 010796852 | R. Schildmeijer Beheer BV / Breze Beheer BV **(NL)** | 35, 41 |
| LEAN SIX SIGMA CONSULTANT | **BX 1360295** | Willem Salentijn **(Benelux)** | 35, 41 |
| LSSA Lean Six Sigma Academy | EM 013136569 | LSSA | 41 |
| Lean Six Sigma France | EM 018705275 | Lean Six Sigma France | 35, 41, **42** |
| Lean Six Sigma Belgium | EM 018707043 | Lean Six Sigma Belgium | 35, 41, **42** |
| Lean Six Sigma International | EM 019281682 (2025) | Lean Six Sigma Belgium | 35, 41, **42** |
| INTERNATIONAL LEAN SIX SIGMA | EM 019217689 (2025) | S. L. Mayagoitia González | 41 |
| IFSS — INSTITUTE FOR LEAN SIX SIGMA | EM 013489117 | IBB Internationale Betriebs Beratung GmbH | 16, 35, 41 |

**DMAIC / DFSS are clear.** No bare DMAIC registration exists in the EU — only the
composite *"Digital DMAIC CESAP…"* (EM 017932955). *"Design for Six Sigma"*
returns **zero** EU/Benelux hits. So the phase and framework names are safe to use
as-is.

**Reading it.** The EU is *more* permissive than the US on the bare terms —
everyone who tried to own "Lean Six Sigma" or "Six Sigma" outright has lost or
abandoned it, and EUIPO would very likely refuse the bare term today as
descriptive (Art. 7(1)(c) EUTMR). But three live composites sit in **class 42**,
which covers software design and SaaS, and the Dutch/Benelux ones belong to
exactly the trainers who would *use* OciDeck. That is a different risk texture from
Minitab's US position: not "will Motorola sue", but "does a Dutch LSS training
company read our module name as trading on theirs".

### 19.4 Certification marks — not implicated

ASQ's CSSBB/CSSGB and IASSC's marks are a **separate regime**: by policy they
attach one-to-one to an **individual** holding a current credential, and permitted
use is **personal self-identification only** (website, e-mail signature, business
card). Nothing in those policies licenses — or is touched by — naming or building
a software product. **Merely supporting the methodology in software does not
implicate them.** Cleanly avoidable, and avoided: OciDeck offers no training and
no certification.

### 19.5 Market practice

Vendors use the terms freely as **product and in-product feature names**, not just
in prose: Minitab ships a paid in-product **"Six Sigma"** module and a **"Lean Six
Sigma"** solution line; iGrafx ships a **"Lean Six Sigma Tools"** template category
*in its shipped UI* and sells *"iGrafx Process for Six Sigma"* — including in the
EU. None carry ®/TM on the methodology terms; none attribute Motorola.

**But market practice is evidence of tolerance, not of a right.** No adjudicated
proceeding was found in either direction — no suit, no TTAB opposition, no EUIPO
opposition, no cease-and-desist, and **no ruling anywhere on genericness**. No
docket search was run. **Absence of found evidence is not evidence of absence.**

### 19.6 Fair use — and why it does not rescue a feature name

This is the crux, and it cuts against naming:

- **EU (operative).** Art. 14(1)(b) EUTMR permits descriptive use — it is a solid
  basis for saying a feature *"supports Lean Six Sigma"*. Art. 14(1)(c)
  referential use is about referring to **the proprietor's** goods, and **does not
  stretch to naming your own module**. All of Art. 14(1) is conditional on Art.
  14(2) *honest practices*.
- **US.** A registrant of a descriptive term gets exclusive rights only in the
  secondary, source-identifying meaning — no monopoly by grabbing it first, and the
  plaintiff always bears the confusion burden. But the §1115(b)(4) descriptive
  fair-use defence requires use **"otherwise than as a mark"** — which a feature
  *name* arguably is not.

Both regimes protect **describing what a tool does**, not **branding your own
feature**. That asymmetry is the whole decision.

### 19.7 Decision

**The module is named "Procesverbetering". "Lean Six Sigma" is used only
descriptively, in prose.**

Rationale, in order of weight:

1. **The naming choice buys almost nothing and carries the only real residual
   risk.** Every defence protects the prose, not the label. There is no upside to
   spend risk on.
2. It is **accurate and broader**: the module serves Lean/Kaizen/A3 users who do
   not call themselves Six Sigma practitioners.
3. It matches the Dutch-first naming of the sibling module,
   "Informatieveiligheid".
4. It keeps a live-mark neighbourhood — Dutch and Belgian training providers in
   classes 35/41/42 — off the product surface.

**Safe wording** in README/USER_GUIDE/CHANGELOG: *"supports Lean Six Sigma
projects (DMAIC, DMADV, Kaizen, A3)"*, *"Lean Six Sigma artefacts"* — descriptive,
lower-case in running text, no ®/TM, no logo, no claim of endorsement,
certification or ISO conformance. **Never**: a menu item, class name, settings
label, marketing headline or package name that reads *"Lean Six Sigma"* as the
name of the thing.

Residual items for counsel, if a public release is planned: (a) whether the
class-42 composites materially change the picture; (b) whether "Procesverbetering"
plus descriptive prose is the complete answer or whether a short trademark notice
is warranted. Tracked as §20.2.

---

## 20. Open questions

1. ~~**Module name**~~ — **resolved (2026-07-16): "Procesverbetering"**, on the
   register evidence in §19. `ModuleId.procesverbetering`,
   `SlideCategory.procesverbetering`.
2. **Trademark — residual items for counsel** *(only if a public release is
   planned; §19.7)*: (a) do the live class-42 composites (Lean Six Sigma
   France/Belgium/International) change the picture, given class 42 covers software
   design? (b) is the neutral name plus descriptive prose the complete answer, or
   is a short trademark notice warranted? Note what §19.5 could **not** establish:
   no enforcement history was found **in either direction**, and no docket search
   was run — absence of found evidence is not evidence of absence.
3. **Spaghetti diagram** — accept the deferral, or is an image+polyline overlay
   engine worth a fifth canvas type? (It would also serve floor layouts and 5S.)
4. **Sigma-level default** — ship with the 1.5σ shift on or off by default? Both
   are defensible; the field is genuinely split. Whichever we pick, it is visible
   per metric (§4).
5. **Framework checklist authorship** — who writes the DMAIC/DMADV artefact
   expectations, and against what public sources, given §19?
6. **Template pack distribution** — bundled asset only (recommended, §8), or also
   importable third-party packs through the existing import sanitisation? The
   latter is the Belt-trainer's ask and reuses `finding_template`'s export/import
   shape.
7. **Does LSS become the sec pack's first real consumer** (§8), or do we leave the
   pack write-only and revisit when a mirror host exists?
8. ~~**`parseCsv` fix** — Phase 2 as proposed, or a separate pre-cursor PR since it
   is a pre-existing bug affecting charts today?~~ **Decided: a separate
   pre-cursor PR**, done, in two rounds. It hit chart users today and nothing
   about the fix needed this module, so it did not wait for a phase that is not
   built. Three rounds in the end: quoting, then separator detection plus
   surfacing what could not be read, then number conventions. The last one
   turned out not to be the LSS data question it was filed as — most of it is
   deducible from the file, and the small remainder is a question for whoever
   has the file open, not for this module. Nothing here is left waiting on LSS.

---

## 21. Prior art in this repo

Nothing here is novel; almost every mechanism has a working precedent:

| This module needs | Existing precedent |
|---|---|
| Opt-in module, enable → reveal | `lib/state/info_safety_provider.dart` |
| Native domain engine, no dependency | `lib/services/cvss/` (CVSS 4.0) |
| Lookup-table-driven maths | CVSS MacroVector table |
| Structured slide type + `_class` round-trip | `finding`, `checklist`, `scopeMatrix` |
| Layout/animation as a *field*, not a type | `TimelineLayout`, `TimelineReveal` |
| `a :: b :: c` list payload | timeline events |
| Tab-indented hierarchy | `bulletLevel()` (`slide.dart:63`) |
| Derived-never-stored | finding severity from CVSS |
| Inline ids parsed back from text | CWE/CVE/CVSS in a finding body |
| Group by shared id | `ocideck_finding_id` + `FindingRole` |
| Auto-numbering | `finding_numbering.dart` |
| Templates as Markdown + front matter | `finding_template_library.dart` |
| Wizard | `finding_wizard.dart` |
| Bundled catalog as JSON asset | `cwe_catalog.dart` + `assets/cwe/` |
| Gap-analysis panel | `miauw_compliance_panel.dart` |
| Issue bridge into the quality panel | `privacy_quality_bridge.dart` (69 lines) |
| Data linked as CSV, stripped on save | `ChartSpec.source` + `_hydrateCharts` |
| Ask once, propagate everywhere | MIAUW CIA → CVSS environmental |
| Off-by-default AI with a hard guardrail | `AI_ASSIST.md` |
