import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/editors/table_editor.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:ocideck/widgets/slides/inline_markdown.dart';

/// Dubbelklik-bewerken van een tabel in de documentmodus (DOCUMENT_MODE.md
/// §4.2): een gerenderde GFM-tabel dubbelklikken opent de volwaardige
/// [TableEditor], en 'Toepassen' schrijft het bewerkte raster terug op zijn
/// plek in de bron. De serialisatie- en telling-logica is puur en wordt hier
/// los, uitputtend getoetst; de widgettest bewijst de bedrading.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Widget editorApp(DocumentNotifier n) => ProviderScope(
    overrides: [documentProvider.overrideWith((ref) => n)],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const DocumentEditorScreen(),
    ),
  );

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
    await tester.pumpWidget(editorApp(n));
    await tester.pump();
    await tester.tap(find.text('Bron'));
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
    await tester.pumpWidget(editorApp(n));
    await tester.pump();
    await tester.tap(find.text('Bron'));
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

  testWidgets(
    'Visueel: het potlood op de tabel-embed bewerkt en schrijft byte-getrouw terug',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1300, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final n = DocumentNotifier()
        ..loadDocument(
          MarkdownDocument.parse(
            '# Rapport\n\n| Naam | Waarde |\n| --- | ---: |\n| Alfa | 1 |\n',
          ),
        );
      await tester.pumpWidget(editorApp(n));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Standaard Visueel: de tabel is een bewerkbare Quill-embed (geen Bron),
      // met hetzelfde potlood als de leesweergave.
      expect(find.byType(QuillEditor), findsOneWidget);
      final pencil = find.byIcon(Icons.edit_outlined);
      expect(pencil, findsOneWidget);
      await tester.tap(pencil);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // De volwaardige tabel-editor opent in de gedeelde embed-dialoog.
      expect(find.byType(TableEditor), findsOneWidget);
      final cellField = find.widgetWithText(TextField, 'Alfa');
      expect(cellField, findsOneWidget);
      await tester.enterText(cellField, 'Bravo');
      await tester.pump();
      await tester.tap(find.text('Toepassen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // De embed schrijft via replaceText terug op de x-embed-table; de
      // markdown-round-trip zet dat weer om naar een GFM-tabel in de bron.
      final source = n.currentState.document!.source;
      expect(source, contains('Bravo'));
      expect(source, isNot(contains('Alfa')));
      expect(source, contains('# Rapport'));
      // De rechtse uitlijning van kolom 2 overleeft de bewerking.
      expect(source, contains('---:'));
    },
  );

  testWidgets('de weergave past de per-kolomuitlijning toe', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DocumentMarkdownView(
              '| A | B |\n| :---: | ---: |\n| x | 9 |\n',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // De cellen in de tabel dragen de uitlijning uit de scheidingsrij: kolom 0
    // gecentreerd, kolom 1 rechts — dus niet alles op de GFM-default (links).
    final aligns = tester
        .widgetList<InlineMarkdownText>(
          find.descendant(
            of: find.byType(Table),
            matching: find.byType(InlineMarkdownText),
          ),
        )
        .map((w) => w.textAlign)
        .toSet();
    expect(aligns.contains(TextAlign.center), isTrue);
    expect(aligns.contains(TextAlign.end), isTrue);
  });

  testWidgets('Toepassen behoudt de uitlijning (geen stille strip, F3)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse(
          '# R\n\n| A | B | C |\n| :--- | :---: | ---: |\n| 1 | 2 | 3 |\n',
        ),
      );
    await tester.pumpWidget(editorApp(n));
    await tester.pump();
    await tester.tap(find.text('Bron'));
    await tester.pump();

    // Open de tabel-editor en pas toe zónder iets te wijzigen.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(TableEditor), findsOneWidget);
    await tester.tap(find.text('Toepassen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // De scheidingsrij mag NIET gestript zijn naar | --- | --- | --- |.
    expect(
      n.currentState.document!.source,
      contains('| :--- | :---: | ---: |'),
    );
  });
}
