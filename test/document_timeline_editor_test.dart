import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor_theme.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';

void main() {
  const source = '''
<!-- timeline -->
| Tijd | Gebeurtenis | Status |
| --- | --- | --- |
| 12:02 | Melding ontvangen | Gemeld |
| 13:41 | Herstelclaim weerlegd | Vastgesteld |
''';

  Future<QuillController> pumpEditor(
    WidgetTester tester, {
    String markdown = source,
  }) async {
    final controller = QuillController(
      document: MarkdownQuillCodec.documentFromMarkdown(markdown),
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(controller.dispose);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: WysiwygNotesField(
              controller: controller,
              scrollController: scroll,
              focusNode: focus,
              editorTheme: MarkdownEditorTheme.documentSurface(
                scheme: const ColorScheme.light(),
              ),
              hintText: '',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  testWidgets('tijdlijn is als kaarten zichtbaar en ter plekke bewerkbaar', (
    tester,
  ) async {
    final controller = await pumpEditor(tester);

    expect(find.text('Melding ontvangen'), findsOneWidget);
    expect(find.text('Herstelclaim weerlegd'), findsOneWidget);
    expect(find.text('Gebeurtenissen bewerken'), findsOneWidget);

    await tester.tap(find.text('Gebeurtenissen bewerken'));
    await tester.pump();
    expect(find.byType(Table), findsOneWidget);

    final eventCell = find.widgetWithText(TextField, 'Melding ontvangen');
    expect(eventCell, findsOneWidget);
    await tester.enterText(eventCell, 'Melding gevalideerd');
    await tester.pump();
    await tester.pump();

    final markdown = MarkdownQuillCodec.markdownFromDocument(
      controller.document,
    );
    expect(markdown, contains('<!-- timeline -->'));
    expect(markdown, contains('Melding gevalideerd'));
  });

  testWidgets('als tabel weergeven verwijdert alleen de marker', (
    tester,
  ) async {
    final controller = await pumpEditor(tester);

    await tester.tap(find.text('Als tabel weergeven'));
    await tester.pump();

    final markdown = MarkdownQuillCodec.markdownFromDocument(
      controller.document,
    );
    expect(markdown, isNot(contains('<!-- timeline -->')));
    expect(markdown, contains('| Tijd | Gebeurtenis | Status |'));
    expect(
      markdown,
      contains('| 13:41 | Herstelclaim weerlegd | Vastgesteld |'),
    );
  });

  testWidgets('sorteren is één Quill-undo', (tester) async {
    final controller = await pumpEditor(tester);
    final before = MarkdownQuillCodec.markdownFromDocument(controller.document);

    await tester.tap(find.text('Gebeurtenissen bewerken'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.showKeyboard(find.widgetWithText(TextField, 'Tijd'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byTooltip('Kolom aflopend sorteren'));
    await tester.pump(const Duration(milliseconds: 350));

    final sorted = MarkdownQuillCodec.markdownFromDocument(controller.document);
    expect(sorted.indexOf('13:41'), lessThan(sorted.indexOf('12:02')));
    expect(controller.hasUndo, isTrue);

    controller.undo();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      MarkdownQuillCodec.markdownFromDocument(controller.document),
      before,
    );
  });

  testWidgets('ongeldige tijdlijnmarker valt terug op een bewerkbare tabel', (
    tester,
  ) async {
    const malformed = '''
<!-- timeline -->
| A | B | C | D |
| --- | --- | --- | --- |
| een | twee | drie | vier |
''';
    final controller = await pumpEditor(tester, markdown: malformed);

    expect(
      find.text(
        'Een tijdlijn werkt met twee of drie kolommen. Pas de tabel aan of toon hem als gewone tabel.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'twee'), findsOneWidget);
    expect(find.text('Als tabel weergeven'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'twee'),
      'twee aangepast',
    );
    await tester.pump();
    await tester.pump();
    final markdown = MarkdownQuillCodec.markdownFromDocument(
      controller.document,
    );
    expect(markdown, contains('<!-- timeline -->\n| A | B | C | D |'));
    expect(markdown, contains('| een | twee aangepast | drie | vier |'));
  });

  testWidgets(
    'activatie toont kolomrollen en laat bronvolgorde of sorteren kiezen',
    (tester) async {
      const table = '''
| Wanneer | Feit | Bron |
| --- | --- | --- |
| 13:41 | Tweede feit | Logboek |
| onbekend | Tijdstip ontbreekt | Interview |
| 12:02 | Eerste feit | Melding |
''';
      final controller = await pumpEditor(tester, markdown: table);

      await tester.tap(find.text('Als tijdlijn weergeven'));
      await tester.pumpAndSettle();

      expect(find.text('Tijdlijn maken?'), findsOneWidget);
      expect(find.textContaining('Volgorde: Wanneer'), findsOneWidget);
      expect(find.textContaining('Gebeurtenis: Feit'), findsOneWidget);
      expect(
        find.textContaining(
          '1 markeringen hebben geen herkenbare volgordewaarde. Ze blijven zichtbaar.',
        ),
        findsOneWidget,
      );
      expect(find.text('Huidige volgorde behouden'), findsOneWidget);
      expect(find.text('Sorteren en tijdlijn maken'), findsOneWidget);

      await tester.tap(find.text('Sorteren en tijdlijn maken'));
      await tester.pumpAndSettle();
      expect(find.text('Waarden bekijken'), findsOneWidget);
      await tester.tap(find.text('Sorteren toepassen'));
      await tester.pumpAndSettle();
      final markdown = MarkdownQuillCodec.markdownFromDocument(
        controller.document,
      );
      expect(markdown, contains('<!-- timeline -->'));
      expect(markdown.indexOf('12:02'), lessThan(markdown.indexOf('13:41')));
    },
  );

  testWidgets('aandachtspunten kunnen vóór sorteren per rij worden bekeken', (
    tester,
  ) async {
    const table = '''
| Tijd | Feit |
| --- | --- |
| 13:41 | Laat |
| onbekend | Geen exact tijdstip |
| 12:02 | Vroeg |
''';
    await pumpEditor(tester, markdown: table);
    await tester.showKeyboard(find.widgetWithText(TextField, 'Tijd'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byTooltip('Sorteren als…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tijd').last);
    await tester.tap(find.text('Oplopend'));
    await tester.pumpAndSettle();

    expect(find.text('Waarden bekijken'), findsOneWidget);
    await tester.tap(find.text('Waarden bekijken'));
    await tester.pumpAndSettle();
    expect(find.text('Niet-herkende waarden'), findsOneWidget);
    expect(find.textContaining('Rij 2: onbekend'), findsOneWidget);

    await tester.tap(find.text('Sluiten'));
    await tester.pumpAndSettle();
    expect(find.text('Sorteren toepassen'), findsOneWidget);
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
  });

  testWidgets('Sorteren als laat type en richting expliciet kiezen', (
    tester,
  ) async {
    const table = '''
| Fase | Feit |
| --- | --- |
| 10 | Tien |
| 2 | Twee |
''';
    await pumpEditor(tester, markdown: table);
    await tester.showKeyboard(find.widgetWithText(TextField, 'Fase'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byTooltip('Sorteren als…'));
    await tester.pumpAndSettle();

    expect(find.text('Automatisch'), findsOneWidget);
    expect(find.text('Tekst'), findsOneWidget);
    expect(find.text('Getal'), findsOneWidget);
    expect(find.text('Datum'), findsOneWidget);
    expect(find.text('Tijd'), findsWidgets);
    expect(find.text('Oplopend'), findsOneWidget);
    expect(find.text('Aflopend'), findsOneWidget);
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
  });
}
