---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Status briefing
language: mt
---

<!-- _class: title -->

# Briefing dwar l-istatus

[[OCIDECK_SEG]]] 

Status ġenerali: fit-triq it-tajba / jeħtieġ attenzjoni / kritiku

[[OCIDECK_SEG]]] 

Żvilupp ewlieni mill-briefing preċedenti:...

[[OCIDECK_SEG]]] 

Prospetti għall-perjodu li ġej:...

[[OCIDECK_SEG]]] 

Sommarju tal-istatus

[[OCIDECK_SEG]]] 

Dashboard tal-istatus

[[OCIDECK_SEG]]] 

Progress għal kull workstream

[[OCIDECK_SEG]]] 

Workstream

[[OCIDECK_SEG]]] 

Status

[[OCIDECK_SEG]]] 

Spjegazzjoni

[[OCIDECK_SEG]]] 

Workstream A

[[OCIDECK_SEG]]] 

🟢 Fit-triq it-tajba

[[OCIDECK_SEG]]] 

Proċediment kif ippjanat

[[OCIDECK_SEG]]] 

Workstream B

[[OCIDECK_SEG]]] 

🟠 Attenzjoni

[[OCIDECK_SEG]]] 

Tistenna deċiżjoni

[[OCIDECK_SEG]]] 

Workstream Ċ

[[OCIDECK_SEG]]] 

🔴 Kritika

[[OCIDECK_SEG]]] 

Nuqqas ta' kapaċità

[[OCIDECK_SEG]]] 

Riskju 1: … (probabbiltà: għolja, impatt: kbir)

[[OCIDECK_SEG]]] 

Riskju 2: … (probabbiltà: baxx, impatt: kbir)

[[OCIDECK_SEG]]] 

Blocker: … — għajnuna meħtieġa minn…

[[OCIDECK_SEG]]] 

Riskji u imblokkaturi

[[OCIDECK_SEG]]] 

Deċiżjoni meħtieġa:…

[[OCIDECK_SEG]]] 

Azzjoni: … (sid, data)

[[OCIDECK_SEG]]] 

Azzjoni: … (sid, data)

[[OCIDECK_SEG]]] 

Deċiżjonijiet u azzjonijiet

[[OCIDECK_SEG]]] 

Briefing dwar l-istatus

---

# Status summary

- Overall status: on track / needs attention / critical
- Key development since the previous briefing: …
- Outlook for the coming period: …

---

<!-- _class: cockpit -->

# Status dashboard

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

# Progress per workstream

| Workstream | Status | Explanation |
| --- | --- | --- |
| Workstream A | 🟢 On track | Proceeding as planned |
| Workstream B | 🟠 Attention | Awaiting decision |
| Workstream C | 🔴 Critical | Lacking capacity |

---

# Risks and blockers

- Risk 1: … (likelihood: high, impact: major)
- Risk 2: … (likelihood: low, impact: major)
- Blocker: … — help needed from …

---

# Decisions and actions

- Decision needed: …
- Action: … (owner, date)
- Action: … (owner, date)
