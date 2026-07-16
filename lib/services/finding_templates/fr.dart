// GEGENEREERD noch handwerk-vrij: de proza hieronder is vertaald, de rest is
// vastgezet. Zie PENTEST_MIAUW §12.1/§12.3 en
// test/finding_template_languages_test.dart.
//
// Wat NIET vertaald mag worden, en waarom:
//  - de `## …`-koppen zijn parse-ankers van FindingSpec; vertaal je ze, dan
//    komt de sectie leeg terug bij het invoegen;
//  - `cwe:` is een MITRE-citaat en `severity:` het door FIRST gepubliceerde
//    bandlabel dat een bevinding zélf ook opslaat;
//  - `cvss_vector`/`cvss_version` zijn tokens, `references` zijn URL's.
//
// Vertaald is wat van ons is: de titel (die de kop van de bevinding wordt) en
// de vier prozasecties — een skelet dat de tester per opdracht aanscherpt.

/// De meegeleverde finding-sjablonen in het Frans (fr).
const Map<String, String> findingTemplatesFr = {
  'sql-injection': '''
---
title: Injection SQL
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Les données saisies par l'utilisateur sont intégrées à une requête SQL sans
paramétrage approprié, ce qui permet à un attaquant d'en modifier la logique.

## Confirmation (reproduction)

Soumettez une valeur forgée dans le paramètre concerné et constatez que
l'application renvoie des données hors de l'ensemble de résultats prévu.

## Possible impact

Un attaquant peut lire, modifier ou supprimer des données dans la base et, selon
la configuration de celle-ci, obtenir un accès plus étendu à l'hôte.

## Recommendation

Utilisez des requêtes paramétrées (requêtes préparées) pour tout accès à la base
et validez les entrées au moyen d'une liste d'autorisation. Utilisez des comptes
de base de données à privilèges minimaux.
''',
  'reflected-xss': '''
---
title: Cross-site scripting (XSS) réfléchi
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Les données saisies par l'utilisateur sont renvoyées dans la réponse sans encodage
de sortie approprié, ce qui permet à un attaquant d'injecter un script exécuté
dans le navigateur de la victime.

## Confirmation (reproduction)

Fournissez une charge utile dans le paramètre concerné et observez son exécution
dans la page rendue.

## Possible impact

Détournement de session, vol d'identifiants et actions effectuées au nom de la
victime au sein de l'application.

## Recommendation

Encodage de sortie adapté au contexte pour toutes les données contrôlées par
l'utilisateur, une Content Security Policy stricte et l'échappement automatique du
framework.
''',
  'weak-password-policy': '''
---
title: Politique de mots de passe faible
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

L'application accepte des mots de passe faibles (courts, courants ou sans
exigence de complexité), ce qui rend les comptes plus faciles à deviner.

## Confirmation (reproduction)

Enregistrez ou modifiez un mot de passe avec une valeur courte et courante et
constatez qu'elle est acceptée.

## Possible impact

Probabilité accrue de prise de contrôle de comptes par des attaques par force
brute ou par bourrage d'identifiants.

## Recommendation

Imposez une longueur minimale, effectuez un contrôle par rapport aux listes de
mots de passe compromis et prenez en charge l'authentification multifacteur.
''',
};
