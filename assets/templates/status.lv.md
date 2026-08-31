---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Statusa brīfings
language: lv
---

<!-- _class: title -->

# Statusa brīfings

---

# Statusa kopsavilkums

- Kopējais statuss: uz pareizā ceļa / nepieciešama uzmanība / kritiska
- Galvenā attīstība kopš iepriekšējās instruktāžas:…
- Perspektīvas nākamajam periodam:…

---

<!-- _class: cockpit -->

# Statusa informācijas panelis

```cockpit
{
  "layout": "auto",
  "animateOnEnter": true,
  "meters": [
    {
      "type": "speedometer",
      "label": "Budžeta izlietojums",
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
      "label": "Riska līmenis",
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
      "label": "Uzticēšanās grafikam",
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
      "label": "Atvērto punktu tendence",
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

# Progress katrā darbplūsmā

| Darbplūsma | Statuss | Paskaidrojums |
| --- | --- | --- |
| Darbplūsma A | 🟢 Uz ceļa | Turpinās kā plānots |
| Darbplūsma B | 🟠 Uzmanību | Gaida lēmumu |
| Darbplūsma C | 🔴 Kritiski | Trūkst jaudas |

---

# Riski un bloķētāji

- 1. risks: … (iespējamība: augsta, ietekme: liela)
- 2. risks: … (iespējamība: zema, ietekme: liela)
- Bloķētājs: … — nepieciešama palīdzība no…

---

# Lēmumi un rīcība

- Nepieciešams lēmums:…
- Darbība: … (īpašnieks, datums)
- Darbība: … (īpašnieks, datums)
