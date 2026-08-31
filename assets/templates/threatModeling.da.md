---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Trusselsmodelleringssession
language: da
---

<!-- _class: title -->

# Trusselsmodelleringssession
## System · Dato · Facilitator · Deltagere

---

# Omfang og mål

- Hvilket system eller komponent modellerer vi i dag?
- Hvad er eksplicit uden for anvendelsesområdet: …
- Forudsætninger vi arbejder med: …
- Resultat: vægtede trusler med afhjælpning og en ejer

---

<!-- _class: table table-editable -->

# Kortlægning af systemet

| Element | Venlig | Noter |
| --- | --- | --- |
| … | Komponent | … |
| … | Dataflow | … |
| … | Ekstern part | … |

---

# Tillidsgrænser

- Hvor krydser data fra pålidelige til ikke-pålidelige?
- Hvilke grænser ser vi: netværk, proces, bruger, forsyningskæde?
- Hvor sker godkendelse og inputvalidering?
- Tegn alle grænser på systemskitsen: …

---

<!-- _class: table -->

# STRIDE-reference

| Kategori | Betydning |
| --- | --- |
| Spoofing | Udgiver sig for at være en anden bruger eller tjeneste |
| Indgreb | Uautoriseret ændring af data eller kode |
| Afvisning | Nægter, at en handling nogensinde har fundet sted |
| Videregivelse af oplysninger | Oplysninger, der når frem til dem, der ikke må se dem |
| Denial of service | Gør systemet ubrugeligt eller utilgængeligt |
| Forhøjelse af privilegier | Får flere privilegier end givet |

---

<!-- _class: table table-editable -->

# Indsamling af trusler

| Trussel | STRIDE kategori | Komponent | Risiko |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Prioritering: sandsynlighed × effekt

- Sandsynlighed: hvor sandsynligt er misbrug (lav, middel, høj)?
- Virkning: hvor meget skade, hvis det sker?
- Risiko = sandsynlighed × effekt; høj-høj går først
- I tvivl: vælg det højere skøn og noter hvorfor

---

<!-- _class: table table-editable -->

# Afbødninger og handlinger

| Afbødning | Ejer | Status |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Hvad vi bevidst accepterer

- Hvilke trusler adresserer vi bevidst ikke: …
- Hvorfor er det berettiget (sandsynlighed, omkostninger, kontekst): …
- Hvem ejer denne beslutning: Rolle
- Hvornår gentager vi dette:...

---

# Session afsluttet
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Omfang og forudsætninger registreret
- [ ] Komponenter, datastrømme og eksterne parter kortlagt
- [ ] Tillidsgrænser trukket
- [ ] Alle seks STRIDE-kategorier gik igennem
- [ ] Trusler prioriteret efter sandsynlighed × effekt
- [ ] Afhjælpninger tildelt en ejer
- [ ] Accepterede risici registreret og ejet
