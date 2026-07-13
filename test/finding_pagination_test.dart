import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/finding_pagination.dart';

String _lorem(int n) => List.filled(n, 'lorem ipsum dolor sit amet').join(' ');

void main() {
  const heading = 'F-03 · SQL-injectie in het loginformulier';
  const vector =
      'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N';

  FindingSpec bigFinding() => FindingSpec(
    heading: heading,
    scopeObject: 'https://app.voorbeeld/login',
    cvssVector: vector,
    cweId: 89,
    description: _lorem(6),
    confirmation: _lorem(6),
    impact: _lorem(6),
    recommendation: _lorem(6),
  );

  group('paginateFinding', () {
    test('a small finding stays a single page', () {
      const spec = FindingSpec(heading: heading, description: 'Kort.');
      final pages = paginateFinding(spec);
      expect(pages, hasLength(1));
      expect(pages.single, same(spec));
    });

    test('a long finding splits into multiple pages', () {
      final pages = paginateFinding(bigFinding());
      expect(pages.length, greaterThan(1));
    });

    test('page 1 keeps the header card; continuations drop it and mark the '
        'heading', () {
      final pages = paginateFinding(bigFinding());
      // Page 1 carries the scope/CVSS/CWE header meta.
      expect(pages.first.scopeObject, isNotEmpty);
      expect(pages.first.cvssVector, isNotEmpty);
      expect(pages.first.cweId, 89);
      // Continuation pages drop the header meta and mark the heading "(i/N)".
      for (final page in pages.skip(1)) {
        expect(page.scopeObject, isEmpty);
        expect(page.cvssVector, isEmpty);
        expect(page.cweId, isNull);
        expect(page.heading, contains('/${pages.length})'));
      }
      // Every section appears on exactly one page.
      final all = pages
          .map(
            (p) => [
              p.description,
              p.confirmation,
              p.impact,
              p.recommendation,
            ].where((s) => s.trim().isNotEmpty).length,
          )
          .fold<int>(0, (a, b) => a + b);
      expect(all, 4);
    });
  });

  group('expandFindingsForRender', () {
    test('expands an overflowing finding, leaves other slides untouched', () {
      final finding = Slide.create(
        SlideType.finding,
      ).copyWith(customMarkdown: bigFinding().toMarkdown());
      final table = Slide.create(SlideType.table);
      final title = Slide.create(SlideType.title);

      final expanded = expandFindingsForRender([title, finding, table]);
      final pages = paginateFinding(FindingSpec.parse(finding.customMarkdown));

      // title + N finding pages + table.
      expect(expanded.length, 2 + pages.length);
      expect(expanded.first.type, SlideType.title);
      expect(expanded.last.type, SlideType.table);
      // The original list is not mutated.
      expect([title, finding, table], hasLength(3));
    });

    test('a finding that fits passes through unchanged', () {
      final finding = Slide.create(SlideType.finding).copyWith(
        customMarkdown: const FindingSpec(
          heading: heading,
          description: 'Kort.',
        ).toMarkdown(),
      );
      final expanded = expandFindingsForRender([finding]);
      expect(expanded, hasLength(1));
    });
  });
}
