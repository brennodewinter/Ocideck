---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Vue d’ensemble du processus SIPOC
language: fr
---

<!-- _class: title -->

# Vue d’ensemble du processus SIPOC
## Fournisseur · Entrée · Processus · Sortie · Client

---

<!-- skip -->

# Voici comment vous travaillez avec ce modèle

- Utilisez SIPOC pour comprendre la portée et les dépendances d'un processus, et non pour enregistrer chaque action.
- Utilisez l'aide et la ligne d'exemple comme liste de contrôle ; entrez vos réponses dans **Limites du processus** et dans la matrice **SIPOC** vide.
- Travaillez de préférence du client au fournisseur, avec des noms pour les entrées et les sorties et des verbes pour les étapes du processus.
- Seules les diapositives étiquetées **Ignorées** seront exclues de la présentation et de l'exportation. Activez ou désactivez **Ignorer** pour obtenir des explications dont votre public peut avoir besoin ou non.

---

# Que cartographie le SIPOC ?

- **Fournisseur :** fournit les informations ou les ressources dont le processus a besoin.
- **Entrée :** données, matériaux ou autres conditions requises par le processus.
- **Processus :** 4 à 7 activités de haut niveau qui transforment l'entrée.
- **Sortie :** le produit, le service ou les informations produites par le processus.
- **Client :** le destinataire interne ou externe de la sortie.

---

<!-- _class: table table-editable -->

# Définir les limites du processus

| Limite | Valeur |
| --- | --- |
| Nom du processus |  |
| Point de départ |  |
| Point final |  |

---

<!-- skip -->

# Liste de contrôle — Quand les limites sont-elles suffisamment claires ?

- **Processus :** donnez-lui un nom reconnaissable avec un verbe et un sujet, par exemple « Enregistrer la commande ».
- **Point de départ :** Nommez un événement observable, par exemple « Demande reçue ».
- **Point final :** nommez un résultat démontrable, par exemple « Confirmation de commande envoyée ».
- Choisissez des limites autour desquelles l’équipe peut conclure des accords significatifs.
- Déplacer les exceptions et les processus adjacents en dehors de la matrice ; notez-les séparément.

---

<!-- skip -->

# Liste de contrôle — Compléter de droite à gauche

1. Définissez des points de début et de fin clairs pour le processus.
2. Nommez les clients qui dépendent du résultat.
3. Décrivez les résultats qu’ils reçoivent.
4. Résumez le processus en 4 à 7 activités de haut niveau.
5. Déterminez les intrants dont ces activités ont besoin.
6. Liez chaque entrée au fournisseur qui la met à disposition.

---

<!-- skip -->
<!-- _class: table -->

# Liste de contrôle — Exemple d'une ligne connectée

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
| Vente | Demande approuvée | Vérifier la commande → s'inscrire → confirmer | Confirmation de commande | Demandeur |

- Lisez la ligne comme une seule chaîne : le fournisseur fournit une entrée, le processus la transforme en sortie pour le client.
- Ajoutez une nouvelle ligne uniquement si la chaîne est significativement différente.
- Vérifiez auprès des personnes impliquées pour vous assurer qu’aucun fournisseur, intrant, produit ou client important ne manque.

---

<!-- _class: matrix -->
<!-- ocideck_template: sipoc -->

# SIPOC

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |

---

<!-- _class: table table-editable -->

# SIPOC ou un organigramme détaillé ?

| Caractéristiques | SIPOC | Organigramme détaillé |
| --- | --- | --- |
| But | Définir la portée et les relations | Documenter le travail et les décisions |
| Détail | 4 à 7 activités de haut niveau | Peut contenir des dizaines d'étapes |
| Se concentrer | Fournisseurs, intrants, extrants et clients | Séquence, transferts et points de décision |
| Utiliser | Début d’un effort d’amélioration | Exécution et analyse des défauts |
