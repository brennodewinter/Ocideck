---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Briefing di status
language: pap
---

<!-- _class: title -->

# Briefing di status

---

# Resumen di status

- Status general: riba bon kaminda / mester di atenshon / krítiko
- Desaroyo klave for di e informashon anterior: …
- Perspektiva pa e periodo benidero: …

---

<!-- _class: cockpit -->

# Dashboard di status

```cockpit
{
  "layout": "auto",
  "animateOnEnter": true,
  "meters": [
    {
      "type": "speedometer",
      "label": "Uso di presupuesto",
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
      "label": "Nivel di risiko",
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
      "label": "Konfiansa den planifikashon",
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
      "label": "Tendensia di puntonan habrí",
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

# Progreso pa fluho di trabou

| Fluho di trabou | Status | Splikashon |
| --- | --- | --- |
| Trabou A | 🟢 Riba kaminda | Siguiendo manera planiá |
| Fluho di trabou B | 🟠 Atenshon | Wardando riba desishon |
| Fluho di trabou C | 🔴 Krítiko | Faltando kapasidat |

---

# Riesgonan i blokeonan

- Riesgo 1: … (probabilidat: haltu, impakto: grandi)
- Riesgo 2: … (probabilidat: abou, impakto: grandi)
- Bloker: … — yudansa nesesario di …

---

# Desishonnan i akshonnan

- Desishon nesesario: …
- Akshon: … (doño, fecha)
- Akshon: … (doño, fecha)
