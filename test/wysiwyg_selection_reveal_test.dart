import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor_theme.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';

/// #2906: een verlengde selectie moet het bewogen eind in beeld houden.
///
/// Quill 11.6.0 (`RenderEditor.getOffsetToRevealCursor`) toont bij een
/// niet-ingeklapte selectie alleen bij `DragTextSelection` de bewogen kant;
/// elke andere niet-ingeklapte selectie — toetsenbord-verlenging, zoekmatch,
/// programmatisch — pakt `endpoints.first`, het document-eerste punt. Zolang
/// het anker zichtbaar is, scrolt er niets: de caret verdwijnt onder de rand.
void main() {
  Future<(QuillController, ScrollController)> pumpField(
    WidgetTester tester, {
    required GlobalKey<EditorState> editorKey,
  }) async {
    final editorTheme = MarkdownEditorTheme.documentSurface(
      scheme: const ColorScheme.light(),
    );
    final controller = QuillController(
      document: MarkdownQuillCodec.documentFromMarkdown(
        List.generate(200, (i) => 'regel ${i + 1}').join('\n\n'),
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(controller.dispose);
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
            width: 600,
            height: 300,
            child: WysiwygNotesField(
              controller: controller,
              scrollController: scroll,
              focusNode: FocusNode(),
              editorTheme: editorTheme,
              hintText: '',
              expand: true,
              editorKey: editorKey,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (controller, scroll);
  }

  testWidgets(
    'een programmatisch verlengde selectie houdt het extent-eind in beeld',
    (tester) async {
      final editorKey = GlobalKey<EditorState>();
      final (controller, scroll) = await pumpField(
        tester,
        editorKey: editorKey,
      );
      expect(scroll.offset, 0);

      // Zoals Shift+Einde: selecteer van het begin tot vlak voor het einde.
      controller.updateSelection(
        TextSelection(
          baseOffset: 0,
          extentOffset: controller.document.length - 5,
        ),
        ChangeSource.local,
      );
      await tester.pumpAndSettle();

      expect(
        scroll.offset,
        greaterThan(0),
        reason: 'het bewogen selectie-eind hoort in beeld gebracht te worden',
      );
    },
  );

  testWidgets('een omhoog verlengde selectie toont het extent-eind', (
    tester,
  ) async {
    final editorKey = GlobalKey<EditorState>();
    final (controller, scroll) = await pumpField(tester, editorKey: editorKey);

    // Eerst omlaag, dan de selectie omhoog verlengen tot boven het beeld.
    controller.updateSelection(
      TextSelection.collapsed(offset: controller.document.length - 5),
      ChangeSource.local,
    );
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));

    controller.updateSelection(
      TextSelection(
        baseOffset: controller.document.length - 5,
        extentOffset: 0,
      ),
      ChangeSource.local,
    );
    await tester.pumpAndSettle();

    expect(
      scroll.offset,
      lessThan(scroll.position.maxScrollExtent),
      reason: 'het omhoog bewogen selectie-eind hoort in beeld te komen',
    );
  });
}
