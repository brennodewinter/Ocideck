---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Būsenos instruktažas
language: lt
---

<!-- _class: title -->

# Būsenos instruktažas

---

# Būsenos santrauka

- Bendra būklė: tinkama / reikia dėmesio / kritinė
- Pagrindiniai pokyčiai po ankstesnio pranešimo:…
- Ateinančio laikotarpio perspektyvos:…

---

<!-- _class: cockpit -->

# Būsenos prietaisų skydelis

```cockpit
{
  "layout": "auto",
  "animateOnEnter": true,
  "meters": [
    {
      "type": "speedometer",
      "label": "Biudžeto naudojimas",
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
      "label": "Rizikos lygis",
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
      "label": "Pasitikėjimas grafiku",
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
      "label": "Atvirų punktų tendencija",
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

# Pažanga pagal darbo eigą

| Darbo srautas | Būsena | Paaiškinimas |
| --- | --- | --- |
| Darbo eiga A | 🟢 Kelyje | Vyksta kaip planuota |
| Darbo eiga B | 🟠 Dėmesio | Laukiama sprendimo |
| Darbo eiga C | 🔴 Kritinis | Trūksta pajėgumų |

---

# Rizika ir blokatoriai

- 1 rizika: … (tikimybė: didelė, poveikis: didelis)
- 2 rizika: … (tikimybė: maža, poveikis: didelis)
- Blokatorius: … — reikalinga pagalba iš…

---

# Sprendimai ir veiksmai

- Reikalingas sprendimas:…
- Veiksmas: … (savininkas, data)
- Veiksmas: … (savininkas, data)
