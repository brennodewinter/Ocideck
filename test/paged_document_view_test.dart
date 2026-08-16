import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/page_size.dart';
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
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagedDocumentView(
            markdown: markdown,
            pageSize: size,
            margins: margins,
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

  testWidgets('drukkersafloop maakt het vel groter dan het snijformaat', (
    tester,
  ) async {
    await pumpDoc(tester, 'Kort.', margins: const PageMargins(bleedMm: 3));
    // A4 plus 3 mm rondom: 216 × 303 mm.
    final size = sheetSizes(tester).single;
    expect(size.width, closeTo(216 * kPxPerMm, 1));
    expect(size.height, closeTo(303 * kPxPerMm, 1));
  });
}
