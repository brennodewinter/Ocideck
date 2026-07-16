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

/// De meegeleverde finding-sjablonen in het Nederlands (nl).
const Map<String, String> findingTemplatesNl = {
  'sql-injection': '''
---
title: SQL-injectie
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Invoer van de gebruiker wordt zonder deugdelijke parameterisatie in een
SQL-query opgenomen, waardoor een aanvaller de logica van de query kan wijzigen.

## Confirmation (reproduction)

Dien een geprepareerde waarde in via de betrokken parameter en constateer dat
de applicatie gegevens teruggeeft buiten de bedoelde resultaatverzameling.

## Possible impact

Een aanvaller kan gegevens in de database lezen, wijzigen of verwijderen en kan,
afhankelijk van de databaseconfiguratie, verdere toegang tot de host verkrijgen.

## Recommendation

Gebruik geparameteriseerde query's (prepared statements) voor alle
databasetoegang en valideer invoer tegen een toegestane lijst. Werk met
database-accounts met minimale rechten.
''',
  'reflected-xss': '''
---
title: Reflected cross-site scripting (XSS)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Invoer van de gebruiker wordt zonder deugdelijke uitvoercodering in de respons
weerspiegeld, waardoor een aanvaller script kan injecteren dat in de browser van
het slachtoffer draait.

## Confirmation (reproduction)

Voer een payload in via de betrokken parameter en constateer dat deze wordt
uitgevoerd in de gerenderde pagina.

## Possible impact

Overname van de sessie, diefstal van inloggegevens en handelingen die namens het
slachtoffer binnen de applicatie worden verricht.

## Recommendation

Contextbewuste uitvoercodering van alle door de gebruiker bepaalde gegevens, een
strikt Content Security Policy en automatische escaping door het framework.
''',
  'weak-password-policy': '''
---
title: Zwak wachtwoordbeleid
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

De applicatie accepteert zwakke wachtwoorden (kort, veelvoorkomend of zonder
complexiteitseisen), waardoor accounts eenvoudiger te raden zijn.

## Confirmation (reproduction)

Registreer of wijzig een wachtwoord naar een korte, veelvoorkomende waarde en
constateer dat deze wordt geaccepteerd.

## Possible impact

Grotere kans op accountovername door brute-force- of
credential-stuffing-aanvallen.

## Recommendation

Dwing een minimale lengte af, toets tegen lijsten met gelekte wachtwoorden en
ondersteun meervoudige authenticatie.
''',
};
