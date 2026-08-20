import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:ocideck/widgets/document_page_chrome.dart';
import 'package:ocideck/widgets/slides/inline_markdown.dart';
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

  /// De stijlbouwer opent op het algemene vlak — daar staat wat beide vlakken
  /// delen. Wie het documentvlak wil toetsen, moet er dus eerst heen.
  Future<void> openSurface(WidgetTester tester, String surface) async {
    await tester.tap(find.byKey(Key('style-surface-$surface')));
    await tester.pumpAndSettle();
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
    await openSurface(tester, 'document');

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

  testWidgets('profielkaart toont het logo en zonder logo een fallback', (
    tester,
  ) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    final vigilis = find.byKey(const Key('style-profile-Vigilis'));
    expect(
      find.descendant(of: vigilis, matching: find.byType(ThemeProfileLogo)),
      findsOneWidget,
    );
    final standard = find.byKey(const Key('style-profile-Standaard'));
    expect(
      find.descendant(
        of: standard,
        matching: find.byIcon(Icons.description_outlined),
      ),
      findsOneWidget,
    );
    final selectedLabel = find.descendant(
      of: find.byKey(const Key('style-profile-LibreKAT')),
      matching: find.text('LibreKAT'),
    );
    final paragraph = tester.renderObject<RenderParagraph>(selectedLabel);
    expect(
      paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 8),
      ),
      hasLength(1),
    );
  });

  testWidgets('elk vlak heeft zijn eigen voorvertoning', (tester) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    // Het algemene vlak staat voorop: dat is wat beide vlakken delen.
    expect(find.byKey(const Key('general-style-preview')), findsOneWidget);
    expect(find.byKey(const Key('document-style-preview')), findsNothing);
    expect(find.byKey(const Key('presentation-style-preview')), findsNothing);
    expect(find.text('Geldt voor documenten en presentaties'), findsOneWidget);

    await openSurface(tester, 'document');
    expect(find.byKey(const Key('document-style-preview')), findsOneWidget);
    expect(find.byKey(const Key('general-style-preview')), findsNothing);
    expect(find.text('Alleen voor documenten'), findsOneWidget);

    await openSurface(tester, 'presentation');
    expect(find.byKey(const Key('presentation-style-preview')), findsOneWidget);
    expect(find.byKey(const Key('document-style-preview')), findsNothing);
    expect(find.text('Alleen voor presentaties'), findsOneWidget);
  });

  // De scheiding zelf: geen veld staat op twee vlakken, en geen vlak draagt een
  // veld van een ander. Dit is de test die terugvalt op het oude gedrag betrapt
  // — daar stonden de basiskleuren én in het document- én in het
  // presentatievlak, met een schakelaar die moest uitleggen wat waar gold.
  testWidgets('elk stijlveld staat op precies één vlak', (tester) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    // Algemeen: lettertype, basiskleuren, checklist, tabel, broncode, severity.
    expect(find.text('Opsommingsteken'), findsOneWidget);
    expect(find.text('Tabelstijl'), findsOneWidget);
    expect(find.text('Syntaxkleuring'), findsOneWidget);
    // …en niets dat maar op één vlak bestaat.
    expect(find.textContaining('Titelachtergrond'), findsNothing);
    expect(find.text('Activatieduur'), findsNothing);
    expect(find.byKey(const Key('document-logo-shared')), findsNothing);
    expect(find.byKey(const Key('document-body-font-size')), findsNothing);

    await openSurface(tester, 'document');
    expect(find.byKey(const Key('document-logo-shared')), findsOneWidget);
    expect(find.byKey(const Key('document-body-font-size')), findsOneWidget);
    expect(find.text('Opsommingsteken'), findsNothing);
    expect(find.textContaining('Titelachtergrond'), findsNothing);
    expect(find.text('Activatieduur'), findsNothing);

    await openSurface(tester, 'presentation');
    expect(find.textContaining('Titelachtergrond'), findsOneWidget);
    expect(find.text('Activatieduur'), findsOneWidget);
    expect(find.text('Opsommingsteken'), findsNothing);
    expect(find.byKey(const Key('document-logo-shared')), findsNothing);
  });

  // Een sprong vanuit het kwaliteitspaneel wijst een kleurveld aan, en dat
  // anker hangt in de boom van één vlak. Landt de sprong op het verkeerde vlak,
  // dan staat de instelling er niet en gebeurt er zichtbaar niets — precies de
  // stille fout die de driedeling kan introduceren.
  //
  // Twee losse tests en niet twee sprongen in één: een tweede `pumpWidget`
  // ruimt het openstaande dialoog niet op, en dan toetst de tweede sprong het
  // venster van de eerste.
  Future<void> openWithField(WidgetTester tester, String field) async {
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
                  highlightThemeField: field,
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
  }

  testWidgets('een sprong naar een diakleur opent het presentatievlak', (
    tester,
  ) async {
    await openWithField(tester, 'titleTextColor');
    expect(find.byKey(const Key('presentation-style-editor')), findsOneWidget);
    // De oplichting dooft na drie seconden; laat die timer aflopen.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('een sprong naar een gedeelde kleur opent het algemene vlak', (
    tester,
  ) async {
    await openWithField(tester, 'textColor');
    expect(find.byKey(const Key('general-style-editor')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('een sprong naar de documentkop opent het documentvlak', (
    tester,
  ) async {
    await openWithField(tester, 'documentHeadingColor');
    expect(find.byKey(const Key('document-style-editor')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('een sprong naar de bandtekst opent het documentvlak', (
    tester,
  ) async {
    await openWithField(tester, 'documentBandTextColor');
    expect(find.byKey(const Key('document-style-editor')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('het gekozen logo staat naast de logokiezer', (tester) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    await tester.tap(find.byKey(const Key('style-profile-Vigilis')));
    await openSurface(tester, 'presentation');

    expect(find.byKey(const Key('style-logo-preview')), findsOneWidget);
  });

  testWidgets('document deelt standaard het presentatielogo en kan afwijken', (
    tester,
  ) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    await tester.tap(find.byKey(const Key('style-profile-Vigilis')));
    await openSurface(tester, 'document');

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

  // Een blad heeft een vaste lettermaat en een dia niet, dus de schuif hoort
  // op het documentvlak — en hij moet het profiel werkelijk verzetten, niet
  // alleen bewegen.
  testWidgets('de basislettergrootte staat op het documentvlak en werkt', (
    tester,
  ) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    await openSurface(tester, 'document');
    final slider = find.byKey(const Key('document-body-font-size'));
    expect(tester.widget<Slider>(slider).value, kDocumentDefaultBodyFontSize);

    // Rechts op de baan tikken: de waarde springt naar die plek. Slepen werkt
    // hier niet — de schuif zit in een scrollbaar paneel en de sleep belandt
    // bij de rol in plaats van bij de knop.
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    final track = tester.getRect(slider);
    await tester.tapAt(Offset(track.right - 12, track.center.dy));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Slider>(slider).value,
      greaterThan(kDocumentDefaultBodyFontSize),
    );
    expect(find.textContaining('Basislettergrootte:'), findsOneWidget);
  });

  testWidgets('document biedt koptekst, voettekst en paginanummers aan', (
    tester,
  ) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    await openSurface(tester, 'document');

    expect(find.byKey(const Key('document-header-LibreKAT')), findsOneWidget);
    expect(find.byKey(const Key('document-footer-LibreKAT')), findsOneWidget);
    expect(find.byKey(const Key('document-page-numbers')), findsOneWidget);
    expect(find.byKey(const Key('document-band-text-color')), findsOneWidget);
    expect(
      find.byKey(const Key('document-band-background-color')),
      findsOneWidget,
    );
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

      await openSurface(tester, 'document');

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

  testWidgets('documentband gebruikt eigen tekst- en achtergrondkleur', (
    tester,
  ) async {
    const profile = ThemeProfile(
      documentHeaderText: 'Kop',
      documentBandTextColor: '#F8FAFC',
      documentBandBackgroundColor: '#172033',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DocumentChromeBand(profile: profile, header: true),
        ),
      ),
    );

    final text = tester.widget<InlineMarkdownText>(
      find.byKey(const Key('document-header-text')),
    );
    expect(text.style.color, const Color(0xFFF8FAFC));
    final band = tester.widget<ColoredBox>(
      find.byKey(const Key('document-header-band')),
    );
    expect(band.color, const Color(0xFF172033));
  });

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
      find.byKey(const Key('general-style-editor')),
    );
    final widePreview = tester.getTopLeft(
      find.byKey(const Key('general-style-preview')),
    );
    expect(widePreview.dx, greaterThan(wideEditor.dx));

    await tester.binding.setSurfaceSize(const Size(700, 1000));
    await tester.pumpAndSettle();
    final narrowEditor = tester.getTopLeft(
      find.byKey(const Key('general-style-editor')),
    );
    final narrowPreview = tester.getTopLeft(
      find.byKey(const Key('general-style-preview')),
    );
    expect(narrowPreview.dy, greaterThan(narrowEditor.dy));
  });
}
