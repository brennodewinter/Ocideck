---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Resumo de status
language: pt
---

<!-- _class: title -->

# Resumo de status

---

# Resumo do status

- Status geral: no caminho certo/precisa de atenção/crítico
- Principais desenvolvimentos desde o briefing anterior:…
- Perspectivas para o próximo período:…

---

<!-- _class: cockpit -->

# Painel de status

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

# Progresso por fluxo de trabalho

| Fluxo de trabalho | Status | Explicação |
| --- | --- | --- |
| Fluxo de trabalho A | 🟢 No caminho certo | Procedendo conforme planejado |
| Fluxo de trabalho B | 🟠 Atenção | Aguardando decisão |
| Fluxo de trabalho C | 🔴 Crítico | Falta de capacidade |

---

# Riscos e bloqueadores

- Risco 1: … (probabilidade: alta, impacto: grande)
- Risco 2: … (probabilidade: baixa, impacto: grande)
- Bloqueador:… — ajuda necessária de…

---

# Decisões e ações

- Decisão necessária:…
- Ação:… (proprietário, data)
- Ação:… (proprietário, data)
