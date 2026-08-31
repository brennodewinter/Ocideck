---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Állapottájékoztató
language: hu
---

<!-- _class: title -->

# Állapottájékoztató

---

# Állapot összefoglaló

- Általános állapot: jó úton halad / figyelmet igényel / kritikus
- Legfontosabb fejlemények az előző tájékoztató óta:…
- Kilátások a következő időszakra:…

---

<!-- _class: cockpit -->

# Állapot irányítópult

```cockpit
{
  "layout": "auto",
  "animateOnEnter": true,
  "meters": [
    {
      "type": "speedometer",
      "label": "Költségvetés felhasználása",
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
      "label": "Kockázati szint",
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
      "label": "Bizalom az ütemtervben",
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
      "label": "Nyitott pontok trendje",
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

# Haladás munkafolyamatonként

| Munkafolyamat | Állapot | Magyarázat |
| --- | --- | --- |
| Munkafolyamat A | 🟢 A pályán | A tervek szerint haladunk |
| Munkafolyamat B | 🟠 Figyelem | Döntésre vár |
| Munkafolyamat C | 🔴 Kritikus | Kapacitás hiánya |

---

# Kockázatok és blokkolók

- 1. kockázat: … (valószínűség: nagy, hatás: jelentős)
- 2. kockázat: … (valószínűség: alacsony, hatás: jelentős)
- Blokkoló: … – segítségre van szükség a…

---

# Döntések és tettek

- Döntés szükséges:…
- Művelet: … (tulajdonos, dátum)
- Művelet: … (tulajdonos, dátum)
