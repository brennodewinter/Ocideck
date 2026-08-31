---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Briefing sullo stato
language: it
---

<!-- _class: title -->

# Briefing sullo stato

---

# Riepilogo dello stato

- Stato generale: in linea/richiede attenzione/critico
- Principali sviluppi rispetto al briefing precedente:...
- Prospettive per il prossimo periodo:...

---

<!-- _class: cockpit -->

# Cruscotto di stato

```cockpit
{
  "layout": "auto",
  "animateOnEnter": true,
  "meters": [
    {
      "type": "speedometer",
      "label": "Consumo del budget",
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
      "label": "Livello di rischio",
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
      "label": "Fiducia nella pianificazione",
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
      "label": "Andamento dei punti aperti",
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

# Progresso per flusso di lavoro

| Flusso di lavoro | Stato | Spiegazione |
| --- | --- | --- |
| Flusso di lavoro A | 🟢 In pista | Procedendo come previsto |
| Flusso di lavoro B | 🟠 Attenzione | In attesa di decisione |
| Flusso di lavoro C | 🔴 Critico | Mancanza di capacità |

---

# Rischi e ostacoli

- Rischio 1: … (probabilità: alta, impatto: grave)
- Rischio 2: … (probabilità: bassa, impatto: grave)
- Bloccante: … – è necessario aiuto da …

---

# Decisioni e azioni

- Decisione necessaria: …
- Azione: … (proprietario, data)
- Azione: … (proprietario, data)
