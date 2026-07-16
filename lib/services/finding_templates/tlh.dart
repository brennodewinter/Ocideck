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

/// De meegeleverde finding-sjablonen in het Klingon (tlh).
const Map<String, String> findingTemplatesTlh = {
  'sql-injection': '''
---
title: SQL ghomHa'moH
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

SQL nej ghojmoHwI' De' lo'lu', 'ach parameter lo'be'lu'. vaj nej meq choHlaH
qoHchoHwI'.

## Confirmation (reproduction)

parameter Daq De' val yIlab, 'ej De' Sovbe'bogh nobbogh app yIlegh.

## Possible impact

De'wI' De' laDlaH, choHlaH, QawlaH je qoHchoHwI'; De'wI' ngoq wIvDaq, nIteb nIH
DachlaH.

## Recommendation

parameter lo'bogh nej (prepared statement) yIlo' Hoch De'wI' Daq; chuvmey chIm
tlhoy' yIlo'. De'wI' quv puS ghaj lo'wI' yIlo'.
''',
  'reflected-xss': '''
---
title: XSS cha'logh (reflected)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

ghojmoHwI' De' HIvje'Daq cha'lu', 'ach mIw'a' ghItlhbe'lu'. vaj qoHchoHwI' De'wI'
QeD lo'laH, 'ej vIttlhegh vumtaH loQ browser.

## Confirmation (reproduction)

parameter Daq payload yIlab, 'ej nav cha'lu'bogh vumtaH yIlegh.

## Possible impact

session nIH, ngoq nIH, 'ej vIttlhegh pong lo' vum app.

## Recommendation

Hoch ghojmoHwI' De' ghItlh 'e' yIchel; Content Security Policy pup yIlo'; framework
escaping yIchu'.
''',
  'weak-password-policy': '''
---
title: mIw ngoq puj
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

ngoq puj lajlaH app (run, motlh, pagh Qatlh). vaj lo'wI' Daq ngeD nIH.

## Confirmation (reproduction)

ngoq run motlh yIqon oder yIchoH, 'ej lajlu' yIlegh.

## Possible impact

lo'wI' Daq nIH ngeD; brute force credential stuffing je lo'laH qoHchoHwI'.

## Recommendation

'ar tIQ yIpoQ; ngoq lujpu'bogh tetlh yIlegh; cha' mIw Sov (MFA) yIchel.
''',
};
