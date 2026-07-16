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

/// De meegeleverde finding-sjablonen in het Kroatisch (hr).
const Map<String, String> findingTemplatesHr = {
  'sql-injection': '''
---
title: SQL injekcija
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Korisnički unos ugrađuje se u SQL upit bez ispravne parametrizacije, što
napadaču omogućuje izmjenu logike upita.

## Confirmation (reproduction)

Pošaljite pripremljenu vrijednost u zahvaćenom parametru i utvrdite da aplikacija
vraća podatke izvan predviđenog skupa rezultata.

## Possible impact

Napadač može čitati, mijenjati ili brisati podatke u bazi te, ovisno o
konfiguraciji baze, ostvariti daljnji pristup poslužitelju.

## Recommendation

Za sav pristup bazi koristite parametrizirane upite (pripremljene izjave) i
provjeravajte unos prema popisu dopuštenih. Koristite račune baze s najmanjim
ovlastima.
''',
  'reflected-xss': '''
---
title: Reflektirani cross-site scripting (XSS)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Korisnički unos odražava se u odgovoru bez ispravnog kodiranja izlaza, pa napadač
može ubaciti skriptu koja se izvršava u pregledniku žrtve.

## Confirmation (reproduction)

Unesite korisni teret u zahvaćeni parametar i promatrajte njegovo izvršavanje na
iscrtanoj stranici.

## Possible impact

Otmica sesije, krađa vjerodajnica i radnje izvršene u ime žrtve unutar
aplikacije.

## Recommendation

Kodiranje izlaza svjesno konteksta za sve podatke pod kontrolom korisnika, stroga
Content Security Policy i automatsko escapiranje u okviru.
''',
  'weak-password-policy': '''
---
title: Slaba politika lozinki
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Aplikacija prihvaća slabe lozinke (kratke, uobičajene ili bez zahtjeva
složenosti), zbog čega je račune lakše pogoditi.

## Confirmation (reproduction)

Registrirajte ili promijenite lozinku na kratku, uobičajenu vrijednost i utvrdite
da je prihvaćena.

## Possible impact

Povećana vjerojatnost preuzimanja računa napadima grubom silom ili credential
stuffingom.

## Recommendation

Nametnite najmanju duljinu, provjeravajte prema popisima procurjelih lozinki i
podržite višefaktorsku autentifikaciju.
''',
};
