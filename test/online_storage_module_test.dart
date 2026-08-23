import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/state/module_registry.dart';
import 'package:ocideck/state/online_storage_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/dialogs/settings/online_storage_module_card.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De module Online opslag (#570): WebDAV, S3 en git als uitbreiding,
/// standaard uit, zodat de interface stil begint.
///
/// De drie regels uit het issue, en waar ze hier bewaakt worden:
///
///  1. **Weglaten, niet grijs maken** — met de module uit staan de online
///     soorten niet in "Verbinding toevoegen".
///  2. **Tonen zodra de inhoud er is** — wie al een online verbinding heeft,
///     valt onder de reveal en verliest niets; dat dekt meteen het menu, de
///     dialogen en de outbox, want die poorten allemaal op bestáánde
///     verbindingen.
///  3. **Een werkende configuratie start aan** — zonder opgeslagen keuze volgt
///     de stand de inhoud; default-uit geldt voor nieuwe installaties.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  GitConnection gitVerbinding() => const GitConnection(
    id: 'git-1',
    name: 'Werk',
    repo: GitRepoConfig(
      baseUrl: 'https://git.example.org',
      owner: 'acme',
      repo: 'decks',
    ),
  );

  group('de stand en de poort', () {
    Future<ProviderContainer> vers({
      Map<String, Object> prefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues({...prefs});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Beide notifiers laten laden: de module leest zijn voorkeursleutel en
      // de instellingen hun verbindingslijst.
      container.read(onlineStorageProvider);
      container.read(settingsProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      return container;
    }

    test('een verse installatie start uit en verborgen', () async {
      final c = await vers();
      expect(c.read(onlineStorageEnabledProvider), isFalse);
      expect(c.read(onlineStorageRevealProvider), isFalse);
    });

    test(
      'een werkende configuratie start áán, zonder migratieschrijf',
      () async {
        // Default-uit geldt voor nieuwe installaties, niet voor wie gisteren al
        // een online verbinding had (#570). Zonder opgeslagen keuze volgt de
        // stand de inhoud.
        final c = await vers();
        await c.read(settingsProvider.notifier).setConnections([
          gitVerbinding(),
        ]);
        expect(c.read(onlineStorageEnabledProvider), isTrue);
        expect(c.read(onlineStorageRevealProvider), isTrue);
      },
    );

    test('bewust uit met bestaande verbindingen: reveal blijft', () async {
      // Regel 2 én 3 van het issue in één: uitzetten maakt bestaand en
      // wachtend werk niet onbereikbaar. De menu-items en de outbox kijken
      // naar bestaande verbindingen, dus déze vlag is wat ze overeind houdt.
      final c = await vers(prefs: {'onlineStorageEnabled': false});
      await c.read(settingsProvider.notifier).setConnections([gitVerbinding()]);
      expect(c.read(onlineStorageEnabledProvider), isFalse);
      expect(c.read(onlineStorageRevealProvider), isTrue);
    });

    test('laatste verbinding weg zonder keuze: de poort valt terug', () async {
      // Het kantelpunt van de afgeleide standaard, als keuze vastgelegd (zie
      // onlineStorageEnabledProvider): geen inhoud en geen opgeslagen keuze
      // ís de standaard — uit. Omkeerbaar via de kaart, en de zoekingang
      // "webdav"/"git" wijst erheen.
      final c = await vers();
      await c.read(settingsProvider.notifier).setConnections([gitVerbinding()]);
      expect(c.read(onlineStorageEnabledProvider), isTrue);

      await c.read(settingsProvider.notifier).setConnections(const []);
      expect(c.read(onlineStorageEnabledProvider), isFalse);
      expect(c.read(onlineStorageRevealProvider), isFalse);
    });

    test('een opgeslagen keuze wint van verdwijnende inhoud', () async {
      final c = await vers(prefs: {'onlineStorageEnabled': true});
      await c.read(settingsProvider.notifier).setConnections([gitVerbinding()]);
      await c.read(settingsProvider.notifier).setConnections(const []);
      expect(c.read(onlineStorageEnabledProvider), isTrue);
    });

    test('de keuze van de gebruiker wordt bewaard', () async {
      final c = await vers();
      await c.read(onlineStorageProvider.notifier).setEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onlineStorageEnabled'), isTrue);
    });

    test('het register kent de modules, in kaartvolgorde', () {
      expect(moduleRegistry.map((m) => m.id), [
        ModuleId.infoSafety,
        ModuleId.ai,
        ModuleId.onlineStorage,
        ModuleId.imports,
        ModuleId.procesverbetering,
        ModuleId.collaboration,
        ModuleId.videoCalls,
        ModuleId.assetRights,
        ModuleId.managementsysteem,
        ModuleId.libreplan,
      ]);
    });
  });

  group('het instellingenvenster', () {
    Future<ProviderContainer> open(
      WidgetTester tester, {
      Map<String, Object> prefs = const {},
      SettingsSection section = SettingsSection.storage,
    }) async {
      SharedPreferences.setMockInitialValues({...prefs});
      await tester.binding.setSurfaceSize(const Size(1500, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  ref.watch(settingsProvider);
                  ref.watch(onlineStorageProvider);
                  return ElevatedButton(
                    onPressed: () =>
                        SettingsDialog.show(context, initialSection: section),
                    child: const Text('open'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.text('open')),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return container;
    }

    Future<void> openVerbindingMenu(WidgetTester tester) async {
      await tester.tap(find.text('Verbinding toevoegen'));
      await tester.pumpAndSettle();
    }

    testWidgets('met de module uit biedt het menu alleen de lokale map', (
      tester,
    ) async {
      await open(tester);
      await openVerbindingMenu(tester);

      expect(find.text('Map op deze computer'), findsOneWidget);
      // Weglaten, niet grijs maken: de soorten stáán er niet.
      expect(find.text('WebDAV-server'), findsNothing);
      expect(find.text('S3-bucket'), findsNothing);
      expect(find.text('Git-repository'), findsNothing);
    });

    testWidgets('met de module aan staan alle vier de soorten er', (
      tester,
    ) async {
      await open(tester, prefs: {'onlineStorageEnabled': true});
      await openVerbindingMenu(tester);

      expect(find.text('Map op deze computer'), findsOneWidget);
      expect(find.text('WebDAV-server'), findsOneWidget);
      expect(find.text('S3-bucket'), findsOneWidget);
      expect(find.text('Git-repository'), findsOneWidget);
    });

    testWidgets('de kaart staat op Uitbreidingen en schakelt de soorten bij', (
      tester,
    ) async {
      await open(tester, section: SettingsSection.modules);
      expect(find.byType(OnlineStorageModuleCard), findsOneWidget);

      final schakelaar = find.descendant(
        of: find.byType(OnlineStorageModuleCard),
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(schakelaar);
      await tester.pumpAndSettle();
      await tester.tap(schakelaar);
      await tester.pumpAndSettle();

      // Naar Opslag: de online soorten zijn er nu wél — zonder Opslaan, want
      // een module aanzetten is een handeling op zichzelf (zelfde gedrag als
      // Informatieveiligheid ernaast).
      await tester.tap(find.text('Opslag'));
      await tester.pumpAndSettle();
      await openVerbindingMenu(tester);
      expect(find.text('WebDAV-server'), findsOneWidget);
    });

    testWidgets(
      'het Uitbreidingen-tabblad toont elke module uit het register',
      (tester) async {
        await open(tester, section: SettingsSection.modules);
        // Eén kaart per registermodule, elk met één schakelaar. Een module
        // zonder kaart laat deze telling vallen.
        expect(
          find.byType(SwitchListTile),
          findsNWidgets(moduleRegistry.length),
        );
      },
    );
  });
}
