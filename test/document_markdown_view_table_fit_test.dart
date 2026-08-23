import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/text_measurement.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';

/// Feature 1: een tabel in de documentweergave past binnen de beschikbare
/// breedte met optimale kolomverdeling (hergebruik `tableColumnWidths`), en
/// valt alleen terug op horizontale scroll wanneer de kolomminima samen breder
/// zijn dan de beschikbare breedte.
void main() {
  /// Een tabel met 8 korte kolommen past in 800px — geen horizontale scroll.
  testWidgets('brede tabel met korte cellen past in 800px zonder scroll', (
    tester,
  ) async {
    const markdown = '''
| A | B | C | D | E | F | G | H |
|---|---|---|---|---|---|---|---|
| 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
| 9 | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
''';
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 800, child: DocumentMarkdownView(markdown)),
        ),
      ),
    );

    // De "fits" tak produceert een Table zonder omhullende
    // SingleChildScrollView. De "val terug op scroll" tak wél.
    final scrollFinder = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );
    expect(
      scrollFinder,
      findsNothing,
      reason:
          'Een tabel met 8 korte kolommen moet in 800px passen zonder '
          'horizontale scroll — de optimale kolomverdeling moet hem laten passen.',
    );

    // De tabel zelf moet wel gerenderd zijn.
    expect(find.byType(Table), findsOneWidget);
  });

  /// Een tabel met extreem lange onbreekbare woorden past niet — terugval op
  /// horizontale scroll.
  testWidgets(
    'tabel met extreem lange woorden valt terug op horizontale scroll',
    (tester) async {
      const longWord =
          'SupercalifragilisticexpialidociousAntidisestablishmentarianismPneumonoultramicroscopicsilicovolcanoconiosis';
      const markdown =
          '''
| $longWord | $longWord | $longWord |
|---|---|---|
| $longWord | $longWord | $longWord |
''';
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 400, child: DocumentMarkdownView(markdown)),
          ),
        ),
      );

      // De kolomminima zijn breder dan 400px, dus de tabel valt terug op
      // horizontale scroll met intrinsieke kolombreedtes.
      final scrollFinder = find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      );
      expect(
        scrollFinder,
        findsOneWidget,
        reason:
            'Een tabel met drie extreem lange woorden per kolom past niet in '
            '400px en moet terugvallen op horizontale scroll.',
      );
    },
  );

  /// De klacht: de kolomverdeling koos een optimum, en dan schoof er van een
  /// woord nét één letter naar de volgende regel. Dat gebeurde doordat de
  /// maatvoering met de preview-celmarge rekende terwijl de documentweergave
  /// een bredere marge tékent — de kolom was dus smaller dan waarop gerekend
  /// was, en precies dat verschil brak het laatste woord.
  testWidgets('geen kolom is smaller dan haar breedste woord plus celmarge', (
    tester,
  ) async {
    // De buurkolom is de dader: zij telt veel korte woorden, weegt daardoor
    // zwaar in een verdeling op tekenaantal, en liet te weinig over voor het
    // lange woord ernaast.
    const markdown = '''
| Nr | Rol | Toelichting |
|----|-----|-------------|
| 1 | Verwerkingsverantwoordelijke | een toelichting die uit veel losse korte woorden bestaat en daardoor zwaar weegt in de verdeling op tekenaantal |
| 2 | Toezichthouder | nog een regel met tekst die de kolom ernaast dreigt plat te drukken tot onder haar eigen woordbreedte |
''';
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 900, child: DocumentMarkdownView(markdown)),
        ),
      ),
    );

    final table = tester.widget<Table>(find.byType(Table));
    final widths = table.columnWidths;
    expect(widths, isNotNull, reason: 'de tabel hoort te passen op 900px');

    // Dezelfde maten als de weergave: celtekst 14px, celmarge = de
    // stijlprofiel-marge (standaard 8) plus 4, per zijde.
    const cellSize = 14.0;
    const hPad = 8.0 + 4.0;
    const longest = <int, String>{1: 'Verwerkingsverantwoordelijke'};
    for (final entry in longest.entries) {
      final width = (widths![entry.key]! as FixedColumnWidth).value;
      final need = measureTextWordWidth(entry.value, cellSize) + hPad * 2;
      expect(
        width,
        greaterThanOrEqualTo(need),
        reason:
            'kolom ${entry.key} is ${width.toStringAsFixed(1)}px maar heeft '
            '${need.toStringAsFixed(1)}px nodig voor "${entry.value}" — '
            'daar breekt het woord',
      );
    }
  });
}
