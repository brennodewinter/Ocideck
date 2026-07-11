import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/finding_template.dart';
import 'package:ocideck/services/cvss/cvss4.dart';
import 'package:ocideck/services/finding_template_library.dart';

const _source = '''
---
title: SQL injection
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of SQL
references:
  - https://owasp.org/a
  - https://cwe.mitre.org/data/definitions/89.html
---
## Description

Body description.

## Recommendation

Use parameterised queries.
''';

void main() {
  group('FindingTemplate.parse', () {
    final t = FindingTemplate.parse(_source, id: 'sql');

    test('reads front matter (title, severity, cvss, cwe, references)', () {
      expect(t.title, 'SQL injection');
      expect(t.severity, 'Critical');
      expect(t.cvssVector, startsWith('CVSS:4.0/AV:N'));
      expect(t.cvssVersion, '4.0');
      expect(t.cweId, 89);
      expect(t.cweName, 'Improper Neutralization of SQL');
      expect(t.references, [
        'https://owasp.org/a',
        'https://cwe.mitre.org/data/definitions/89.html',
      ]);
    });

    test('reads the body sections via FindingSpec', () {
      expect(t.description, 'Body description.');
      expect(t.recommendation, 'Use parameterised queries.');
    });

    test(
      'instantiates into a finding whose severity derives from the vector',
      () {
        final spec = t.toFindingSpec();
        expect(spec.heading, 'SQL injection');
        expect(spec.cweId, 89);
        expect(spec.severity, Cvss4Severity.critical);
        expect(spec.scopeObject, ''); // engagement-specific, left blank
        // The generated finding Markdown re-parses to the same fields.
        final back = FindingSpec.parse(spec.toMarkdown());
        expect(back.recommendation, 'Use parameterised queries.');
        expect(back.cvssVector, t.cvssVector);
      },
    );

    test('round-trips through toMarkdown', () {
      final again = FindingTemplate.parse(t.toMarkdown());
      expect(again.title, t.title);
      expect(again.cvssVector, t.cvssVector);
      expect(again.cweId, t.cweId);
      expect(again.references, t.references);
      expect(again.description, t.description);
      expect(again.recommendation, t.recommendation);
    });
  });

  group('FindingTemplateLibrary', () {
    final lib = FindingTemplateLibrary.instance;

    test('parses every bundled template with a title and CWE', () {
      expect(lib.bundled, isNotEmpty);
      for (final t in lib.bundled) {
        expect(t.title, isNotEmpty, reason: 'template ${t.id} has no title');
        expect(t.cweId, isNotNull, reason: 'template ${t.id} has no CWE');
      }
    });

    test('search matches by title and by CWE id', () {
      expect(lib.search('sql').map((t) => t.id), contains('sql-injection'));
      expect(lib.search('CWE-79').map((t) => t.id), contains('reflected-xss'));
      expect(lib.search(''), hasLength(lib.bundled.length));
      expect(lib.search('nonexistentxyz'), isEmpty);
    });
  });
}
