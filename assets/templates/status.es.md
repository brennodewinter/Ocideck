---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Briefing de estado
language: es
---

<!-- _class: title -->

# Briefing de estado

---

# Resumen de estado

- Estado general: según lo previsto / necesita atención / crítico
- Desarrollo clave desde el informe anterior: …
- Perspectiva para el próximo periodo: …

---

<!-- _class: cockpit -->

# Panel de estado

```cockpit
{
  "layout": "auto",
  "animateOnEnter": true,
  "meters": [
    {
      "type": "speedometer",
      "label": "Uso de presupuesto",
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
      "label": "Nivel de riesgo",
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
      "label": "Confianza en el cronograma",
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
      "label": "Tendencia de elementos abiertos",
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

# Progreso por línea de trabajo

| Línea de trabajo | Estado | Explicación |
| --- | --- | --- |
| Línea A | 🟢 Según lo previsto | Procede según lo planificado |
| Línea B | 🟠 Atención | A la espera de decisión |
| Línea C | 🔴 Crítico | Falta de capacidad |

---

# Riesgos y bloqueos

- Riesgo 1: … (probabilidad: alta, impacto: mayor)
- Riesgo 2: … (probabilidad: baja, impacto: mayor)
- Bloqueo: … — ayuda necesaria de …

---

# Decisiones y acciones

- Decisión necesaria: …
- Acción: … (responsable, fecha)
- Acción: … (responsable, fecha)
