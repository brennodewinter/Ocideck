import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/utils/visual_markdown_flush.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor.dart';

/// #2621: tien aanslagen achter elkaar worden één omzetting, en een flush
/// (opslaan) neemt ze allemaal mee zonder op de timer te wachten.
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

  testWidgets('tien snelle aanslagen worden één omzetting', (tester) async {
    final controller = TextEditingController(text: 'Hallo');
    addTearDown(controller.dispose);
    final flush = VisualMarkdownFlush();
    var writes = 0;
    var last = controller.text;
    controller.addListener(() {
      if (controller.text == last) return;
      last = controller.text;
      writes++;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MarkdownNotesEditor(
          controller: controller,
          editorTheme: theme,
          hintText: '',
          showToolbar: false,
          showModeToggle: false,
          pendingFlush: flush,
        ),
      ),
    );
    await tester.pump();

    final quill = tester
        .widget<QuillEditor>(find.byType(QuillEditor))
        .controller;
    final start = quill.selection.isValid ? quill.selection.baseOffset : 0;
    for (var i = 0; i < 10; i++) {
      final at = start + i;
      quill.replaceText(at, 0, '$i', TextSelection.collapsed(offset: at + 1));
    }
    await tester.pump();
    expect(writes, 0, reason: 'de omzetting wacht de pauze af');

    flush.flush();
    expect(writes, 1, reason: 'tien aanslagen delen één omzetting');
    expect(controller.text, contains('0123456789'));
  });

  testWidgets('een cursorbeweging schrijft de bron niet opnieuw', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Hallo');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MarkdownNotesEditor(
          controller: controller,
          editorTheme: theme,
          hintText: '',
          showToolbar: false,
          showModeToggle: false,
        ),
      ),
    );
    await tester.pump();
    final quill = tester
        .widget<QuillEditor>(find.byType(QuillEditor))
        .controller;
    quill.updateSelection(
      const TextSelection.collapsed(offset: 2),
      ChangeSource.local,
    );
    await tester.pump();
    await tester.pump(kVisualMarkdownFlushDelay);
    expect(controller.text, 'Hallo');
  });
}
