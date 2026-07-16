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

/// De meegeleverde finding-sjablonen in het Duits (de).
const Map<String, String> findingTemplatesDe = {
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

Benutzereingaben werden ohne ordnungsgemäße Parametrisierung in eine
SQL-Abfrage übernommen, sodass ein Angreifer die Logik der Abfrage ändern kann.

## Confirmation (reproduction)

Übermitteln Sie einen präparierten Wert im betroffenen Parameter und stellen Sie
fest, dass die Anwendung Daten außerhalb der vorgesehenen Ergebnismenge liefert.

## Possible impact

Ein Angreifer kann Daten in der Datenbank lesen, ändern oder löschen und je nach
Datenbankkonfiguration weiteren Zugriff auf den Host erlangen.

## Recommendation

Verwenden Sie parametrisierte Abfragen (Prepared Statements) für jeden
Datenbankzugriff und validieren Sie Eingaben gegen eine Positivliste. Nutzen Sie
Datenbankkonten mit minimalen Rechten.
''',
  'reflected-xss': '''
---
title: Reflektiertes Cross-Site-Scripting (XSS)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Benutzereingaben werden ohne ordnungsgemäße Ausgabecodierung in der Antwort
zurückgegeben, sodass ein Angreifer Skript einschleusen kann, das im Browser des
Opfers ausgeführt wird.

## Confirmation (reproduction)

Übergeben Sie eine Payload im betroffenen Parameter und beobachten Sie deren
Ausführung in der gerenderten Seite.

## Possible impact

Übernahme der Sitzung, Diebstahl von Zugangsdaten und Aktionen, die im Namen des
Opfers in der Anwendung ausgeführt werden.

## Recommendation

Kontextbezogene Ausgabecodierung aller benutzergesteuerten Daten, eine strikte
Content Security Policy und automatisches Escaping durch das Framework.
''',
  'weak-password-policy': '''
---
title: Schwache Passwortrichtlinie
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Die Anwendung akzeptiert schwache Passwörter (kurz, häufig verwendet oder ohne
Komplexitätsanforderungen), wodurch Konten leichter zu erraten sind.

## Confirmation (reproduction)

Registrieren oder ändern Sie ein Passwort auf einen kurzen, häufig verwendeten
Wert und stellen Sie fest, dass er akzeptiert wird.

## Possible impact

Erhöhte Wahrscheinlichkeit einer Kontoübernahme durch Brute-Force- oder
Credential-Stuffing-Angriffe.

## Recommendation

Erzwingen Sie eine Mindestlänge, prüfen Sie gegen Listen geleakter Passwörter und
unterstützen Sie Mehr-Faktor-Authentifizierung.
''',
};
