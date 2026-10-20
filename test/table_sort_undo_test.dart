import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/utils/table_row_permutation.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/editors/matrix_editor.dart';
import 'package:ocideck/widgets/editors/table_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regressietest voor #2486: één kolomsortering is op élk oppervlak één
/// undo-transactie — document Visueel, document Bron, tabeldia en matrix.
/// De sorteerkern zelf (types, lege waarden, herhaling) zit in
/// `table_sort_test.dart`; hier staat de bedrading: sorteren → undo → redo,
/// en dat een risicoregel nooit in losse cellen uiteenvalt.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  DeckNotifier deckNotifier() {
    final md = MarkdownService();
    final file = FileService(md, ImageService(), () => const ThemeProfile());
    return DeckNotifier(md, file);
  }

  Widget docApp(DocumentNotifier n) => ProviderScope(
    overrides: [documentProvider.overrideWith((ref) => n)],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const DocumentEditorScreen(),
    ),
  );

  /// Activeer een cel zodat de tabelwerkbalk verschijnt, en sorteer.
  /// `showKeyboard` in plaats van `tap`: een pointer op een cel in de
  /// Quill-embed raakt quills eigen gesturelaag (#1712-gebied).
  Future<void> tapSort(
    WidgetTester tester,
    String tooltip, {
    bool confirmAttention = false,
  }) async {
    final cell = find.descendant(
      of: find.byType(Table),
      matching: find.byType(TextField),
    );
    await tester.showKeyboard(cell.first);
    await tester.pump();
    await tester.tap(find.byTooltip(tooltip));
    await tester.pump();
    if (confirmAttention) {
      await tester.tap(find.text('Sorteren toepassen'));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 350));
  }

  group('isTableRowPermutation', () {
    const a = [
      ['R-001', 'x'],
      ['R-002', 'y'],
      ['R-003', 'z'],
    ];
    test('dezelfde rijen anders gerangschikt is een permutatie', () {
      expect(isTableRowPermutation(a, [a[1], a[0], a[2]]), isTrue);
    });
    test('dezelfde volgorde is geen wijziging', () {
      expect(isTableRowPermutation(a, [a[0], a[1], a[2]]), isFalse);
    });
    test('gewijzigde celinhoud is geen permutatie (dat was typen)', () {
      expect(
        isTableRowPermutation(a, [
          a[0],
          const ['R-002', 'gewijzigd'],
          a[2],
        ]),
        isFalse,
      );
    });
    test('een extra rij is geen permutatie (dat was invoegen)', () {
      expect(
        isTableRowPermutation(a, [
          ...a,
          const ['R-004', 'q'],
        ]),
        isFalse,
      );
    });
    test('dubbele rijen tellen correct mee', () {
      const dup = [
        ['R-001', 'x'],
        ['R-001', 'x'],
        ['R-002', 'y'],
      ];
      expect(isTableRowPermutation(dup, [dup[0], dup[2], dup[1]]), isTrue);
    });
  });

  /// De tabel uit de acceptatie: risico-ID's die met hun waarde meereizen,
  /// een numerieke 2/10-valkuil en een lege waarde die onderaan blijft.
  const bronTabel =
      '| ID | Score |\n'
      '| --- | --- |\n'
      '| R-010 | 10 |\n'
      '| R-002 | 2 |\n'
      '| R-003 |  |\n';

  testWidgets('document Bron: sorteren is één undo-stap, ID reist mee', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('# Rapport\n\n$bronTabel'));
    await tester.pumpWidget(docApp(n));
    await tester.pump();
    await tester.tap(find.text('Bron'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Cel in de Score-kolom activeren, dan oplopend sorteren. De lege waarde
    // maakt het een aandachtspunt: de dialoog hoort bij de handeling.
    final scoreCell = find.descendant(
      of: find.byType(Table),
      matching: find.byType(TextField),
    );
    // Rij 0 is de kop; kolom 1 is Score. Activeer de scorecel van de kop.
    await tester.showKeyboard(scoreCell.at(1));
    await tester.pump();
    await tester.tap(find.byTooltip('Kolom oplopend sorteren'));
    await tester.pump();
    await tester.tap(find.text('Sorteren toepassen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    var source = n.currentState.document!.source;
    // Numeriek: 2 voor 10, de lege waarde blijft onderaan — en de rijen
    // bleven heel (R-002 hoort bij 2, R-010 bij 10).
    expect(
      source.indexOf('| R-002 | 2 |'),
      lessThan(source.indexOf('| R-010 | 10 |')),
    );
    expect(
      source.indexOf('| R-010 | 10 |'),
      lessThan(source.indexOf('| R-003 |')),
    );

    n.undo();
    source = n.currentState.document!.source;
    expect(
      source.indexOf('| R-010 | 10 |'),
      lessThan(source.indexOf('| R-002 | 2 |')),
    );

    n.redo();
    source = n.currentState.document!.source;
    expect(
      source.indexOf('| R-002 | 2 |'),
      lessThan(source.indexOf('| R-010 | 10 |')),
    );
  });

  testWidgets('document Bron: undo op de sortering laat de typstap staan', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse(
          '# Rapport\n\n'
          '| ID | Score |\n| --- | --- |\n| R-010 | 10 |\n| R-002 | 2 |\n',
        ),
      );
    await tester.pumpWidget(docApp(n));
    await tester.pump();
    await tester.tap(find.text('Bron'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Typ eerst in de scorecel van R-010 — een gewone, gecoalesceerde stap.
    final cell = find.descendant(
      of: find.byType(Table),
      matching: find.widgetWithText(TextField, '10'),
    );
    await tester.enterText(cell, '12');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Sorteer daarna de kolom — dat mag de typstap niet meetrekken (#2486).
    await tester.showKeyboard(
      find
          .descendant(of: find.byType(Table), matching: find.byType(TextField))
          .at(1),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Kolom oplopend sorteren'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    var source = n.currentState.document!.source;
    expect(
      source.indexOf('| R-002 | 2 |'),
      lessThan(source.indexOf('| R-010 | 12 |')),
    );

    n.undo();
    source = n.currentState.document!.source;
    // De getypte '12' is er nog — alleen de rijvolgorde is hersteld.
    expect(source, contains('| R-010 | 12 |'));
    expect(
      source.indexOf('| R-010 | 12 |'),
      lessThan(source.indexOf('| R-002 | 2 |')),
    );
  });

  testWidgets('document Visueel: sorteren via de embed is één undo-stap', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse(
          '# Rapport\n\n'
          '| ID | Score |\n| --- | --- |\n| R-010 | 10 |\n| R-002 | 2 |\n',
        ),
      );
    await tester.pumpWidget(docApp(n));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(QuillEditor), findsOneWidget);
    // Oplopend verandert de volgorde écht (R-002 komt voor R-010): een
    // verandering die undo zichtbaar terugdraait en redo opnieuw toepast.
    await tapSort(tester, 'Kolom oplopend sorteren');

    var source = n.currentState.document!.source;
    expect(source.indexOf('R-002'), lessThan(source.indexOf('R-010')));

    n.undo();
    source = n.currentState.document!.source;
    expect(source.indexOf('R-010'), lessThan(source.indexOf('R-002')));

    n.redo();
    source = n.currentState.document!.source;
    expect(source.indexOf('R-002'), lessThan(source.indexOf('R-010')));
  });

  testWidgets('tabeldia: aflopend sorteren → undo → redo via de deck-stapel', (
    tester,
  ) async {
    final n = deckNotifier()..newDeck('D');
    final table = Slide.create(SlideType.table).copyWith(
      tableRows: const [
        ['ID', 'Score'],
        ['R-010', '10'],
        ['R-002', '2'],
        ['R-003', '7'],
      ],
    );
    // De dia staat ook écht in het deck — anders herstelt undo terecht naar
    // de titelsdia die er stond en toetst de test niets.
    n.updateSlide(0, table);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TableEditor(
              slide: table,
              onUpdate: (s) => n.updateSlide(0, s),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final cell = find.descendant(
      of: find.byType(Table),
      matching: find.byType(TextField),
    );
    await tester.tap(cell.at(1));
    await tester.pump();
    await tester.tap(find.byTooltip('Kolom aflopend sorteren'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    var rows = n.state.deck!.slides.first.tableRows;
    expect(rows.map((r) => r.first), ['ID', 'R-010', 'R-003', 'R-002']);

    n.undo();
    rows = n.state.deck!.slides.first.tableRows;
    expect(rows.map((r) => r.first), ['ID', 'R-010', 'R-002', 'R-003']);

    n.redo();
    rows = n.state.deck!.slides.first.tableRows;
    expect(rows.map((r) => r.first), ['ID', 'R-010', 'R-003', 'R-002']);
  });

  testWidgets('matrix: sorteren raakt alleen bronrijen; undo herstelt alles', (
    tester,
  ) async {
    final n = deckNotifier()..newDeck('D');
    final fmea = Slide.create(SlideType.matrix).copyWith(
      improvementTemplateId: 'fmea',
      tableRows: const [
        [
          'Processtap',
          'Faalwijze',
          'Effect',
          'S',
          'Oorzaak',
          'O',
          'Beheersing',
          'D',
        ],
        ['Meten', 'R-010 drift', 'Afwijking', '5', 'Slijtage', '4', 'Kal', '6'],
        [
          'Meten',
          'R-002 uitval',
          'Geen beeld',
          '7',
          'Kabel',
          '4',
          'Check',
          '5',
        ],
      ],
    );
    n.updateSlide(0, fmea);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MatrixEditor(
              slide: fmea,
              onUpdate: (s) => n.updateSlide(0, s),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Sorteer op faalwijze (kolom 1): R-002 komt alfabetisch vóór R-010.
    final cells = find.descendant(
      of: find.byType(Table),
      matching: find.byType(TextField),
    );
    // Kop = rij 0 met 8 opgeslagen kolommen; rij 1 kolom 1 is 'R-010 drift'.
    await tester.tap(cells.at(9));
    await tester.pump();
    await tester.tap(find.byTooltip('Kolom oplopend sorteren'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    var rows = n.state.deck!.slides.first.tableRows;
    expect(rows[1][1], 'R-002 uitval');
    expect(rows[2][1], 'R-010 drift');
    // De hele rij reisde mee — geen losse cellen.
    expect(rows[1][3], '7');
    expect(rows[2][3], '5');

    n.undo();
    rows = n.state.deck!.slides.first.tableRows;
    expect(rows[1][1], 'R-010 drift');
    expect(rows[2][1], 'R-002 uitval');

    n.redo();
    rows = n.state.deck!.slides.first.tableRows;
    expect(rows[1][1], 'R-002 uitval');
  });

  testWidgets('gemengde kolom: de soortvraag leidt tot één undo-bare sort', (
    tester,
  ) async {
    final n = deckNotifier()..newDeck('D');
    // Eén tekst en één getal: geen dominante soort — de sort vraagt hoe te
    // lezen in plaats van destructief te gokken.
    final table = Slide.create(SlideType.table).copyWith(
      tableRows: const [
        ['ID', 'Waarde'],
        ['R-001', 'appel'],
        ['R-002', '12'],
      ],
    );
    // De dia staat ook écht in het deck — anders herstelt undo terecht naar
    // de titelsdia die er stond en toetst de test niets.
    n.updateSlide(0, table);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TableEditor(
              slide: table,
              onUpdate: (s) => n.updateSlide(0, s),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final cell = find.descendant(
      of: find.byType(Table),
      matching: find.byType(TextField),
    );
    await tester.tap(cell.at(1));
    await tester.pump();
    await tester.tap(find.byTooltip('Kolom oplopend sorteren'));
    await tester.pump();

    // Gemengde inhoud vraagt eerst hoe te lezen — geen destructieve gok.
    expect(find.text('Hoe wil je deze kolom sorteren?'), findsOneWidget);
    await tester.tap(find.text('Tekst'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    var rows = n.state.deck!.slides.first.tableRows;
    // Tekstsortering: '12' vóór 'appel'.
    expect(rows.map((r) => r.last), ['Waarde', '12', 'appel']);

    n.undo();
    rows = n.state.deck!.slides.first.tableRows;
    expect(rows.map((r) => r.last), ['Waarde', 'appel', '12']);
  });

  testWidgets(
    'sorteren via het toetsenbord (Alt+Shift+pijl) is dezelfde stap',
    (tester) async {
      final n = deckNotifier()..newDeck('D');
      final table = Slide.create(SlideType.table).copyWith(
        tableRows: const [
          ['ID', 'Score'],
          ['R-010', '10'],
          ['R-002', '2'],
        ],
      );
      n.updateSlide(0, table);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: TableEditor(
                slide: table,
                onUpdate: (s) => n.updateSlide(0, s),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Focus de scorecel van R-010 (rij 1, kolom 1) en sorteer oplopend.
      final cell = find.descendant(
        of: find.byType(Table),
        matching: find.byType(TextField),
      );
      await tester.tap(cell.at(1));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      var rows = n.state.deck!.slides.first.tableRows;
      expect(rows.map((r) => r.last), ['Score', '2', '10']);

      n.undo();
      rows = n.state.deck!.slides.first.tableRows;
      expect(rows.map((r) => r.last), ['Score', '10', '2']);

      n.redo();
      rows = n.state.deck!.slides.first.tableRows;
      expect(rows.map((r) => r.last), ['Score', '2', '10']);
    },
  );
}
