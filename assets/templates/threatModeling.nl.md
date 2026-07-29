---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Threat modeling-sessie
language: nl
---

<!-- _class: title -->

# Threat modeling-sessie
## Systeem · Datum · Facilitator · Deelnemers

---

# Scope en doel

- Welk systeem of onderdeel modelleren we vandaag?
- Wat valt er expliciet buiten scope: …
- Aannames waarmee we werken: …
- Resultaat: gewogen dreigingen mét maatregelen en eigenaar

---

<!-- _class: table table-editable -->

# Het systeem in kaart

| Element | Soort | Toelichting |
| --- | --- | --- |
| … | Component | … |
| … | Datastroom | … |
| … | Externe partij | … |

---

# Vertrouwensgrenzen

- Waar gaat data over van vertrouwd naar onvertrouwd?
- Welke grenzen zien we: netwerk, proces, gebruiker, keten?
- Waar vindt authenticatie en invoervalidatie plaats?
- Teken elke grens in op de systeemschets: …

---

<!-- _class: table -->

# STRIDE-referentie

| Categorie | Betekenis |
| --- | --- |
| Spoofing | Zich voordoen als een andere gebruiker of dienst |
| Tampering | Ongeautoriseerd wijzigen van data of code |
| Repudiation | Ontkennen dat een handeling heeft plaatsgevonden |
| Information disclosure | Informatie komt terecht bij wie er niet bij mag |
| Denial of service | Het systeem onbruikbaar of onbereikbaar maken |
| Elevation of privilege | Meer rechten verwerven dan toegekend |

---

<!-- _class: table table-editable -->

# Dreigingen verzamelen

| Dreiging | STRIDE-categorie | Component | Risico |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Prioriteren: kans × impact

- Kans: hoe waarschijnlijk is misbruik (laag, midden, hoog)?
- Impact: hoe groot is de schade als het gebeurt?
- Risico = kans × impact; hoog-hoog pakken we eerst
- Bij twijfel: kies de hogere inschatting en noteer waarom

---

<!-- _class: table table-editable -->

# Maatregelen en acties

| Maatregel | Eigenaar | Status |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Wat we bewust accepteren

- Welke dreigingen pakken we bewust niet op: …
- Waarom is dat verantwoord (kans, kosten, context): …
- Wie draagt dit besluit: Rol
- Wanneer kijken we hier opnieuw naar: …

---

# Sessie compleet
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Scope en aannames vastgelegd
- [ ] Componenten, datastromen en externe partijen in kaart
- [ ] Vertrouwensgrenzen ingetekend
- [ ] Alle zes STRIDE-categorieën langsgelopen
- [ ] Dreigingen geprioriteerd op kans × impact
- [ ] Maatregelen belegd met eigenaar
- [ ] Geaccepteerde risico's vastgelegd en gedragen
