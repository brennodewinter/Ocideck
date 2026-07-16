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

/// De meegeleverde finding-sjablonen in het Engels (en).
const Map<String, String> findingTemplatesEn = {
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

User-supplied input is incorporated into an SQL query without proper
parameterisation, allowing an attacker to alter the query's logic.

## Confirmation (reproduction)

Submit a crafted value in the affected parameter and observe that the
application returns data outside the intended result set.

## Possible impact

An attacker can read, modify or delete data in the database, and depending on
the database configuration may achieve further access to the host.

## Recommendation

Use parameterised queries (prepared statements) for all database access and
validate input against an allow-list. Apply least-privilege database accounts.
''',
  'reflected-xss': '''
---
title: Reflected cross-site scripting (XSS)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

User input is reflected in the response without proper output encoding, so an
attacker can inject script that runs in the victim's browser.

## Confirmation (reproduction)

Supply a payload in the affected parameter and observe it executing in the
rendered page.

## Possible impact

Session hijacking, credential theft and actions performed on behalf of the
victim within the application.

## Recommendation

Context-aware output encoding of all user-controlled data, a strict Content
Security Policy, and framework auto-escaping.
''',
  'weak-password-policy': '''
---
title: Weak password policy
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

The application accepts weak passwords (short, common or without complexity
requirements), making accounts easier to compromise by guessing.

## Confirmation (reproduction)

Register or change a password to a short, common value and observe it is
accepted.

## Possible impact

Increased likelihood of account takeover through brute-force or
credential-stuffing attacks.

## Recommendation

Enforce a minimum length, screen against breached-password lists, and support
multi-factor authentication.
''',
};
