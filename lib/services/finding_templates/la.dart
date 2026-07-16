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

/// De meegeleverde finding-sjablonen in het Latijn (la).
const Map<String, String> findingTemplatesLa = {
  'sql-injection': '''
---
title: Iniectio SQL
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Input usoris in interrogationem SQL sine debita parametrisatione inseritur, unde
oppugnator logicam interrogationis mutare potest.

## Confirmation (reproduction)

Mitte valorem fictum in parametro affecto et animadverte applicationem data extra
copiam eventuum intentam reddere.

## Possible impact

Oppugnator data in basi datorum legere, mutare vel delere potest et, pro
configuratione basis, ulteriorem aditum ad hospitem consequi.

## Recommendation

Utere interrogationibus parametrisatis (praeparatis) ad omnem aditum basis datorum
et input contra indicem permissorum proba. Adhibe rationes basis datorum minimis
iuribus.
''',
  'reflected-xss': '''
---
title: Cross-site scripting (XSS) reflexum
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Input usoris in responso sine debita codificatione exitus refertur, unde oppugnator
scriptum inicere potest quod in navigatro victimae exsequitur.

## Confirmation (reproduction)

Praebe onus in parametro affecto et observa illud in pagina reddita exsequi.

## Possible impact

Sessionis interceptio, furtum credentialium et actiones nomine victimae intra
applicationem factae.

## Recommendation

Codificatio exitus contextui apta omnium datorum ab usore rectorum, Content Security
Policy stricta et automatica effugatio a compage.
''',
  'weak-password-policy': '''
---
title: Ratio tesserarum infirma
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Applicatio tesseras infirmas accipit (breves, usitatas vel sine postulatis
complexitatis), unde rationes facilius divinantur.

## Confirmation (reproduction)

Inscribe vel muta tesseram in valorem brevem et usitatum et animadverte eam accipi.

## Possible impact

Maior probabilitas rationis occupandae per impetus vi brutali vel credential
stuffing.

## Recommendation

Impone longitudinem minimam, contra indices tesserarum divulgatarum proba et
authenticationem multifactorialem sustine.
''',
};
