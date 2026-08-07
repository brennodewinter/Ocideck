import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/utils/markdown_blocks.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/editors/table_editor.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';

/// Dubbelklik-bewerken van een tabel in de documentmodus (DOCUMENT_MODE.md
/// §4.2): een gerenderde GFM-tabel dubbelklikken opent de volwaardige
/// [TableEditor], en 'Toepassen' schrijft het bewerkte raster terug op zijn
/// plek in de bron. De serialisatie- en telling-logica is puur en wordt hier
/// los, uitputtend getoetst; de widgettest bewijst de bedrading.
void main() {
  group('rowsToGfmTable', () {
    test('bouwt een koprij, scheidingsrij en body', () {
      final gfm = rowsToGfmTable([
        ['Naam', 'Waarde'],
        ['Alfa', '1'],
        ['Bravo', '2'],
      ]);
      expect(
        gfm,
        '| Naam | Waarde |\n| --- | --- |\n| Alfa | 1 |\n| Bravo | 2 |',
      );
    });

    test('ontsnapt een pijp in een cel zodat de kolomgrens heel blijft', () {
      final gfm = rowsToGfmTable([
        ['a|b', 'c'],
        ['d', 'e'],
      ]);
      expect(gfm.split('\n').first, r'| a\|b | c |');
    });

    test('vult ragged rijen aan tot de breedste', () {
      final gfm = rowsToGfmTable([
        ['H1', 'H2', 'H3'],
        ['x'],
      ]);
      expect(gfm.split('\n').last, '| x |  |  |');
    });
  });

  group('nthTableBlockRange telt zoals de weergave', () {
    const doc =
        '# Kop\n\n'
        '| A | B |\n| --- | --- |\n| 1 | 2 |\n\n'
        'tussentekst\n\n'
        '```\n| geen tabel maar code |\n| --- |\n```\n\n'
        '| C | D |\n| --- | --- |\n| 3 | 4 |\n';

    test('slaat een pipe-regel binnen een fence over en telt twee tabellen', () {
      // Eerste tabel: regels 2..5 (kop, scheiding, body).
      expect(DocumentMarkdownView.nthTableBlockRange(doc, 0), [2, 5]);
      // Tweede tabel staat ná het codeblok — bewijst dat de fence is genegeerd.
      final second = DocumentMarkdownView.nthTableBlockRange(doc, 1)!;
      expect(doc.split('\n').sublist(second[0], second[1]).first, '| C | D |');
      // Geen derde tabel.
      expect(DocumentMarkdownView.nthTableBlockRange(doc, 2), isNull);
    });
  });

  group('replaceNthTableBlock', () {
    test('vervangt het n-de blok en laat de rest byte-getrouw staan', () {
      const source =
          'intro\n\n'
          '| A | B |\n| --- | --- |\n| 1 | 2 |\n\n'
          'midden\n\n'
          '| C | D |\n| --- | --- |\n| 3 | 4 |\n\n'
          'slot\n';

      final next = replaceNthTableBlock(
        source,
        1,
        '| X | Y |\n| --- | --- |\n| 9 | 8 |',
      );

      expect(next, contains('| X | Y |'));
      // Alles eromheen staat er byte-getrouw nog.
      expect(next, contains('intro\n'));
      expect(next, contains('| A | B |'));
      expect(next, contains('midden\n'));
      expect(next, contains('slot\n'));
      // De tweede tabel (C/D) is weg; alleen de eerste bleef.
      expect(next, isNot(contains('| C | D |')));
    });

    test('een ordinaal buiten bereik laat de bron ongemoeid', () {
      const source = '| A | B |\n| --- | --- |\n| 1 | 2 |\n';
      expect(replaceNthTableBlock(source, 5, '| X |\n| --- |\n| 9 |'), source);
    });
  });

  test('gfmTableCells ontleedt de rauwe regels en ontsnapte pijpen', () {
    final cells = gfmTableCells([r'| a\|b | c |', '| d | e |']);
    expect(cells, [
      ['a|b', 'c'],
      ['d', 'e'],
    ]);
  });

  testWidgets('dubbelklik op de tabel opent de editor en past het toe', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse(
          '# Rapport\n\n| Naam | Waarde |\n| --- | --- |\n| Alfa | 1 |\n',
        ),
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [documentProvider.overrideWith((ref) => n)],
        child: const MaterialApp(home: DocumentEditorScreen()),
      ),
    );
    await tester.pump();

    // De tabel rendert in de weergave.
    final table = find.byType(Table);
    expect(table, findsOneWidget);

    // Dubbelklik: twee tikken binnen de dubbelklik-tijd.
    final center = tester.getCenter(table);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // De volwaardige tabel-editor staat nu in een dialoog, met de cellen erin.
    expect(find.byType(TableEditor), findsOneWidget);
    final cellField = find.widgetWithText(TextField, 'Alfa');
    expect(cellField, findsOneWidget);

    // Bewerk een cel en pas toe → het blok wordt teruggeschreven in de bron.
    await tester.enterText(cellField, 'Bravo');
    await tester.pump();
    await tester.tap(find.text('Toepassen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final source = n.currentState.document!.source;
    expect(source, contains('Bravo'));
    expect(source, isNot(contains('Alfa')));
    // Nog steeds precies één tabel, en de omringende tekst staat er nog.
    expect(DocumentMarkdownView.nthTableBlockRange(source, 1), isNull);
    expect(source, contains('# Rapport'));
  });

  testWidgets('het potlood is zichtbaar en opent met één klik de editor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse(
          '# Rapport\n\n| Naam | Waarde |\n| --- | --- |\n| Alfa | 1 |\n',
        ),
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [documentProvider.overrideWith((ref) => n)],
        child: const MaterialApp(home: DocumentEditorScreen()),
      ),
    );
    await tester.pump();

    // Het potlood-knopje is zichtbaar op de tabel en opent met één klik dezelfde
    // volwaardige editor — ontdekbaar zonder de dubbelklik te hoeven raden.
    final pencil = find.byIcon(Icons.edit_outlined);
    expect(pencil, findsOneWidget);
    await tester.tap(pencil);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(TableEditor), findsOneWidget);
  });
}
