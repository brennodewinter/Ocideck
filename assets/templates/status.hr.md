---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Obavijest o statusu
language: hr
---

<!-- _class: title -->

# Obavijest o statusu

---

# Sažetak statusa

- Cjelokupni status: na pravom putu / treba pozornost / kritično
- Ključni razvoj događaja od prethodnog brifinga: …
- Izgledi za naredni period: …

---

<!-- _class: cockpit -->

# Nadzorna ploča statusa

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

# Napredak po toku rada

| Radni tok | Status | Objašnjenje |
| --- | --- | --- |
| Tok rada A | 🟢 Na putu | Nastavak prema planu |
| Radni tok B | 🟠 Pažnja | Čeka se odluka |
| Radni tok C | 🔴 Kritično | Nedostatak kapaciteta |

---

# Rizici i blokatori

- Rizik 1: … (vjerojatnost: velika, utjecaj: veliki)
- Rizik 2: … (vjerojatnost: mala, utjecaj: veliki)
- Blokator: … — potrebna pomoć od …

---

# Odluke i akcije

- Potrebna odluka: …
- Radnja: … (vlasnik, datum)
- Radnja: … (vlasnik, datum)
