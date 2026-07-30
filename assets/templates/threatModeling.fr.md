---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Séance de modélisation des menaces
language: fr
---

<!-- _class: title -->

# Séance de modélisation des menaces
## Système · Date · Facilitateur · Participants

---

# Portée et objectif

- Quel système ou composant modélisons-nous aujourd’hui ?
- Ce qui est explicitement hors de portée : …
- Hypothèses avec lesquelles nous travaillons : …
- Résultat : menaces pondérées avec atténuations et propriétaire

---

<!-- _class: table table-editable -->

# Cartographie du système

| Élément | Genre | Remarques |
| --- | --- | --- |
| … | Composant | … |
| … | Flux de données | … |
| … | Partie externe | … |

---

# Limites de confiance

- Où les données passent-elles de fiables à non fiables ?
- Quelles frontières voyons-nous : réseau, processus, utilisateur, chaîne d’approvisionnement ?
- Où se déroulent l’authentification et la validation des entrées ?
- Dessinez chaque limite sur l’esquisse du système : …

---

<!-- _class: table -->

# Référence STRIDE

| Catégorie | Signification |
| --- | --- |
| Usurpation | Faire semblant d'être un autre utilisateur ou un autre service |
| Falsification | Modification non autorisée de données ou de code |
| Répudiation | Nier qu'une action ait jamais eu lieu |
| Divulgation d'informations | Informations atteignant ceux qui ne sont pas autorisés à les voir |
| Déni de service | Rendre le système inutilisable ou inaccessible |
| Élévation de privilège | Obtenir plus de privilèges que ceux accordés |

---

<!-- _class: table table-editable -->

# Collecte des menaces

| Menace | Catégorie FOULÉE | Composant | Risque |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Priorisation : probabilité × impact

- Probabilité : quelle est la probabilité d'abus (faible, moyenne, élevée) ?
- Impact : combien de dégâts si cela se produit ?
- Risque = probabilité × impact ; le haut-le-haut passe en premier
- En cas de doute : choisissez l'estimation la plus élevée et notez pourquoi

---

<!-- _class: table table-editable -->

# Atténuations et actions

| Atténuation | Propriétaire | Statut |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Ce que nous acceptons sciemment

- À quelles menaces ne nous attaquons-nous délibérément pas : …
- Pourquoi est-ce justifié (probabilité, coût, contexte) : …
- À qui appartient cette décision : rôle
- Quand reviendrons-nous sur cela : …

---

# Séance terminée
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Périmètre et hypothèses retenues
- [ ] Composants, flux de données et parties externes cartographiés
- [ ] Des limites de confiance tracées
- [ ] Les six catégories STRIDE parcourues
- [ ] Menaces classées par probabilité × impact
- [ ] Atténuations attribuées à un propriétaire
- [ ] Risques acceptés enregistrés et détenus
