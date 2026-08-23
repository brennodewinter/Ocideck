import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  Widget harness(DocumentNotifier notifier) => ProviderScope(
    overrides: [documentProvider.overrideWith((ref) => notifier)],
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

  test('een leeg bestand is regel 1, elke newline opent de volgende', () {
    expect(documentSourceLineCount(''), 1);
    expect(documentSourceLineCount('kop'), 1);
    expect(documentSourceLineCount('kop\n'), 2);
    expect(documentSourceLineCount('# Kop\n\nTekst.'), 3);
  });

  test('de nummerkolom groeit mee met het aantal cijfers', () {
    expect(documentSourceGutterWidth(9), 36);
    expect(documentSourceGutterWidth(99), 36);
    expect(documentSourceGutterWidth(100), 36);
    expect(documentSourceGutterWidth(1000), 44);
  });

  testWidgets('Bron toont regelnummers die niet in de bron belanden', (
    tester,
  ) async {
    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('# Kop\n\nTekst.'));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    expect(find.byKey(const Key('document-source-gutter')), findsNothing);

    await tester.tap(find.text('Bron'));
    await tester.pump();

    expect(find.byKey(const Key('document-source-gutter')), findsOneWidget);
    expect(find.byKey(const Key('document-source-line-1')), findsOneWidget);
    expect(find.byKey(const Key('document-source-line-3')), findsOneWidget);
    expect(find.byKey(const Key('document-source-line-4')), findsNothing);

    await tester.enterText(find.byType(TextField), 'een\ntwee');
    await tester.pump();

    expect(n.currentState.document!.source, 'een\ntwee');
    expect(find.byKey(const Key('document-source-line-2')), findsOneWidget);
    expect(find.byKey(const Key('document-source-line-3')), findsNothing);
  });
}
