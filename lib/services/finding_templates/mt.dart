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

/// De meegeleverde finding-sjablonen in het Maltees (mt).
const Map<String, String> findingTemplatesMt = {
  'sql-injection': '''
---
title: Injezzjoni SQL
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

L-input tal-utent jiddaħħal f'mistoqsija SQL mingħajr parametrizzazzjoni xierqa,
u b'hekk attakkant jista' jbiddel il-loġika tal-mistoqsija.

## Confirmation (reproduction)

Ibgħat valur ippreparat fil-parametru kkonċernat u kkonferma li l-applikazzjoni
tirritorna dejta barra mis-sett ta' riżultati maħsub.

## Possible impact

Attakkant jista' jaqra, ibiddel jew iħassar dejta fid-database u, skont
il-konfigurazzjoni tagħha, jikseb aċċess ulterjuri għall-host.

## Recommendation

Uża mistoqsijiet parametrizzati (prepared statements) għal kull aċċess
għad-database u vvalida l-input kontra lista ta' permessi. Uża kontijiet
tad-database bl-inqas privileġġi.
''',
  'reflected-xss': '''
---
title: Cross-site scripting (XSS) rifless
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

L-input tal-utent jiġi rifless fir-rispons mingħajr kodifikazzjoni tal-output
xierqa, u b'hekk attakkant jista' jinjetta script li jaħdem fil-browser
tal-vittma.

## Confirmation (reproduction)

Ipprovdi payload fil-parametru kkonċernat u osserva li jitħaddem fil-paġna
renderjata.

## Possible impact

Ħtif tas-sessjoni, serq ta' kredenzjali u azzjonijiet imwettqa f'isem il-vittma
fl-applikazzjoni.

## Recommendation

Kodifikazzjoni tal-output skont il-kuntest għad-dejta kollha kkontrollata
mill-utent, Content Security Policy stretta u escaping awtomatiku tal-framework.
''',
  'weak-password-policy': '''
---
title: Politika dgħajfa tal-passwords
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

L-applikazzjoni taċċetta passwords dgħajfa (qosra, komuni jew mingħajr rekwiżiti
ta' kumplessità), li jagħmel il-kontijiet aktar faċli biex jinqatgħu.

## Confirmation (reproduction)

Irreġistra jew ibdel password għal valur qasir u komuni u kkonferma li jiġi
aċċettat.

## Possible impact

Probabbiltà akbar ta' teħid ta' kontijiet permezz ta' attakki brute-force jew
credential stuffing.

## Recommendation

Infurza tul minimu, iċċekkja kontra listi ta' passwords miksura u appoġġja
l-awtentikazzjoni b'diversi fatturi.
''',
};
