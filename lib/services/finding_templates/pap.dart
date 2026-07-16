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

/// De meegeleverde finding-sjablonen in het Papiaments (pap).
const Map<String, String> findingTemplatesPap = {
  'sql-injection': '''
---
title: Inyekshon SQL
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Input di e usuario ta wòrdu inkluí den un konsulta SQL sin parametrisashon
korekto, loke ta permití un atakante kambia e lógika di e konsulta.

## Confirmation (reproduction)

Manda un balor prepará den e parámetro afektá i konstatá ku e aplikashon ta duna
datos pafó di e konhunto di resultado previsto.

## Possible impact

Un atakante por lesa, kambia òf kita datos den e base di datos i, dependiendo di su
konfigurashon, haña mas akseso na e host.

## Recommendation

Usa konsultanan parametrisá (prepared statements) pa tur akseso na e base di datos
i validá input kontra un lista di permitido. Usa kuentanan di base di datos ku
derechonan mínimo.
''',
  'reflected-xss': '''
---
title: Cross-site scripting (XSS) reflehá
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Input di e usuario ta wòrdu reflehá den e respondi sin kodifikashon di salida
korekto, asina un atakante por inyektá skript ku ta kore den e browser di e
víktima.

## Confirmation (reproduction)

Duna un payload den e parámetro afektá i opservá ku e ta ehekutá den e página
renderisá.

## Possible impact

Sekuestro di seshon, hòrtamentu di kredensial i akshonnan hasí na nòmber di e
víktima den e aplikashon.

## Recommendation

Kodifikashon di salida segun konteksto pa tur dato kontrolá pa e usuario, un Content
Security Policy strikto i escaping outomátiko di e framework.
''',
  'weak-password-policy': '''
---
title: Polítika di kontraseña débil
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

E aplikashon ta aseptá kontraseñanan débil (kòrtiku, komun òf sin rekisito di
kompleksidat), loke ta hasi kuentanan mas fásil pa rei.

## Confirmation (reproduction)

Registrá òf kambia un kontraseña pa un balor kòrtiku i komun i konstatá ku e ta
wòrdu aseptá.

## Possible impact

Mas chèns di tumamentu di kuenta pa medio di atake di fuerza bruta òf credential
stuffing.

## Recommendation

Eksigí un largura mínimo, kontrolá kontra lista di kontraseña lek i sostené
outentikashon multifaktor.
''',
};
