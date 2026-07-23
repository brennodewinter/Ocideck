---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: CAB / release readiness
language: nl
---

<!-- _class: title -->

# CAB / release readiness

---

# Wijziging samengevat

- Wat verandert er: …
- Waarom nu: …
- Aangevraagd door: …

---

# Scope en impact

- Systemen en diensten geraakt: …
- Gebruikers geraakt: …
- Verwachte verstoring: … (duur, moment)

---

<!-- _class: table table-editable -->

# Teststatus

| Test | Resultaat | Bewijs |
| --- | --- | --- |
| Functionele test | Geslaagd / open | … |
| Regressietest | … | … |
| Performancetest | … | … |

---

# Security- en privacycheck
<!-- ocideck_list_style: checklist -->

- [ ] Security-review uitgevoerd
- [ ] Geen nieuwe persoonsgegevens — of DPIA gecheckt
- [ ] Secrets en toegangsrechten gecontroleerd
- [ ] Kwetsbaarhedenscan schoon

---

<!-- _class: table table-editable -->

# Implementatieplan

| Stap | Tijd | Wie |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Rollbackplan
<!-- ocideck_list_style: numbered -->

1. Terugdraaien kan tot: …
2. Rollback-stappen: …
3. Beslismoment go/no-go rollback: …

---

# Communicatieplan

- Vooraf informeren: … (wie, wanneer)
- Tijdens de wijziging: …
- Achteraf bevestigen: …

---

# Go / no-go checklist
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Tests afgerond en akkoord
- [ ] Rollback beproefd of aannemelijk
- [ ] Communicatie klaargezet
- [ ] Beheer geïnformeerd en beschikbaar

---

<!-- _class: table table-editable -->

# Besluit CAB

| Besluit | Voorwaarden | Datum en tijd |
| --- | --- | --- |
| Go / no-go / uitgesteld | … | … |

