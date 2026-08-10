import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/cvss_builder.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/finding_pagination.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

const _headerBody =
    '# F-03 · SQL injection in the login form\n'
    '\n'
    '**Scope object:** `https://app.client.example/login`\n'
    '**CVSS 4.0:** 9.3 (Critical) · '
    '`CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N`\n'
    '**CWE:** [CWE-89 — Improper Neutralization of SQL]'
    '(https://cwe.mitre.org/data/definitions/89.html)\n'
    '**CVE:** [CVE-2024-1234](https://nvd.nist.gov/vuln/detail/CVE-2024-1234)\n'
    '\n'
    '## Description\n\nx\n';

Widget _host(Slide slide, {Map<String, CiaRating> scopeCia = const {}}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 800,
          height: 450,
          child: SlidePreviewWidget(
            slide: slide,
            themeProfile: const ThemeProfile(),
            scopeCia: scopeCia,
          ),
        ),
      ),
    ),
  );
}

Slide _finding(String body) => Slide.create(
  SlideType.finding,
).copyWith(customMarkdown: body, findingId: 'F-03');

double _meterPosition(WidgetTester tester) {
  final meterBox = tester.getRect(
    find.byKey(const ValueKey('finding-cvss-meter')),
  );
  final markerCenter = tester.getCenter(
    find.byKey(const ValueKey('finding-cvss-meter-marker')),
  );
  return (markerCenter.dx - meterBox.left) / meterBox.width;
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('finding renders a derived CVSS score and CWE/CVE chips', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_finding(_headerBody)));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Score + severity are derived from the vector, not read from text.
    expect(find.text('9.3'), findsOneWidget);
    expect(find.text('Critical'), findsOneWidget);
    expect(find.text('CWE-89'), findsOneWidget);
    expect(find.text('CVE-2024-1234'), findsOneWidget);
    expect(
      find.textContaining('SQL injection in the login form'),
      findsOneWidget,
    );
  });

  testWidgets('a rated scope object adds a context badge beside the base', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _finding(_headerBody),
        scopeCia: const {
          'https://app.client.example/login': CiaRating(
            confidentiality: CiaLevel.low,
            integrity: CiaLevel.low,
            availability: CiaLevel.low,
          ),
        },
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // De contextkaart toont de gewogen score als primaire waarde; de
    // oorspronkelijke basisscore blijft daarnaast transparant zichtbaar.
    expect(
      find.byKey(const ValueKey('finding-cvss-score-card')),
      findsOneWidget,
    );
    expect(find.text('8.9'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.textContaining('Basis 9.3'), findsOneWidget);
    expect(find.textContaining('Context'), findsOneWidget);
    // De schaal hoort bij de primaire contextscore (8,9), niet bij de
    // daarnaast getoonde basisscore (9,3).
    expect(_meterPosition(tester), closeTo(0.89, 0.015));
  });

  testWidgets('a resolved-after-retest finding shows a retest badge', (
    tester,
  ) async {
    final md = const FindingSpec(
      heading: 'F-1 · Fixed thing',
      retest: RetestStatus.resolved,
    ).toMarkdown();
    await tester.pumpWidget(_host(_finding(md)));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Opgelost na hertest'), findsOneWidget);
  });

  testWidgets('CVSS score stays outside its visual meter (#1059)', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_finding(_headerBody)));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // De score blijft gewone widgettekst. De schaal is een aparte visuele
    // meter en mag de waarde dus niet opnieuw in zichzelf schilderen.
    expect(find.text('CVSS'), findsOneWidget);
    expect(find.text('9.3'), findsOneWidget);
    expect(find.text('Critical'), findsOneWidget);
    final scoreCard = find.byKey(const ValueKey('finding-cvss-score-card'));
    final meter = find.byKey(const ValueKey('finding-cvss-meter'));
    final marker = find.byKey(const ValueKey('finding-cvss-meter-marker'));
    expect(scoreCard, findsOneWidget);
    expect(meter, findsOneWidget);
    expect(marker, findsOneWidget);
    expect(
      find.descendant(of: meter, matching: find.text('9.3')),
      findsNothing,
    );
    expect(_meterPosition(tester), closeTo(0.93, 0.015));
  });

  testWidgets('a finding without a CVSS shows no score card', (tester) async {
    final md = const FindingSpec(heading: 'F-1 · Geen score').toMarkdown();
    await tester.pumpWidget(_host(_finding(md)));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('CVSS'), findsNothing);
    expect(find.byKey(const ValueKey('finding-cvss-score-card')), findsNothing);
    expect(find.byKey(const ValueKey('finding-cvss-meter')), findsNothing);
    expect(
      find.byKey(const ValueKey('finding-cvss-meter-marker')),
      findsNothing,
    );
  });

  testWidgets('the CVSS meter exposes its score and range to assistive tech', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(_host(_finding(_headerBody)));
    await tester.pump();

    expect(
      tester.getSemantics(find.byKey(const ValueKey('finding-cvss-meter'))),
      isSemantics(label: 'CVSS', value: '9.3 / 10 · Critical'),
    );
    semantics.dispose();
  });

  testWidgets('a finding linked to a test shows the test id chip (#8)', (
    tester,
  ) async {
    final md = const FindingSpec(
      heading: 'F-1 · Linked thing',
      testId: 'WSTG-ATHN-07',
    ).toMarkdown();
    await tester.pumpWidget(_host(_finding(md)));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('WSTG-ATHN-07'), findsOneWidget);
  });

  testWidgets('a finding with no CVSS renders without a badge or a crash', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_finding('# F-01 · Bare finding\n\n## Description\n\nx\n')),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Bare finding'), findsOneWidget);
    // No CVSS vector → no severity badge text of the form "score · band".
    expect(find.textContaining(' · Critical'), findsNothing);
  });

  // A finding with four full prose sections — more than fits one slide at full
  // size, so it must paginate.
  const longFinding =
      '# F-07 · Uitgebreide bevinding met veel tekst\n'
      '\n'
      '**Scope object:** `https://api.voorbeeld.example/v1/deur`\n'
      '**CVSS 4.0:** 9.3 (Critical) · '
      '`CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N`\n'
      '**CWE:** [CWE-798](https://cwe.mitre.org/data/definitions/798.html)\n'
      '\n'
      '## Description\n'
      'Een uitgebreide beschrijving die over meerdere regels loopt en zo de '
      'volledige hoogte van de sectie vult met genoeg tekst om te tellen voor de '
      'paginering en de breedtebenutting van de dia goed te kunnen meten.\n'
      '\n'
      '## Confirmation (reproduction)\n'
      '1. Eerste stap met een flinke hoeveelheid uitleg erbij ter illustratie.\n'
      '2. Tweede stap, opnieuw met voldoende woorden om een regel te vullen.\n'
      '3. Derde stap die de reproductie afrondt en de sectie compleet maakt.\n'
      '\n'
      '## Possible impact\n'
      'De mogelijke gevolgen beschreven over meerdere zinnen zodat de sectie een '
      'realistische hoogte krijgt en meetelt voor de hoogteberekening van de '
      'paginering, net als in een echt rapport.\n'
      '\n'
      '## Recommendation\n'
      'De aanbeveling met concrete maatregelen, ook weer lang genoeg om een '
      'volwaardige sectie te vormen die niet zomaar bij de vorige past op één '
      'enkele dia.\n';

  // The width fraction the preview actually renders at. The scaffold's FittedBox
  // (BoxFit.scaleDown, top-left) lays the content out at the full slide width and
  // shrinks it uniformly when it is too tall; since it keeps aspect ratio, the
  // height ratio it shrinks by is exactly the fraction of the slide width left in
  // use — the very thing this bug was about (a too-tall finding using a third).
  Future<double> renderWidthFraction(WidgetTester tester, String md) async {
    await tester.pumpWidget(_host(_finding(md)));
    await tester.pump();
    final ro =
        tester.renderObject(find.byType(FittedBox))
            as RenderObjectWithChildMixin<RenderBox>;
    final own = (ro as RenderBox).size;
    return (own.height / ro.child!.size.height).clamp(0.0, 1.0);
  }

  testWidgets('an overflowing finding paginates into (near-)full-width pages', (
    tester,
  ) async {
    final pages = paginateFinding(FindingSpec.parse(longFinding));
    expect(pages.length, greaterThan(1), reason: 'this finding must split');

    // The whole source finding — what the thumbnail and the in-editor preview
    // receive, un-paginated — now renders its FIRST PAGE at (near-)full width.
    // Before #1147 the single-slide preview scaled the whole overflowing finding
    // down uniformly to a fraction of the width (F-01 at ~a third); it now
    // paginates on the way in, exactly like the presenter and the export.
    expect(
      await renderWidthFraction(tester, longFinding),
      greaterThan(0.70),
      reason:
          'whole source finding should render its first page full-width (#1147)',
    );

    for (var i = 0; i < pages.length; i++) {
      final frac = await renderWidthFraction(tester, pages[i].toMarkdown());
      if (i == 0) {
        // Page 1 now uses the room below the compact score card for the first
        // section. It may scale modestly, but never past the readability floor.
        expect(
          frac,
          greaterThan(0.70),
          reason: 'header page should remain readable, was $frac',
        );
      } else {
        // Related complete sections may share a continuation page. They remain
        // comfortably above the same readability floor.
        expect(
          frac,
          greaterThan(0.70),
          reason: 'content page ${i + 1} should remain readable, was $frac',
        );
      }
    }
  });

  testWidgets(
    'an overflowing finding fills the slide width in a single-slide preview '
    '(#1147)',
    (tester) async {
      // The thumbnail and the in-editor live preview render one source slide and
      // never run expandFindingsForRender. Before #1147 an overflowing finding
      // was scaled down uniformly there, so the header card used a fraction of
      // the slide width — parked top-left with the meta squeezed into the left
      // half. It must now fill the width like the paged preview and the export.
      await tester.pumpWidget(_host(_finding(longFinding)));
      await tester.pump();
      expect(tester.takeException(), isNull);

      final slide = tester.getRect(find.byType(SlidePreviewWidget));
      final card = tester.getRect(
        find.byKey(const ValueKey('finding-header-card')),
      );
      final fill = card.width / slide.width;
      expect(
        fill,
        greaterThan(0.5),
        reason:
            'header card should fill most of the slide width, was '
            '${fill.toStringAsFixed(2)} (pre-fix ~0.13)',
      );
    },
  );

  testWidgets(
    'a continuation page drops the severity card for a plain heading',
    (tester) async {
      final pages = paginateFinding(FindingSpec.parse(longFinding));
      final continuation = pages[1];

      await tester.pumpWidget(_host(_finding(continuation.toMarkdown())));
      await tester.pump();

      expect(tester.takeException(), isNull);
      // The marked heading is shown…
      expect(find.textContaining('(2/'), findsOneWidget);
      // …but none of the header meta (no CVSS gauge, no severity badge).
      expect(find.text('CVSS'), findsNothing);
      expect(find.textContaining(' · Critical'), findsNothing);
    },
  );

  testWidgets(
    'the continuation heading remains smaller than page 1 (#1198 follow-up)',
    (tester) async {
      // The repeated heading on a continuation page is a compact reminder, not a
      // full title — a large one wasted half the slide on the finding's name. It
      // must stay clearly smaller than page 1's header heading.
      double headingSize(Finder root, String heading) {
        final text = tester.widget<Text>(
          find.descendant(of: root, matching: find.text(heading)),
        );
        return text.style!.fontSize!;
      }

      final pages = paginateFinding(FindingSpec.parse(longFinding));

      await tester.pumpWidget(_host(_finding(pages.first.toMarkdown())));
      await tester.pump();
      final page1 = headingSize(
        find.byKey(const ValueKey('finding-header-card')),
        pages.first.heading,
      );

      await tester.pumpWidget(_host(_finding(pages[1].toMarkdown())));
      await tester.pump();
      final continuation = headingSize(
        find.byKey(const ValueKey('finding-continuation-heading')),
        pages[1].heading,
      );

      expect(
        continuation,
        lessThan(page1 * 0.7),
        reason:
            'continuation heading ($continuation) should remain clearly smaller '
            'than the page-1 heading ($page1)',
      );
    },
  );

  testWidgets('page 1 without metadata still renders the finding header', (
    tester,
  ) async {
    final firstPage = const FindingSpec(
      heading: 'F-08 · Bevinding zonder metadata (1/2)',
      description: 'De eerste pagina heeft bewust geen CVSS of scope.',
    );

    await tester.pumpWidget(_host(_finding(firstPage.toMarkdown())));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('finding-header-card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('finding-continuation-heading')),
      findsNothing,
    );
  });
}
