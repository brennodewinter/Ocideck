---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Status-briefing
language: nl
---

<!-- _class: title -->

# Status-briefing

---

# Samenvatting status

- Algemene status: op koers / aandacht nodig / kritiek
- Belangrijkste ontwikkeling sinds de vorige briefing: …
- Verwachting voor de komende periode: …

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
      "label": "Budgetverbruik",
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
      "label": "Risiconiveau",
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
      "label": "Vertrouwen planning",
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
      "label": "Trend openstaande punten",
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

# Voortgang per werkstroom

| Werkstroom | Status | Toelichting |
| --- | --- | --- |
| Werkstroom A | 🟢 Op koers | Loopt volgens planning |
| Werkstroom B | 🟠 Aandacht | Wacht op besluit |
| Werkstroom C | 🔴 Kritiek | Capaciteit ontbreekt |

---

# Risico's en blokkades

- Risico 1: … (kans: hoog, impact: groot)
- Risico 2: … (kans: laag, impact: groot)
- Blokkade: … — hulp nodig van …

---

# Besluiten en acties

- Besluit nodig: …
- Actie: … (eigenaar, datum)
- Actie: … (eigenaar, datum)

