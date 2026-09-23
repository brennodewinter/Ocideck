import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show
        FlutterQuillLocalizations,
        QuillEditor,
        QuillToolbarToggleCheckListButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_until.dart';

/// Getypte Markdown aan het regelbegin wordt in de visuele stand meteen echte
/// opmaak: wie `- [ ] ` typte zag voorheen letterlijke brackets en had in de
/// werkbalk geen checklistknop.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  Future<DocumentNotifier> pumpEditor(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final notifier = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('Intro\n'));
    await tester.pumpWidget(
      ProviderScope(
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
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(QuillEditor), findsOneWidget);
    return notifier;
  }

  testWidgets('de werkbalk van de visuele stand heeft een checklistknop', (
    tester,
  ) async {
    await pumpEditor(tester);

    expect(find.byType(QuillToolbarToggleCheckListButton), findsOneWidget);
  });

  testWidgets('`- [ ] ` typen wordt een checklistitem, geen brackets', (
    tester,
  ) async {
    final notifier = await pumpEditor(tester);

    await tester.tap(find.byType(QuillEditor));
    await tester.pump();
    // Typ `- [ ] ` aan het begin van de eerste regel — zoals een gebruiker
    // die kale markdown invoert.
    tester
        .widget<WysiwygNotesField>(find.byType(WysiwygNotesField))
        .controller
        .replaceText(0, 0, '- [ ] ', const TextSelection.collapsed(offset: 6));
    await pumpUntil(
      tester,
      () => notifier.currentState.document?.body.startsWith('- [ ]') == true,
      reason: 'de getypte trigger werd nooit een checklistitem',
    );

    expect(notifier.currentState.document!.body, '- [ ] Intro');
  });

  testWidgets('een lijstknop omzetten schrijft `- [ ]` in de bron', (
    tester,
  ) async {
    final notifier = await pumpEditor(tester);

    await tester.tap(find.byType(QuillToolbarToggleCheckListButton));
    await pumpUntil(
      tester,
      () => notifier.currentState.document?.body.startsWith('- [ ]') == true,
      reason: 'de checklistknop bereikte de bron niet',
    );

    expect(notifier.currentState.document!.body, '- [ ] Intro');
  });
}
