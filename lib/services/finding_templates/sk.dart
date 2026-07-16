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

/// De meegeleverde finding-sjablonen in het Slowaaks (sk).
const Map<String, String> findingTemplatesSk = {
  'sql-injection': '''
---
title: SQL injection
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Vstup od používateľa sa vkladá do SQL dotazu bez riadnej parametrizácie, čo
útočníkovi umožňuje zmeniť logiku dotazu.

## Confirmation (reproduction)

Odošlite podvrhnutú hodnotu v dotknutom parametri a overte, že aplikácia vracia
údaje mimo zamýšľanej množiny výsledkov.

## Possible impact

Útočník môže čítať, meniť alebo mazať údaje v databáze a podľa konfigurácie
databázy získať ďalší prístup k hostiteľovi.

## Recommendation

Používajte parametrizované dotazy (prepared statements) pri každom prístupe k
databáze a overujte vstup voči zoznamu povolených hodnôt. Používajte databázové
účty s minimálnymi oprávneniami.
''',
  'reflected-xss': '''
---
title: Odrazené cross-site scripting (XSS)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Vstup od používateľa sa odráža v odpovedi bez riadneho kódovania výstupu, takže
útočník môže vložiť skript, ktorý sa spustí v prehliadači obete.

## Confirmation (reproduction)

Zadajte payload do dotknutého parametra a sledujte jeho spustenie na vykreslenej
stránke.

## Possible impact

Únos relácie, krádež prihlasovacích údajov a akcie vykonané v mene obete v rámci
aplikácie.

## Recommendation

Kódovanie výstupu podľa kontextu pre všetky údaje riadené používateľom, striktná
Content Security Policy a automatické escapovanie frameworkom.
''',
  'weak-password-policy': '''
---
title: Slabá politika hesiel
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Aplikácia prijíma slabé heslá (krátke, bežné alebo bez požiadaviek na zložitosť),
čo uľahčuje uhádnutie účtov.

## Confirmation (reproduction)

Zaregistrujte alebo zmeňte heslo na krátku, bežnú hodnotu a overte, že je
prijaté.

## Possible impact

Vyššia pravdepodobnosť prevzatia účtu útokmi hrubou silou alebo credential
stuffing.

## Recommendation

Vynucujte minimálnu dĺžku, kontrolujte voči zoznamom uniknutých hesiel a
podporujte viacfaktorové overovanie.
''',
};
