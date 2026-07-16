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

/// De meegeleverde finding-sjablonen in het Fries (fy).
const Map<String, String> findingTemplatesFy = {
  'sql-injection': '''
---
title: SQL-ynjeksje
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Ynfier fan de brûker wurdt sûnder deugdlike parameterisaasje yn in SQL-query
opnommen, wêrtroch't in oanfaller de logika fan de query feroarje kin.

## Confirmation (reproduction)

Tsjin in preparearre wearde yn fia de belutsen parameter en stel fêst dat de
aplikaasje gegevens werombringt bûten de bedoelde resultaatferzameling.

## Possible impact

In oanfaller kin gegevens yn de database lêze, feroarje of wiskje en kin,
ôfhinklik fan de databasekonfiguraasje, fierdere tagong ta de host krije.

## Recommendation

Brûk parameterisearre query's (prepared statements) foar alle databasetagong en
validearje ynfier tsjin in tastiene list. Wurkje mei database-akkounts mei minimale
rjochten.
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

Ynfier fan de brûker wurdt sûnder deugdlike útfierkodearring yn de respons
wjerspegele, wêrtroch't in oanfaller skript ynjektearje kin dat yn de browser fan
it slachtoffer draait.

## Confirmation (reproduction)

Fier in payload yn fia de belutsen parameter en stel fêst dat dizze útfierd wurdt
yn de renderde side.

## Possible impact

Oername fan de sesje, stellerij fan oanmeldgegevens en hannelingen dy't út namme
fan it slachtoffer yn de aplikaasje ferrjochte wurde.

## Recommendation

Kontekstbewuste útfierkodearring fan alle troch de brûker bepaalde gegevens, in
strang Content Security Policy en automatyske escaping troch it framework.
''',
  'weak-password-policy': '''
---
title: Swak wachtwurdbelied
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

De aplikaasje akseptearret swakke wachtwurden (koart, faak foarkommend of sûnder
kompleksiteitseasken), wêrtroch't akkounts makliker te rieden binne.

## Confirmation (reproduction)

Registrearje of feroarje in wachtwurd nei in koarte, faak foarkommende wearde en
stel fêst dat dizze akseptearre wurdt.

## Possible impact

Gruttere kâns op akkountoername troch brute-force- of
credential-stuffing-oanfallen.

## Recommendation

Twing in minimale lingte ôf, toets tsjin listen mei lekte wachtwurden en stypje
meardere-faktor-autentikaasje.
''',
};
