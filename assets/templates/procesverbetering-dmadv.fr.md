---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: "Amélioration des processus : projet DMADV"
language: fr
ocideck_improvement_framework: dmadv
---

<!-- _class: title -->

# Amélioration des processus : projet DMADV

---

<!-- skip -->

# Voici comment vous travaillez avec ce modèle

- Utilisez DMADV pour un processus nouveau ou fondamentalement repensé et choisissez un résultat client mesurable (**Y-01**).
- Utilisez les questions de chaque diapositive du guide comme liste de contrôle ; puis ajoutez des diapositives régulières pour vos réponses.
- Remplacez l'explication de la charte et de l'arborescence CTQ par les informations de votre projet, complétez le SIPOC et rendez les exigences testables avant de concevoir.
- Les diapositives d'aide ne sont ni présentées ni exportées. Si vous souhaitez en afficher une, désactivez **Ignorer** pour cette diapositive.

---

<!-- _class: section -->

# Définir

---

<!-- skip -->

# Liste de contrôle — Qu'enregistrez-vous lors de la définition ?

- Quel client ou utilisateur a quel besoin non satisfait ?
- Pourquoi une nouvelle conception est-elle nécessaire et pourquoi l’amélioration du processus existant ne suffit-elle pas ?
- Quel résultat la conception doit-elle produire (**Y-01**) et dans quelle portée ?
- Qui décide des exigences, des choix de conception et de la version ?
- Quels sont les critères de planification, de conditions préalables et de réussite ?

---

<!-- _class: canvas -->
<!-- ocideck_template: charter -->

# Charte de projet

## Problème ou opportunité

Décrivez le besoin non satisfait, le groupe cible et la raison démontrable.

## Objectif

Formulez le résultat souhaité de manière mesurable et limitée dans le temps.

## Portée

Notez le point de départ, le point final, les points de contact et ce qui ne fait pas partie de la conception.

## Équipe

Nommer le client, le propriétaire de la conception, les utilisateurs et les experts requis.

## Chronologie

Enregistrez les jalons, les portes de décision et le déploiement prévu.

## Critères de réussite
Quand la conception répond-elle manifestement aux besoins du client ?

---

<!-- _class: tree -->
<!-- ocideck_template: ctq-tree -->
<!-- ocideck_layout: tree -->

# Exigences clients mesurables (arbre CTQ)

- De quel résultat le client a-t-il besoin ? — **Y-01**
  - Traduire ce besoin en exigence mesurable 1
  - Traduire ce besoin en exigence mesurable 2

---

<!-- skip -->

# Liste de contrôle — Comment remplir le SIPOC ?

- Commencez par le **Client** : qui utilise le nouveau résultat du processus ?
- Identifiez ensuite la **Sortie** requise et les 4 à 7 étapes du **Processus** prévues.
- Notez l'**Entrée** requise et le **Fournisseur** qui rend chaque entrée disponible.
- Gardez un aperçu général ; les détails de conception suivront plus tard.
- Vérifiez si les limites sélectionnées correspondent à la charte et à Y-01.

---

<!-- _class: matrix -->
<!-- ocideck_template: sipoc -->

# SIPOC

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |
|  |  |  |  |  |

---

<!-- _class: section -->

# Mesurer

---

<!-- skip -->

# Liste de contrôle — Que enregistrez-vous lorsque vous mesurez ?

- Quels besoins des clients ont été traduits en exigences et priorités mesurables ?
- Que sont la valeur cible, la limite inférieure ou supérieure, l'unité et la méthode de mesure de l'Y-01 ?
- Quels cas d'utilisation, volumes et exceptions la conception doit-elle être capable de gérer ?
- Quelles réalisations ou alternatives existantes utilisez-vous comme référence ?
- Comment testerez-vous objectivement si chaque exigence a été remplie ?

---

<!-- _class: section -->

# Analyser

---

<!-- skip -->

# Liste de contrôle — Qu'enregistrez-vous lors de l'analyse ?

- Quelles fonctions le processus doit-il remplir pour répondre aux exigences ?
- Quelles relations et compromis existent entre les souhaits des clients, les risques et les caractéristiques de conception ?
- Quelles hypothèses doivent encore être explorées ou testées ?
- Quels modes de défaillance et dépendances sont les plus importants ?
- À quels critères de conception minimaux chaque solution doit-elle répondre ?

---

<!-- _class: section -->

# Conception

---

<!-- skip -->

# Liste de contrôle — Qu'enregistrez-vous dans Design ?

- Quelles variantes de conception ont été envisagées et sur quels critères ont-elles été comparées ?
- À quoi ressemble le flux de processus choisi, y compris les rôles, les systèmes et les transferts ?
- Comment la conception prévient-elle ou contrôle-t-elle les principaux modes de défaillance ?
- Qu’enseigne un prototype ou un test sur le fonctionnement et la facilité d’utilisation ?
- Quelle variante va à la vérification, avec quels points ouverts ?

---

<!-- _class: section -->

# Vérifier

---

<!-- skip -->

# Liste de contrôle — Que enregistrez-vous lors de la vérification ?

- Quel test prouve pour chaque exigence que la conception fonctionne dans des conditions réalistes ?
- Quels résultats ont été obtenus et quels écarts subsistent ?
- Que pensent les utilisateurs et les propriétaires de processus du fonctionnement et de la faisabilité ?
- Quels contrôles, instructions et mesures sont nécessaires après la mise en service ?
- Qui publie le design et sur la base de quelles preuves ?
