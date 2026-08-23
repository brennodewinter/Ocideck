import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor_theme.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:ocideck/widgets/reader/writing_page_breaks.dart';

/// Een pagina-einde in de schrijfstand is alleen iets waard als het op dezelfde
/// plek valt als in de druk. Dat lukt alleen wanneer schrijven en weergeven
/// dezelfde hoogte opleveren — dus meet dat, in plaats van het te hopen.
///
/// Vóór de documenttypografie was het schrijfvlak 1,29x compacter: over drie
/// A4-pagina's liep de schrijfstand daarmee een heel vel achter.
void main() {
  // Een document van pagina's, niet van een handvol regels: pas op die schaal
  // zie je of een afwijking meeloopt met de lengte of alleen aan de randen zit.
  final markdown = [
    '# Een kop',
    for (var i = 0; i < 30; i++)
      'Alinea $i met genoeg tekst om over meerdere regels te lopen wanneer de '
          'kolom de breedte van een A4-tekstvlak heeft, zodat de vergelijking '
          'iets voorstelt.',
  ].join('\n\n');

  testWidgets('schrijfvlak en documentweergave leveren dezelfde hoogte', (
    tester,
  ) async {
    const width = 643.0;
    await tester.binding.setSurfaceSize(const Size(900, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: DocumentMarkdownView(markdown, maxTextWidth: null),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final readerHeight = tester
        .getSize(find.byType(DocumentMarkdownView))
        .height;

    final controller = QuillController(
      document: MarkdownQuillCodec.documentFromMarkdown(markdown),
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(controller.dispose);
    final editorKey = GlobalKey<EditorState>();
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
            width: width,
            height: 1800,
            child: WysiwygNotesField(
              controller: controller,
              scrollController: scroll,
              focusNode: focus,
              editorKey: editorKey,
              editorTheme: MarkdownEditorTheme.documentSurface(
                scheme: const ColorScheme.light(),
                documentTypography: true,
              ),
              hintText: '',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final heights = writingBlockHeights(editorKey.currentState?.renderEditor);
    final editorHeight = heights.fold<double>(0, (a, b) => a + b);

    // Tien procent speling: de twee tekenaars zijn niet identiek (Quill zet
    // zijn regels zelf), maar een afwijking die tot een heel vel oploopt mag
    // niet terugkomen.
    expect(
      editorHeight / readerHeight,
      closeTo(1.0, 0.02),
      reason:
          'schrijfvlak ${editorHeight.toStringAsFixed(0)}px tegenover weergave '
          '${readerHeight.toStringAsFixed(0)}px — dan valt het pagina-einde in '
          'de schrijfstand op een andere plek dan in de druk',
    );
  });
}
