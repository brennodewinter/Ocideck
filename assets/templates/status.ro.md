---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Briefing de stare
language: ro
---

<!-- _class: title -->

# Briefing de stare

---

# Rezumatul stării

- Stare generală: pe drumul cel bun / necesită atenție / critic
- Evoluție cheie de la briefingul precedent: …
- Perspective pentru perioada următoare:…

---

<!-- _class: cockpit -->

# Tabloul de bord de stare

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

# Progres pe flux de lucru

| Flux de lucru | Stare | Explicaţie |
| --- | --- | --- |
| Fluxul de lucru A | 🟢 Pe drumul cel bun | Se procedează conform planului |
| Fluxul de lucru B | 🟠 Atenție | În așteptarea deciziei |
| Fluxul de lucru C | 🔴 Critic | Lipsă de capacitate |

---

# Riscuri și blocante

- Riscul 1: … (probabilitate: mare, impact: major)
- Riscul 2: … (probabilitate: scăzută, impact: major)
- Blocker: … — nevoie de ajutor de la …

---

# Decizii și acțiuni

- Decizia necesară:…
- Acțiune: … (proprietar, data)
- Acțiune: … (proprietar, data)
