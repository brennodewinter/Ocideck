import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/reader/paged_document_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Vergroot tot schermbreedte": één klik zet de zoom zo dat de tekstkolom
/// of het vel het scherm vult — geen stapjes meer.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  test('documentFitWidthZoom: vult, klemt, en zwijgt als het al past', () {
    // 900 beschikbaar, kolom 600 → 150%.
    expect(documentFitWidthZoom(availablePx: 900, basePx: 600), 1.5);
    // Over de grens heen wordt op de zoomlimiet geklemd, niet afgewezen.
    expect(
      documentFitWidthZoom(availablePx: 9000, basePx: 600),
      kDocumentEditorZoomMax,
    );
    // Geen vaste kolom of geen ruimte → geen knop.
    expect(documentFitWidthZoom(availablePx: 900, basePx: null), isNull);
    expect(documentFitWidthZoom(availablePx: 900, basePx: 0), isNull);
    expect(documentFitWidthZoom(availablePx: 0, basePx: 600), isNull);
    // Al breder dan het scherm → niets te vergroten; uitverkleinen kiest
    // de gebruiker zelf.
    expect(documentFitWidthZoom(availablePx: 500, basePx: 600), isNull);
  });

  testWidgets('de fit-knop zet de zoom op schermbreedte', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final notifier = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse('# Kop\n\nTekst met een flinke lengte.\n'),
      );
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

    final container = ProviderScope.containerOf(
      tester.element(find.byType(DocumentEditorScreen)),
    );
    expect(container.read(settingsProvider).documentEditorZoom, 1.0);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vergroot tot schermbreedte'));
    await tester.pump();
    expect(
      container.read(settingsProvider).documentEditorZoom,
      greaterThan(1.1),
    );
  });
}
