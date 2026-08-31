---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Irányítóbizottság / projektbizottság frissítése
language: hu
---

<!-- _class: title -->

# Irányítóbizottság / projektbizottság frissítése

---

# Menedzsment összefoglaló

- Állapot egy mondatban:…
- Főbb fejlesztések:…
- Kulcskérdés az irányítóbizottsághoz:…

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
      "value": 55.0
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
      "value": 78.0
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
      "value": 4.0
    }
  ]
}
```

---

<!-- _class: timeline -->

# Ütemezés és mérföldkövek

- Q1 :: 1. mérföldkő :: Teljesítve.
- Q2 :: 2. mérföldkő :: A pályán.
- Q3 :: 3. mérföldkő :: Figyelmet igényel.

---

<!-- _class: table -->

# Költségvetés és források

| Tétel | Költségvetésben | Elköltött | Előrejelzés |
| --- | --- | --- | --- |
| Teljes költségvetés | … | … | … |
| Csapatmunka (FTE) | … | … | … |

---

<!-- _class: table table-editable -->

# Kockázatok és problémák

| Kockázat vagy probléma | Állapot | Akció |
| --- | --- | --- |
| … | Új / folyamatban lévő / lezárt | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# Kért határozatokat

| határozat | Magyarázat | Eredmény |
| --- | --- | --- |
| … | … | Jóváhagyva / elutasítva / elhalasztva |
| … | … | … |

---

<!-- _class: table table-editable -->

# Múltkori akciók

| Akció | Tulajdonos | Állapot |
| --- | --- | --- |
| … | … | Befejezve / folyamatban / késve |
| … | … | … |

---

<!-- _class: table table-editable -->

# Új akciók

| Akció | Tulajdonos | Határidő |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Eszkalációk

- Eszkaláció: … – az irányítóbizottságtól kérve: …
- Nincs eszkaláció: erősítse meg és rögzítse
