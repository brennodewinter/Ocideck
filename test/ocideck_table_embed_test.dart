// De `x-embed-ocideck-table` in de visuele editor: toont de gemarkeerde
// contracttabel mét zijn badge, en schrijft een celbewerking terug mét de
// marker erbij — zonder de markerregels als losse tekst te lekken.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor_theme.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';

void main() {
  const source = '''
Een alinea vooraf.

<!-- ocideck:risks v1 id=hoofd method=fmea rev=1 next=2 cols=id,failure,s_b -->
| ID | Faalwijze | S b |
|---|---|---|
| R-001 | Sensor valt uit | 7 |
''';

  Future<QuillController> pumpEditor(
    WidgetTester tester, [
    String body = source,
  ]) async {
    final controller = QuillController(
      document: MarkdownQuillCodec.documentFromMarkdown(body),
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
          ...GlobalMaterialLocalizations.delegates,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 600,
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

  testWidgets('badge + tabel zichtbaar, markerregel niet als tekst', (
    tester,
  ) async {
    await pumpEditor(tester);

    expect(find.textContaining('Risicoregister'), findsOneWidget);
    expect(find.textContaining('Sensor valt uit'), findsWidgets);
    // De marker is drager, geen inhoud.
    expect(find.textContaining('<!-- ocideck:risks'), findsNothing);
  });

  testWidgets('loskoppelen maakt een gewone tabel van de momentopname', (
    tester,
  ) async {
    final controller = await pumpEditor(tester);

    await tester.tap(find.textContaining('Marker verwijderen'));
    await tester.pump();

    final terug = MarkdownQuillCodec.markdownFromDocument(controller.document);
    expect(terug, isNot(contains('<!-- ocideck:risks')));
    expect(terug, contains('| R-001 | Sensor valt uit | 7 |'));
    expect(terug, contains('Een alinea vooraf.'));
  });

  testWidgets('verversen herbouwt een gekoppelde weergave uit de bron', (
    tester,
  ) async {
    const viewSource = '''
<!-- ocideck:risks v1 id=hoofd method=fmea rev=3 next=4 cols=id,failure,s_b,s_n -->
| ID | Faalwijze | S b | S n |
|---|---|---|---|
| R-1 | Sensor valt uit | 7 | 3 |
| R-2 | Kabel breekt | 5 | 1 |

<!-- ocideck:view v1 source=hoofd projection=netto gen=1 cols=id,failure,s_n -->
| ID | Faalwijze | S n |
|---|---|---|
| R-1 | VERLOPEN | 9 |
''';
    final controller = QuillController(
      document: MarkdownQuillCodec.documentFromMarkdown(viewSource),
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
          ...GlobalMaterialLocalizations.delegates,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 600,
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

    await tester.tap(find.textContaining('Verversen'));
    await tester.pump();

    final terug = MarkdownQuillCodec.markdownFromDocument(controller.document);
    expect(terug, contains('gen=3'));
    expect(terug, isNot(contains('VERLOPEN')));
    // De projectie toont id + faalwijze + alleen S n uit de bron.
    expect(terug, contains('| R-2 | Kabel breekt | 1 |'));
    // De brontabel zelf bleef onaangeroerd.
    expect(terug, contains('| R-1 | Sensor valt uit | 7 | 3 |'));
  });

  testWidgets('berekening toevoegen schrijft een calc-marker en rekent', (
    tester,
  ) async {
    const calcSource = '''
<!-- ocideck:risks v1 id=hoofd method=fmea rev=1 next=2 cols=id,failure,s_b,x-prio -->
| ID | Faalwijze | S b | Prio |
|---|---|---|---|
| R-001 | Sensor valt uit | 7 |  |
''';
    final controller = await pumpEditor(tester, calcSource);

    await tester.tap(find.textContaining('Berekening'));
    await tester.pumpAndSettle();
    expect(find.text('Berekening toevoegen'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('x-prio').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      's_b * 2',
    );
    await tester.pump();
    await tester.tap(find.text('Opslaan'));
    await tester.pumpAndSettle();

    final terug = MarkdownQuillCodec.markdownFromDocument(controller.document);
    expect(terug, contains('<!-- ocideck:calc col=x-prio expr="s_b * 2" -->'));
    // De kolom materialiseert meteen: 7 * 2 = 14.
    expect(terug, contains('| 14 |'));
  });

  testWidgets('gekoppelde weergave maken voegt een view-marker toe', (
    tester,
  ) async {
    final controller = await pumpEditor(tester);

    await tester.tap(find.textContaining('Gekoppelde weergave'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Netto'));
    await tester.pumpAndSettle();

    final terug = MarkdownQuillCodec.markdownFromDocument(controller.document);
    expect(
      terug,
      contains('<!-- ocideck:view v1 source=hoofd projection=netto'),
    );
  });

  testWidgets('als risicoregister markeren mappt kolommen expliciet', (
    tester,
  ) async {
    const plain = '''
Een alinea vooraf.

| ID | Faalwijze | Ernst |
|---|---|---|
| A | Sensor valt uit | 7 |
''';
    final controller = await pumpEditor(tester, plain);

    await tester.tap(find.textContaining('Als risicoregister markeren'));
    await tester.pumpAndSettle();
    expect(find.text('Tabel als risicoregister markeren'), findsOneWidget);

    // Methode staat op FMEA; wijs 'Ernst' toe aan de bruto-S.
    await tester.tap(find.byType(DropdownButton<String?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('id').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String?>).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('s_b').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Markeren'));
    await tester.pumpAndSettle();

    final terug = MarkdownQuillCodec.markdownFromDocument(controller.document);
    expect(terug, contains('<!-- ocideck:risks v1'));
    expect(terug, contains('method=fmea'));
  });
}
