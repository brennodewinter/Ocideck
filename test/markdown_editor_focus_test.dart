import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor.dart';

Widget _testApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
      FlutterQuillLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

MarkdownNotesEditor _editor({
  required TextEditingController controller,
  required FocusNode focusNode,
  required NotesEditorMode mode,
}) {
  return MarkdownNotesEditor.legacy(
    controller: controller,
    focusNode: focusNode,
    baseStyle: const TextStyle(fontSize: 16, color: Colors.black),
    linkColor: Colors.blue,
    hintText: 'Notities',
    initialMode: mode,
    showModeToggle: false,
  );
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('raw markdown toolbar returns focus to the editor', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'tekst');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _testApp(
        _editor(
          controller: controller,
          focusNode: focusNode,
          mode: NotesEditorMode.markdown,
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.tap(find.byTooltip('Vet'));
    await tester.pump();
    await tester.pump();

    expect(controller.text, '**tekst**');
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('visual toolbar returns focus to the editor', (tester) async {
    final controller = TextEditingController(text: 'tekst');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _testApp(
        _editor(
          controller: controller,
          focusNode: focusNode,
          mode: NotesEditorMode.visual,
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.tap(find.byIcon(Icons.format_bold).first);
    await tester.pump();
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);
  });
}
