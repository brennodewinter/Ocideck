---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Business continuity / DR-test
language: sv
---

<!-- _class: title -->

# Business continuity / DR-test

---

# Testscenario

- Scenario: … (t.ex. datacenteravbrott, ransomware)
- Antagande i förväg: …
- Testtyp: bordsskiva / partiell / hel

---

# Mål och framgångskriterier

- Mål med testet: …
- Framgångskriterium 1: …
- Framgångskriterium 2: …

---

<!-- _class: table table-editable -->

# Kritiska processer

| Behandla | Prioritet | Beror på |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# RTO / RPO översikt

| Process eller system | RTO | RPO | Träffade? |
| --- | --- | --- | --- |
| … | … | … | Ja/nej |
| … | … | … | … |

---

<!-- _class: timeline -->

# Testa tidslinjen

- T+0 :: Teststart :: Scenario tillkännagav.
- T+... :: Failover startade
- T+... :: Återställning verifierad
- T+... :: Testslut

---

<!-- _class: table table-editable -->

# Fynd

| Fynd | Stränghet | Komponent |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Avvikelser och blockerare

- Avvikelse från spelboken: …
- Blockerare under testet: …
- Använda lösningen: …

---

# Förbättringspunkter
<!-- ocideck_list_style: checklist -->

- [ ] Uppdatera spelboken direkt: …
- [ ] Justera tekniska inställningar: …
- [ ] Schemalägg träning eller träning:...

---

# Go / no-go återställningsförmåga
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Kritiska processer återvinns inom RTO
- [ ] Dataförlusten stannade inom RPO
- [ ] Playbook visade sig användbar
- [ ] Bedömning: återställningsförmåga demonstrerad
