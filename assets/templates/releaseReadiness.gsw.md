---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: CAB / Release Readiness
language: gsw
---

<!-- _class: title -->

# CAB / Release Readiness

---

# Zusammenfassung ändern

- Was ändert sich: …
- Warum jetzt: …
- Angefordert von: …

---

# Umfang und Wirkung

- Betroffene Systeme und Dienste: …
- Betroffene Benutzer: …
- Erwartete Störung: … (Dauer, Zeitpunkt)

---

<!-- _class: table table-editable -->

# Teststatus

| Testen | Ergebnis | Beweise |
| --- | --- | --- |
| Funktionstest | Bestanden / offen | … |
| Regressionstest | … | … |
| Leistungstest | … | … |

---

# Sicherheits- und Datenschutzprüfung
<!-- ocideck_list_style: checklist -->

- [ ] Sicherheitsüberprüfung durchgeführt
- [ ] Keine neuen personenbezogenen Daten – oder DPIA geprüft
- [ ] Geheimnisse und Zugriffsrechte überprüft
- [ ] Schwachstellenscan sauber

---

<!-- _class: table table-editable -->

# Umsetzungsplan

| Schritt | Zeit | Wer |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Rollback-Plan
<!-- ocideck_list_style: numbered -->

1. Zrugrolle möglich bis: …
2. Rollback-Schritt: …
3. Go/No-go-Entscheidpunkt fürs Rollback: …

---

# Kommunikationsplan

- Vorab informieren: … (wer, wann)
- Während des Wechsels: …
- Anschliessend bestätigen: …

---

# Go/No-Go-Checkliste
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Tests abgeschlossen und genehmigt
- [ ] Rollback getestet oder plausibel
- [ ] Kommunikation vorbereitet
- [ ] Betriebe informiert und verfügbar

---

<!-- _class: table table-editable -->

# CAB-Entscheidung

| Entscheidung | Bedingungen | Datum und Uhrzeit |
| --- | --- | --- |
| Go / No-Go / verschoben | … | … |
