import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  Widget harness(DocumentNotifier notifier) => ProviderScope(
    overrides: [documentProvider.overrideWith((_) => notifier)],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const DocumentEditorScreen(),
    ),
  );

  Future<DocumentNotifier> pumpLargeDocument(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tables = List.generate(
      80,
      (i) => '| Kolom | Waarde |\n| --- | --- |\n| Rij $i | gelijk |',
    ).join('\n\n');
    final notifier = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('Voorwoord.\n\n$tables'));
    await tester.pumpWidget(harness(notifier));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    return notifier;
  }

  testWidgets('een aanslag herbouwt niet het hele documentscherm', (
    tester,
  ) async {
    final notifier = await pumpLargeDocument(tester);
    final before = tester.widget<MarkdownNotesEditor>(
      find.byType(MarkdownNotesEditor),
    );
    final quill = tester
        .widget<WysiwygNotesField>(find.byType(WysiwygNotesField))
        .controller;

    quill.replaceText(0, 0, 'x', const TextSelection.collapsed(offset: 1));
    await tester.pump();

    expect(notifier.currentState.document!.body, startsWith('xVoorwoord.'));
    expect(
      tester.widget<MarkdownNotesEditor>(find.byType(MarkdownNotesEditor)),
      same(before),
      reason: 'de providerupdate mag het hele schrijfvlak niet herbouwen',
    );
  });

  testWidgets('macOS-compositie schrijft één aanslag precies één keer', (
    tester,
  ) async {
    final notifier = await pumpLargeDocument(tester);
    final raw = tester.state<QuillRawEditorState>(find.byType(QuillRawEditor));
    raw.requestKeyboard();
    await tester.pump();
    final current = raw.currentTextEditingValue!;
    final composing = TextEditingValue(
      text: 'x${current.text}',
      selection: const TextSelection.collapsed(offset: 1),
      composing: const TextRange(start: 0, end: 1),
    );

    raw.updateEditingValue(composing);
    raw.updateEditingValue(composing.copyWith(composing: TextRange.empty));
    await tester.pump();

    expect(notifier.currentState.document!.body, startsWith('xVoorwoord.'));
    expect(notifier.currentState.document!.body, isNot(startsWith('xx')));
  });
}
