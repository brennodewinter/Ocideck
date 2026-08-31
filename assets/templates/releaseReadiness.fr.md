---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: CAB / préparation à la mise en production
language: fr
---

<!-- _class: title -->

# CAB / préparation à la mise en production

---

# Résumé des modifications

- Ce qui change : …
- Pourquoi maintenant : …
- Demandé par : …

---

# Portée et impact

- Systèmes et services concernés : …
- Utilisateurs concernés : …
- Perturbation attendue : … (durée, timing)

---

<!-- _class: table table-editable -->

# Statut des tests

| Tester | Résultat | Preuve |
| --- | --- | --- |
| Test fonctionnel | Réussi / ouvert | … |
| Test de régression | … | … |
| Test de performances | … | … |

---

# Contrôle de sécurité et de confidentialité
<!-- ocideck_list_style: checklist -->

- [ ] Examen de sécurité effectué
- [ ] Aucune nouvelle donnée personnelle – ou DPIA vérifiée
- [ ] Secrets et droits d'accès vérifiés
- [ ] Analyse de vulnérabilité propre

---

<!-- _class: table table-editable -->

# Plan de mise en œuvre

| Étape | Temps | Qui |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Plan de restauration
<!-- ocideck_list_style: numbered -->

1. Retour arrière possible jusqu'à : …
2. Étapes de retour arrière : …
3. Point de décision go/no-go du retour arrière : …

---

# Plan de communication

- Informer à l'avance : … (qui, quand)
- Lors du changement : …
- Confirmez ensuite : …

---

# Liste de contrôle Go / No Go
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Tests réalisés et approuvés
- [ ] Rollback testé ou plausible
- [ ] Communication préparée
- [ ] Opérations informées et disponibles

---

<!-- _class: table table-editable -->

# Décision du CAB

| Décision | Conditions | Date et heure |
| --- | --- | --- |
| Aller / non-aller / reporté | … | … |
