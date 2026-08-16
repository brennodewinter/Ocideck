import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor.dart';

/// Feature 2: de visuele editor gebruikt de instelbare
/// `documentMaxWidth` — bij een waarde wordt de `ConstrainedBox`-grens
/// gerespecteerd, bij `null` vult het veld de beschikbare breedte.
void main() {
  const theme = MarkdownEditorTheme(
    surface: Colors.white,
    text: Colors.black,
    hint: Colors.grey,
    link: Colors.blue,
    heading: Colors.black,
    subheading: Colors.black54,
    codeBackground: Color(0xFFF1F5F9),
    toolbarIcon: Colors.black,
    accent: Colors.blue,
    border: Colors.grey,
  );

  testWidgets('documentMaxWidth = 1100 beperkt de schrijfbreedte tot 1100px', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = TextEditingController(text: 'Test');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownNotesEditor(
            controller: controller,
            editorTheme: theme,
            hintText: '',
            surfaceStyle: NotesSurfaceStyle.document,
            documentMaxWidth: 1100,
            showToolbar: false,
            showModeToggle: false,
          ),
        ),
      ),
    );

    final constrained = find.byWidgetPredicate(
      (w) =>
          w is ConstrainedBox &&
          w.constraints.maxWidth == 1100 &&
          w.child is DecoratedBox,
    );
    expect(constrained, findsOneWidget);
  });

  testWidgets(
    'documentMaxWidth = null vult de beschikbare breedte (geen smalle beperking)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = TextEditingController(text: 'Test');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownNotesEditor(
              controller: controller,
              editorTheme: theme,
              hintText: '',
              surfaceStyle: NotesSurfaceStyle.document,
              documentMaxWidth: null,
              showToolbar: false,
              showModeToggle: false,
            ),
          ),
        ),
      );

      // Bij null is maxWidth double.infinity — geen smalle beperking.
      // Er zijn meerdere ConstrainedBox-widgets in de boom; de documentpagina
      // mag niet meer de oude 860-beperking hebben.
      final oldConstraint = find.byWidgetPredicate(
        (w) =>
            w is ConstrainedBox &&
            w.constraints.maxWidth == 860 &&
            w.child is DecoratedBox,
      );
      expect(
        oldConstraint,
        findsNothing,
        reason: 'De oude 860px-beperking mag niet meer voorkomen bij null.',
      );
      final infinityConstraint = find.byWidgetPredicate(
        (w) =>
            w is ConstrainedBox &&
            w.constraints.maxWidth == double.infinity &&
            w.child is DecoratedBox,
      );
      expect(infinityConstraint, findsWidgets);
    },
  );
}
