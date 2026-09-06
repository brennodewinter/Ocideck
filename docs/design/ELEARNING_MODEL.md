# OciDeck — eLearning: vraag- en assessmentmodel (ontwerp)

*Het uitbreidbare model voor eLearning-vragen, toetsregels en
leeractiviteiten — de inhoudelijke basis onder QTI/SCORM/OLX-import en de
eLearning-slide-types.*

> **Status:** ontwerp, gedeeltelijk gebouwd · **Status last reviewed:** 2026-09-06 · **Published by:** Stichting LibreKAT

> **Dit is een ontwerpdocument, geen shipping-contract.** Het beschrijft het
> data-model en de sidecargrens vóór de bouw. De on-disk specifics die hier
> worden voorgesteld landen in [`FILE_FORMAT.md`](../FILE_FORMAT.md) pas wanneer
> de code ze schrijft; tot die tijd is dit document de plaats waar de keuzes
> staan en waar een latere bouwsessie ze aantreft. Waar shipping bewust
> afwijkt, wint het later bijgewerkte `FILE_FORMAT.md`.

> **Wat er inmiddels van gebouwd is (bijgewerkt 2026-09-06, tweemaal).** De status
> zei tot vandaag "nog niet geïmplementeerd", en dat is achterhaald. Gebouwd: de
> drie nieuwe `kind`-waarden met hun velden en de gedeelde velden uit §3.3, hun
> editors, de vier structurele slide-types uit §6, de module-schakelaar uit §6, en
> de importherkenning en -lezers uit §11. Het versiecontract van de sidecar uit §7
> is er ook, en bewaart bovendien sleutels die deze build niet kent. Niet gebouwd:
> elke presentatiekant — geen weergave waarin een kijker matching, hotspot of
> fill-in beantwoordt, en geen laag die scoort, pogingen telt of feedback toont; de
> modulehiërarchie uit §6; en het schrijven en lezen van het sidecarbestand zelf,
> waarvan alleen het model bestaat. Eén punt wijkt nog bewust van dit ontwerp af en
> staat bij §6 aangetekend; de twee andere afwijkingen die daar stonden zijn weg —
> kennischeck volgt het ontwerp weer, en de body van de vier tekstsoorten komt
> terug.

> Sibling-ontwerpen: [`PROCESS_IMPROVEMENT.md`](PROCESS_IMPROVEMENT.md) (de
> module-spiek voor een opt-in tab + slide-types),
> [`PENTEST_MIAUW.md`](PENTEST_MIAUW.md) (de module-spiek voor onvoorwaardelijk
> parsen + authoring-toggle). Hoofdfeature: #1992. Bouw van slide-types: #1999.

---

## 1. Doel en harde grens

OciDeck moet eLearning-inhoud kunnen vastleggen — vraagdefinities,
toetsregels, leerdoelen, cursusstructuur — zowel handmatig getekend als
geïmporteerd uit QTI/SCORM/xAPI/cmi5/AICC/OLX. Dit ontwerp beschrijft het
**gedeelde data-model** dat beide routes dragen, en de **sidecargrens** die
bepaalt wat in het `.md` staat en wat ernaast.

### Harde grens: geen historische learnerresultaten

Historische learnerresultaten vallen **buiten scope**. We slaan nu niet op wie
een vraag goed of fout had, welke pogingen iemand deed, persoonlijke
voortgang, mastery-status, suspend data of runtime-resultaten. Dit ontwerp
beschrijft alleen **toetsinhoud en uitvoeringsregels**: antwoordmodel, scoring,
feedback, tijd, pogingsregels, slaaggrens en cursusstructuur.

Deze grens is niet een "later invullen"-veld. §8 legt uit waarom het formaat
**geen** sleutels reserveert voor toekomstige resultaatdata: een gereserveerde
sleutel met placeholder-betekenis botst met de FILE_FORMAT-regel dat *de
betekenis van een bestaande sleutel nooit verandert* (§3.0 regel 4). Een
toekomstige resultaatlaag krijgt nieuwe sleutels met nieuwe betekenis, niet
de oude.

---

## 2. Het ene ontwerpbesluit: de sidecargrens

De bewaker-toets — *open het `.md` in een teksteditor en in Marp; is het nog
leesbaar en bruikbaar?* — deelt de eLearning-data in twee lagen:

### In het `.md` (leesbaar, bron van waarheid voor inhoud)

Alles wat de auteur met de hand zou kunnen schrijven en wat een vreemde lezer
begrijpt:

1. **Vraagdefinities** — uitbreiding van het bestaande ```question``` fenced
   blok (§3). Nieuwe `kind`-waarden en kind-specifieke velden. Prompt,
   antwoorden, per-antwoord feedback, hint, punten, basale scoring en
   leerdoelverwijzingen staan hier.
2. **Structurele slides** — nieuwe `_class` tokens voor leerdoel (`objective`),
   module/hoofdstuk (`module`), feedback/remediation (`feedback`) en
   assessment-samenvatting (`assessment-summary`). Hun inhoud is gewone
   Markdown of een licht fenced blok.
