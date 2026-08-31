---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Statusgenomgång
language: sv
---

<!-- _class: title -->

# Statusgenomgång

---

# Statusöversikt

- Övergripande status: på väg / behöver uppmärksamhet / kritisk
- Nyckelutveckling sedan föregående genomgång: …
- Utsikter för den kommande perioden: …

---

<!-- _class: cockpit -->

# Status instrumentpanel

```cockpit
{
  "layout": "auto",
  "animateOnEnter": true,
  "meters": [
    {
      "type": "speedometer",
      "label": "Budgetförbrukning",
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
      "label": "Risknivå",
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
      "label": "Förtroende för planen",
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
      "label": "Trend för öppna punkter",
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

# Framsteg per arbetsflöde

| Arbetsström | Status | Förklaring |
| --- | --- | --- |
| Arbetsflöde A | 🟢 På gång | Fortsätter som planerat |
| Arbetsflöde B | 🠠 Uppmärksamhet | Väntar på beslut |
| Arbetsflöde C | 🔴 Kritisk | Saknar kapacitet |

---

# Risker och blockerare

- Risk 1: … (sannolikhet: hög, påverkan: stor)
- Risk 2: … (sannolikhet: låg, påverkan: stor)
- Blockerare: … — hjälp behövs från …

---

# Beslut och handlingar

- Beslut krävs: …
- Åtgärd: … (ägare, datum)
- Åtgärd: … (ägare, datum)
