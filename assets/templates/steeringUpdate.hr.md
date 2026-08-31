---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Ažuriranje Upravnog odbora / projektnog odbora
language: hr
---

<!-- _class: title -->

# Ažuriranje Upravnog odbora / projektnog odbora

---

# Sažetak upravljanja

- Status u jednoj rečenici: …
- Ključni razvoj: …
- Ključno pitanje za upravni odbor: …

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
      "label": "Potrošnja proračuna",
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
      "label": "Povjerenje u plan",
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
      "label": "Razina rizika",
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

# Raspored i prekretnice

- Q1 :: Prekretnica 1 :: Ostvareno.
- Q2 :: Prekretnica 2 :: Na putu.
- Q3 :: Prekretnica 3 :: Treba pozornost.

---

<!-- _class: table -->

# Proračun i resursi

| Stavka | U proračunu | Potrošeno | Prognoza |
| --- | --- | --- | --- |
| Ukupni proračun | … | … | … |
| Timski rad (FTE) | … | … | … |

---

<!-- _class: table table-editable -->

# Rizici i problemi

| Rizik ili problem | Status | Akcija |
| --- | --- | --- |
| … | Novo / u tijeku / zatvoreno | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# Tražene odluke

| Odluka | Objašnjenje | Ishod |
| --- | --- | --- |
| … | … | Odobreno / odbijeno / odgođeno |
| … | … | … |

---

<!-- _class: table table-editable -->

# Radnje od prošli put

| Akcija | Vlasnik | Status |
| --- | --- | --- |
| … | … | Dovršeno / u tijeku / odgođeno |
| … | … | … |

---

<!-- _class: table table-editable -->

# Nove akcije

| Akcija | Vlasnik | Rok |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Eskalacije

- Eskalacija: … — traženo od upravnog odbora: …
- Nema eskalacija: potvrdite i zabilježite
