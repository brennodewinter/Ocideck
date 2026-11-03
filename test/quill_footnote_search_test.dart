import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor.dart';

void main() {
  testWidgets('Quill-voetnootnummer vormt geen eigen zoektreffer', (
    tester,
  ) async {
    final controller = TextEditingController(
      text: 'Een noot[^a].\n\n[^a]: toelichting',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => MarkdownNotesEditor(
              controller: controller,
              editorTheme: MarkdownEditorTheme.documentSurface(
                scheme: Theme.of(context).colorScheme,
              ),
              hintText: '',
              showToolbar: false,
              showModeToggle: false,
              findQuery: '1',
              findMatchIndex: 0,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('1'),
      findsWidgets,
      reason: 'de gegenereerde cijfers blijven zichtbaar',
    );
    expect(find.byKey(const Key('document-search-highlight')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
