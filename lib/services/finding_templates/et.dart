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

/// De meegeleverde finding-sjablonen in het Ests (et).
const Map<String, String> findingTemplatesEt = {
  'sql-injection': '''
---
title: SQL-süst
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Kasutaja sisend lisatakse SQL-päringusse ilma nõuetekohase parameetristamiseta,
võimaldades ründajal muuta päringu loogikat.

## Confirmation (reproduction)

Esitage mõjutatud parameetris ettevalmistatud väärtus ja tuvastage, et rakendus
tagastab andmeid väljaspool ettenähtud tulemuste hulka.

## Possible impact

Ründaja saab andmebaasis andmeid lugeda, muuta või kustutada ning olenevalt
andmebaasi seadistusest saada hostile edasise juurdepääsu.

## Recommendation

Kasutage kogu andmebaasipöörduse jaoks parameetristatud päringuid (prepared
statements) ja valideerige sisend lubatute loendi alusel. Kasutage minimaalsete
õigustega andmebaasikontosid.
''',
  'reflected-xss': '''
---
title: Peegeldatud cross-site scripting (XSS)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Kasutaja sisend peegeldub vastuses ilma nõuetekohase väljundikodeerimiseta, mistõttu
saab ründaja sisestada skripti, mis käivitub ohvri brauseris.

## Confirmation (reproduction)

Sisestage mõjutatud parameetrisse kasulik koormus ja jälgige selle käivitumist
renderdatud lehel.

## Possible impact

Seansi kaaperdamine, mandaatide vargus ja ohvri nimel rakenduses tehtud toimingud.

## Recommendation

Kontekstiteadlik väljundikodeerimine kõigi kasutaja juhitavate andmete jaoks, range
Content Security Policy ja raamistiku automaatne varjestamine.
''',
  'weak-password-policy': '''
---
title: Nõrk paroolipoliitika
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Rakendus aktsepteerib nõrku paroole (lühikesed, levinud või ilma
keerukusnõueteta), mistõttu on kontosid lihtsam ära arvata.

## Confirmation (reproduction)

Registreerige või muutke parool lühikeseks, levinud väärtuseks ja tuvastage, et
see aktsepteeritakse.

## Possible impact

Suurem tõenäosus konto ülevõtmiseks jõuründe või credential stuffing'u kaudu.

## Recommendation

Nõudke minimaalset pikkust, kontrollige lekkinud paroolide loendite vastu ja
toetage mitmeastmelist autentimist.
''',
};