3. **Vraag-slides in de eLearning-tab** — kennischeck, matching, invulvraag en
   hotspot zijn `question` slides met de passende `kind`; geen nieuwe `_class`
   nodig. De eLearning-tab is een editor-UI-groepering, geen
   bestandsformaat-concept.

### In de sidecar `<name>.elearning.json` (structuur, bronmetadata, import)

Alles wat "over het document gaat" in plaats van "deel van het document is",
of wat te onleesbaar is om met de hand te schrijven:

1. **Assessment/test-definitie** — sections, question groups, item pools, pass
   threshold, max score, test-/sectie-tijdlimieten, navigation mode,
   completion rule, prerequisites (§5).
2. **Bronmetadata** — source-id's (QTI/SCORM/OLX identifiers), source format
   en version, original location, mapping report, import warnings (§7).
3. **Complexe scoring** — outcome declarations, scoring formulas die niet in
   het leesbare blok passen (§4.3).
4. **Cursusstructuur-relaties** — nested module-relaties, kind-relaties tussen
   modules en items (§6).
5. **Toegankelijkheidsmetadata "over" de content** — alternatieve
   presentatie-vlaggen, QTI AfA-extensions die niet ondersteund worden (§4.7).

De sidecar volgt het bestaande versiecontract uit
`lib/services/sidecar_format.dart`: een `version` int; een bestand dat een
hoger versie declareert dan deze build ondersteunt wordt **niet ingelezen en
niet overschreven** — beide kanten matteren, half inlezen en dan opslaan
wist de rest.

### Waarom deze grens

De bestaande patronen zijn de precedenten: het ```question``` blok is al de
round-trip bron van waarheid voor quizvragen; het ```chart``` blok houdt
styling in het `.md` terwijl `data/*.json` de data ernaast zet; de seal zit in
`.seal.json` naast het bestand. Dit ontwerp volgt dezelfde lijn: **inhoud in
het `.md`, structuur en bronmetadata ernaast.** De assessment-test-definitie
is geen enkele slide — het is deck-brede structuur — en hoort dus naast het
bestand, met een leesbare samenvattingsslide in het `.md` als menselijke
weergave.

---

## 3. Het gedeelde vraagmodel: uitbreiding van `QuestionSpec`

Het bestaande `lib/models/question.dart` definieert `QuestionSpec` (de
authored spec, opgeslagen als ```question``` fenced blok) en `QuestionView`
(de live sessie-state, nooit gepersisteerd). Zes `QuestionKind`-waarden:
`multipleChoice`, `trueFalse`, `multipleCorrect`, `ordering`, `imagePair`,
`openText`.

**Het ontwerp: voeg nieuwe `kind`-waarden en kind-specifieke velden toe aan
het bestaande blok. Geen nieuw fenced blok, geen nieuw `_class` token voor
vraag-slides.** De commentaar in `question.dart` zegt het al: *"more kinds
slot in here without a model rebuild."*

### 3.1 Nieuwe `kind`-waarden

| kind | issue | Wat het doet |
| --- | --- | --- |
| `matching` | #2000 | Twee kolommen; de lerende maakt paren. Correcte paren zijn per index in de authored lijst. |
| `hotspot` | #2014 / #2001 | Afbeelding + klikbare gebieden; de lerende wijst één (of meer) correcte gebied(en) aan. |
| `fillIn` | #2013 / #2002 | Tekst/numeriek invulveld met expliciete evaluatiestrategie (exact/contains/similar/numericRange). |

`openText` blijft bestaan met zijn huidige `similarityThreshold`-semantiek
(Jaro-Winkler) — de betekenis van een bestaande sleutel verandert niet
(§3.0 regel 4). `fillIn` is het nieuwere, rijkere invulmodel met expliciete
`matchMode`; de editor biedt `fillIn` voor nieuwe content, en `openText`
leest terug en blijft bewerkbaar.

### 3.2 Kind-specifieke velden in het ```question``` blok

Hieronder de velden die bij de nieuwe kinds horen. Ze worden alleen
geschreven voor de kind waarop ze betrekking hebben (hetzelfde principe als
het bestaande `statementIsTrue` dat alleen voor `trueFalse` wordt geschreven).

#### `matching`

```json
{
  "kind": "matching",
  "prompt": "Koppel de term aan de definitie",
  "pairs": [
    { "id": "t1", "left": "TCP", "right": "Transportlaag" },
    { "id": "t2", "left": "IP",  "right": "Netwerklaag" }
  ],
  "distractors": ["Sessielaag"],
  "points": 2,
  "scoring": "partialPerPair"
}
```

- `pairs[]` — authored paren; `id` is stabiel binnen de vraag (niet de
  bron-id; die zit in de sidecar). De correcte koppeling is per index: pair
  *i* hoort `left[i]` bij `right[i]`. De presentatie shuffelt de
  rechterkolom; de answer key verandert niet.
- `distractors` — extra rechteritems zonder correcte partner (optioneel).
- Eén-op-één is de eerste subset; één-op-meerdere is een expliciete
  uitbreidingsstap (§9 open questions).
