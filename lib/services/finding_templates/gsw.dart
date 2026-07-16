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

/// De meegeleverde finding-sjablonen in het Zwitserduits (gsw).
const Map<String, String> findingTemplatesGsw = {
  'sql-injection': '''
---
title: SQL-Injection
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Benutzeriigab wird ohni rächti Parametrisierig in ere SQL-Abfrog übernoh, so dass
en Aagryffer d'Logik vo de Abfrog cha ändere.

## Confirmation (reproduction)

Schick en präparierte Wärt im betroffene Parameter und stell fescht, dass
d'Aawendig Date usserhalb vom vorgseh Ergebnis zrugg git.

## Possible impact

En Aagryffer cha Date i de Datebank läse, ändere oder lösche und je nach
Datebank-Konfiguration wytere Zuegriff uf de Host über.

## Recommendation

Bruuch parametrisierti Abfroge (Prepared Statements) für jede Datebank-Zuegriff und
validier d'Iigab gäge ne Positivlischte. Nimm Datebank-Konte mit minimale Rächt.
''',
  'reflected-xss': '''
---
title: Reflektierts Cross-Site-Scripting (XSS)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Benutzeriigab wird ohni rächti Usgab-Codierig i de Antwort zrugg gspieglet, so dass
en Aagryffer Skript cha iischleuse, wo im Browser vom Opfer lauft.

## Confirmation (reproduction)

Gib e Payload im betroffene Parameter ii und lueg zue, wie si i de gerenderte Syte
usgführt wird.

## Possible impact

Übernahm vo de Sitzig, Klau vo Aameldedate und Aktione, wo im Name vom Opfer i de
Aawendig usgführt werde.

## Recommendation

Kontextbezogeni Usgab-Codierig vo allne benutzergsteuerte Date, e strengi Content
Security Policy und automatischs Escaping vom Framework.
''',
  'weak-password-policy': '''
---
title: Schwachi Passwort-Richtlinie
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

D'Aawendig nimmt schwachi Passwörter a (churz, hüfig oder ohni
Komplexitätsaaforderige), womit Konte liechter z'errate sind.

## Confirmation (reproduction)

Registrier oder änder es Passwort uf en churze, hüfige Wärt und stell fescht, dass
er aagno wird.

## Possible impact

Grösseri Wahrschynlichkeit vo ere Konteübernahm dur Brute-Force- oder
Credential-Stuffing-Aagriff.

## Recommendation

Erzwing e Mindestlängi, prüef gäge Lischte vo gleakte Passwörter und unterstütz
Mehr-Faktor-Authentifizierig.
''',
};
