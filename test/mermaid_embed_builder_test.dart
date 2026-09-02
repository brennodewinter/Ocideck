// De mermaid-fence in de visuele editor (#1920): tekent de builder het diagram,
// en komt de fence er byte-gelijk weer uit?
//
// Vóór deze embed kende de codec geen mermaid en werd de fence een gewoon
// Quill-codeblok — de fence-scanner in markdown_visual_compatibility.dart slaat
// alles binnen een fence bewust over, dus de visuele modus ging wél open maar
// toonde als enige weergave de brontekst. `find.byType(DocMermaidView)` is
// daarom de dragende toets: onder `flutter test` is er geen WebView en valt die
// weergave zichtbaar terug op een codeblok, maar de wídget bewijst dat het
// diagrampad gekozen is en niet het codeblokpad.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/utils/mermaid_embed_syntax.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor_theme.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';
import 'package:ocideck/widgets/reader/doc_mermaid_view.dart';

void main() {
  const source = '''
Een alinea vooraf.

```mermaid
graph TD;
  A[Start] --> B{Keuze};
  B --> C[Klaar];
```

Een alinea erna.
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

  test('de fence reist als één embed door de codec', () {
    final document = MarkdownQuillCodec.documentFromMarkdown(source);
    final embeds = document.toDelta().toList().where(
      (op) =>
          op.data is Map &&
          (op.data! as Map).containsKey(EmbeddableMermaid.mermaidType),
    );
    expect(embeds, hasLength(1));
    // De embed draagt de héle fence, beide ```-regels inbegrepen: dat is wat de
    // terugweg verbatim wegschrijft.
    final data =
        (embeds.first.data! as Map)[EmbeddableMermaid.mermaidType] as String;
    expect(data, startsWith('```mermaid'));
    expect(data, endsWith('```'));
    expect(data, contains('B{Keuze}'));
  });

  testWidgets('de builder tekent de fence als diagram, niet als codeblok', (
    tester,
  ) async {
    await pumpEditor(tester);
    expect(find.byType(DocMermaidView), findsOneWidget);
  });

  testWidgets('typen naast het diagram laat de fence byte-gelijk', (
    tester,
  ) async {
    final controller = await pumpEditor(tester);

    controller.replaceText(
      'Een alinea vooraf.'.length,
      0,
      ' Erbij.',
      const TextSelection.collapsed(offset: 0),
    );
    await tester.pump();

    final terug = MarkdownQuillCodec.markdownFromDocument(controller.document);
    expect(terug, contains('Een alinea vooraf. Erbij.'));
    // De fence is onaangeroerd: geen ontsnapte leestekens, geen weggevallen
    // regels, geen herschreven accolades.
    expect(
      terug,
      contains(
        '```mermaid\n'
        'graph TD;\n'
        '  A[Start] --> B{Keuze};\n'
        '  B --> C[Klaar];\n'
        '```',
      ),
    );
  });

  test('een fence met een eigen %%{init}-directive blijft ongeschonden', () {
    const withInit = '''
```mermaid
%%{init: {"themeVariables": {"primaryColor": "#ff0"}}}%%
graph TD; A-->B;
```
''';
    final terug = MarkdownQuillCodec.markdownFromDocument(
      MarkdownQuillCodec.documentFromMarkdown(withInit),
    );
    // De rijke-tekstlaag escapet leestekens; een diagram is geen proza, dus de
    // directive moet er teken voor teken uitkomen zoals hij erin ging.
    expect(
      terug,
      contains('%%{init: {"themeVariables": {"primaryColor": "#ff0"}}}%%'),
    );
  });

  test('een gewoon codeblok blijft een codeblok', () {
    // De syntax mag alleen de mermaid-fence opeisen: een `dart`-fence hoort
    // gewoon door de standaardregel te gaan.
    final document = MarkdownQuillCodec.documentFromMarkdown(
      '```dart\nvoid main() {}\n```\n',
    );
    final embeds = document.toDelta().toList().where(
      (op) =>
          op.data is Map &&
          (op.data! as Map).containsKey(EmbeddableMermaid.mermaidType),
    );
    expect(embeds, isEmpty);
  });
}
