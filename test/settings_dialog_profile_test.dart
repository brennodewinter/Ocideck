import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:ocideck/widgets/document_page_chrome.dart';
import 'package:ocideck/widgets/theme_profile_logo.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dekking voor `settings_dialog_profile.dart` — de stijlprofiel-kiezer en
/// de actieknoppen (nieuw, standaard laden, exporteren, importeren,
/// verwijderen). De smoke-test opent het dialoog en wandelt door de tabbladen,
/// maar interageert niet met de profiel-kiezer.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> openAppearanceTab(
    WidgetTester tester, {
    Size surfaceSize = const Size(1500, 1100),
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
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

  testWidgets('het profiel-menu toont de beschikbare profielen', (
    tester,
  ) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    // Het dropdown-icoon opent het popup-menu met profielnamen.
    await tester.tap(find.byIcon(Icons.arrow_drop_down).first);
    await tester.pumpAndSettle();

    // Het standaardprofiel heet "Standaard" en moet in de lijst staan.
    expect(find.text('Standaard'), findsWidgets);
  });

  testWidgets('het tekstveld bijt de profielnaam bij', (tester) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    // Typ een nieuwe naam in het tekstveld.
    await tester.enterText(find.byType(TextField).first, 'Mijn profiel');
    await tester.pump();

    // De naam is nu in het veld zichtbaar.
    expect(find.text('Mijn profiel'), findsOneWidget);
  });

  testWidgets('"Standaardprofiel laden" zet het profiel terug', (tester) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    // Druk op het reset-icoon (restart_alt).
    await tester.tap(find.byIcon(Icons.restart_alt).first);
    await tester.pumpAndSettle();

    // Het profiel is teruggezet — geen crash, dialoog staat nog.
    expect(find.byType(SettingsDialog), findsOneWidget);
  });

  testWidgets('"Nieuw profiel" maakt een profiel aan', (tester) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    final before = container.read(settingsProvider).themeProfiles.length;
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();
    final after = container.read(settingsProvider).themeProfiles.length;

    expect(after, greaterThan(before));
  });

  testWidgets('"Profiel verwijderen" is ingeschakeld bij meerdere profielen', (
    tester,
  ) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    // Maak een tweede profiel aan zodat de verwijderknop actief is.
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    final btn = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.delete_outline).first,
    );
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('Vigilis-profiel kleurt de documentpreview direct', (
    tester,
  ) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    await tester.tap(find.byKey(const Key('style-profile-Vigilis')));
    await tester.pump();

    final rule = tester.widget<Container>(
      find.byKey(const Key('document-style-accent-rule')),
    );
    final decorationColor = rule.color;
    expect(
      decorationColor,
      AppTheme.parseHexColor(ThemeProfile.vigilis.accentColor),
    );
    expect(find.byKey(const Key('document-style-preview')), findsOneWidget);
  });

  testWidgets('document en presentatie hebben elk een echte preview', (
    tester,
  ) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    expect(find.byKey(const Key('document-style-preview')), findsOneWidget);
    expect(find.byKey(const Key('presentation-style-preview')), findsNothing);

    await tester.tap(find.byKey(const Key('style-surface-presentation')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('document-style-preview')), findsNothing);
    expect(find.byKey(const Key('presentation-style-preview')), findsOneWidget);
    expect(find.text('Opsommingsteken'), findsOneWidget);
    expect(find.text('Activatieduur'), findsOneWidget);
    expect(find.text('Logo positie'), findsOneWidget);
  });

  testWidgets('het gekozen logo staat naast de logokiezer', (tester) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    await tester.tap(find.byKey(const Key('style-profile-Vigilis')));
    await tester.tap(find.byKey(const Key('style-surface-presentation')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('style-logo-preview')), findsOneWidget);
  });

  testWidgets('document deelt standaard het presentatielogo en kan afwijken', (
    tester,
  ) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    await tester.tap(find.byKey(const Key('style-profile-Vigilis')));
    await tester.pumpAndSettle();

    final shared = tester.widget<SwitchListTile>(
      find.byKey(const Key('document-logo-shared')),
    );
    expect(shared.value, isTrue);
    expect(find.byKey(const Key('document-logo-preview')), findsNothing);
    expect(find.byKey(const Key('document-header-text')), findsOneWidget);
    expect(find.byType(DocumentChromeBand), findsWidgets);
    expect(find.text('Bestuurlijk rapport'), findsWidgets);
    expect(find.byKey(const Key('document-footer-text')), findsOneWidget);
    expect(find.byKey(const Key('document-page-number')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('document-logo-shared')));
    await tester.tap(find.byKey(const Key('document-logo-shared')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('document-logo-preview')), findsOneWidget);
  });

  testWidgets('document biedt koptekst, voettekst en paginanummers aan', (
    tester,
  ) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    expect(find.byKey(const Key('document-header-LibreKAT')), findsOneWidget);
    expect(find.byKey(const Key('document-footer-LibreKAT')), findsOneWidget);
    expect(find.byKey(const Key('document-page-numbers')), findsOneWidget);
    expect(find.byKey(const Key('document-logo-position')), findsOneWidget);
    expect(
      find.byKey(const Key('document-logo-size-LibreKAT')),
      findsOneWidget,
    );

    final header = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('document-header-LibreKAT')),
        matching: find.byType(TextField),
      ),
    );
    final footer = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('document-footer-LibreKAT')),
        matching: find.byType(TextField),
      ),
    );
    expect(header.maxLines, greaterThan(1));
    expect(footer.maxLines, greaterThan(1));
  });

  testWidgets(
    'meerregelige Markdown en documentlogomaat verversen de preview',
    (tester) async {
      final container = await openAppearanceTab(tester);
      addTearDown(container.dispose);

      final header = find.byKey(const Key('document-header-LibreKAT'));
      await tester.enterText(header, '**Vertrouwelijk**\nTweede regel');
      await tester.pump();
      expect(find.text('Vertrouwelijk\nTweede regel'), findsOneWidget);

      final size = find.byKey(const Key('document-logo-size-LibreKAT'));
      await tester.enterText(size, '240');
      await tester.pump();
      final chrome = tester
          .widgetList<DocumentChromeBand>(find.byType(DocumentChromeBand))
          .first;
      expect(chrome.profile.effectiveDocumentLogoSize, 240);
    },
  );

  testWidgets('een gekozen lokaal logo wordt als afbeelding getoond', (
    tester,
  ) async {
    final temp = Directory.systemTemp.createTempSync('style_logo_preview');
    addTearDown(() => temp.deleteSync(recursive: true));
    final logo = File('${temp.path}/logo.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=',
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: ThemeProfileLogo(
          profile: const ThemeProfile().copyWith(logoPath: logo.path),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
  });

  testWidgets('stijlbouwer splitst breed en stapelt smal', (tester) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    final wideEditor = tester.getTopLeft(
      find.byKey(const Key('document-style-editor')),
    );
    final widePreview = tester.getTopLeft(
      find.byKey(const Key('document-style-preview')),
    );
    expect(widePreview.dx, greaterThan(wideEditor.dx));

    await tester.binding.setSurfaceSize(const Size(700, 1000));
    await tester.pumpAndSettle();
    final narrowEditor = tester.getTopLeft(
      find.byKey(const Key('document-style-editor')),
    );
    final narrowPreview = tester.getTopLeft(
      find.byKey(const Key('document-style-preview')),
    );
    expect(narrowPreview.dy, greaterThan(narrowEditor.dy));
  });
}
