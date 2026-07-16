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

/// De meegeleverde finding-sjablonen in het Zweeds (sv).
const Map<String, String> findingTemplatesSv = {
  'sql-injection': '''
---
title: SQL-injektion
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Användarindata infogas i en SQL-fråga utan korrekt parametrisering, vilket gör
att en angripare kan ändra frågans logik.

## Confirmation (reproduction)

Skicka ett preparerat värde i den berörda parametern och konstatera att
applikationen returnerar data utanför den avsedda resultatmängden.

## Possible impact

En angripare kan läsa, ändra eller radera data i databasen och kan beroende på
databaskonfigurationen få ytterligare åtkomst till värden.

## Recommendation

Använd parametriserade frågor (prepared statements) för all databasåtkomst och
validera indata mot en tillåtlista. Använd databaskonton med minsta möjliga
behörighet.
''',
  'reflected-xss': '''
---
title: Reflekterad cross-site scripting (XSS)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Användarindata återges i svaret utan korrekt utdatakodning, så att en angripare
kan injicera skript som körs i offrets webbläsare.

## Confirmation (reproduction)

Ange en nyttolast i den berörda parametern och observera att den körs på den
renderade sidan.

## Possible impact

Sessionskapning, stöld av inloggningsuppgifter och åtgärder som utförs för
offrets räkning i applikationen.

## Recommendation

Kontextmedveten utdatakodning av alla användarstyrda data, en strikt Content
Security Policy och automatisk escaping i ramverket.
''',
  'weak-password-policy': '''
---
title: Svag lösenordspolicy
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Applikationen accepterar svaga lösenord (korta, vanliga eller utan krav på
komplexitet), vilket gör konton lättare att gissa.

## Confirmation (reproduction)

Registrera eller ändra ett lösenord till ett kort, vanligt värde och konstatera
att det accepteras.

## Possible impact

Ökad risk för kontoövertagande genom brute force- eller
credential stuffing-attacker.

## Recommendation

Kräv en minsta längd, kontrollera mot listor över läckta lösenord och stöd
flerfaktorsautentisering.
''',
};
