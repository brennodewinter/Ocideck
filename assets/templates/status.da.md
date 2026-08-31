---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Status briefing
language: da
---

<!-- _class: title -->

# Status briefing

---

# Statusoversigt

- Overordnet status: på vej / kræver opmærksomhed / kritisk
- Nøgleudvikling siden den forrige briefing: …
- Forventninger til den kommende periode: …

---

<!-- _class: cockpit -->

# Status dashboard

```cockpit
{
  "layout": "auto",
  "animateOnEnter": true,
  "meters": [
    {
      "type": "speedometer",
      "label": "Budgetforbrug",
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
      "label": "Risikoniveau",
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
      "label": "Tillid til planen",
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
      "label": "Tendens for åbne punkter",
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

# Fremskridt pr. arbejdsstrøm

| Arbejdsstrøm | Status | Forklaring |
| --- | --- | --- |
| Arbejdsstrøm A | 🟢 På vej | Fortsætter som planlagt |
| Arbejdsstrøm B | 🠀 Opmærksomhed | Afventer afgørelse |
| Arbejdsstrøm C | 🔴 Kritisk | Manglende kapacitet |

---

# Risici og blokkere

- Risiko 1: … (sandsynlighed: høj, indvirkning: større)
- Risiko 2: … (sandsynlighed: lav, indvirkning: større)
- Blokering: … — brug for hjælp fra …

---

# Beslutninger og handlinger

- Nødvendig beslutning: …
- Handling: … (ejer, dato)
- Handling: … (ejer, dato)
