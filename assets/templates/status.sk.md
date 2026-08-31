---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Statusový briefing
language: sk
---

<!-- _class: title -->

# Statusový briefing

---

# Súhrn stavu

- Celkový stav: na ceste / vyžaduje pozornosť / kritický
- Kľúčový vývoj od predchádzajúceho brífingu: …
- Výhľad na najbližšie obdobie:…

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
      "label": "Čerpanie rozpočtu",
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
      "label": "Úroveň rizika",
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
      "label": "Dôvera v plán",
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
      "label": "Trend otvorených bodov",
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

# Pokrok na pracovný tok

| Pracovný tok | Stav | Vysvetlenie |
| --- | --- | --- |
| Pracovný prúd A | 🢢 Na ceste | Postup podľa plánu |
| Pracovný tok B | 🠠 Pozor | Čaká sa na rozhodnutie |
| Pracovný tok C | 🔴 Kritické | Nedostatok kapacity |

---

# Riziká a blokátory

- Riziko 1: … (pravdepodobnosť: vysoká, vplyv: veľký)
- Riziko 2: … (pravdepodobnosť: nízka, vplyv: veľký)
- Blokátor: … — potrebná pomoc od…

---

# Rozhodnutia a činy

- Potrebné rozhodnutie:…
- Akcia: … (majiteľ, dátum)
- Akcia: … (majiteľ, dátum)
