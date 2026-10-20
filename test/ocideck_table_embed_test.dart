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

  Future<QuillController> pumpEditor(WidgetTester tester) async {
    final controller = QuillController(
      document: MarkdownQuillCodec.documentFromMarkdown(source),
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
}
