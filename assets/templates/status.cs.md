---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Stavový briefing
language: cs
---

<!-- _class: title -->

# Stavový briefing

---

# Shrnutí stavu

- Celkový stav: na cestě / vyžaduje pozornost / kritický
- Klíčový vývoj od předchozího briefingu: …
- Výhled na další období:…

---

<!-- _class: cockpit -->

# Stavový panel

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

# Pokrok na pracovní tok

| Pracovní proud | Stav | Vysvětlení |
| --- | --- | --- |
| Pracovní proud A | 🢢 Na cestě | Postup podle plánu |
| Pracovní proud B | 🠠 Pozor | Čekání na rozhodnutí |
| Pracovní proud C | 🔴 Kritické | Nedostatek kapacity |

---

# Rizika a blokátory

- Riziko 1: … (pravděpodobnost: vysoká, dopad: velký)
- Riziko 2: … (pravděpodobnost: nízká, dopad: velký)
- Blocker: … — potřebná pomoc od…

---

# Rozhodnutí a činy

- Potřebné rozhodnutí:…
- Akce: … (majitel, datum)
- Akce: … (majitel, datum)
