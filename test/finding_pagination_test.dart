import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/finding_pagination.dart';

String _lorem(int n) => List.filled(n, 'lorem ipsum dolor sit amet').join(' ');

// A section long enough to force a page split under the tuned heuristic.
String _bigSection() => _lorem(24);

void main() {
  const heading = 'F-03 · SQL-injectie in het loginformulier';
  const vector =
      'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N';

  FindingSpec bigFinding() => FindingSpec(
    heading: heading,
    scopeObject: 'https://app.voorbeeld/login',
    cvssVector: vector,
    cweId: 89,
    description: _bigSection(),
    confirmation: _bigSection(),
    impact: _bigSection(),
    recommendation: _bigSection(),
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

    test('a realistic finding packs denser since the smaller finding type '
        '(#1163)', () {
      // The same four ~5-line sections fit two balanced pages: page 1 uses the
      // room below the compact header for two sections, page 2 carries the
      // remaining two. This is the calibration guard for "more content per
      // page" — if font and pagination scaling drift apart, the packing moves.
      final description = 'Beschrijving: ${_lorem(8)}';
      final confirmation = 'Bevestiging: ${_lorem(8)}';
      final impact = 'Impact: ${_lorem(8)}';
      final recommendation = 'Aanbeveling: ${_lorem(8)}';
      final spec = FindingSpec(
        heading: heading,
        scopeObject: 'https://app.voorbeeld/login',
        cvssVector: vector,
        cweId: 89,
        description: description,
        confirmation: confirmation,
        impact: impact,
        recommendation: recommendation,
      );

      final pages = paginateFinding(spec);

      expect(pages, hasLength(2));
      expect(pages[0].description, description);
      expect(pages[0].confirmation, confirmation);
      expect(pages[0].impact, isEmpty);
      expect(pages[0].recommendation, isEmpty);
      expect(pages[1].description, isEmpty);
      expect(pages[1].confirmation, isEmpty);
      expect(pages[1].impact, impact);
      expect(pages[1].recommendation, recommendation);

      // Reconstruct the authored section stream from the rendered pages. This
      // makes the test fail if a section is dropped, duplicated or reordered,
      // even when the page count and non-empty checks still happen to pass.
      final renderedSections = [
        for (final page in pages)
          ...[
            page.description,
            page.confirmation,
            page.impact,
            page.recommendation,
          ].where((section) => section.isNotEmpty),
      ];
      expect(renderedSections, [
        description,
        confirmation,
        impact,
        recommendation,
      ]);
    });

    test('fills page one before adding an avoidable continuation slide', () {
      // Two short sections followed by two longer ones used to become three
      // slides solely because page 1 stopped after the first section. With the
      // compact header the two short sections share page 1 and the two longer
      // sections share page 2, both above the readability floor.
      final sections = [
        'Beschrijving: ${_lorem(1)}',
        'Bevestiging: ${_lorem(12)}',
        'Impact: ${_lorem(12)}',
        'Aanbeveling: ${_lorem(12)}',
      ];
      final spec = FindingSpec(
        heading: heading,
        description: sections[0],
        confirmation: sections[1],
        impact: sections[2],
        recommendation: sections[3],
      );

      final pages = paginateFinding(spec);

      expect(pages, hasLength(2));
      expect(pages[0].description, sections[0]);
      expect(pages[0].confirmation, sections[1]);
      expect(pages[1].impact, sections[2]);
      expect(pages[1].recommendation, sections[3]);
      expect([
        for (final page in pages)
          ...[
            page.description,
            page.confirmation,
            page.impact,
            page.recommendation,
          ].where((section) => section.isNotEmpty),
      ], sections);
    });

    test('a finding stays single until it would shrink past the scale floor', () {
      // "Fits one page" means header + sections that still render at ≥0.80
      // width. A short finding stays single; growing it until the slide would
      // scale down past the floor splits it BETWEEN sections instead of
      // shrinking the whole thing (the bug that made a finding render at a third
      // of the width). A finding must have more than one section to split — a
      // single section cannot be broken, so it is returned whole (#1198).
      final small = FindingSpec(heading: heading, description: _lorem(2));
      expect(paginateFinding(small), hasLength(1));

      final big = FindingSpec(
        heading: heading,
        description: _lorem(24),
        confirmation: _lorem(24),
      );
      expect(paginateFinding(big).length, greaterThan(1));
    });

    test('an overflowing finding uses the room below its compact header', () {
      final spec = bigFinding().copyWith(description: _lorem(8));
      final pages = paginateFinding(spec);

      expect(pages.first.description, isNotEmpty);
      expect(pages.first.confirmation, isEmpty);
      expect(pages.first.scopeObject, isNotEmpty);
      expect(pages.first.cvssVector, isNotEmpty);
    });

    test('a paginated page serialises only its own section heading', () {
      // The render markdown must not carry the blanked sections' `##` headings:
      // the Marp/HTML export prints Markdown verbatim (the Flutter preview skips
      // empty `##` blocks, so present/PDF are fine either way).
      final pages = paginateFinding(
        bigFinding().copyWith(
          description: _lorem(8),
          confirmation: _lorem(8),
          impact: _lorem(8),
          recommendation: _lorem(8),
        ),
      );
      final headingRe = RegExp(r'^## ', multiLine: true);
      // Every page serialises exactly one `##` heading per section it actually
      // carries — no blanked section leaks its heading, and no page is empty.
      for (final page in pages) {
        final md = page.toMarkdown(omitEmptySections: true);
        final sectionsOnPage = [
          page.description,
          page.confirmation,
          page.impact,
          page.recommendation,
        ].where((s) => s.isNotEmpty).length;
        expect(
          sectionsOnPage,
          greaterThanOrEqualTo(1),
          reason: 'no page may be section-less, got:\n$md',
        );
        expect(
          headingRe.allMatches(md).length,
          sectionsOnPage,
          reason: 'heading count must match the sections on the page:\n$md',
        );
      }
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

  group('logo-bewuste paginering', () {
    // Een bevinding die net op één pagina past zonder logo, moet splitsen
    // wanneer een logo verticale ruimte opeist — anders loopt de tekst onder
    // het logo door.
    final profileWithLogo = const ThemeProfile(
      logoPath: 'logo.png',
      logoPosition: 'bottom-right',
      logoSize: 160,
    );

    test('een bevinding die past zonder logo splitst niet met logo (#1932)', () {
      // #1932: finding is een panel-slide — het logo zit in de hoek op top
      // van de inhoud, en reserveert geen verticale strook meer. De paginering
      // wordt daardoor niet meer beïnvloed door het logo.
      final finding = Slide.create(SlideType.finding).copyWith(
        customMarkdown: FindingSpec(
          heading: heading,
          description: 'Beschrijving: ${_lorem(12)}',
          confirmation: 'Bevestiging: ${_lorem(12)}',
        ).toMarkdown(),
      );

      // Zonder logo: één pagina.
      expect(expandFindingsForRender([finding]), hasLength(1));

      // Met logo: nog steeds één pagina (corner-mode, geen reserve).
      final withLogo = expandFindingsForRender([
        finding,
      ], profile: profileWithLogo);
      expect(withLogo.length, 1);
    });

    test('een profiel zonder logo verandert de paginering niet', () {
      final finding = Slide.create(
        SlideType.finding,
      ).copyWith(customMarkdown: bigFinding().toMarkdown());
      final withoutProfile = expandFindingsForRender([finding]);
      final withEmptyProfile = expandFindingsForRender([
        finding,
      ], profile: const ThemeProfile());
      expect(withEmptyProfile.length, withoutProfile.length);
    });

    test('showLogo false neemt het logo niet mee in de begroting', () {
      final finding = Slide.create(SlideType.finding).copyWith(
        customMarkdown: FindingSpec(
          heading: heading,
          description: _lorem(2),
        ).toMarkdown(),
        showLogo: false,
      );

      final withLogoProfile = expandFindingsForRender([
        finding,
      ], profile: profileWithLogo);
      expect(withLogoProfile, hasLength(1));
    });
  });

  group('identiteitsvelden op de eerste pagina', () {
    test('MASWE, hertest en testverwijzing gaan niet verloren', () {
      // Deze vier ontbraken volledig in de paginabouwer — óók op pagina één.
      // Een bevinding die lang genoeg was om te paginëren verloor ze daarmee uit
      // élke weergave, en een verdwenen hertest-uitkomst is in een opgeleverd
      // rapport het verschil tussen "opgelost" en niets.
      final spec = bigFinding().copyWith(
        masweId: 'MASWE-0005',
        testId: 'T-42',
        retest: RetestStatus.resolved,
        retestNote: 'gepatcht in 2026.3',
      );
      final pages = paginateFinding(spec);
      expect(pages.length, greaterThan(1), reason: 'anders test dit niets');

      expect(pages.first.masweId, 'MASWE-0005');
      expect(pages.first.testId, 'T-42');
      expect(pages.first.retest, RetestStatus.resolved);
      expect(pages.first.retestNote, 'gepatcht in 2026.3');

      // Vervolgpagina's dragen ze niet — net als scope, CVSS en CWE horen ze
      // bij de kop van de bevinding, niet bij elke pagina.
      for (final page in pages.skip(1)) {
        expect(page.masweId, isEmpty);
        expect(page.testId, isEmpty);
        expect(page.retest, RetestStatus.notRetested);
      }
    });
  });

  group('firstRenderPageSpec (single-slide preview)', () {
    Slide slideOf(FindingSpec spec) => Slide.create(SlideType.finding).copyWith(
      customMarkdown: spec.toMarkdown(),
      findingRole: FindingRole.header,
    );

    test('a finding that fits is returned whole', () {
      const spec = FindingSpec(heading: heading, description: 'Kort.');
      final shown = firstRenderPageSpec(slideOf(spec));
      // Same content as the source: nothing is dropped for a single-page finding.
      expect(shown.heading, heading);
      expect(shown.description, 'Kort.');
    });

    test('an overflowing finding yields its first page, not the whole', () {
      // Without this the thumbnail / in-editor preview would render the whole
      // overflowing finding, which the FittedBox scales down uniformly until the
      // header card uses a fraction of the width (#1147).
      final source = bigFinding();
      final pages = paginateFinding(source);
      expect(pages.length, greaterThan(1), reason: 'anders test dit niets');

      final shown = firstRenderPageSpec(slideOf(source));
      // It is exactly what the paginated first page would render — the header
      // keeps its "(1/N)" marker and the later sections are not all present.
      expect(shown.heading, pages.first.heading);
      expect(shown.heading, contains('(1/'));
      final sourceSections = [
        source.description,
        source.confirmation,
        source.impact,
        source.recommendation,
      ].where((s) => s.trim().isNotEmpty).length;
      final shownSections = [
        shown.description,
        shown.confirmation,
        shown.impact,
        shown.recommendation,
      ].where((s) => s.trim().isNotEmpty).length;
      expect(shownSections, lessThan(sourceSections));
    });
  });
}
