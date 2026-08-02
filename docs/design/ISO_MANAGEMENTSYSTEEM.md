# OciDeck — Managementsysteem-rapportage (ISO 27001 / 9001 / 42001) · product design

*De module waarmee een organisatie de **voortgang van haar eigen
managementsysteem** rapporteert: ISO/IEC 27001 (ISMS), ISO 9001 (QMS) en
ISO/IEC 42001 (AIMS). Verslag richting directie, bestuur, of een certificerende
instantie.*

> **Status:** ontwerp (nog niet gebouwd) · **Laatst herzien:** 2026-08-02 · **Uitgegeven door:** Stichting LibreKAT

> **Dit spiegelt bewust twee bestaande modules.** De informatieveiligheid-module
> ([`PENTEST_MIAUW.md`](PENTEST_MIAUW.md)) rapporteert een *pentest* tegen een
> norm; de procesverbetering-module ([`PROCESS_IMPROVEMENT.md`](PROCESS_IMPROVEMENT.md))
> voert *Lean Six Sigma*-werk. Deze module is de derde tak op dezelfde stam:
> **compliance-voortgang tegen een managementsysteemnorm.** Waar dit doc een
> mechanisme noemt dat al bestaat, verwijst het naar de siblingdoc in plaats van
> het over te schrijven.
>
> **Geschreven om koud opgepakt te worden:** exacte bestandspaden, datavormen,
> invarianten en open vragen staan uitgeschreven, zodat een latere bouwsessie
> niets hoeft te herleiden.

---

## 1. Doel & scope

Een organisatie die aan ISO 27001, 9001 of 42001 werkt, moet periodiek verslag
doen van de **voortgang**: welke eisen en beheersmaatregelen zijn geïmplementeerd,
welke lopen nog, wie is eigenaar, welke afwijkingen zijn open, en welke
verbeteracties draaien. Vandaag doen mensen dat in losse spreadsheets en
PowerPoints waarin het overzicht en de details uit elkaar lopen. OciDeck kan dat
in één bestand, met het overzicht **afgeleid** uit de details — dus consistent by
construction, precies zoals de MIAUW-compliance-overview en de management-summary
dat nu al doen.

### Bron van waarheid voor de normen

De drie normen delen sinds Annex SL dezelfde **geharmoniseerde structuur** (HS),
clausules 4–10:

| Clausule | HS-onderwerp |
|---|---|
| 4 | Context van de organisatie |
| 5 | Leiderschap |
| 6 | Planning |
| 7 | Ondersteuning |
| 8 | Uitvoering |
| 9 | Evaluatie van de prestaties |
| 10 | Verbetering |

Daarbovenop draagt elke norm zijn eigen beheersmaatregelen:

- **ISO/IEC 27001:2022** — Annex A, 93 controls in vier thema's: A.5 Organisatorisch
  (37), A.6 Mensen (8), A.7 Fysiek (14), A.8 Technologisch (34).
- **ISO/IEC 42001:2023** — Annex A, ~38 controls over de beheersdoelstellingen
  A.2–A.10 (Annexen B/C/D zijn leidraad, geen te volgen controls).
- **ISO 9001:2015** — clausule-gebaseerd, **geen Annex A**. De voortgang wordt
  hier tegen de clausules 4–10 gerapporteerd.

### Doelen

- Per **control/clausule** een status, volwassenheid, eigenaar, streefdatum en
  bewijsverwijzing kunnen vastleggen.
- Een **voortgangsoverzicht** dat automatisch uit die details rolt (per thema,
  per norm, totaal-percentage geïmplementeerd).
- Een **managementreview**-sjabloon (clausule 9.3) en koppeling naar
  verbeteracties/CAPA (clausule 10).
- **Trend over de tijd** (voortgang t.o.v. de vorige reviewcyclus).
- Alles **offline**, in platte Markdown, zonder de normtekst te bundelen.

### Niet-doelen

- **Geen normtekst bundelen** (auteursrecht — zie §9). Alleen de index:
  control-/clausulenummer + korte canonieke titel + thema.
- **Geen certificeringsbesluit nabootsen.** OciDeck rapporteert voortgang; het
  velt geen conformiteitsoordeel en is geen vervanging voor een auditor.
- **Geen risicoregister-motor.** Risico's kunnen als findings/tabel, maar een
  volwaardig risicomanagementsysteem valt buiten scope (verwijst naar 6.1).
- **Eén managementsysteem per deck.** Geen multi-tenant/klantdimensie (dat is de
  keuze "eigen organisatie"; de pentestmodule dekt het klantgeval al).

---

## 2. Ontwerpprincipes & hoe ze op OciDeck landen

