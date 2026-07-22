import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/info_safety_provider.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:ocideck/widgets/privacy_badge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Smoke test for the settings dialog. Its tab bodies are built into an
/// IndexedStack, so a single render exercises every tab; tapping the nav icons
/// then exercises the tab-selection path.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('SettingsDialog renders and switches tabs', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SettingsDialog.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsOneWidget);

    // Walk the navigation rail to exercise each tab's selection, including the
    // Security tab (shield) and the branded footer that opens "Over OciDeck".
    for (final icon in const [
      Icons.format_paint_outlined,
      Icons.slideshow_outlined,
      Icons.speed_outlined,
      Icons.privacy_tip_outlined,
      Icons.shield_outlined,
      Icons.cloud_outlined,
      Icons.info_outline,
      Icons.tune,
    ]) {
      final finder = find.byIcon(icon);
      if (finder.evaluate().isNotEmpty) {
        await tester.tap(finder.first);
        await tester.pumpAndSettle();
      }
    }

    expect(find.byType(SettingsDialog), findsOneWidget);
  });

  // De logo-instelling staat sinds #506 achter `supportsLocalProjectFolders`,
  // omdat een logo als pad in het themaprofiel wordt bewaard en de browser geen
  // bruikbaar pad teruggeeft. Deze test dekt de dráaiende helft van die poort:
  // op een platform mét bestandssysteem moet de instelling er gewoon zijn.
  //
  // De web-helft is hier structureel niet te toetsen: onder `flutter test` is
  // `kIsWeb` altijd false, de vlag komt via een conditionele import zonder
  // injectiepunt, en er is geen `--platform chrome`-doel. Die kant wordt door
  // #505 bewaakt, met een statische regel in plaats van een test.
  testWidgets(
    'de logo-instelling staat er op een platform met bestandssysteem',
    (tester) async {
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

      // Positie en grootte horen bij de logokeuze en staan er dus alleen als de
      // poort openstaat. Het pad zelf is geen anker: standaard staat er al een
      // logo ingesteld, dus de "geen logo"-tekst verschijnt nooit.
      expect(find.text('Logo positie'), findsOneWidget);
      expect(find.text('Logo px'), findsOneWidget);

      // De footer hoort er náást te staan: die heeft geen bestandssysteem nodig
      // en mag door de logo-poort niet zijn meegesleept.
      expect(find.text('Footertekst'), findsOneWidget);
    },
  );

  // De taalkeuze wisselt de interface meteen en schrijft dus buiten Opslaan om
  // in de instellingen. Annuleren moet dat terugdraaien, anders verwerpt het je
  // andere wijzigingen wél en blijft de taal staan.
  group('de taal volgt Opslaan en Annuleren', () {
    /// Opent het venster en wisselt de taal zoals de dropdown dat doet: meteen,
    /// via de provider. Geeft de container terug om de taal uit te lezen. De
    /// container hangt bewust ónder de widgetboom (niet ernaast): de tabs­provider
    /// draait een periodieke timer, en alleen zo ruimt het afbreken van de boom
    /// die op tijd op.
    Future<ProviderContainer> openAndSwitchLanguage(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => SettingsDialog.show(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).languageCode, 'nl');

      await container.read(settingsProvider.notifier).setLanguageCode('de');
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).languageCode, 'de');

      return container;
    }

    // De knoppen staan ná de wissel in het Duits; hun labels komen daarom uit
    // de vertaling en niet uit een hardgecodeerd 'Annuleren'/'Opslaan'.
    const german = AppLocalizations(Locale('de'));

    testWidgets('Annuleren zet de taal terug zoals ze was', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1500, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = await openAndSwitchLanguage(tester);

      await tester.tap(find.text(german.t('cancel')));
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).languageCode, 'nl');
    });

    testWidgets('Opslaan houdt de nieuwe taal vast', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1500, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = await openAndSwitchLanguage(tester);

      await tester.tap(find.text(german.t('saveSettings')));
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).languageCode, 'de');
    });
  });

  // De CVE-schakelaar zet je bloot: de zoekterm gaat naar de mirror en bij een
  // misser ook naar ENISA en MITRE. De badge moet dat zichtbaar maken, náást de
  // schakelaar, en niet stilletjes verdwijnen als iemand de sectie herschikt.
  testWidgets('the CVE lookup toggle carries a privacy badge', (tester) async {
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
                  initialSection: SettingsSection.security,
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

    // De module Informatieveiligheid aanzetten: sinds #648 zit dit oppervlak
    // erachter, en met de module uit hoort het er juist níét te staan.
    await ProviderScope.containerOf(
      tester.element(find.text('open')),
      listen: false,
    ).read(infoSafetyProvider.notifier).enable();
    await tester.pumpAndSettle();
    // Het Beveiliging-tabblad draagt er inmiddels twee: één bij de online
    // zoekopdracht (wat je prijsgeeft) en één bij de lokale database (dat je
    // dan niets meer prijsgeeft). Die van de online schakelaar moet de keten
    // benoemen die de zoekterm doorstuurt.
    final tooltips = tester
        .widgetList<PrivacyBadge>(find.byType(PrivacyBadge))
        .map((b) => b.tooltip)
        .toList();

    expect(tooltips, isNotEmpty);
    expect(
      tooltips.any((t) => t.contains('ENISA') && t.contains('MITRE')),
      isTrue,
      reason:
          'de badge bij de online CVE-schakelaar noemt de doorstuurketen niet',
    );
  });
}