- Validatie: dubbele `id` → fout; ontbrekende paren → fout; `left` of
  `right` leeg → dat paar telt niet mee maar de vraag blijft geldig.

#### `hotspot`

```json
{
  "kind": "hotspot",
  "prompt": "Klik op de kwetsbare component",
  "image": "images/schema.png",
  "regions": [
    { "id": "r1", "shape": "rect", "coords": [0.10, 0.20, 0.30, 0.40], "correct": true, "label": "Firewall" },
    { "id": "r2", "shape": "rect", "coords": [0.50, 0.50, 0.70, 0.70], "correct": false, "label": "Database" }
  ],
  "multiSelect": false,
  "points": 1,
  "scoring": "allOrNothing"
}
```

- `image` — deck-relatief pad, bestaand asset-systeem. Geen externe URL
  tijdens presentatie (fail-closed: placeholder als het bestand ontbreekt).
- `regions[].coords` — **genormaliseerd 0–1** in de referentieruimte van de
  afbeelding, niet in pixels. Zo overleeft het resize/crop/export. `rect` =
  `[x, y, w, h]` genormaliseerd; `circle` = `[cx, cy, r]`; `poly` = `[x0, y0,
  x1, y1, …]` (uitbreiding na `rect`, §9).
- `multiSelect` — of meerdere gebieden mogen worden gekozen (default false).
- Validatie: coords buiten [0,1] → clamp + waarschuwing; afbeelding ontbreekt
  → niet-presenteerbaar (`isPresentable` false); nul correcte gebieden →
  niet-presenteerbaar.
- Hit-test-tolerantie: een kleine genormaliseerde marge (vast te leggen in
  de editor, default 0.01) zodat een klik op de rand nog telt.

#### `fillIn`

```json
{
  "kind": "fillIn",
  "prompt": "Hoeveel lagen heeft het OSI-model?",
  "fields": [
    {
      "id": "f1",
      "accepted": ["7", "zeven"],
      "matchMode": "exact",
      "caseSensitive": false,
      "normalize": ["trim", "collapseWhitespace", "diacritics"],
      "placeholder": "aantal",
      "maxLength": 20
    }
  ],
  "feedback": { "wrong": "Het OSI-model heeft 7 lagen." },
  "points": 1
}
```

- `fields[]` — één of meer invulvelden. `id` stabiel binnen de vraag.
- `accepted` — geaccepteerde antwoorden (de answer key).
- `matchMode` — `exact` | `contains` | `similar` | `numericRange`.
  - `exact`: na normalisatie gelijk aan een accepted waarde.
  - `contains`: de genormaliseerde invoer bevat een accepted waarde.
  - `similar`: Jaro-Winkler ≥ `similarityThreshold` (hergebruikt het
    bestaande veld, default 0.85).
  - `numericRange`: `accepted` bevat bereiken als `"6..8"` of `"7±1"`;
    `tolerance` en `unit` optioneel.
