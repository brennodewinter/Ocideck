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

/// De meegeleverde finding-sjablonen in het Lets (lv).
const Map<String, String> findingTemplatesLv = {
  'sql-injection': '''
---
title: SQL ievainojums
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Lietotāja ievade tiek iekļauta SQL vaicājumā bez pienācīgas parametrizācijas,
ļaujot uzbrucējam mainīt vaicājuma loģiku.

## Confirmation (reproduction)

Nosūtiet sagatavotu vērtību attiecīgajā parametrā un konstatējiet, ka lietotne
atgriež datus ārpus paredzētās rezultātu kopas.

## Possible impact

Uzbrucējs var lasīt, mainīt vai dzēst datus datubāzē un atkarībā no tās
konfigurācijas iegūt plašāku piekļuvi resursdatoram.

## Recommendation

Visai datubāzes piekļuvei izmantojiet parametrizētus vaicājumus (sagatavotos
vaicājumus) un validējiet ievadi pret atļauto sarakstu. Izmantojiet datubāzes
kontus ar minimālām tiesībām.
''',
  'reflected-xss': '''
---
title: Atspoguļots cross-site scripting (XSS)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Lietotāja ievade tiek atspoguļota atbildē bez pienācīgas izvades kodēšanas, tāpēc
uzbrucējs var ievadīt skriptu, kas darbojas upura pārlūkprogrammā.

## Confirmation (reproduction)

Ievadiet lietderīgo slodzi attiecīgajā parametrā un vērojiet tās izpildi
atveidotajā lapā.

## Possible impact

Sesijas nolaupīšana, akreditācijas datu zādzība un darbības, kas veiktas upura
vārdā lietotnē.

## Recommendation

Kontekstam atbilstoša izvades kodēšana visiem lietotāja kontrolētajiem datiem,
stingra Content Security Policy un ietvara automātiskā aizsargāšana.
''',
  'weak-password-policy': '''
---
title: Vāja paroļu politika
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Lietotne pieņem vājas paroles (īsas, izplatītas vai bez sarežģītības prasībām),
padarot kontus vieglāk uzminamus.

## Confirmation (reproduction)

Reģistrējiet vai nomainiet paroli uz īsu, izplatītu vērtību un konstatējiet, ka tā
tiek pieņemta.

## Possible impact

Lielāka konta pārņemšanas iespējamība ar rupja spēka vai credential stuffing
uzbrukumiem.

## Recommendation

Pieprasiet minimālo garumu, pārbaudiet pret nopludināto paroļu sarakstiem un
atbalstiet daudzfaktoru autentifikāciju.
''',
};