Dezelfde principes als de twee bestaande modules ([`PENTEST_MIAUW.md`](PENTEST_MIAUW.md) §2):

- **Bestand = waarheid.** Een control-statuslijst leeft als een **platte
  Markdown-tabel** in de dia, net als de checklist. Een getypeerde *view*
  (`ControlStatusSpec`) leest en schrijft die tabel; de opslag blijft een gewone
  tabel in `Slide.tableRows`. Round-trip verliesvrij, geen lock-in.
- **Overzicht is afgeleid, nooit los opgeslagen.** Het voortgangspercentage
  regenereert uit de statustabellen — zoals `deckStandardsUsed` /
  `MiauwComplianceAnalyzer` dat doen. Twee getallen die uit sync kunnen lopen is
  precies wat we vermijden.
- **Stabiele Engelse tokens op schijf.** Status- en volwassenheidswaarden worden
  als taalonafhankelijke ankers opgeslagen (zoals `ChecklistStatus.token`); de
  UI localiseert bij het tonen.
- **Niets verlaat de machine.** De catalogi zijn ingebakken `const`-data; geen
  netwerkuitgang. De verouderingspoort bevraagt upstream alleen bij een expliciete
  `make`-run, niet vanuit de app.

---

## 3. Datamodel & opslag (Markdown-dichtbij)

### 3.1 Een control-statuslijst op schijf

Eén dia per normonderdeel (bv. "Annex A — Organisatorisch"), als tabel. De
kop-rij en de tokens zijn stabiele Engelse ankers; de UI localiseert.

```markdown
# ISO 27001 · Annex A — Organisatorisch (A.5) · 22/37 geïmplementeerd

| ID | Control | Status | Maturity | Owner | Target | Evidence | Note |
|----|---------|--------|----------|-------|--------|----------|------|
| A.5.1 | Beleid voor informatiebeveiliging | Implemented | 4 | CISO | — | policy-repo#12 | — |
| A.5.7 | Informatie over dreigingen | Partial | 2 | SOC | 2026-Q4 | — | pilot loopt |
| A.5.23 | Informatiebeveiliging clouddiensten | Planned | 0 | IT | 2027-Q1 | — | — |
```

- **Status-tokens** (Engels, op schijf): `NotStarted`, `Planned`, `Partial`,
  `Implemented`, `NotApplicable`. De laatste vraagt een reden in `Note`
  (Verklaring van Toepasselijkheid / SoA-motivatie voor 27001 6.1.3 d).
- **Maturity** (optioneel, 0–5; 0/leeg = niet gescoord). Voortgang telt op status,
  niet op maturity — maturity is een *tweede*, fijnere blik voor wie hem wil.
- **Voortgang in de titel is afgeleid**, nooit los opgeslagen (zoals de
  checklist "87/98 tested").

De canonieke titels in de `Control`-kolom komen uit de gebundelde index (§7) bij
het importeren; een auteur mag ze overschrijven (bv. een eigen vertaling), en de
`ID` blijft de sleutel waarop het overzicht koppelt.

### 3.2 Deck-metadata (front matter)

Platte front-mattersleutels (nested is verboden, zie [`FILE_FORMAT.md`](../FILE_FORMAT.md)):

```yaml
ocideck_ms_standard: iso27001        # iso27001 | iso9001 | iso42001
ocideck_ms_period: 2026-Q3           # de reviewcyclus die dit deck rapporteert
ocideck_ms_scope: "Hoofdkantoor + SaaS-platform"
```

`ocideck_ms_standard` bepaalt welke catalogus de importers en het overzicht
gebruiken; `ocideck_ms_period` verankert de trend (§6).

---

## 4. Nieuwe slidetypes

Volgens de volledige ketting in de **`nieuw-slidetype`-skill** (de compiler wijst
maar een handvol plekken aan; de rest faalt stil — o.a. `_tableBackedTypes`,
`SlideCategory`-mapping, `_class`-token in serialize/parse, editor, preview,
picker, `management_summary`-switch, l10n-labels, tests).

- **`controlStatus`** — de statustabel uit §3.1. Tabel-gedragen (in
  `_tableBackedTypes`), eigen editor + preview, `_class`-token `controlStatus`.
  Draagt `SlideCategory.managementsysteem`.
- **Managementreview (9.3)** — géén nieuw slidetype. Een **`canvas`-sjabloon**
  (drop-in Markdown onder `assets/`, nul Dart) met de vaste 9.3-secties. Hergebruik
  van de procesverbetering-machinerie.
