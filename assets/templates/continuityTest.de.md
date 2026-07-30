---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Geschäftskontinuitäts-/DR-Test
language: de
---

<!-- _class: title -->

# Geschäftskontinuitäts-/DR-Test

---

# Testszenario

- Szenario: … (z. B. Ausfall des Rechenzentrums, Ransomware)
- Annahme vorab: …
- Testtyp: Tischgerät / teilweise / vollständig

---

# Ziele und Erfolgskriterien

- Ziel des Tests: …
- Erfolgskriterium 1: …
- Erfolgskriterium 2: …

---

<!-- _class: table table-editable -->

# Kritische Prozesse

| Prozess | Priorität | Hängt davon ab |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# RTO/RPO-Übersicht

| Prozess oder System | RTO | RPO | Getroffen? |
| --- | --- | --- | --- |
| … | … | … | Ja/nein |
| … | … | … | … |

---

<!-- _class: timeline -->

# Testzeitleiste

- T+0 :: Teststart :: Szenario angekündigt.
- T+… :: Failover gestartet
- T+… :: Wiederherstellung verifiziert
- T+… :: Testende

---

<!-- _class: table table-editable -->

# Erkenntnisse

| Finden | Schweregrad | Komponente |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Abweichungen und Blocker

- Abweichung vom Spielbuch: …
- Blocker während des Tests: …
- Verwendeter Workaround: …

---

# Verbesserungspunkte
<!-- ocideck_list_style: checklist -->

- [ ] Playbook auf den Punkt aktualisieren: …
- [ ] Technisches Setup anpassen: …
- [ ] Planen Sie ein Training oder eine Übung: …

---

# Go/No-Go-Wiederherstellungsfunktion
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Kritische Prozesse wurden innerhalb von RTO wiederhergestellt
- [ ] Der Datenverlust blieb innerhalb des RPO
- [ ] Playbook erwies sich als brauchbar
- [ ] Urteil: Wiederherstellungsfähigkeit nachgewiesen
