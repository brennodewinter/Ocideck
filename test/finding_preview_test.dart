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

  testWidgets('a finding shows CVSS as text without a painted meter (#1059)', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_finding(_headerBody)));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // De score is gewone, selecteerbare widgettekst en zit niet langer
    // verstopt in een decoratieve cockpitmeter.
    expect(find.text('CVSS'), findsOneWidget);
    expect(find.text('9.3'), findsOneWidget);
    expect(find.text('Critical'), findsOneWidget);
    final scoreCard = find.byKey(const ValueKey('finding-cvss-score-card'));
    expect(scoreCard, findsOneWidget);
    expect(
      find.descendant(of: scoreCard, matching: find.byType(CustomPaint)),
      findsNothing,
    );
  });

  testWidgets('a finding without a CVSS shows no score card', (tester) async {
    final md = const FindingSpec(heading: 'F-1 · Geen score').toMarkdown();
    await tester.pumpWidget(_host(_finding(md)));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('CVSS'), findsNothing);
    expect(find.byKey(const ValueKey('finding-cvss-score-card')), findsNothing);
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

    // Rendered whole (the pre-fix behaviour), it scales down to a fraction of
    // the width — the reported bug (F-01 rendered at ~a third).
    expect(await renderWidthFraction(tester, longFinding), lessThan(0.6));

    for (var i = 0; i < pages.length; i++) {
      final frac = await renderWidthFraction(tester, pages[i].toMarkdown());
      if (i == 0) {
        // Page 1 is the header card, taller than a slide on its own: close to,
        // not exactly, full width.
        expect(
          frac,
          greaterThan(0.85),
          reason: 'header page should be near-full width, was $frac',
        );
      } else {
        // Content pages use essentially the whole slide width.
        expect(
          frac,
          greaterThan(0.95),
          reason: 'content page ${i + 1} should be full width, was $frac',
        );
      }
    }
  });

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
}
