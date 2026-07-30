---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Ohjauskomitean/projektin hallituksen päivitys
language: fi
---

<!-- _class: title -->

# Ohjauskomitean/projektin hallituksen päivitys

---

# Johdon yhteenveto

- Status yhdellä lauseella:…
- Keskeinen kehitystyö:…
- Keskeinen kysymys johtokunnalle:…

---

<!-- _class: cockpit -->

# Tilan hallintapaneeli

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
      "value": 55.0
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
      "value": 78.0
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
      "value": 4.0
    }
  ]
}
```

---

<!-- _class: timeline -->

# Aikataulu ja virstanpylväät

- Q1 :: Virstanpylväs 1 :: Saavutettu.
- Q2 :: Milestone 2 :: Raidalla.
- Q3 :: Virstanpylväs 3 :: Vaatii huomiota.

---

<!-- _class: table -->

# Budjetti ja resurssit

| Tuote | Budjetoitu | Käytetty | Ennuste |
| --- | --- | --- | --- |
| Kokonaisbudjetti | … | … | … |
| Ryhmätyö (FTE) | … | … | … |

---

<!-- _class: table table-editable -->

# Riskit ja ongelmat

| Riski tai ongelma | Tila | Toiminta |
| --- | --- | --- |
| … | Uusi / käynnissä / suljettu | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# Pyydetyt päätökset

| Päätös | Selitys | Tulos |
| --- | --- | --- |
| … | … | Hyväksytty / hylätty / lykätty |
| … | … | … |

---

<!-- _class: table table-editable -->

# Toimet viime kerrasta

| Toiminta | Omistaja | Tila |
| --- | --- | --- |
| … | … | Valmis / kesken / myöhässä |
| … | … | … |

---

<!-- _class: table table-editable -->

# Uusia toimia

| Toiminta | Omistaja | Määräaika |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Eskalaatiot

- Eskaloituminen: … – ohjauskomitealta pyydetty: …
- Ei eskalaatioita: vahvista ja tallenna
