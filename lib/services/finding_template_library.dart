import '../models/finding_template.dart';

/// The reusable finding-template library (PENTEST_MIAUW §17). This first
/// increment ships a small set of **bundled** starter templates and a search;
/// the importable community/team packs (through the existing import
/// sanitisation + limits) and CWE-keyed autofill extend this later.
///
/// Templates are authored as plain Markdown with front matter (the exact on-disk
/// form a user can export, diff and re-import), kept as source strings here so
/// they need no asset wiring; each is parsed once, lazily.
class FindingTemplateLibrary {
  FindingTemplateLibrary._();

  static final FindingTemplateLibrary instance = FindingTemplateLibrary._();

  List<FindingTemplate>? _bundled;

  /// The bundled starter templates, parsed on first use.
  List<FindingTemplate> get bundled => _bundled ??= _bundledSources.entries
      .map((e) => FindingTemplate.parse(e.value, id: e.key))
      .toList();

  /// Templates whose title/CWE/severity contain every whitespace-separated term
  /// in [query] (case-insensitive). An empty query returns all templates.
  List<FindingTemplate> search(String query) {
    final terms = query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((t) => t.isEmpty);
    if (terms.isEmpty) return bundled;
    return bundled
        .where((t) => terms.every((term) => t.searchText.contains(term)))
        .toList();
  }
}

/// slug → template source Markdown. English content (the deterministic snippet
/// floor); a tester specialises it per engagement after inserting it.
const Map<String, String> _bundledSources = {
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
