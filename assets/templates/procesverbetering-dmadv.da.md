---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: "Procesforbedring: DMADV-projekt"
language: da
ocideck_improvement_framework: dmadv
---

<!-- _class: title -->

# Procesforbedring: DMADV-projekt

---

<!-- skip -->

# Sådan arbejder du med denne skabelon

- Brug DMADV til en ny eller fundamentalt redesignet proces, og vælg ét målbart kunderesultat (**Y-01**).
- Brug spørgsmålene på hvert guidedias som en tjekliste; Tilføj derefter almindelige slides til dine svar.
- Erstat forklaringen i charteret og CTQ-træet med dine projektoplysninger, udfyld SIPOC'en og gør kravene testbare, før du designer.
- Hjælpeslides præsenteres eller eksporteres ikke. Hvis du vil vise en, skal du slå **Spring over** fra for det dias.

---

<!-- _class: section -->

# Definer

---

<!-- skip -->

# Tjekliste — Hvad registrerer du, når du definerer?

- Hvilken kunde eller bruger har hvilket udækket behov?
- Hvorfor er et nyt design nødvendigt, og hvorfor er det ikke nok at forbedre den eksisterende proces?
- Hvilket resultat skal designet levere (**Y-01**) og inden for hvilket omfang?
- Hvem bestemmer over krav, designvalg og frigivelse?
- Hvilken planlægning, forudsætninger og succeskriterier gælder?

---

<!-- _class: canvas -->
<!-- ocideck_template: charter -->

# Projektcharter

## Problem eller mulighed

Beskriv det udækkede behov, målgruppe og påviselig årsag.

## Mål

Formuler det ønskede resultat på en målbar og tidsbestemt måde.

## Omfang

Bemærk udgangspunkt, slutpunkt, kontaktpunkter og hvad der falder uden for designet.

## Hold

Navngiv klient, designejer, brugere og nødvendige eksperter.

## Tidslinje

Registrer milepæle, beslutningsporte og tilsigtet implementering.

## Succeskriterier
Hvornår opfylder designet beviseligt kundernes behov?

---

<!-- _class: tree -->
<!-- ocideck_template: ctq-tree -->
<!-- ocideck_layout: tree -->

# Målbare kundekrav (CTQ-træ)

- Hvilket resultat har kunden brug for? — **Y-01**
  - Oversæt det behov til målbart krav 1
  - Oversæt det behov til målbart krav 2

---

<!-- skip -->

# Tjekliste — Hvordan gennemfører du SIPOC?

- Start med **Kunden**: hvem bruger det nye procesresultat?
- Identificer derefter de nødvendige **Output** og 4 til 7 tilsigtede **Proces**-trin.
- Bemærk den nødvendige **Input** og **Leverandøren**, der gør hver input tilgængelig.
- Hold et generelt overblik; designdetaljer følger senere.
- Tjek om de valgte grænser svarer til charter og Y-01.

---

<!-- _class: matrix -->
<!-- ocideck_template: sipoc -->

# SIPOC

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |
|  |  |  |  |  |

---

<!-- _class: section -->

# Mål

---

<!-- skip -->

# Tjekliste — Hvad registrerer du, når du måler?

- Hvilke kundebehov er blevet omsat til målbare krav og prioriteringer?
- Hvad er målværdi, nedre eller øvre grænse, enhed og målemetode for Y-01?
- Hvilke use cases, volumener og undtagelser skal designet kunne håndtere?
- Hvilke eksisterende resultater eller alternativer bruger du som reference?
- Hvordan vil du objektivt teste, om hvert enkelt krav er opfyldt?

---

<!-- _class: section -->

# Analyser

---

<!-- skip -->

# Tjekliste — Hvad registrerer du, når du analyserer?

- Hvilke funktioner skal processen opfylde for at opfylde kravene?
- Hvilke relationer og afvejninger eksisterer der mellem kundeønsker, risici og designfunktioner?
- Hvilke antagelser mangler stadig at blive udforsket eller testet?
- Hvilke fejltilstande og afhængigheder er vigtigst?
- Hvilke minimumsdesignkriterier skal hver løsning opfylde?

---

<!-- _class: section -->

# Design

---

<!-- skip -->

# Tjekliste — Hvad optager du i Design?

- Hvilke designvarianter blev overvejet, og på hvilke kriterier blev de sammenlignet?
- Hvordan ser det valgte procesflow ud, herunder roller, systemer og overførsler?
- Hvordan forhindrer eller kontrollerer designet de store fejltilstande?
- Hvad lærer en prototype eller test om betjening og brugervenlighed?
- Hvilken variant går til verifikation, med hvilke åbne punkter?

---

<!-- _class: section -->

# Verificere

---

<!-- skip -->

# Tjekliste — Hvad registrerer du, når du verificerer?

- Hvilken test beviser for hvert krav, at designet fungerer under realistiske forhold?
- Hvilke resultater er opnået, og hvilke afvigelser er der tilbage?
- Hvad synes brugere og procesejere om drift og gennemførlighed?
- Hvilken kontrol, instruktion og måling kræves efter idriftsættelse?
- Hvem frigiver designet og på baggrund af hvilke beviser?
