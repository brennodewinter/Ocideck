import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor_theme.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';

/// De echte proef voor invullen-in-de-tabel: niet de losse cel-widget, maar de
/// tabel zoals hij in de visuele editor staat. Daar leeft hij binnen een
/// Quill-document, en dat vangt normaal élke toetsaanslag af. Typt de cel toch
/// in zichzelf, en komt het resultaat als GFM-tabel terug in de Markdown-bron?
void main() {
  const source = '''
Een alinea vooraf.

| Naam | Rol |
|------|-----|
| Aap | Tester |
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
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 800,
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

  testWidgets('de tabel in de visuele editor is ter plekke invulbaar', (
    tester,
  ) async {
    await pumpEditor(tester);
    // Vier cellen (2×2) als tekstveld binnen de gerenderde tabel — geen
    // dialoog, geen losse formulierrij.
    expect(find.byType(Table), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(4));
  });

  testWidgets('typen in een cel landt in de Markdown-bron als GFM-tabel', (
    tester,
  ) async {
    final controller = await pumpEditor(tester);

    await tester.enterText(find.byType(TextField).at(2), 'Aapje');
    await tester.pump();

    final markdown = MarkdownQuillCodec.markdownFromDocument(
      controller.document,
    );
    expect(markdown, contains('| Aapje | Tester |'));
    expect(
      markdown,
      contains('Een alinea vooraf.'),
      reason: 'de rest van het document blijft ongemoeid',
    );
  });

  testWidgets('de alinea buiten de tabel blijft gewoon typen', (tester) async {
    final controller = await pumpEditor(tester);

    // De tabel mag het document niet gijzelen: tekst buiten de tabel gaat nog
    // steeds naar het Quill-document zelf.
    controller.replaceText(
      0,
      0,
      'Nieuw. ',
      const TextSelection.collapsed(offset: 7),
    );
    await tester.pump();

    final markdown = MarkdownQuillCodec.markdownFromDocument(
      controller.document,
    );
    expect(markdown, contains('Nieuw. Een alinea vooraf.'));
    expect(markdown, contains('| Aap | Tester |'));
  });
}
