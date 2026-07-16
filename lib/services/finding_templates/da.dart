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

/// De meegeleverde finding-sjablonen in het Deens (da).
const Map<String, String> findingTemplatesDa = {
  'sql-injection': '''
---
title: SQL-injektion
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Brugerinput indsættes i en SQL-forespørgsel uden korrekt parametrisering, så en
angriber kan ændre forespørgslens logik.

## Confirmation (reproduction)

Indsend en manipuleret værdi i den berørte parameter, og konstatér at
applikationen returnerer data uden for det tilsigtede resultatsæt.

## Possible impact

En angriber kan læse, ændre eller slette data i databasen og kan afhængigt af
databasekonfigurationen opnå yderligere adgang til værten.

## Recommendation

Brug parametriserede forespørgsler (prepared statements) til al databaseadgang,
og validér input mod en tilladelsesliste. Anvend databasekonti med færrest mulige
rettigheder.
''',
  'reflected-xss': '''
---
title: Reflekteret cross-site scripting (XSS)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Brugerinput gengives i svaret uden korrekt outputkodning, så en angriber kan
indsætte script, der kører i offerets browser.

## Confirmation (reproduction)

Angiv en payload i den berørte parameter, og observér at den udføres på den
gengivne side.

## Possible impact

Sessionskapring, tyveri af legitimationsoplysninger og handlinger udført på
offerets vegne i applikationen.

## Recommendation

Kontekstbevidst outputkodning af alle brugerstyrede data, en streng Content
Security Policy og automatisk escaping i frameworket.
''',
  'weak-password-policy': '''
---
title: Svag adgangskodepolitik
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Applikationen accepterer svage adgangskoder (korte, almindelige eller uden
kompleksitetskrav), hvilket gør konti lettere at gætte.

## Confirmation (reproduction)

Opret eller skift en adgangskode til en kort, almindelig værdi, og konstatér at
den accepteres.

## Possible impact

Øget risiko for kontoovertagelse gennem brute force- eller
credential stuffing-angreb.

## Recommendation

Håndhæv en minimumslængde, kontrollér mod lister over lækkede adgangskoder, og
understøt multifaktorgodkendelse.
''',
};
