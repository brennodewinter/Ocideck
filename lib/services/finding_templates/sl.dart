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

/// De meegeleverde finding-sjablonen in het Sloveens (sl).
const Map<String, String> findingTemplatesSl = {
  'sql-injection': '''
---
title: Vrivanje SQL
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Uporabnikov vnos se vključi v poizvedbo SQL brez ustrezne parametrizacije, kar
napadalcu omogoča spremembo logike poizvedbe.

## Confirmation (reproduction)

Pošljite prirejeno vrednost v prizadetem parametru in ugotovite, da aplikacija
vrne podatke zunaj predvidene množice rezultatov.

## Possible impact

Napadalec lahko bere, spreminja ali briše podatke v zbirki in glede na njeno
nastavitev pridobi nadaljnji dostop do gostitelja.

## Recommendation

Za ves dostop do zbirke uporabljajte parametrizirane poizvedbe (pripravljene
izjave) in vnos preverjajte s seznamom dovoljenih. Uporabljajte račune zbirke z
najmanjšimi pravicami.
''',
  'reflected-xss': '''
---
title: Odbito cross-site scripting (XSS)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Uporabnikov vnos se odraža v odgovoru brez ustreznega kodiranja izhoda, zato
lahko napadalec vrine skript, ki se izvede v brskalniku žrtve.

## Confirmation (reproduction)

Vnesite koristni tovor v prizadeti parameter in opazujte njegovo izvajanje na
izrisani strani.

## Possible impact

Ugrabitev seje, kraja poverilnic in dejanja, izvedena v imenu žrtve znotraj
aplikacije.

## Recommendation

Kontekstno občutljivo kodiranje izhoda vseh podatkov pod nadzorom uporabnika,
stroga Content Security Policy in samodejno ubežanje v ogrodju.
''',
  'weak-password-policy': '''
---
title: Šibka politika gesel
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Aplikacija sprejema šibka gesla (kratka, pogosta ali brez zahtev po
zapletenosti), zaradi česar je račune lažje uganiti.

## Confirmation (reproduction)

Registrirajte ali spremenite geslo na kratko, pogosto vrednost in ugotovite, da
je sprejeto.

## Possible impact

Večja verjetnost prevzema računa z napadi s surovo silo ali credential stuffing.

## Recommendation

Uveljavite najmanjšo dolžino, preverjajte s seznami razkritih gesel in podprite
večfaktorsko preverjanje pristnosti.
''',
};