- `normalize` — welke normalisaties worden toegepast vóór vergelijking:
  `trim`, `collapseWhitespace`, `diacritics` (verwijder), `punctuation`
  (verwijder leestekens), `lowercase`. De strategie wordt **expliciet**
  vastgelegd, nooit impliciet afgeleid uit tekst (#2002 eis).
- Validatie: lege `accepted` → niet-presenteerbaar; `numericRange` met
  onleesbare bereiken → dat veld valt terug op `exact` + waarschuwing.

*(Aangetekend 2026-09-06: `FillField` draagt al deze sleutels, inclusief
`tolerance` en `unit`, en bewaart ze bij een rondgang zonder ze uit te voeren — er
is nog geen evaluatie van een fillIn-antwoord. `tolerance` en `unit` ontbraken
eerst in het model, waardoor een blok dat dit ontwerp letterlijk volgde ze bij de
eerste opslag verloor. Ontbreekt `normalize`, dan geldt de standaard
`["trim", "collapseWhitespace"]`; een lege lijst betekent "niets normaliseren" en
blijft daarvan onderscheiden. Van de genoemde normalisaties wordt er nog geen één
toegepast, om dezelfde reden.)*

### 3.3 Velden die voor alle kinds gelden (uitbreiding op bestaand blok)

Deze velden zijn nieuw maar gelden voor elke `kind` (ook de bestaande zes).
Ze worden alleen geschreven wanneer ze afwijken van de default, behalve waar
het bestaande blok ze altijd schrijft (`optionCount`, `timeLimitSeconds`,
`onWrong`).

| veld | default | issue | betekenis |
| --- | --- | --- | --- |
| `points` | `1` | #2003 | Maximaal te halen punten voor deze vraag. |
| `scoring` | `allOrNothing` | #2003 | `allOrNothing` \| `partialPerCorrect` \| `partialPerPair` \| `partialPerAnswer`. |
| `penalty` | `0` | #2003 | Punten afgetrokken per fout poging (niet onder nul). |
| `maxAttempts` | `1` | #2005 | Maximum pogingen (`0` = onbeperkt). Bouwt voort op bestaande `onWrong`. |
| `feedback` | — | #2004 | `{correct, wrong, partial, timeout}` — per-uitkomst feedback als Markdown. Alleen geschreven wanneer gevuld. |
| `hint` | — | #2004 | String of array van progressieve hints. Alleen geschreven wanneer gevuld. |
| `remediation` | — | #2004 | Slide-anchor verwijzing naar een `feedback` slide. Alleen geschreven wanneer gevuld. |
| `objectiveRefs` | — | #2008 | Array van slide-anchors naar `objective` slides. Alleen geschreven wanneer gevuld. |
| `metadata` | — | #2008 | Leesbare metadata: `title`, `language`, `subject`, `difficulty`, `estimatedDurationSeconds`, `tags`. Alleen geschreven wanneer gevuld. |

#### Per-antwoord feedback

`answers[].feedback` (voor de kinds die `answers` gebruiken) — feedback die
verschijnt wanneer die specifieke antwoord wordt gekozen. Markdown, alleen
geschreven wanneer gevuld.

#### Compatibiliteit met bestaande `onWrong` en `timeLimitSeconds`

`onWrong` (`retry` | `lockAndContinue`) en `timeLimitSeconds` blijven
bestaan met hun huidige betekenis. `maxAttempts` is de uitbreiding: bij
`maxAttempts > 1` en `onWrong: retry` krijgt de lerende extra pogingen; bij
`onWrong: lockAndContinue` wordt na de laatste poging het antwoord onthuld.
De mapping is bewust een compatibiliteitslaag, niet een vervanging — een
bestaand blok zonder `maxAttempts` blijft `1` poging doen, zoals altijd.

---

## 4. Per-ondeel-specificatie

### 4.1 Matching (#2000)

- **Round-trip formaat:** ```question``` blok met `kind: matching`, `pairs`,
  `distractors` (§3.2). De answer key (per-index koppeling) staat in het
  deck; dat is authoring content.
- **Validatie:** dubbele `id`, ontbrekende paren, onmogelijke configuratie
  (nul paren) → fout of niet-presenteerbaar.
- **UI-gedrag:** editor met twee kolommen (left/right), drag-to-pair of
  select-then-select. Presenter: twee kolommen, toetsenbordbediening
  (tab tussen kolommen, enter om te koppelen), geselecteerde/gekoppelde
  toestand visueel, reset-knop.
- **Presenter/export:** live matching met sync over het audience-window
  (hergebruikt het `QuestionView`-kanaal). Static export (PDF/PPTX/HTML):
  toont de twee kolommen als leesbare lijsten zonder interactieve belofte;
  de answer key is verborgen in presentatie, zichtbaar in authoring-weergave.
- **Teststrategie:** parser/serializer round-trip; editor; presenter sync;
  toetsenbord; export; randomisatie zonder answer-key-corruptie; distractors.

### 4.2 Hotspot / select-point (#2001, #2014)

- **Round-trip formaat:** ```question``` blok met `kind: hotspot`, `image`,
  `regions` met genormaliseerde coords (§3.2).
- **Validatie:** coords buiten [0,1] → clamp + waarschuwing; ontbrekende
  afbeelding → niet-presenteerbaar; nul correcte gebieden → niet-presenteerbaar.
- **UI-gedrag:** editor toont de afbeelding met tekenbare gebieden
  (rechthoek-sleep; circle/poly in een tweede stap). Presenter: klik/tap op
  gebieden; toetsenbord-alternatief (genummerde lijst van gebieden, kies met
  toets). Selectie-indicatoren.
- **Presenter/export:** live klik met sync. Static export: afbeelding +
  genummerde regiolijst (toetsenbord-fallback is ook de export-fallback).
  Alt-tekst voor de afbeelding via het bestaande image-alt mechanisme.
- **Teststrategie:** schaal, crop, ontbrekende afbeelding, buiten-bounds,
  meerdere hotspots, resize behoudt coords, export, round-trip, keyboard.

### 4.3 Fill-in / short answer / numeric (#2002, #2013)

- **Round-trip formaat:** ```question``` blok met `kind: fillIn`, `fields`
  met `accepted`, `matchMode`, `normalize` (§3.2).
- **Validatie:** lege `accepted` → niet-presenteerbaar; onleesbaar
  numericRange → fallback + waarschuwing; veilige afwijzing van onduidelijke
  answer keys (een veld met alleen `matchMode: similar` en geen
  `similarityThreshold` krijgt de default).
- **UI-gedrag:** editor met veld-rows (accepted antwoorden, matchMode-keuze,
  normalisatie-opties). Presenter: invoerveld(en) met placeholder/eenheid,
  inputtype (text/number), timeout. Authoring mode toont de answer key;
  presentatie verbergt hem.
- **Presenter/export:** live invoer met sync. Static export: toont de prompt
  en lege velden (of de vraag zonder interactieve belofte); de answer key
  is verborgen. `openText`-compatibiliteit: bestaand `openText` blijft
  werken met `similarityThreshold`.
- **Teststrategie:** Unicode, lege invoer, numerieke grenzen, decimalen,
  eenheden, meerdere geldige antwoorden, false positives, normalisatie,
  export, round-trip.

### 4.4 Partial credit en scoring rules (#2003)

- **Round-trip formaat:** `points`, `scoring`, `penalty` in het ```question```
  blok (§3.3). De scoreberekening is **deterministisch**: gegeven de answer
  key en een poging, is de score reproduceerbaar. Afronding op 2 decimalen,
  half-away-from-zero.
- **Scoring modes:**
  - `allOrNothing`: volledig goed → `points`, anders 0.
  - `partialPerCorrect`: `points` × (aantal goed / aantal te beantwoorden).
  - `partialPerPair` (matching): `points` × (goede paren / totaal paren).
  - `partialPerAnswer`: `points` × (goede deelitems / totaal deelitems).
- **Complexe scoring** (QTI outcome declarations, custom formulas) → sidecar
  `scoring.outcomeDeclarations`. Onbekende response processing → warning +
  placeholder, nooit stilzwijgend omgezet.
- **Harde grens:** geen score berekenen uit historische learnerresultaten.
  Het model beschrijft alleen hoe een toekomstige poging zou worden
  beoordeeld.
- **Teststrategie:** fixtures voor volledig goed, deels goed, fout, negatieve
  punten (geclamped op nul), afronding, onmogelijke regels. Mutatietests op
  scoreberekening.

### 4.5 Feedback, hints en remediation (#2004, #2015)

- **Round-trip formaat:** `feedback` (per-uitkomst), `answers[].feedback`
  (per-antwoord), `hint`, `remediation` in het ```question``` blok (§3.3).
  De `feedback` slide (`_class: feedback`) is een aparte slide met uitleg als
  gewone Markdown.
- **Zichtbaarheid en timing:**
  - `feedback.correct/wrong/partial/timeout` — verschijnt na het antwoord.
  - `hint` — verschijnt vóór het antwoord, op verzoek of na een foutpoging.
  - `remediation` — verwijst naar een `feedback` slide (slide-anchor); de
    presenter navigeert erheen.
- **Veiligheid:** feedback is Markdown, gesaneerd via het bestaande
  Markdown-sanitisatie-pad. Geen scripts, geen externe HTML. QTI
  `modalFeedback`, OLX `hints`, SCORM/AICC waarschuwingen worden gemapped;
  niet-ondersteunde feedback-vormen → sidecar + warning.
- **UI-gedrag:** `feedback` slide-editor is een gewone Markdown-editor met
  optionele velden voor gekoppeld leerdoel en vervolgactie. De slide toont
  geen learnerstatus.
- **Teststrategie:** alle feedbackpaden, ontbrekende feedback, onbekende
  target-slide, export, toegankelijkheid, HTML-sanitisatie.

### 4.6 Attempts, retry, tijd en navigatie (#2005)

- **Per-vraag (in ```question``` blok):** `maxAttempts` (§3.3), bestaande
  `timeLimitSeconds` en `onWrong`. Retry-beleid: bij `onWrong: retry` en
  `maxAttempts > 1` krijgt de lerende extra pogingen met een verse
  optie-set (waar van toepassing). Lock-after-failure: na de laatste poging
  wordt het antwoord onthuld (`lockAndContinue`) of de slide vergrendeld.
- **Per-assessment (in sidecar):** `navigation` (linear | free),
  `timeLimitSeconds` (test-niveau), `completionRule` (allAnswered |
  allCorrect | manual), sectie-tijdlimieten (§5).
- **Gedrag bij ontbrekende/tegenstrijdige regels:** ontbreekt `maxAttempts` →
  1 (compatibel). `maxAttempts: 0` → onbeperkt. Tegenstrijdige
  `onWrong: lockAndContinue` + `maxAttempts > 1` → `maxAttempts` wint
  (extra pogingen, dan lock).
- **Harde grens:** alleen regels voor een toekomstige sessie. Niet opslaan
  welke persoon hoeveel pogingen gebruikte.
- **Teststrategie:** retry, timeout, zero/unlimited, randomisatie zonder
  answer-key-corruptie, reload (sessie-state niet op schijf), static export.

### 4.7 Toegankelijkheid en alternatieve presentaties (#2007)

- **In het `.md`:** alt-tekst voor afbeeldingen/hotspots via het bestaande
  image-alt mechanisme (`![alt](path)`). Alternatieve tekst voor stimulus en
  antwoordopties: `prompt` is Markdown (screenreader-volgorde volgt de
  render-volgorde). `answers[].text` is leesbare tekst.
- **In de sidecar:** `accessibility` blok met QTI AfA-extensions en
  alternatieve-presentatie-vlaggen die niet in gewone Markdown passen.
  Niet-ondersteunde alternatives → warning, niet stilzwijgend weggegooid.
- **Implementatie-eisen (geen formaat-concept):** 200%-teksttest,
  toetsenbordbediening, focus-volgorde, screenreader-labels, contrast. Dit
  geldt per slide-type bij de bouw (#1999), niet als opgeslagen data.
- **Teststrategie:** 200%-tekst, toetsenbord, focus, screenreaderlabels,
  contrast, static export. QTI AfA-mapping getest op round-trip.

### 4.8 Identifiers, metadata en leerdoelkoppeling (#2008)

- **In het ```question``` blok:** `objectiveRefs` (array van slide-anchors
  naar `objective` slides) en `metadata` (leesbaar: `title`, `language`,
  `subject`, `difficulty`, `estimatedDurationSeconds`, `tags`). Dit is
  authoring content die de auteur met de hand kan invullen.
- **In de sidecar:** `source.identifiers` (bron-id's: QTI `ident`, SCORM
  `itemIdentifier`, OLX `url_name`), `source.format`, `source.version`,
  `source.location`, `source.mappingReport`, `source.warnings`. Dit is
  import-metadata die de auteur niet met de hand schrijft.
- **Lokaal OciDeck-id:** de slide-anchor (de bestaande manier waarop slides
  naar elkaar verwijzen in het deck). Geen aparte numerieke id nodig.
- **Merge en duplicate-beleid:** bij re-import worden bron-id's gematcht;
  een gewijzigde bronvolgorde beschadigt de relaties niet omdat de koppeling
  via slide-anchor + bron-id in de sidecar loopt. Duplicate bron-id's →
  warning, niet stilzwijgend samengevoegd.
- **Onbekende extensies:** bewaard in de sidecar, niet uitvoerbaar gemaakt.
- **Teststrategie:** duplicate ids, gewijzigde bronvolgorde, re-import,
  round-trip, ontbrekende bronmetadata.

---

## 5. Assessmentmodel: teststructuur, score en pass/fail (#2006)

De assessment-test-definitie is **deck-brede structuur**, geen enkele slide.
Hij staat in de sidecar `<name>.elearning.json`:

```json
{
  "version": 1,
  "assessment": {
    "title": "Netwerken — eindtoets",
    "maxScore": 100,
    "passThreshold": 60,
    "timeLimitSeconds": 3600,
    "navigation": "linear",
    "completionRule": "allAnswered",
    "prerequisites": ["slide:0"],
    "objectiveRefs": ["slide:0"],
    "sections": [
      {
        "title": "Basisbegrippen",
        "questionRefs": ["slide:3", "slide:5"],
        "selection": "fixed",
        "timeLimitSeconds": 600
      },
      {
        "title": "Willekeurige subset",
        "questionRefs": ["slide:7", "slide:8", "slide:9", "slide:10"],
        "selection": "random",
        "poolSize": 4,
        "drawCount": 2,
        "timeLimitSeconds": 900
      }
    ]
  }
}
```

- `questionRefs` — slide-anchors naar `question` slides.
- `selection` — `fixed` (alle refs) of `random` (`drawCount` uit `poolSize`).
- `passThreshold` — percentage (0–100) of absoluut? **Ontwerpkeuze:
  percentage van `maxScore`**, zodat een gewijzigd `maxScore` de grens niet
  stilzwijgend verlegt.
- `prerequisites` — slide-anchors die voltooid moeten zijn vóór de toets.
- `completionRule` — wanneer de toets als voltooid geldt.

### De leesbare samenvattingsslide (`assessment-summary`, #2016)

In het `.md` staat een `assessment-summary` slide met een menselijk-leesbaar
overzicht: naam, sections, aantal vragen, max score, pass threshold, tijd,
prerequisites. De slide is gewone Markdown + een licht fenced blok voor
gestructureerde velden die de sidecar spiegelen. De sidecar is de bron van
waarheid voor de regels; de slide is de leesbare weergave. Bij een wijziging
in de editor wordt de sidecar bijgewerkt en de slide herschreven.

---

## 6. Nieuwe slide-types en hun `_class` tokens

| slide-type | `_class` token | inhoud | issue |
| --- | --- | --- | --- |
| Leerdoel/competentie | `objective` | Titel, beschrijving, niveau, indicatoren. Gewone Markdown + optioneel `metadata` fenced blok. | #2009 |
| Module/hoofdstuk | `module` | Titel, samenvatting, volgnummer. Nested relaties in sidecar. | #2010 |
| Kennischeck | `question` | Bestaand `question` blok; de eLearning-tab groepeert het. | #2011 |
| Matching | `question` | `kind: matching`. | #2012 |
| Invulvraag | `question` | `kind: fillIn`. | #2013 |
| Hotspot | `question` | `kind: hotspot`. | #2014 |
| Feedback/remediation | `feedback` | Uitleg als gewone Markdown + optionele verwijzing. | #2015 |
| Assessment-samenvatting | `assessment-summary` | Leesbaar overzicht + spiegeling van sidecar. | #2016 |

> **Eén afwijking in wat er gebouwd is (aangetekend 2026-09-06, bijgewerkt
> diezelfde dag).** De eLearning-tab groepeert alléén de vier structurele types;
> de drie nieuwe vraagsoorten staan in de vraagsoort-keuzelijst van élke vraag-dia
> en zijn dus niet achter de module-schakelaar gezet.
>
> Hier stonden er eerst drie. Dat de code kennischeck een eigen `_class`-token gaf
> in plaats van het `question` uit de tabel hierboven, geldt niet meer: dat type is
> geschrapt en het token leest voortaan als `question`, dus de tabel klopt weer. En
> dat de vier tekstgebaseerde types hun body wel schreven maar niet teruglazen was
> geen ontwerpkeuze maar een gat; dat is gerepareerd. Zie de eLearning-alinea in
> [`FILE_FORMAT.md`](../FILE_FORMAT.md) §4, *Slide Classes and Behavior*.

### Modulehiërarchie (#2010)

*(Ontwerp; niet gebouwd — aangetekend 2026-09-06. Wat er is, is het
`module`-diatype; er wordt geen `structure.modules` geschreven of gelezen.)*

`module` slides vormen een boom. De nested structuur staat in de sidecar
(`structure.modules`: parent/child-relaties via slide-anchors), zodat
herordenen de bronrelaties niet beschadigt. De slide zelf toont titel en
samenvatting; de boom-relatie is zijdelings in de sidecar, niet in de
Markdown-volgorde (de volgorde in het `.md` is de presentatievolgorde).

### De eLearning-tab (#1999)

De eLearning-tab in de slide-typekeuze is een **editor-UI-groepering**, geen
bestandsformaat-concept. Hij groepeert:
- de bestaande vraag-kinds (multipleChoice, trueFalse, multipleCorrect,
  ordering, imagePair, openText) als "kennischeck",
- de nieuwe kinds (matching, fillIn, hotspot),
- de structurele slides (objective, module, feedback, assessment-summary).

De tab verschijnt alleen wanneer de eLearning-module aan staat (opt-in,
spiegelt het Procesverbetering-module-patroon: parsen is onvoorwaardelijk,
authoring is achter een toggle).

---

## 7. De eLearning-sidecar: `<name>.elearning.json`

```json
{
  "version": 1,
  "assessment": { "...": "§5" },
  "structure": {
    "modules": [
      { "ref": "slide:1", "parent": null, "order": 0 },
      { "ref": "slide:3", "parent": "slide:1", "order": 0 }
    ]
  },
  "source": {
    "format": "qti-3.0",
    "version": "3.0",
    "location": "manifest.xml",
    "identifiers": {
      "slide:3": "qti-item-001",
      "slide:5": "qti-item-002"
    },
    "mappingReport": [
      { "ref": "slide:3", "status": "mapped", "note": "multipleChoice → multipleChoice" },
      { "ref": "slide:7", "status": "degraded", "note": "textEntryInteraction → fillIn (exact)" }
    ],
    "warnings": [
      { "ref": "slide:9", "severity": "warning", "message": "Adaptive item not supported; rule stored verbatim" }
    ]
  },
  "scoring": {
    "outcomeDeclarations": []
  },
  "accessibility": {
    "alternatives": []
  }
}
```

- `version` — int, volgt `sidecar_format.dart`. Een hoger versie wordt niet
  ingelezen en niet overschreven.
- `assessment` — §5.
- `structure.modules` — nested module-relaties (#2010).
- `source` — bronmetadata, mapping, warnings (#2008). `identifiers` koppelt
  slide-anchors aan bron-id's.
- `scoring.outcomeDeclarations` — complexe scoring die niet in het blok past
  (#2003).
- `accessibility.alternatives` — niet-onsteunde QTI AfA-extensions (#2007).

### Wanneer de sidecar wordt geschreven

*(Ontwerp; niet gebouwd — aangetekend 2026-09-06, bijgewerkt diezelfde dag.
`ElearningSidecar` kan coderen en ontleden en houdt het versiecontract uit
`sidecar_format.dart` aan: een hogere versie wordt geweigerd in plaats van half
gelezen, en sleutels die deze build niet kent — waaronder `structure`, `source` en
`scoring` uit dit hoofdstuk — blijven bewaard, zodat een toekomstige schrijver ze
niet weggooit. Wat ontbreekt is de schrijver zelf: geen opslagroute schrijft of
leest `<name>.elearning.json`. De alinea hieronder beschrijft dus wanneer het
bestand geschreven zou moeten worden, niet wat er gebeurt.)*

De sidecar wordt alleen geschreven wanneer er iets in staat: een
assessment-definitie, module-relaties, bronmetadata, of complexe scoring.
Een deck met alleen losse `question` slides en `objective` slides zonder
assessments of imports schrijft geen sidecar. Dit spiegelt het
`.user-notes.json`-patroon: leeg → geen bestand.

---

## 8. Historische resultaten: expliciet niet gereserveerd

**Geen enkele sleutel in dit ontwerp reserveert ruimte voor toekomstige
learnerresultaat-data.** Er is geen `results`, `attempts` (historisch),
`learnerData`, `suspendData`, `progress` of `mastery` sleutel met
placeholder-betekenis. De reden is de FILE_FORMAT-regel (§3.0 regel 4):

> De betekenis van een bestaande sleutel verandert nooit. Een gewijzigde
> betekenis krijgt een nieuwe sleutel.

Een gereserveerde sleutel met placeholder-betekenis ("hier komen later
resultaten") zou ofwel later een andere betekenis krijgen (verboden), ofwel
een betekenis krijgen die botst met wat een andere build al in dat veld
schreef. Beide gevallen breken het compatibiliteitscontract.

Een toekomstige resultaatlaag — als die komt — krijgt **nieuwe sleutels met
nieuwe betekenis**, in een nieuwe sidecar (bijv. `<name>.results.json`) of
een nieuw versioned blok, niet de sleutels uit dit ontwerp. Dit ontwerp
vermeldt die mogelijkheid expliciet als toekomstige uitbreiding, en reserveert
niets.

---

## 9. Versieing, migratie en compatibiliteit

- **`ocideck_format` in front matter:** de nieuwe slide-types en de
  uitbreiding van het ```question``` blok zijn backward-compatible: een
  ouder bestand zonder de nieuwe velden opent normaal (defaults). Een
  nieuwer blok met onbekende `kind` of onbekende velden wordt bewaard en
  niet uitgevoerd (het bestaande `_preservedSource`-patroon uit
  `QuestionSpec`).

  *(Gecorrigeerd 2026-09-06: die laatste zin beschrijft niet wat de code doet.
  `_preservedSource` bewaart alleen een blok dat over zijn antwoordlimiet gaat; een
  geldig blok wordt bij elke opslag opnieuw uit het ontlede model geschreven, dus
  een sleutel die deze build niet kent gaat niet mee. Een deck met deze kinds
  openen in een oudere build is veilig, het daar opslaan niet. Zie
  [`FILE_FORMAT.md`](../FILE_FORMAT.md) §5, bij `answers`.)*
- **Sidecar-versioning:** `<name>.elearning.json` declareert `version: 1`.
  Een hoger versie wordt niet ingelezen en niet overschreven
  (`sidecar_format.dart`). *(Gebouwd 2026-09-06: `ElearningSidecar.parse` leest de
  gedeclareerde versie via `sidecar_format.dart` en geeft null terug bij een
  hogere; overschrijven is nog niet aan de orde omdat er geen schrijver is.)*
- **Onbekende `kind`:** een `kind` die deze build niet kent → de vraag is
  niet-presenteerbaar maar het blok wordt verbatim bewaard
  (`_preservedSource`). De editor toont de ruwe JSON. Dit is het bestaande
  gedrag voor oversized answer pools, veralgemeend naar onbekende kinds.
- **`openText` naar `fillIn`:** geen automatische migratie. `openText`
  behoudt zijn semantiek. De editor kan een "upgrade naar fillIn"-actie
  bieden, maar dat is een expliciete authoring-keuze die het blok herschrijft.
- **Marp-compatibiliteit:** de nieuwe `_class` tokens (`objective`,
  `module`, `feedback`, `assessment-summary`) zijn voor Marp onbekende
  classes die een vreemde lezer straffeloos negeert. Het ```question``` blok
  is al een fenced code block dat in Marp als codeblok rendert.

---

## 10. Open vragen (voor de bouwsessie)

1. **Matching één-op-meerdere:** de eerste subset is één-op-één. Eén-op-
   meerdere (één left-item kan naar meerdere right-items) vereist een
   uitbreiding van het `pairs`-model. Open: is dat nodig voor de eerste
   import-golf, of volstaat één-op-één?
2. **Hotspot polygon/circle:** `rect` is de eerste shape. `circle` en `poly`
   als uitbreidingsstap. Open: in de editor tekenbaar in de eerste versie,
   of alleen in het JSON te zetten?
3. **Assessment `passThreshold` als percentage vs absoluut:** ontwerp kiest
   percentage van `maxScore`. Bevestigen bij de bouw.
4. **Kennischeck (#2011) als groepering:** is een kennischeck-slide die
   meerdere vragen toont één `question` blok met meerdere items, of een
   aparte slide die naar andere vraag-slides verwijst? Ontwerp neigt naar
   verwijzing, omdat een slide één vraag draagt in het bestaande model.
5. **eLearning-module-toggle:** opt-in zoals Procesverbetering, of altijd aan
   zoals Managementsysteem? Ontwerp stelt opt-in (spiegelt Procesverbetering),
   maar parsen is onvoorwaardelijk.

---

## 11. Afhankelijkheden

- **Hoofdfeature:** #1992 (eLearning-import + uitbreiding in instellingen).
- **Bouw van slide-types:** #1999 (eLearning-tab + de 8 slide-types).
- **Import-formaten:** #1993 (SCORM), #1994 (QTI), #1995 (xAPI/cmi5),
  #1996 (AICC), #1997 (OLX) — deze leveren de data die in dit model landt.
- **Kind-issues:** #2000–#2008 (de onderdelen die §4 specificeert).

Dit ontwerp is het fundament: de import-issues en de slide-type-bouw leunen
allen op het data-model en de sidecargrens die hier staan.
