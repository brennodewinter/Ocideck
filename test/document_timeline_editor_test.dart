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
}