- **Verbeteracties / CAPA (clausule 10)** — hergebruik de procesverbetering-module
  (A3, 8D, PDCA) via `Slide.improvementTemplateId`. Geen nieuwe code.
- **KPI's & trend** — hergebruik `scorecard` (waarde vs. vorige, polariteit) en
  `cockpit` (meters). Geen nieuwe code.
- **Mijlpalen** — hergebruik `timeline` en `phaseGate`.

Alleen `controlStatus` is dus écht nieuw; de rest is compositie.

### 4.1 Wizard

Eén "Nieuw managementsysteem-rapport"-wizard: kies norm → scope + periode →
genereer een skelet: titeldia, één `controlStatus`-dia per thema/clausule
(vooraf gevuld uit de index met alle controls op `NotStarted`), een
managementreview-`canvas`, een `scorecard` en een sign-off. Zo staat er na één
handeling een compleet, correct gestructureerd rapport dat de auteur alleen nog
invult — hetzelfde patroon als de pentest-scaffold.

---

## 5. Slidetype-picker: de categorie-tab

Nieuwe waarde `SlideCategory.managementsysteem` op `controlStatus`. De picker
leidt zijn tab-balk af uit de aanwezige categorieën, dus de tab verschijnt vanzelf
zodra de module iets levert — identiek aan hoe `informationSecurity` en
`procesverbetering` nu werken ([slide.dart](../../lib/models/slide.dart)).

---

## 6. Voortgangsoverzicht (afgeleid) & trend

### 6.1 Het overzicht

Een `ManagementSystemAnalyzer` naar het patroon van
[`MiauwComplianceAnalyzer`](../../lib/services/miauw_compliance_analyzer.dart) en
[`management_summary.dart`](../../lib/services/management_summary.dart): leest alle
`controlStatus`-dia's, telt per status en per thema/clausule, en levert:

