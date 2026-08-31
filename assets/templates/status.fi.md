---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Tilannetiedotus
language: fi
---

<!-- _class: title -->

# Tilannetiedotus

---

# Yhteenveto tilasta

- Kokonaistila: raiteilla / vaatii huomiota / kriittinen
- Keskeinen kehitys edellisen tiedotustilaisuuden jälkeen:…
- Näkymät tulevalle kaudelle:…

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
      "label": "Budjetin käyttö",
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
      "label": "Riskitaso",
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
      "label": "Luottamus aikatauluun",
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
      "label": "Avoimien kohtien suuntaus",
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

# Edistyminen työvirtaa kohti

| Työvirta | Tila | Selitys |
| --- | --- | --- |
| Työvirta A | 🟢 Reitillä | Jatketaan suunnitelmien mukaan |
| Työvirta B | 🟠 Huomio | Päätöstä odotellessa |
| Työvirta C | 🔴 Kriittinen | Kapasiteetin puute |

---

# Riskit ja estoaineet

- Riski 1: … (todennäköisyys: suuri, vaikutus: suuri)
- Riski 2: … (todennäköisyys: pieni, vaikutus: suuri)
- Esto: … — apua tarvitaan…

---

# Päätökset ja teot

- Tarvittava päätös:…
- Toimi: … (omistaja, päivämäärä)
- Toimi: … (omistaja, päivämäärä)
