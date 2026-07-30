---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Staatuse briifing
language: et
---

<!-- _class: title -->

# Staatuse briifing

---

# Oleku kokkuvõte

- Üldine seisund: õigel teel / vajab tähelepanu / kriitiline
- Põhiareng pärast eelmist infotundi: …
- Tuleva perioodi väljavaade: …

---

<!-- _class: cockpit -->

# Oleku armatuurlaud

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

# Edenemine töövoo kohta

| Töövoog | Olek | Selgitus |
| --- | --- | --- |
| Töövoog A | 🟢 Rajal | Edasi plaanipäraselt |
| Töövoog B | 🟠 Tähelepanu | Otsuse ootel |
| Töövoog C | 🔴 Kriitiline | Puudub võimsus |

---

# Riskid ja blokaatorid

- Risk 1: … (tõenäosus: suur, mõju: suur)
- Risk 2: … (tõenäosus: väike, mõju: suur)
- Blokeerija: … — abi vajatakse…

---

# Otsused ja teod

- Vajalik otsus:…
- Toiming: … (omanik, kuupäev)
- Toiming: … (omanik, kuupäev)
