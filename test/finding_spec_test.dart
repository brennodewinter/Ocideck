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

  group('retest', () {
    test('round-trips the status and note', () {
      const spec = FindingSpec(
        heading: 'F-1',
        retest: RetestStatus.resolved,
        retestNote: 'hertest 2026-07-20',
      );
      final md = spec.toMarkdown();
      expect(md, contains('**Retest:** Resolved — hertest 2026-07-20'));
      final back = FindingSpec.parse(md);
      expect(back.retest, RetestStatus.resolved);
      expect(back.retestNote, 'hertest 2026-07-20');
    });

    test('a not-retested finding emits no Retest line', () {
      final md = const FindingSpec(heading: 'F-1').toMarkdown();
      expect(md, isNot(contains('**Retest:**')));
      expect(FindingSpec.parse(md).retest, RetestStatus.notRetested);
    });

    test('fromToken maps the tokens; unknown/empty -> notRetested', () {
      expect(RetestStatus.fromToken('Resolved'), RetestStatus.resolved);
      expect(RetestStatus.fromToken('notresolved'), RetestStatus.notResolved);
      expect(
        RetestStatus.fromToken('PartiallyResolved'),
        RetestStatus.partiallyResolved,
      );
      expect(RetestStatus.fromToken(''), RetestStatus.notRetested);
      expect(RetestStatus.fromToken('bogus'), RetestStatus.notRetested);
    });
  });

  group('test link (feedback #8)', () {
    test('round-trips the linked checklist test id', () {
      const spec = FindingSpec(heading: 'F-1', testId: 'WSTG-ATHN-07');
      final md = spec.toMarkdown();
      expect(md, contains('**Test:** `WSTG-ATHN-07`'));
      expect(FindingSpec.parse(md).testId, 'WSTG-ATHN-07');
    });

    test('an unlinked finding emits no Test line', () {
      final md = const FindingSpec(heading: 'F-1').toMarkdown();
      expect(md, isNot(contains('**Test:**')));
      expect(FindingSpec.parse(md).testId, isEmpty);
    });
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

  group('inhoud die stilzwijgend verdween', () {
    FindingSpec rt(FindingSpec x) => FindingSpec.parse(x.toMarkdown());

    test('copyWith houdt het MASWE-nummer vast', () {
      // Het hernummeren van bevindingen roept copyWith aan en schrijft het
      // resultaat terug naar de `.md`, dus dit wiste de regel definitief.
      const spec = FindingSpec(heading: 'F-01 Iets', masweId: 'MASWE-0005');
      expect(spec.copyWith(heading: 'F-02 Iets').masweId, 'MASWE-0005');
      expect(rt(spec.copyWith(heading: 'F-02 Iets')).masweId, 'MASWE-0005');
    });

    test(
      'een kopregel in de beschrijving verspringt niet naar een ander veld',
      () {
        const spec = FindingSpec(
          heading: 'H',
          description: 'Stap 1\n## Possible impact\nnep',
          impact: 'ECHT',
        );
        final out = rt(spec);
        expect(out.description, spec.description);
        expect(out.impact, 'ECHT', reason: 'niet vermengd met de beschrijving');
      },
    );

    test('een backtick in scope of test kapt de waarde niet af', () {
      final out = rt(
        const FindingSpec(
          heading: 'H',
          scopeObject: 'https://a/`b`/c',
          testId: 'A`B',
        ),
      );
      expect(out.scopeObject, 'https://a/`b`/c');
      expect(out.testId, 'A`B');
    });

    test('een CVSS-vector van een andere versie blijft staan', () {
      // De schrijfkant zette hem gewoon terug in de tekst; alleen de lezer was
      // streng, dus een overgenomen 3.1-vector verdween bij het herladen.
      final out = rt(
        const FindingSpec(heading: 'H', cvssVector: 'CVSS:3.1/AV:N/AC:L'),
      );
      expect(out.cvssVector, 'CVSS:3.1/AV:N/AC:L');
    });

    test('een 4.0-vector wordt nog steeds gescoord', () {
      const v =
          'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N';
      final out = rt(const FindingSpec(heading: 'H', cvssVector: v));
      expect(out.cvssVector, v);
      expect(out.cvss, isNotNull, reason: 'scoren mag niet stukgaan');
    });

    test('een blokhaak in de CWE-naam kapt hem niet af', () {
      final out = rt(
        const FindingSpec(heading: 'H', cweId: 79, cweName: 'Foo [bar] baz'),
      );
      expect(out.cweId, 79);
      expect(out.cweName, 'Foo [bar] baz');
    });

    test('een meerregelige hertest-notitie overleeft', () {
      final out = rt(
        const FindingSpec(
          heading: 'H',
          retest: RetestStatus.resolved,
          retestNote: 'r1\nr2',
        ),
      );
      expect(out.retestNote, 'r1\nr2');
      expect(out.retest, RetestStatus.resolved);
    });

    test('een letterlijke <br> in de notitie blijft letterlijk', () {
      final out = rt(
        const FindingSpec(
          heading: 'H',
          retest: RetestStatus.resolved,
          retestNote: 'letterlijk <br> hier',
        ),
      );
      expect(out.retestNote, 'letterlijk <br> hier');
    });

    test('een volle bevinding round-trippt veldsgewijs', () {
      const full = FindingSpec(
        heading: 'F-01 Iets',
        scopeObject: 'https://a/`b`',
        cvssVector: 'CVSS:3.1/AV:N/AC:L',
        cweId: 79,
        cweName: 'Foo [bar] baz',
        masweId: 'MASWE-0005',
        cveIds: ['CVE-2021-44228'],
        description: 'D',
        confirmation: 'C',
        impact: 'I',
        recommendation: 'R',
        retest: RetestStatus.resolved,
        retestNote: 'gepatcht',
        testId: 'T`1',
      );
      final out = rt(full);
      expect(out.heading, full.heading);
      expect(out.scopeObject, full.scopeObject);
      expect(out.cvssVector, full.cvssVector);
      expect(out.cweId, full.cweId);
      expect(out.cweName, full.cweName);
      expect(out.masweId, full.masweId);
      expect(out.cveIds, full.cveIds);
      expect(out.testId, full.testId);
      expect(out.retest, full.retest);
      expect(out.retestNote, full.retestNote);
      expect(out.description, full.description);
      // En stabiel: nog een rondje verandert niets meer.
      expect(rt(out).toMarkdown(), out.toMarkdown());
    });
  });
}
