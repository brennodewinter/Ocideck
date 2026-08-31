---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Faisnéisiú stádais
language: ga
---

<!-- _class: title -->

# Faisnéisiú stádais

---

# Achoimre ar stádas

- Stádas foriomlán: de réir a chéile / de dhíth / aird chriticiúil
- Príomhfhorbairt ón gcruinniú faisnéise roimhe seo: …
- Forbhreathnú don tréimhse amach romhainn: …

---

<!-- _class: cockpit -->

# Deais stádais

```cockpit
{
  "layout": "auto",
  "animateOnEnter": true,
  "meters": [
    {
      "type": "speedometer",
      "label": "Úsáid an bhuiséid",
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
      "label": "Leibhéal riosca",
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
      "label": "Muinín as an sceideal",
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
      "label": "Treocht na míreanna oscailte",
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

# Dul chun cinn in aghaidh an tsrutha oibre

| Sruth oibre | Stádas | Míniú |
| --- | --- | --- |
| Sruth Oibre A | 🟢 Ar an mbóthar | Ag dul ar aghaidh mar a bhí beartaithe |
| Sruth Oibre B | 🟠 Aird | Ag feitheamh ar chinneadh |
| Sruth Oibre C | 🔴 Chriticiúil | Easpa acmhainne |

---

# Rioscaí agus bacóirí

- Riosca 1: … (dóchúlacht: ard, tionchar: mór)
- Riosca 2: … (dóchúlacht: íseal, tionchar: mór)
- Blocálaí: … — cabhair ag teastáil ó …

---

# Cinntí agus gníomhartha

- Cinneadh ag teastáil: …
- Gníomh: … (úinéir, dáta)
- Gníomh: … (úinéir, dáta)
