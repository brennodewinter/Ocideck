---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Status-briefing
language: fy
---

<!-- _class: title -->

# Status-briefing

---

# Status gearfetting

- Algemiene status: op spoar / moat oandacht / kritysk
- Key ûntwikkeling sûnt de foarige briefing: ...
- Foarútsjoch foar de kommende perioade: …

---

<!-- _class: cockpit -->

# Statusdashboard

```cockpit
{
  "layout": "auto",
  "animateOnEnter": true,
  "meters": [
    {
      "type": "speedometer",
      "label": "Budzjetferbrûk",
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
      "label": "Risikonivo",
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
      "label": "Fertrouwen yn de planning",
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
      "label": "Trend iepensteande punten",
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

# Foarútgong per wurkstream

| Wurkstream | Status | Taljochting |
| --- | --- | --- |
| Wurkstream A | 😢 Op koers | Trochgean lykas pland |
| Wurkstream B | 🠠 Oandacht | Wachtsje op beslút |
| Wurkstream C | 🔴 Kritysk | Gebrek oan kapasiteit |

---

# Risiko's en blokkers

- Risiko 1: … (wierskynlikens: heech, ynfloed: grut)
- Risiko 2: … (wierskynlikens: leech, ynfloed: grut)
- Blocker: ... - help nedich fan ...

---

# Besluten en aksjes

- Beslút nedich: …
- Aksje: … (eigner, datum)
- Aksje: … (eigner, datum)
