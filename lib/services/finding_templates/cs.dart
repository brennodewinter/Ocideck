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

/// De meegeleverde finding-sjablonen in het Tsjechisch (cs).
const Map<String, String> findingTemplatesCs = {
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

Vstup od uživatele je vložen do SQL dotazu bez řádné parametrizace, což útočníkovi
umožňuje změnit logiku dotazu.

## Confirmation (reproduction)

Odešlete podvržnou hodnotu v dotčeném parametru a ověřte, že aplikace vrací data
mimo zamýšlenou množinu výsledků.

## Possible impact

Útočník může číst, měnit nebo mazat data v databázi a podle konfigurace databáze
získat další přístup k hostiteli.

## Recommendation

Používejte parametrizované dotazy (prepared statements) pro veškerý přístup k
databázi a ověřujte vstup proti seznamu povolených hodnot. Používejte databázové
účty s minimálními oprávněními.
''',
  'reflected-xss': '''
---
title: Odražené cross-site scripting (XSS)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Vstup od uživatele se odráží v odpovědi bez řádného kódování výstupu, takže
útočník může vložit skript, který se spustí v prohlížeči oběti.

## Confirmation (reproduction)

Zadejte payload do dotčeného parametru a sledujte jeho spuštění na vykreslené
stránce.

## Possible impact

Únos relace, krádež přihlašovacích údajů a akce provedené jménem oběti v rámci
aplikace.

## Recommendation

Kódování výstupu podle kontextu pro veškerá data řízená uživatelem, striktní
Content Security Policy a automatické escapování frameworkem.
''',
  'weak-password-policy': '''
---
title: Slabá politika hesel
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Aplikace přijímá slabá hesla (krátká, běžná nebo bez požadavků na složitost), což
usnadňuje uhodnutí účtů.

## Confirmation (reproduction)

Zaregistrujte nebo změňte heslo na krátkou, běžnou hodnotu a ověřte, že je
přijato.

## Possible impact

Vyšší pravděpodobnost převzetí účtu útoky hrubou silou nebo credential stuffing.

## Recommendation

Vynucujte minimální délku, kontrolujte proti seznamům uniklých hesel a podporujte
vícefaktorové ověřování.
''',
};
