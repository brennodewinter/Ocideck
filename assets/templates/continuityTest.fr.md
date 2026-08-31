---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Continuité d'activité / test DR
language: fr
---

<!-- _class: title -->

# Continuité d'activité / test DR

---

# Scénario de test

- Scénario : … (par exemple, panne du centre de données, ransomware)
- Hypothèse préalable : …
- Type de test : sur table / partiel / complet

---

# Objectifs et critères de réussite

- Objectif du test : …
- Critère de réussite 1 : …
- Critère de réussite 2 : …

---

<!-- _class: table table-editable -->

# Processus critiques

| Processus | Priorité | Cela dépend |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# Aperçu des RTO/RPO

| Processus ou système | RTO | RPO | Rencontré ? |
| --- | --- | --- | --- |
| … | … | … | Oui/non |
| … | … | … | … |

---

<!-- _class: timeline -->

# Chronologie des tests

- T+0 :: Début du test :: Scénario annoncé.
- T+… : Failover démarré
- T+… :: Récupération vérifiée
- T+… :: Fin du test

---

<!-- _class: table table-editable -->

# Résultats

| Trouver | Gravité | Composant |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Déviations et bloqueurs

- Écart par rapport au playbook : …
- Bloqueur lors du test : …
- Solution de contournement utilisée : …

---

# Points d'amélioration
<!-- ocideck_list_style: checklist -->

- [ ] Mise à jour du playbook sur le point : …
- [ ] Ajuster la configuration technique : …
- [ ] Programmer un entraînement ou un exercice : …

---

# Capacité de récupération Go/No-Go
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Processus critiques récupérés au sein de RTO
- [ ] La perte de données est restée dans les limites du RPO
- [ ] Le Playbook s'est avéré utilisable
- [ ] Verdict : capacité de récupération démontrée
