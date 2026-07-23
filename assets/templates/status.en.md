---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Status briefing
language: en
---

<!-- _class: title -->

# Status briefing

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
