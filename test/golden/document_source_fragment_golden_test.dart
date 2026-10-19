@Tags(['golden'])
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Een stuk bron dat de rijke-tekstlaag niet verliesvrij draagt (#2463):
/// de golden legt vast dat het als één monospace bronvlak met het bijschrift
/// "Bron" tussen de gewone tekst staat — en dat de tekst eromheen gewoon
/// visueel schrijfbaar blijft.
void main() {
  testWidgets('bronblok in de visuele editor', (tester) async {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
    const size = Size(900, 620);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final notifier = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse(
          'Eerste alinea blijft visueel.\n\n'
          '<!-- marp: true -->\n\n'
          'Tweede alinea blijft ook visueel.',
        ),
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [documentProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
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
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(QuillEditor),
      matchesGoldenFile('goldens/document_source_fragment.png'),
    );
  });
}
