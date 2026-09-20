import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De letterinstellingen van #2119 in het instellingenvenster: de kopletter op
/// het documentvlak en het gewenste lettertype op beide vlakken. Bewaakt dat
/// een keuze in het profiel landt (te zien aan de voorvertoning, die het
/// bewerkte profiel draagt), dat een lege naam de voorkeur wist, en dat een
/// naam die uit CSS kan breken niet verder komt dan een foutmelding.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SettingsDialog.show(
                  context,
                  initialSection: SettingsSection.presentation,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  }

  /// Het profiel zoals de bouwer het nu heeft: de documentvoorvertoning
  /// tekent ermee.
  ThemeProfile edited(WidgetTester tester) => tester
      .widget<DocumentMarkdownView>(find.byType(DocumentMarkdownView).first)
      .themeProfile!;

  Future<void> openSurface(WidgetTester tester, String surface) async {
    await tester.ensureVisible(find.byKey(Key('style-surface-$surface')));
    await tester.tap(find.byKey(Key('style-surface-$surface')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'de kopletter staat op het documentvlak en landt in het profiel',
    (tester) async {
      final container = await open(tester);
      addTearDown(container.dispose);
      await openSurface(tester, 'document');

      expect(find.byKey(const Key('document-heading-font')), findsOneWidget);
      expect(edited(tester).documentHeadingFontFamily, isNull);

      await tester.ensureVisible(
        find.byKey(const Key('document-heading-font-Georgia')),
      );
      await tester.tap(find.byKey(const Key('document-heading-font-Georgia')));
      await tester.pumpAndSettle();
      expect(edited(tester).documentHeadingFontFamily, 'Georgia');

      // Terug naar "zelfde als de tekst" wist het veld weer.
      await tester.ensureVisible(
        find.byKey(const Key('document-heading-font-body')),
      );
      await tester.tap(find.byKey(const Key('document-heading-font-body')));
      await tester.pumpAndSettle();
      expect(edited(tester).documentHeadingFontFamily, isNull);
    },
  );

  testWidgets('de gewenste kopletter wordt gesaneerd bewaard of geweigerd', (
    tester,
  ) async {
    final container = await open(tester);
    addTearDown(container.dispose);
    await openSurface(tester, 'document');

    final field = find.byKey(
      const Key('preferred-document-heading-font-family'),
    );
    await tester.ensureVisible(field);
    await tester.enterText(field, '  Aptos Display ');
    await tester.pumpAndSettle();
    expect(edited(tester).preferredDocumentHeadingFontFamily, 'Aptos Display');

    // Een naam met een breekpunt komt niet in het profiel; de vorige blijft.
    await tester.enterText(field, "Aptos'; }");
    await tester.pumpAndSettle();
    expect(edited(tester).preferredDocumentHeadingFontFamily, 'Aptos Display');
    expect(find.textContaining('Alleen letters'), findsOneWidget);

    await tester.enterText(field, '');
    await tester.pumpAndSettle();
    expect(edited(tester).preferredDocumentHeadingFontFamily, isNull);
    expect(find.textContaining('Alleen letters'), findsNothing);
  });

  testWidgets('het gewenste lettertype staat bij het lettertype zelf', (
    tester,
  ) async {
    final container = await open(tester);
    addTearDown(container.dispose);

    final field = find.byKey(const Key('preferred-font-family'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Aptos Light');
    await tester.pumpAndSettle();
    await openSurface(tester, 'document');
    expect(edited(tester).preferredFontFamily, 'Aptos Light');
    expect(edited(tester).exportFontFamily, 'Aptos Light');
  });
}
