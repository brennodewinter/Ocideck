---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Briefing tal-istatus
language: mt
---

<!-- _class: title -->

# Briefing tal-istatus

---

# Sommarju tal-istatus

- Status ġenerali: fit-triq it-tajba / jeħtieġ attenzjoni / kritiku
- Żvilupp ewlieni mill-briefing preċedenti:...
- Prospetti għall-perjodu li ġej:...

---

<!-- _class: cockpit -->

# Dashboard tal-istatus

```cockpit
{
  "layout": "auto",
  "animateOnEnter": true,
  "meters": [
    {
      "type": "speedometer",
      "label": "Użu tal-baġit",
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
      "label": "Livell ta' riskju",
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
      "label": "Fiduċja fl-iskeda",
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
      "label": "Xejra tal-punti miftuħa",
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

# Progress għal kull workstream

| Workstream | Status | Spjegazzjoni |
| --- | --- | --- |
| Workstream A | 🟢 Fit-triq it-tajba | Proċediment kif ippjanat |
| Workstream B | 🟠 Attenzjoni | Tistenna deċiżjoni |
| Workstream Ċ | 🔴 Kritika | Nuqqas ta' kapaċità |

---

# Riskji u imblokkaturi

- Riskju 1: … (probabbiltà: għolja, impatt: kbir)
- Riskju 2: … (probabbiltà: baxx, impatt: kbir)
- Blocker: … — għajnuna meħtieġa minn…

---

# Deċiżjonijiet u azzjonijiet

- Deċiżjoni meħtieġa:…
- Azzjoni: … (sid, data)
- Azzjoni: … (sid, data)
