import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/services/cvss/cvss4.dart';

/// The canonical §3.1 example, used as the round-trip fixture.
const _example = '''
# F-03 · SQL injection in the login form

**Scope object:** `https://app.client.example/login`
**CVSS 4.0:** 9.3 (Critical) · `CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N`
**CWE:** [CWE-89 — Improper Neutralization of SQL](https://cwe.mitre.org/data/definitions/89.html)
**CVE:** [CVE-2024-1234](https://nvd.nist.gov/vuln/detail/CVE-2024-1234)

## Description

The login form concatenates the username straight into the query.

## Confirmation (reproduction)

`' OR '1'='1` in the username field returns every row.

## Possible impact

Full read/write access to the user table.

## Recommendation

Use parameterised queries.''';

void main() {
  group('FindingSpec.parse', () {
    final spec = FindingSpec.parse(_example);

    test('extracts every inline field', () {
      expect(spec.heading, 'F-03 · SQL injection in the login form');
      expect(spec.scopeObject, 'https://app.client.example/login');
      expect(
        spec.cvssVector,
        'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N',
      );
      expect(spec.cweId, 89);
      expect(spec.cweName, 'Improper Neutralization of SQL');
      expect(spec.cveIds, ['CVE-2024-1234']);
    });

    test('routes each section to its field', () {
      expect(spec.description, contains('concatenates the username'));
      expect(spec.confirmation, contains("OR '1'='1"));
      expect(spec.impact, contains('read/write access'));
      expect(spec.recommendation, 'Use parameterised queries.');
    });

    test('derives severity from the vector, never stores it', () {
      // 9.3 → Critical per the FIRST bands; the score text is not read back.
      expect(spec.severity, Cvss4Severity.critical);
      expect(spec.cvss!.score, closeTo(9.3, 0.05));
    });

    test('tolerates a missing CVE line and a bare CWE (no name)', () {
      final s = FindingSpec.parse(
        '# T\n\n**CWE:** [CWE-79](https://cwe.mitre.org/data/definitions/79.html)\n\n## Description\n\nx',
      );
      expect(s.cweId, 79);
      expect(s.cweName, '');
      expect(s.cveIds, isEmpty);
    });
  });

  group('FindingSpec.toMarkdown', () {
    test('recomputes the score/severity prefix from the vector', () {
      final md = const FindingSpec(
        heading: 'F-01 · Test',
        cvssVector:
            'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/'
            'SC:N/SI:N/SA:N',
      ).toMarkdown();
      expect(md, contains('**CVSS 4.0:** 9.3 (Critical) · `CVSS:4.0/AV:N'));
    });

    test('derives the canonical CWE/CVE URLs', () {
      final md = const FindingSpec(
        heading: 'x',
        cweId: 89,
        cweName: 'SQLi',
        cveIds: ['CVE-2024-1234'],
      ).toMarkdown();
      expect(
        md,
        contains(
          '[CWE-89 — SQLi](https://cwe.mitre.org/data/definitions/89.html)',
        ),
      );
      expect(
        md,
        contains(
          '[CVE-2024-1234](https://nvd.nist.gov/vuln/detail/CVE-2024-1234)',
        ),
      );
    });

    test(
      'omits field lines with no content but always emits the 4 sections',
      () {
        final md = const FindingSpec(heading: 'x').toMarkdown();
        expect(md, isNot(contains('**Scope object:**')));
        expect(md, isNot(contains('**CVSS 4.0:**')));
        expect(md, contains('## Description'));
        expect(md, contains('## Confirmation (reproduction)'));
        expect(md, contains('## Possible impact'));
        expect(md, contains('## Recommendation'));
      },
    );
  });

  test('parse(toMarkdown(parse(x))) is a fixed point', () {
    final once = FindingSpec.parse(_example);
    final twice = FindingSpec.parse(once.toMarkdown());
    expect(twice.heading, once.heading);
    expect(twice.scopeObject, once.scopeObject);
    expect(twice.cvssVector, once.cvssVector);
    expect(twice.cweId, once.cweId);
    expect(twice.cweName, once.cweName);
    expect(twice.cveIds, once.cveIds);
    expect(twice.description, once.description);
    expect(twice.confirmation, once.confirmation);
    expect(twice.impact, once.impact);
    expect(twice.recommendation, once.recommendation);
    // And the serialisation itself is stable.
    expect(twice.toMarkdown(), once.toMarkdown());
  });
}
