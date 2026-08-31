---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Business continuity / DR-test
language: da
---

<!-- _class: title -->

# Business continuity / DR-test

---

# Testscenarie

- Scenario: … (f.eks. datacenterafbrydelse, ransomware)
- Antagelse på forhånd: …
- Testtype: bordplade / delvis / fuld

---

# Mål og succeskriterier

- Formål med testen: …
- Succeskriterium 1: …
- Succeskriterium 2: …

---

<!-- _class: table table-editable -->

# Kritiske processer

| Proces | Prioritet | Afhænger af |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# RTO / RPO oversigt

| Proces eller system | RTO | RPO | mødt? |
| --- | --- | --- | --- |
| … | … | … | Ja/nej |
| … | … | … | … |

---

<!-- _class: timeline -->

# Test tidslinje

- T+0 :: Teststart :: Scenario annonceret.
- T+... :: Failover startede
- T+... :: Gendannelse verificeret
- T+... :: Testslut

---

<!-- _class: table table-editable -->

# Fund

| Finde | Sværhedsgrad | Komponent |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Afvigelser og blokkere

- Afvigelse fra spillebogen: …
- Blokering under testen: …
- Brugt løsning: …

---

# Forbedringspunkter
<!-- ocideck_list_style: checklist -->

- [ ] Opdater spillebogen på punkt: …
- [ ] Juster teknisk opsætning: …
- [ ] Planlæg træning eller motion:...

---

# Go / no-go gendannelsesevne
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Kritiske processer gendannet inden for RTO
- [ ] Datatab forblev inden for RPO
- [ ] Playbook viste sig brugbar
- [ ] Bedømmelse: genoprettelsesevne demonstreret
