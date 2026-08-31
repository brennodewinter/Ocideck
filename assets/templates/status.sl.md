---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Poročilo o stanju
language: sl
---

<!-- _class: title -->

# Poročilo o stanju

---

# Povzetek stanja

- Splošno stanje: na pravi poti / zahteva pozornost / kritično
- Ključni razvoj dogodkov od prejšnjega poročila: …
- Obeti za prihodnje obdobje: …

---

<!-- _class: cockpit -->

# Nadzorna plošča stanja

```cockpit
{
  "layout": "auto",
  "animateOnEnter": true,
  "meters": [
    {
      "type": "speedometer",
      "label": "Poraba proračuna",
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
      "label": "Raven tveganja",
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
      "label": "Zaupanje v načrt",
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
      "label": "Trend odprtih točk",
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

# Napredek na tok dela

| Delovni tok | Stanje | Razlaga |
| --- | --- | --- |
| Delovni tok A | 🟢 Na dobri poti | Nadaljevanje po načrtih |
| Delovni tok B | 🟠 Pozor | Čakanje na odločitev |
| Delovni tok C | 🔴 Kritično | Pomanjkanje zmogljivosti |

---

# Tveganja in blokatorji

- Tveganje 1: … (verjetnost: velika, vpliv: velik)
- Tveganje 2: … (verjetnost: majhna, vpliv: velik)
- Blokator: … — potrebna pomoč od …

---

# Odločitve in dejanja

- Potrebna odločitev: …
- Dejanje: … (lastnik, datum)
- Dejanje: … (lastnik, datum)
