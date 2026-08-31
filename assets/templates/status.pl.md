---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Informacje o stanie
language: pl
---

<!-- _class: title -->

# Informacje o stanie

---

# Podsumowanie stanu

- Stan ogólny: na dobrej drodze / wymaga uwagi / krytyczny
- Kluczowe zmiany od czasu poprzedniej odprawy: …
- Perspektywy na nadchodzący okres: …

---

<!-- _class: cockpit -->

# Panel stanu

```cockpit
{
  "layout": "auto",
  "animateOnEnter": true,
  "meters": [
    {
      "type": "speedometer",
      "label": "Wykorzystanie budżetu",
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
      "label": "Poziom ryzyka",
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
      "label": "Zaufanie do harmonogramu",
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
      "label": "Trend otwartych punktów",
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

# Postęp według strumienia pracy

| Strumień pracy | Status | Wyjaśnienie |
| --- | --- | --- |
| Strumień pracy A | 🟢 Na dobrej drodze | Postępowanie zgodnie z planem |
| Strumień pracy B | 🟠 Uwaga | Oczekiwanie na decyzję |
| Strumień pracy C | 🔴 Krytyczny | Brak możliwości |

---

# Zagrożenia i blokady

- Ryzyko 1: … (prawdopodobieństwo: wysokie, wpływ: poważny)
- Ryzyko 2: … (prawdopodobieństwo: niskie, wpływ: poważny)
- Bloker: … — potrzebna pomoc od…

---

# Decyzje i działania

- Potrzebna decyzja: …
- Akcja: … (właściciel, data)
- Akcja: … (właściciel, data)
