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

/// De meegeleverde finding-sjablonen in het Fins (fi).
const Map<String, String> findingTemplatesFi = {
  'sql-injection': '''
---
title: SQL-injektio
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Käyttäjän syöte liitetään SQL-kyselyyn ilman asianmukaista parametrointia, mikä
antaa hyökkääjälle mahdollisuuden muuttaa kyselyn logiikkaa.

## Confirmation (reproduction)

Lähetä muokattu arvo kyseiseen parametriin ja totea, että sovellus palauttaa
tietoja tarkoitetun tulosjoukon ulkopuolelta.

## Possible impact

Hyökkääjä voi lukea, muuttaa tai poistaa tietokannan tietoja ja saada
tietokannan asetuksista riippuen laajemman pääsyn palvelimeen.

## Recommendation

Käytä parametroituja kyselyitä (prepared statements) kaikessa tietokantakäytössä
ja validoi syöte sallittujen luetteloa vasten. Käytä tietokantatilejä, joilla on
vähimmäisoikeudet.
''',
  'reflected-xss': '''
---
title: Heijastettu cross-site scripting (XSS)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Käyttäjän syöte heijastuu vastaukseen ilman asianmukaista tulosteen koodausta,
jolloin hyökkääjä voi injektoida skriptin, joka suoritetaan uhrin selaimessa.

## Confirmation (reproduction)

Anna hyötykuorma kyseiseen parametriin ja havaitse sen suoritus renderöidyllä
sivulla.

## Possible impact

Istunnon kaappaus, tunnusten varastaminen ja uhrin puolesta sovelluksessa
suoritetut toimet.

## Recommendation

Kontekstitietoinen tulosteen koodaus kaikelle käyttäjän hallitsemalle datalle,
tiukka Content Security Policy ja kehyksen automaattinen escaping.
''',
  'weak-password-policy': '''
---
title: Heikko salasanakäytäntö
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Sovellus hyväksyy heikkoja salasanoja (lyhyitä, yleisiä tai ilman
monimutkaisuusvaatimuksia), mikä tekee tileistä helpommin arvattavia.

## Confirmation (reproduction)

Rekisteröi tai vaihda salasana lyhyeksi, yleiseksi arvoksi ja totea, että se
hyväksytään.

## Possible impact

Kohonnut riski tilin kaappaamisesta brute force- tai
credential stuffing -hyökkäyksillä.

## Recommendation

Vaadi vähimmäispituus, tarkista vuotaneiden salasanojen luetteloita vasten ja tue
monivaiheista todennusta.
''',
};
