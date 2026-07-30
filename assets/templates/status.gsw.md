---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Statusbesprechung
language: gsw
---

<!-- _class: title -->

# Statusbesprechung

---

# Statuszusammenfassung

- Gesamtstatus: auf dem richtigen Weg / braucht Aufmerksamkeit / kritisch
- Wichtigste Entwicklung seit dem letzten Briefing: …
- Ausblick für die kommende Zeit: …

---

<!-- _class: cockpit -->

# Status-Dashboard

```cockpit
{
  "layout": "auto",
  "animateOnEnter": true,
  "meters": [
    {
      "type": "speedometer",
      "label": "Budget usage",
      "unit": "%",
      "min": 0.0,
      "max": 100.0,
      "greenFrom": 0.0,
      "greenTo": 60.0,
      "redFrom": 85.0,
      "value": 58.0
    },
    {
      "type": "thermometer",
      "label": "Risk level",
      "unit": "/10",
      "min": 0.0,
      "max": 10.0,
      "greenFrom": 0.0,
      "greenTo": 3.0,
      "redFrom": 7.0,
      "value": 4.5
    },
    {
      "type": "voltmeter",
      "label": "Schedule confidence",
      "unit": "%",
      "min": 0.0,
      "max": 100.0,
      "greenFrom": 75.0,
      "greenTo": 100.0,
      "redFrom": 50.0,
      "value": 80.0
    },
    {
      "type": "climbDescent",
      "label": "Trend of open items",
      "min": -10.0,
      "max": 10.0,
      "neutralFrom": -2.0,
      "neutralTo": 2.0,
      "value": 3.0
    }
  ]
}
```

---

<!-- _class: table -->

# Fortschritt pro Workstream

| Arbeitsstream | Status | Erklärung |
| --- | --- | --- |
| Arbeitsstream A | 🟢 Auf dem richtigen Weg | Ablauf wie geplant |
| Arbeitsstream B | 🟠 Achtung | Warten auf Entscheidung |
| Arbeitsstream C | 🔴 Kritisch | Mangelnde Kapazität |

---

# Risiken und Blocker

- Risiko 1: … (Wahrscheinlichkeit: hoch, Auswirkung: gross)
- Risiko 2: … (Wahrscheinlichkeit: gering, Auswirkung: gross)
- Blocker: … – Hilfe benötigt von …

---

# Entscheidungen und Handlungen

- Entscheidung nötig: …
- Aktion: … (Inhaber, Datum)
- Aktion: … (Inhaber, Datum)
