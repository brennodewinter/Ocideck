# OciDeck — Risk dossier file contract (Design)

> **Status:** design proposal, revision 1 — decided by owner 2026-10-20, implementation in progress · **Published by:** Stichting LibreKAT

This document fixes the open file contract for risk dossiers in OciDeck
(EPIC #2485, gate issue #2488). It covers where canonical risk records,
measures, scales, linked views, formulas and Bowtie models live inside an
ordinary `.md` file, how other tools see the same bytes, and how old and new
readers round-trip without losing data they do not understand.

Owner decisions recorded (2026-10-20):

- **D1** — Canonical records live in a **GFM table carrying a visible ID
  column**, with machine metadata in a preceding `<!-- ocideck:* -->` comment
  marker. Not YAML front matter, not a fenced data block.
- **D2** — A linked view is a **real GFM table plus a `view` marker**: cells
  hold materialised values so any reader sees content; OciDeck regenerates
  them and treats them as read-only. Hand edits surface as discrepancies in
  the quality check, they are never silently overwritten.
- **D3** — A table formula travels as a **`calc` marker line** next to the
  table marker; the cell holds the computed value.
- **D4** — Link scope is **within one file**. A table copied to another file
  becomes an independent, fully readable snapshot. Cross-file links are out
  of scope until a separate, explicit design.

The deciding test (bewaker): open the `.md` in a text editor and in another
Marp/Markdown tool — every risk, measure, score and warning is still readable
as ordinary tables; every machine marker is an HTML comment a foreign reader
ignores harmlessly.

## 1. Weighed alternatives

Three shapes were weighed. D1 picked A.

### A. GFM table + comment marker (recommended, chosen)

```markdown
<!-- ocideck:risks v1 id=hoofd method=fmea scale=sod-1-10 rev=3 -->
| ID | Faalwijze | S (bruto) | O (bruto) | D (bruto) |
|----|-----------|-----------|-----------|-----------|
| R-001 | Sensor valt uit | 7 | 4 | 5 |
```

- *For:* the only representation a plain reader needs is the table itself;
  the marker is the same mechanism OciDeck already uses
  (`<!-- ocideck_template: fmea -->`, `<!-- spacer -->`). One truth: the row
  IS the record.
- *Against:* wide tables get unwieldy in raw text (accepted — Markdown
  tables are still diffable and editable; views exist to show subsets).
- *Against:* a hand edit can desync a marker claim (e.g. `cols=`) from the
  header row. Mitigated: positional `cols=` contract + the quality check
  reports mismatches instead of guessing.

### B. YAML front-matter records (rejected)

Records as YAML in front matter, tables rendered from them.

- *For:* compact machine grammar, native types.
- *Against:* risk content leaves the readable Markdown body — a missing or
  truncated front-matter block makes the only risk description disappear,
  which the issue explicitly forbids. Two representations (YAML + rendered
  table) invite exactly the dual-truth drift this format exists to prevent.

### C. Fenced data block (rejected)

A ```` ```ocideck-risk ```` block with structured data next to a readable table.

- *For:* one machine-readable source, arbitrary depth.
- *Against:* renders as raw code in Marp and other readers; the block and the
  table can drift (two truths again); foreign tools cannot edit the data
  meaningfully. A fenced block is right for *opaque render input* (charts,
  quiz) — wrong for *content the user must be able to read and fix by hand*.

## 2. Marker grammar

```text
<!-- ocideck:<kind> v<version> <key=value> [<key=value> …] -->
```

- One marker per line, on its own line, directly above the table it
  annotates (blank line allowed between marker block and table for
  readability; not between stacked markers). Several marker lines may stack
  — the same convention as the slide comment block
  (`ocideck_template`, `ocideck_layout`, view-limit comments).
- `key=value` tokens are separated by single spaces; values containing
  spaces or `|` are double-quoted. Keys are lowercase `[a-z][a-z0-9_]*`.
- `v<N>` is the marker grammar version. A reader that meets a higher `v` or
  an unknown `kind` preserves marker and table verbatim and treats the table
  as ordinary — see §6.
- Kinds: `risks`, `measures`, `scale`, `view`, `bowtie`, `calc`.

## 3. Canonical records

### 3.1 Identity

- Risks carry visible IDs `R-<digits>` (`R-001`), measures `M-<digits>`.
  Bowtie path groups use `P-<digit>`. IDs are document-scoped, allocated by
  the owning table's `next=` counter, and **never reused** within a file —
  a deleted `R-004` stays deleted; a new risk is `R-005`.
- The ID column is a normal visible column (contract key `id`); header text
  is free (`ID`, `Nr.`, …).
- Duplicate or missing IDs are integrity findings for the quality check
  (#2490), never silently renumbered.

### 3.2 The `cols=` contract

Every marked table declares its column meaning positionally:

```text
cols=id,step,failure,effect,s_b,cause,o_b,control,d_b,measures
```

- Keys are machine names; the header row above them is free text, so
  authors may rename headers or translate them without breaking the
  contract.
- If the `cols=` count differs from the header count, or a required key is
  absent, the table still opens — the quality check reports it.
- Columns present in the table but not in `cols=` are treated as free
  author columns and preserved verbatim.

### 3.3 `risks` — the risk register

```markdown
<!-- ocideck:risks v1 id=hoofd method=fmea scale=sod-1-10 rev=3 next=4 -->
| ID | Processtap | Faalwijze | Effect | S b | O b | D b | Maatregelen | S n | O n | D n | Netto-basis | Netto-datum | Netto-door |
```

Contract keys (per method; `*_b` = bruto/inherent, `*_n` = netto/residual):

- shared: `id`, `title`/`failure`, `description`, `status`, `source`,
  `assessed`, `measures`, `notes`, `x-*` (author columns)
- `method=fmea`: `step`, `effect`, `cause`, `control`, `s_b`, `o_b`, `d_b`,
  `s_n`, `o_n`, `d_n`, `netto_basis`, `netto_date`, `netto_by`
- `method=likelihood-impact`: `event`, `cause`, `consequence`,
  `existing_measures`, `l_b`, `i_b`, `l_n`, `i_n`, `netto_basis`,
  `netto_date`, `netto_by`, `uncertainty`

Derived values (`RPN`, risk class) are **never contract keys** — they are
computed at render/export, exactly as `MatrixSpec.derivedRpn` already works.

### 3.4 `measures` — the measure register

```markdown
<!-- ocideck:measures v1 id=mat rev=2 next=3 -->
| ID | Type | Beschrijving | Eigenaar | Status | Bewijs | Toetsdatum | Vervalt | Risico's |
```

Contract keys: `id`, `type` (`preventive|detective|mitigating|escalation`),
`description`, `owner`, `status`, `evidence`, `test_date`, `expires`,
`risks` (comma-separated `R-###`), `notes`.

Status tokens in the file (UI localises):

| token | meaning |
|---|---|
| `proposed` | suggested, not accepted |
| `planned` | accepted, not yet done |
| `implemented` | done, not yet tested |
| `tested` | tested, outcome recorded |
| `working` | tested and effective |
| `ineffective` | tested, does not work |

`planned`/`implemented` measures never lower a netto score by themselves:
netto exists only after an explicit re-assessment (`netto_basis` referencing
`tested`/`working` measures + `netto_date` + `netto_by`).

### 3.5 `scale` — assessment scale

```markdown
<!-- ocideck:scale v1 id=lik5 version=1 -->
| Waarde | Label | Betekenis |
```

Built-in scales referenced by name: `sod-1-10` (FMEA S/O/D 1–10),
`li-1-5` (likelihood × impact 1–5). A custom scale table is a marked table
with `cols=value,label,meaning` and a `version` attr; `risks` markers point
at it via `scale=<id>`. Editing a scale after assessments exist triggers an
impact overview in the UI — stored scores are never silently rewritten.

### 3.6 `view` — linked projection

```markdown
<!-- ocideck:view v1 source=hoofd projection=netto gen=3 cols=id,failure,s_n,o_n,d_n,rpn sort=s_n:desc -->
| ID | Faalwijze | S n | O n | D n | RPN |
```

- `source` = `id` of a marked table in the same file. `projection` is a
  named subset (`bruto`, `netto`, `overview`) or omitted for an explicit
  `cols=`/`filter=`/`sort=` projection.
- The table body holds the materialised values (D2). OciDeck regenerates
  them on open/edit/export and marks the cells read-only; a foreign edit is
  a discrepancy the quality check shows with inspect/adjust/detach choices.
- `gen=<rev>` records the source `rev` the snapshot was built from — a cheap
  staleness hint only; the quality check always compares values, never
  trusts `gen`.
- Detaching ("Loskoppelen als momentopname") removes the marker and leaves
  the ordinary table — the documented exit, as easy as the entry.

### 3.7 `calc` — bounded formulas

```markdown
<!-- ocideck:calc col=rpn_n expr="s_n * o_n * d_n" -->
```

- Stacked on the owning table's marker block; `col` names the derived
  contract key, `expr` the expression.
- Grammar (whole language, nothing else): decimal literals, `+ - * / ( )`,
  column refs `key` (current row), row-qualified `key@R-001`, aggregates
  `sum(key) avg(key) min(key) max(key) count(key)`, `wsum(valueKey,weightKey)`.
- Rules: no code evaluation, no functions beyond the list, no references
  outside the file. Empty/unparseable input → result *unknown* (rendered
  `—`), never `0`. Division by zero, overflow and cycles → *unknown* plus a
  quality-check finding. References follow IDs and column keys, not screen
  position, so sorting/inserting rows never retargets a formula.
- The cell stores the last computed value so every reader sees a number;
  OciDeck recomputes on load/edit/export and flags stored-vs-computed drift
  via the quality check. Typing into a derived cell asks first (change
  input / edit formula / replace formula) — the formula is only removed by
  the explicit, undoable "replace" choice.

### 3.8 `bowtie` — Bowtie source model

```markdown
<!-- ocideck:bowtie v1 id=bt1 rev=1 cols=path,side,role,element,measure,status,owner -->
| Pad | Zijde | Rol | Element | Maatregel | Status | Eigenaar |
| P-1 | links | dreiging | Corrosie | | | |
| P-1 | links | barriere-preventief | Coating inspecteren | M-002 | werkt | J.J. |
| P-1 | top | topgebeurtenis | Breuk in leiding | | | |
| P-1 | rechts | barriere-mitigerend | Noodafsluiter | M-003 | gepland | |
| P-1 | rechts | gevolg | Overstrooming | | | |
| P-1 | links | escalatiefactor | Inspectiecapaciteit te kort | M-004 | voorgesteld | |
```

- One row per element; `path` groups rows into threat→consequence paths;
  `role`: `dreiging|barriere-preventief|topgebeurtenis|barriere-mitigerend|
  gevolg|escalatiefactor|barriere-escalatie` (file tokens are Dutch-domain
  neutral English in practice: `threat|barrier-preventive|top-event|
  barrier-mitigating|consequence|escalation|barrier-escalation` — both are
  accepted on read, the English set is written).
- `measure` links a barrier to the shared `measures` table — a barrier IS a
  measure viewed in a path role, not a second dataset. Per-path status may
  differ from the measure row only through an explicit override column.
- An incomplete bowtie (missing top event, open path side) is a draft:
  valid to keep, visibly warned — never rendered as full coverage.

## 4. Full example

See [`examples/risk-dossier.md`](examples/risk-dossier.md). In a plain
Markdown reader it is a section with five ordinary tables; in Marp the
comments vanish; in OciDeck it is a dossier with a bruto/netto view, an
overview, and a Bowtie.

## 5. Parse and write rules

1. A marker binds to the first table that follows it; markers not followed
   by a table are preserved verbatim and ignored as annotation.
2. Readers preserve **every** `<!-- ocideck:* -->` line they do not consume,
   in position — including markers of unknown kind/version and unknown
   attributes on known kinds. Nothing is dropped on save.
3. Writers never invent markers: a table only becomes `risks`/`view`/…
   through an explicit user action. Opening and saving a file without
   touching a marked table leaves its bytes unchanged.
4. `rev` bumps once per committed mutation of that table (row/cell/structure).
   `next=` bumps on ID allocation only — never reused, gaps stay.
5. Sorting reorders body rows only: header, delimiter and markers do not
   move; the `cols=` contract is positional and unaffected (§3.2).
6. Escaping is the existing `encodeMarkdownTableCell` contract (`\|`, `\\`,
   `<br>`); marker attribute values use double quotes with `\"` escape.
7. A marked table inside a deck slide follows the same rules; slide-level
   metadata comments (class, template) stay in the slide comment block and
   are independent of table markers.

## 6. Compatibility matrix

| Reader | What it sees | Round-trip |
|---|---|---|
| Plain Markdown editor / Marp | Ordinary tables; comments invisible | Full — nothing to lose |
| Other GFM tool | Same | Full |
| Older OciDeck (pre-dossier) | Tables editable; in document visual mode unknown comments surface as source fragments (the `#2463` mechanism); in decks they pass through the slide comment block | Markers preserved; a resave can demote a `view` to a plain table only if the user edits it — acceptable, documented |
| OciDeck with this contract | Typed dossier UI, linked views, quality check | Full |

New file in old reader: the ID columns and materialised view values remain
readable text — no information is hidden behind the format. Old file in new
reader: unmarked tables stay unmarked; upgrading is explicit (§7).

## 7. Migration of existing FMEA content

- A matrix slide carrying `<!-- ocideck_template: fmea -->` keeps working
  unchanged as a legacy matrix; nothing auto-converts.
- An explicit "import as risk dossier" action maps template columns by key
  (`severity→s_b`, `occurrence→o_b`, `detection→d_b`, `control→control`,
  `cause→cause`, `step→step`, `failure→failure`, `effect→effect`), allocates
  `R-###` IDs, and leaves every original cell intact. New fields start
  empty — never guessed. RPN is derived on both sides, so nothing derived
  is copied.
- Free GFM tables import via the same explicit column-mapping preview.
- A copy of a marked table to another file arrives **without** the marker:
  an independent snapshot per D4, visibly labelled as such.

## 8. Quality-check hooks (feeds #2490)

Blocking integrity errors: duplicate/empty IDs, `cols=` mismatch,
view `source` not found, measure reference to a nonexistent `M-###`,
formula cycle. Content warnings: unassessed risk, netto without
`netto_basis`+tested/working measure, stale view (`gen < rev` or value
mismatch), formula stored-vs-computed drift, invalid scale value,
barrier on the wrong side, expired `test_date`. A draft may export as
draft with a visible warning; never as quiet certainty.

## 9. Explicit non-goals

- No certification claim, no AIAG/VDA Action Priority without a licensed
  implementation; RPN is presented as OciDeck-RPN.
- No cross-file linking (D4), no network, account, or telemetry anywhere in
  the contract.
- No hidden sidecar that would make the `.md` alone incomplete.
- No automatic risk acceptance — human sign-off with name, date and
  motivation is data, not a computed verdict.
