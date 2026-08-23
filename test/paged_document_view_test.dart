import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/services/document_footnote_setup.dart';
import 'package:ocideck/models/settings.dart' show ThemeProfile;
import 'package:ocideck/widgets/document_page_chrome.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:ocideck/widgets/reader/paged_document_view.dart';

/// Werken met echte pagina's: het document wordt op maat gezet, met de gekozen
/// marges, en breekt waar het vel vol is. De einden worden gemeten aan de echte
/// render — een schatting loopt stil uit de pas.
void main() {
  Future<void> pumpDoc(
    WidgetTester tester,
    String markdown, {
    PageSizeSpec size = PageSizeSpec.a4,
    PageMargins margins = const PageMargins(),
    FootnotePlacement footnotes = FootnotePlacement.page,
    double textScale = 1,
    ThemeProfile? profile,
    TlpLevel tlp = TlpLevel.none,
    Map<String, String> fields = const {},
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: PagedDocumentView(
              markdown: markdown,
              pageSize: size,
              margins: margins,
              profile: profile,
              tlp: tlp,
              fields: fields,
              footnotePlacement: footnotes,
            ),
          ),
        ),
      ),
    );
    // Eerste frame meet, tweede frame zet de pagina's neer.
    await tester.pumpAndSettle();
  }

  List<Size> sheetSizes(WidgetTester tester) => find
      .byKey(const Key('document-sheet'))
      .evaluate()
      .map((e) => (e.renderObject! as RenderBox).size)
      .toList();

  bool hasVisibleInstance(WidgetTester tester, Finder finder) {
    for (final element in finder.evaluate()) {
      final render = element.renderObject;
      if (render is! RenderBox || !render.hasSize) continue;
      Element? page;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget.key == const Key('document-page-window')) {
          page = ancestor;
          return false;
        }
        return true;
      });
      final pageRender = page?.renderObject;
      if (pageRender is! RenderBox || !pageRender.hasSize) continue;
      final itemRect = render.localToGlobal(Offset.zero) & render.size;
      final pageRect = pageRender.localToGlobal(Offset.zero) & pageRender.size;
      final visible = itemRect.intersect(pageRect);
      if (visible.width > 1 && visible.height > 1) return true;
    }
    return false;
  }

  testWidgets('een korte tekst wordt één vel op de gekozen maat', (
    tester,
  ) async {
    await pumpDoc(tester, 'Een korte alinea.');

    final pages = find.byWidgetPredicate(
      (w) =>
          w is Semantics && (w.properties.label ?? '').startsWith('Pagina 1 '),
    );
    expect(pages, findsOneWidget);

    // A4 portret op 96 dpi: 210 × 297 mm.
    final size = sheetSizes(tester).single;
    expect(size.width, closeTo(210 * kPxPerMm, 1));
    expect(size.height, closeTo(297 * kPxPerMm, 1));
  });

  testWidgets('een lange tekst breekt in meerdere vellen', (tester) async {
    final long = List.generate(
      60,
      (i) => 'Alinea $i met genoeg tekst om de pagina echt te vullen.',
    ).join('\n\n');
    await pumpDoc(tester, long);

    final pages = find.byWidgetPredicate(
      (w) => w is Semantics && (w.properties.label ?? '').startsWith('Pagina '),
    );
    expect(
      pages.evaluate().length,
      greaterThan(1),
      reason: 'zestig alinea\'s passen niet op een enkele A4',
    );
  });

  testWidgets(
    'een tijdlijnvervolg tekent de rail opnieuw en benoemt het vervolg',
    (tester) async {
      final events = List.generate(
        19,
        (i) =>
            '| 2026-0${i + 1} | Gebeurtenis $i met een uitvoerige toelichting '
            'die de kaart voldoende hoogte geeft om de tijdlijn over meerdere '
            'bladzijden te verdelen. |',
      ).join('\n');
      await pumpDoc(
        tester,
        '<!-- timeline -->\n'
        '| Tijd | Gebeurtenis |\n'
        '| --- | --- |\n'
        '$events',
        size: const PageSizeSpec(series: PaperSeries.a, number: 6),
        margins: const PageMargins.uniform(0),
        profile: const ThemeProfile(documentHeaderText: 'Kop'),
        tlp: TlpLevel.red,
      );

      final pages = find.byKey(const Key('document-page-window'));
      final continuations = find.byKey(
        const Key('document-timeline-continuation'),
      );
      expect(pages.evaluate().length, greaterThan(1));
      expect(continuations, findsWidgets);
      for (var i = 0; i < continuations.evaluate().length; i++) {
        final continuation = continuations.at(i);
        final sheet = find.ancestor(
          of: continuation,
          matching: find.byKey(const Key('document-sheet')),
        );
        final header = find.descendant(
          of: sheet,
          matching: find.byKey(const Key('document-header-band')),
        );
        final window = find.descendant(
          of: sheet,
          matching: find.byKey(const Key('document-page-window')),
        );
        expect(
          tester.getTopLeft(continuation).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(header).dy),
        );
        expect(
          tester.getBottomLeft(continuation).dy,
          lessThanOrEqualTo(tester.getTopLeft(window).dy),
        );
      }
      for (var i = 0; i < 19; i++) {
        final event = find.textContaining('Gebeurtenis $i');
        expect(event, findsWidgets);
        expect(
          hasVisibleInstance(tester, event),
          isTrue,
          reason: 'Gebeurtenis $i moet in minstens één paginavenster staan',
        );
      }
      expect(
        find.descendant(
          of: continuations.first,
          matching: find.textContaining('Tijdlijn · vervolg — Tijd ·'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('ook een uitzonderlijk hoge kaart benoemt ieder vervolgvel', (
    tester,
  ) async {
    final detail = List.generate(80, (i) => 'bewijsregel $i').join('<br>');
    await pumpDoc(
      tester,
      '<!-- timeline -->\n'
      '| Tijd | Gebeurtenis |\n'
      '| --- | --- |\n'
      '| 12:02 | $detail |',
      size: const PageSizeSpec(series: PaperSeries.a, number: 6),
      margins: const PageMargins(
        topMm: 10,
        rightMm: 10,
        bottomMm: 10,
        leftMm: 10,
      ),
    );

    expect(
      find.byKey(const Key('document-timeline-continuation')),
      findsAtLeastNWidgets(2),
    );
    expect(
      find.text('Tijdlijn · vervolg — Tijd · 12:02'),
      findsAtLeastNWidgets(2),
    );
    expect(find.textContaining('bewijsregel 79'), findsWidgets);
  });

  testWidgets('een lange vervolgmarkering blijft op tekstschaal bij 200%', (
    tester,
  ) async {
    final events = List.generate(
      8,
      (i) =>
          '| Een uitzonderlijk lange fasebenaming nummer $i die niet klein mag worden | Gebeurtenis $i met voldoende toelichting voor een vervolgpagina |',
    ).join('\n');
    await pumpDoc(
      tester,
      '<!-- timeline -->\n'
      '| Fase | Gebeurtenis |\n'
      '| --- | --- |\n'
      '$events',
      size: const PageSizeSpec(series: PaperSeries.a, number: 6),
      margins: const PageMargins(
        topMm: 10,
        rightMm: 10,
        bottomMm: 10,
        leftMm: 10,
      ),
      textScale: 2,
    );

    final continuation = find
        .byKey(const Key('document-timeline-continuation'))
        .first;
    expect(
      find.descendant(of: continuation, matching: find.byType(FittedBox)),
      findsNothing,
    );
    final label = tester.widget<Text>(
      find.descendant(of: continuation, matching: find.byType(Text)),
    );
    expect(label.maxLines, 2);
    expect(label.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('de paginamaat volgt de instelling', (tester) async {
    await pumpDoc(
      tester,
      'Kort.',
      size: const PageSizeSpec(series: PaperSeries.a, number: 5),
    );
    // A5 portret: 148 × 210 mm.
    final size = sheetSizes(tester).single;
    expect(size.width, closeTo(148 * kPxPerMm, 1));
    expect(size.height, closeTo(210 * kPxPerMm, 1));
  });

  testWidgets('het vel heeft dezelfde papierkleur als het tekstvlak', (
    tester,
  ) async {
    // Een vel met een andere kleur rand dan midden is geen vel meer. Dit is
    // precies waar de twee uit elkaar konden lopen: de weergave schildert het
    // tekstvlak met de profielachtergrond, het vel eromheen deed dat niet.
    const profile = ThemeProfile(
      name: 'Toets',
      slideBackgroundColor: '#FFFFFF',
    );
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: PagedDocumentView(
            markdown: 'Kort.',
            pageSize: PageSizeSpec.a4,
            margins: PageMargins(),
            profile: profile,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sheet = tester
        .widgetList<Container>(find.byType(Container))
        .firstWhere((c) => (c.decoration as BoxDecoration?)?.boxShadow != null);
    final content = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(DocumentMarkdownView),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(
      (sheet.decoration as BoxDecoration).color,
      content.color,
      reason:
          'de rand van het vel hoort hetzelfde papier te zijn als het midden',
    );
  });

  // De beeldkeuring vond dit: elk vel toonde onderaan de eerste regels van het
  // blok dat juist naar de vólgende pagina was geschoven, doormidden gesneden.
  // Het venster liep tot een volle paginahoogte in plaats van tot waar het
  // volgende vel begint.
  testWidgets('een vel toont niets van het blok dat is doorgeschoven', (
    tester,
  ) async {
    final long = List.generate(
      40,
      (i) => 'Alinea $i met genoeg tekst om de pagina echt te vullen.',
    ).join('\n\n');
    await pumpDoc(tester, long);

    final windows = find.byKey(const Key('document-page-window'));
    expect(windows, findsWidgets);

    // Geen venster is hoger dan het tekstvlak. Een venster dat een volle
    // paginahoogte toonde terwijl het blok al was doorgeschoven, sneed dat
    // blok doormidden onderaan het vel.
    final textArea = (297 - 25 - 25) * kPxPerMm;
    for (final element in windows.evaluate()) {
      final h = (element.renderObject! as RenderBox).size.height;
      expect(h, greaterThan(0));
      expect(h, lessThanOrEqualTo(textArea + 0.5));
    }
  });

  // En dit: met een kop-/voetband verdween er tekst. De banden stonden in
  // dezelfde kolom als de tekst en aten hoogte op waar de paginaverdeling al
  // over had beschikt.
  testWidgets('een kop- en voetband kosten geen tekstvlak', (tester) async {
    const profile = ThemeProfile(
      name: 'Toets',
      slideBackgroundColor: '#FFFFFF',
      documentHeaderText: 'Kopregel',
      documentFooterText: 'Voetregel',
      documentShowPageNumbers: true,
    );
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagedDocumentView(
            markdown: 'Een alinea.',
            pageSize: PageSizeSpec.a4,
            margins: const PageMargins(),
            profile: profile,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // De band staat er...
    expect(find.byType(DocumentChromeBand), findsNWidgets(2));
    // ...en het tekstvlak is nog steeds het volle tekstvlak: paginahoogte min
    // de marges, zonder dat de banden er iets van afsnoepen.
    final window = tester.getSize(
      find.byKey(const Key('document-page-window')).first,
    );
    expect(window.height, closeTo((297 - 25 - 25) * kPxPerMm, 1));
  });

  testWidgets('één TLP geldt in kop en voet op ieder vel', (tester) async {
    final long = List.generate(
      60,
      (i) => 'Alinea $i met genoeg tekst om meerdere vellen te vullen.',
    ).join('\n\n');

    await pumpDoc(tester, long);
    final pagesWithoutTlp = sheetSizes(tester).length;
    final heightsWithoutTlp = [
      for (final element
          in find.byKey(const Key('document-page-window')).evaluate())
        (element.renderObject! as RenderBox).size.height,
    ];
    expect(find.byKey(const Key('document-header-tlp')), findsNothing);
    expect(find.byKey(const Key('document-footer-tlp')), findsNothing);

    await pumpDoc(tester, long, tlp: TlpLevel.red);
    final pagesWithTlp = sheetSizes(tester).length;
    final heightsWithTlp = [
      for (final element
          in find.byKey(const Key('document-page-window')).evaluate())
        (element.renderObject! as RenderBox).size.height,
    ];

    expect(pagesWithTlp, pagesWithoutTlp);
    expect(pagesWithTlp, greaterThan(1));
    expect(heightsWithTlp, heightsWithoutTlp);
    expect(
      find.byKey(const Key('document-header-tlp')),
      findsNWidgets(pagesWithTlp),
    );
    expect(
      find.byKey(const Key('document-footer-tlp')),
      findsNWidgets(pagesWithTlp),
    );
    expect(find.text('TLP:RED'), findsNWidgets(pagesWithTlp * 2));
  });

  testWidgets('TLP blijft zichtbaar bij nulmarges', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PagedDocumentView(
            markdown: 'Tekst.',
            pageSize: PageSizeSpec.a4,
            margins: PageMargins(topMm: 0, bottomMm: 0, leftMm: 0, rightMm: 0),
            profile: ThemeProfile.vigilis,
            tlp: TlpLevel.red,
            fields: {'title': 'Rapport', 'author': 'Ada Lovelace'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('document-header-tlp')), findsOneWidget);
    expect(find.byKey(const Key('document-footer-tlp')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('document-header-band'))).height,
      greaterThan(0),
    );
    final headerBottom = tester
        .getBottomLeft(find.byKey(const Key('document-header-band')))
        .dy;
    final textTop = tester
        .getTopLeft(find.byKey(const Key('document-page-window')))
        .dy;
    final footerTop = tester
        .getTopLeft(find.byKey(const Key('document-footer-band')))
        .dy;
    final textBottom = tester
        .getBottomLeft(find.byKey(const Key('document-page-window')))
        .dy;
    expect(textTop, greaterThanOrEqualTo(headerBottom));
    expect(textBottom, lessThanOrEqualTo(footerTop));
    expect(
      tester.getSize(find.byKey(const Key('document-footer-band'))).height,
      greaterThan(0),
    );
  });

  testWidgets('opgeloste kop en voet worden op ieder vel herhaald', (
    tester,
  ) async {
    final long = List.generate(
      60,
      (i) => 'Alinea $i met genoeg tekst om meerdere vellen te vullen.',
    ).join('\n\n');
    const profile = ThemeProfile(
      documentHeaderText: '{title} · {project-id}',
      documentFooterText: '{author}',
    );

    await pumpDoc(
      tester,
      long,
      profile: profile,
      fields: const {
        'title': 'Kwartaalaudit',
        'project-id': 'P42',
        'author': 'Ada Lovelace',
      },
    );

    final pages = sheetSizes(tester).length;
    expect(pages, greaterThan(1));
    expect(find.byKey(const Key('document-header-text')), findsNWidgets(pages));
    expect(find.byKey(const Key('document-footer-text')), findsNWidgets(pages));
    expect(find.text('Kwartaalaudit · P42'), findsNWidgets(pages));
    expect(find.text('Ada Lovelace'), findsNWidgets(pages));
    expect(find.textContaining('{title}'), findsNothing);
    expect(find.textContaining('{author}'), findsNothing);
  });

  // Zonder stijlprofiel draagt geen enkel vel een kop- of voetband, en dus ook
  // geen paginanummer — terwijl je deze stand juist opent om te zien wat op
  // welke bladzijde komt. Het nummer staat daarom onder het vel.
  testWidgets('elk vel draagt een zichtbaar paginanummer', (tester) async {
    final long = List.generate(
      40,
      (i) => 'Alinea $i met genoeg tekst om de pagina echt te vullen.',
    ).join('\n\n');
    await pumpDoc(tester, long);

    final pages = find
        .byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label ?? '').startsWith('Pagina '),
        )
        .evaluate()
        .length;
    expect(pages, greaterThan(1));
    expect(find.text('Pagina 1 van $pages'), findsOneWidget);
    expect(find.text('Pagina $pages van $pages'), findsOneWidget);
  });

  // A0 staat gewoon in de maatlijst, en de vellen staan in een verticale rol:
  // zonder terugschalen zou de rechterhelft onbereikbaar zijn.
  testWidgets('een vel dat breder is dan het venster wordt passend gemaakt', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PagedDocumentView(
            markdown: 'Kort.',
            // A2: 420 × 594 mm, ruim breder dan 700 px.
            pageSize: PageSizeSpec(series: PaperSeries.a, number: 2),
            margins: PageMargins(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sheet = sheetSizes(tester).single;
    expect(
      sheet.width,
      lessThanOrEqualTo(700),
      reason: 'het vel hoort binnen het venster te passen',
    );
  });

  // De band hoort op dezelfde lijn te beginnen en eindigen als de tekst
  // eronder. Tegen de papierrand geplakt liep het woordmerk er half af.
  testWidgets('de kop- en voetband blijven binnen de zijmarges', (
    tester,
  ) async {
    const profile = ThemeProfile(
      name: 'Toets',
      slideBackgroundColor: '#FFFFFF',
      documentHeaderText: 'Kopregel',
      documentFooterText: 'Voetregel',
    );
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PagedDocumentView(
            markdown: 'Een alinea.',
            pageSize: PageSizeSpec.a4,
            margins: PageMargins(),
            profile: profile,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final band = tester.getSize(find.byType(DocumentChromeBand).first);
    final window = tester.getSize(
      find.byKey(const Key('document-page-window')).first,
    );
    expect(
      band.width,
      closeTo(window.width, 1),
      reason: 'de band hoort net zo breed te zijn als de tekstkolom',
    );
  });

  testWidgets('drukkersafloop maakt het vel groter dan het snijformaat', (
    tester,
  ) async {
    await pumpDoc(tester, 'Kort.', margins: const PageMargins(bleedMm: 3));
    // A4 plus 3 mm rondom: 216 × 303 mm.
    final size = sheetSizes(tester).single;
    expect(size.width, closeTo(216 * kPxPerMm, 1));
    expect(size.height, closeTo(303 * kPxPerMm, 1));
  });
  group('voetnoten op het vel', () {
    const withNote = '''
# Kop

Een zin met een noot [^1] erin.

[^1]: De noot hoort onderaan dit blad.
''';

    testWidgets('de noot staat op het vel, de definitie niet in de tekst', (
      tester,
    ) async {
      await pumpDoc(tester, withNote);

      expect(find.textContaining('De noot hoort onderaan'), findsOneWidget);
      expect(find.textContaining('[^1]:'), findsNothing);
    });

    testWidgets('achterin het document loopt de noot in de tekststroom mee', (
      tester,
    ) async {
      await pumpDoc(tester, withNote, footnotes: FootnotePlacement.document);

      // Ook dan staat hij er — maar dan als laatste blok van het document, niet
      // als los blok tegen de ondermarge.
      expect(find.textContaining('De noot hoort onderaan'), findsOneWidget);
    });
  });
}
