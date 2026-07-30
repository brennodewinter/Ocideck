---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Briefing sur l'état
language: fr
---

<!-- _class: title -->

# Briefing sur l'état

---

# Résumé de l'état

- Statut général : en bonne voie / nécessite une attention particulière / critique
- Développement clé depuis le briefing précédent : …
- Perspectives pour la période à venir : …

---

<!-- _class: cockpit -->

# Tableau de bord d'état

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

# Progrès par domaine de travail

| Flux de travail | Statut | Explication |
| --- | --- | --- |
| Axe de travail A | 🟢 En bonne voie | Procéder comme prévu |
| Axe de travail B | 🟠Attention | En attente de décision |
| Domaine de travail C | 🔴 Critique | Manque de capacité |

---

# Risques et bloqueurs

- Risque 1 : … (probabilité : élevée, impact : majeur)
- Risque 2 : … (probabilité : faible, impact : majeur)
- Bloqueur : … — aide nécessaire de la part de…

---

# Décisions et actions

- Décision nécessaire : …
- Action : … (propriétaire, date)
- Action : … (propriétaire, date)
