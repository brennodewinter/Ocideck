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

/// De meegeleverde finding-sjablonen in het Roemeens (ro).
const Map<String, String> findingTemplatesRo = {
  'sql-injection': '''
---
title: Injecție SQL
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Datele introduse de utilizator sunt incluse într-o interogare SQL fără o
parametrizare corespunzătoare, permițând unui atacator să modifice logica
interogării.

## Confirmation (reproduction)

Trimiteți o valoare special construită în parametrul afectat și constatați că
aplicația returnează date din afara setului de rezultate prevăzut.

## Possible impact

Un atacator poate citi, modifica sau șterge date din baza de date și, în funcție
de configurația acesteia, poate obține acces suplimentar la gazdă.

## Recommendation

Folosiți interogări parametrizate (prepared statements) pentru orice acces la baza
de date și validați datele de intrare cu o listă de permise. Utilizați conturi de
bază de date cu privilegii minime.
''',
  'reflected-xss': '''
---
title: Cross-site scripting (XSS) reflectat
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Datele introduse de utilizator sunt reflectate în răspuns fără o codificare
corespunzătoare a ieșirii, astfel încât un atacator poate injecta script care
rulează în browserul victimei.

## Confirmation (reproduction)

Furnizați un payload în parametrul afectat și observați executarea acestuia în
pagina randată.

## Possible impact

Deturnarea sesiunii, furtul de credențiale și acțiuni efectuate în numele victimei
în cadrul aplicației.

## Recommendation

Codificarea ieșirii în funcție de context pentru toate datele controlate de
utilizator, o Content Security Policy strictă și escaparea automată a
frameworkului.
''',
  'weak-password-policy': '''
---
title: Politică de parole slabă
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Aplicația acceptă parole slabe (scurte, comune sau fără cerințe de complexitate),
ceea ce face conturile mai ușor de ghicit.

## Confirmation (reproduction)

Înregistrați sau schimbați o parolă cu o valoare scurtă, comună și constatați că
este acceptată.

## Possible impact

Probabilitate crescută de preluare a conturilor prin atacuri de forță brută sau
credential stuffing.

## Recommendation

Impuneți o lungime minimă, verificați față de listele de parole compromise și
susțineți autentificarea cu mai mulți factori.
''',
};