- totaal **% geïmplementeerd** (Implemented / (totaal − NotApplicable));
- een verdeling per thema (Annex A) of clausule (9001);
- het aantal open afwijkingen (uit aanwezige `finding`-dia's, hergebruik);
- de "standaarden gebruikt"-regel uit de norm-front-matter.

Altijd **on demand afgeleid**, nooit opgeslagen. Een managementsamenvatting-dia
rendert deze roll-up.

### 6.2 Trend — deck-per-periode

Voortgang is inherent periodiek (managementreview-cadans). Aanbevolen model:
**één deck per reviewcyclus** (`ocideck_ms_period`). Trend komt op twee manieren:

- **Scorecard "vs. vorige"** — al aanwezig ([scorecard_spec.dart](../../lib/models/scorecard_spec.dart)):
  %geïmplementeerd nu vs. vorig kwartaal, met de goede kleurpijl.
- **Burn-up-grafiek** — via het bestaande **chart-derivation**-mechanisme uit de
  procesverbetermodule (`yRef`, resolve-at-draw-time): een `chart`-dia die het
  %geïmplementeerd over de `controlStatus`-dia's afleidt.

Zo blijft "bestand = waarheid" intact: geen verborgen tijdreeks-database, elk deck
staat op zichzelf en is los te lezen. Een lichte helper kan de "vorige"-waarden uit
het vorige-periode-deck voorstellen bij het aanmaken (optioneel, §8).

---

## 7. De "Managementsysteem"-module: catalogi als data

Drie nieuwe `ReferenceStandard`-entries in
[`reference_standards.dart`](../../lib/services/reference_standards.dart), elk met
een eigen index-catalogus (naar het model van `wstg_catalog` /
`miauw_eis_catalog`). Per control/clausule alléén: stabiel `id`, korte canonieke
titel, thema/clausule. **Geen normatieve tekst.**

Voorbeeld-veldwaarden voor de ISO 27001-entry:

```
id:             'iso27001'
name:           'ISO/IEC 27001'
bundledVersion: '2022'
url:            'https://www.iso.org/standard/27001'   // EIS-4.8.2.3-stijl bronverwijzing
bundled:        'Alleen de index van Annex A (control-id + korte titel + thema) '
                'en de clausulekoppen 4–10. De normtekst is NIET gebundeld.'
licence:        'ISO copyright — index als feitreferentie, normtekst niet meegeleverd'
probe:          UpstreamProbe.<n.t.b.>   // zie open vraag §8
advisory:       true                      // een editiewissel is geen bouwblokkade
```

De importers leveren, net als `checklistSources`, een klik-om-te-laden bron per
norm(-thema): "Laad ISO 27001 Annex A", "Laad ISO 9001 clausules", enzovoort — die
een `controlStatus`-dia vullen met alle controls op `NotStarted`.

---

## 8. Gefaseerd plan & open vragen

**Blok A — Fundament & catalogi.** De drie index-catalogi + `ReferenceStandard`-
entries + licentienota in [`LICENSE_COMPLIANCE.md`](../LICENSE_COMPLIANCE.md) en
`THIRD_PARTY_NOTICES.md`. Verouderingspoort-koppeling. *Levert:* control-lijsten
importeerbaar, juridisch schoon.

**Blok B — Statusmodel.** `controlStatus`-slidetype (view over Markdown-tabel) +
editor + preview + de volledige `nieuw-slidetype`-ketting + afgeleide voortgang in
de titel. *Levert:* per-control rapporteren end-to-end.

**Blok C — Overzicht & review.** `ManagementSystemAnalyzer` + managementsamenvatting-
render + managementreview-`canvas`-sjabloon + CAPA-hergebruik + burn-up via
chart-derivation. *Levert:* een compleet reviewrapport.

**Blok D — Trend & afronding.** Deck-per-periode-delta's + provenance/sign-off-
hergebruik + docs (USER_GUIDE / SOURCE_MAP / FILE_FORMAT / CHANGELOG) + l10n (31
talen) + tests + groene poorten.

### Open vragen

1. **Verouderingsprobe voor ISO.** ISO publiceert geen GitHub-releases. Opties:
   een handmatige `bundledVersion` (editiejaar) met een `advisory`-poort die de
   mens eraan herinnert periodiek te controleren, of een `successorDocument`-achtige
   probe tegen de ISO-catalogus-URL. Bewust `advisory: true`: een nieuwe editie is
   een *inhoudelijke migratie*, geen bouwblokkade. (Vergelijk de MASWE-afweging in
   [reference_standard.dart](../../lib/models/reference_standard.dart).)
2. **Volwassenheidsschaal.** 0–5 (CMMI-achtig) optioneel, of weglaten in v1 en
   later toevoegen? Voorstel: optioneel meenemen, want de kolom is goedkoop en veel
   ISMS-rapportages willen hem.
3. **Verklaring van Toepasselijkheid (SoA, 27001 6.1.3 d).** Is de `controlStatus`-
   tabel met `NotApplicable`+reden voldoende als SoA-bron, of wil een auditor een
   aparte SoA-render? Voorstel: aparte afgeleide SoA-view in Blok C, uit dezelfde
   tabel.
4. **9001 zonder Annex A.** Rapporteren we 9001 puur op de clausules 4–10, of ook
   op sub-clausules (bv. 8.5.1)? Voorstel: clausule + sub-clausule als
   catalogus-index, diepte instelbaar bij import.

---

## 9. Auteursrecht & licenties (het kernontwerppunt)

ISO-normen zijn **auteursrechtelijk beschermd** en worden door ISO/NEN verkocht —
anders dan OWASP (CC-BY-SA) of CWE (MITRE-terms). Daarom:

- **Wel gebundeld:** control-/clausule**nummers + korte canonieke titels + thema**.
  Deze feitelijke index is universeel herbruikt in elke ISMS/QMS-tool ("A.5.1 —
  Beleid voor informatiebeveiliging") en is te kort/te feitelijk voor
  auteursrechtelijke bescherming van de individuele regel.
- **Niet gebundeld:** de normatieve eistekst, toelichtingen en leidraad. Wie de
  eis wil lezen, koopt de norm; de `url`-verwijzing wijst naar de officiële bron.
- Dit is **exact het bestaande patroon** ("bundel de index, niet de gids-inhoud",
  zoals WSTG/MASTG). De `bundled`- en `licence`-velden maken die grens expliciet,
  en de nota's in [`LICENSE_COMPLIANCE.md`](../LICENSE_COMPLIANCE.md) en
  `THIRD_PARTY_NOTICES.md` leggen hem vast.

> Toets dit vóór Blok A met de jurist-skill: bevestig dat de index-only-lijn voor
> ISO net zo houdbaar is als voor de OWASP-catalogi, en of NEN-specifieke voorwaarden
> spelen bij de Nederlandse vertalingen van de titels.

---

## 10. Prior art

- [`PENTEST_MIAUW.md`](PENTEST_MIAUW.md) — de module die deze spiegelt: findings,
  checklist, scope matrix, compliance-overview, sign-off, seal.
- [`PROCESS_IMPROVEMENT.md`](PROCESS_IMPROVEMENT.md) — de template-gedreven
  render-vorm-slidetypes en chart-derivation die deze module hergebruikt.
- [`reference_standards.dart`](../../lib/services/reference_standards.dart) — het
  catalogus- + verouderingspoortpatroon dat de ISO-index gebruikt.
