---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Le point sur le comité de pilotage / comité de projet
language: fr
---

<!-- _class: title -->

# Le point sur le comité de pilotage / comité de projet

---

# Résumé de gestion

- Statut en une phrase : …
- Développement clé : …
- Question clé pour le comité de pilotage : …

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

# Calendrier et jalons

- Q1 :: Jalon 1 :: Atteint.
- Q2 :: Jalon 2 :: En bonne voie.
- Q3 :: Jalon 3 :: Nécessite une attention particulière.

---

<!-- _class: table -->

# Budget et ressources

| Article | Budgétisé | Dépensé | Prévisions |
| --- | --- | --- | --- |
| Budget total | … | … | … |
| Effort d'équipe (ETP) | … | … | … |

---

<!-- _class: table table-editable -->

# Risques et problèmes

| Risque ou problème | Statut | Action |
| --- | --- | --- |
| … | Nouveau / en cours / fermé | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# Décisions demandées

| Décision | Explication | Résultat |
| --- | --- | --- |
| … | … | Approuvé / rejeté / différé |
| … | … | … |

---

<!-- _class: table table-editable -->

# Actions de la dernière fois

| Action | Propriétaire | Statut |
| --- | --- | --- |
| … | … | Terminé / en cours / retardé |
| … | … | … |

---

<!-- _class: table table-editable -->

# Nouvelles actions

| Action | Propriétaire | Date limite |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Escalades

- Escalade : … — demandée au comité directeur : …
- Aucune escalade : confirmer et enregistrer
