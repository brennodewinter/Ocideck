@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/state/openkat_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/dialogs/settings/openkat_module_card.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:ocideck/widgets/shell/openkat_import_action.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// De module OpenKAT (#767, #772): rapportages inlezen als uitbreiding,
/// standaard uit, met de rapportagemap onder Integraties.
///
/// De drie regels die deze module met de andere deelt, en waar ze hier
/// bewaakt worden:
///
///  1. **Standaard uit** — een nieuwe installatie ziet er niets van.
///  2. **Weglaten, niet grijs maken** — met de module uit bestaat het tabblad
///     Integraties niet; er staat geen leeg tabblad te wachten.
///  3. **Tonen zodra de inhoud er is** — wie een rapportagemap heeft
///     aangewezen houdt het invoerpunt, ook met de schakelaar uit, zodat een
///     bestaand OpenKAT-deck bij te werken blijft.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Future<ProviderContainer> vers({Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues({...prefs});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(openKatProvider);
    // De voorkeuren laden asynchroon; één beurt is genoeg.
    await Future<void>.delayed(Duration.zero);
    return c;
  }

  group('de stand en de poort', () {
    test('een nieuwe installatie start uit', () async {
      final c = await vers();
      expect(c.read(openKatEnabledProvider), isFalse);
      expect(c.read(openKatRevealProvider), isFalse);
      expect(c.read(openKatDirectoryProvider), isNull);
    });

    test('de keuze van de gebruiker wordt bewaard', () async {
      final c = await vers();
      await c.read(openKatProvider.notifier).setEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('openkatModuleEnabled'), isTrue);
      expect(c.read(openKatRevealProvider), isTrue);
    });

    test('de rapportagemap wordt bewaard en is te wissen', () async {
      final c = await vers();
      await c
          .read(openKatProvider.notifier)
          .setReportDirectory('/pad/naar/kat');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('openkatReportDirectory'), '/pad/naar/kat');
      expect(c.read(openKatDirectoryProvider), '/pad/naar/kat');

      await c.read(openKatProvider.notifier).setReportDirectory(null);
      expect(c.read(openKatDirectoryProvider), isNull);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'openkatReportDirectory',
        ),
        isNull,
      );
    });

    test('een map houdt het invoerpunt bereikbaar met de module uit', () async {
      // De vaste regel van dit project. Zonder deze poort zou uitzetten een
      // bestaand OpenKAT-deck onbijwerkbaar maken.
      final c = await vers(
        prefs: {
          'openkatModuleEnabled': false,
          'openkatReportDirectory': '/pad/naar/kat',
        },
      );
      expect(c.read(openKatEnabledProvider), isFalse);
      expect(c.read(openKatRevealProvider), isTrue);
    });

    test('een lege map telt als geen map', () async {
      final c = await vers(prefs: {'openkatReportDirectory': ''});
      expect(c.read(openKatDirectoryProvider), isNull);
      expect(c.read(openKatRevealProvider), isFalse);
    });
  });

  group('het tabblad Integraties', () {
    List<SettingsSection> nav({required bool openKatRevealed}) =>
        SettingsSection.navItems(
          infoSafetyRevealed: false,
          hasChecklists: false,
          aiRevealed: false,
          openKatRevealed: openKatRevealed,
        );

    test('met de module uit staat het tabblad er niet', () {
      // Zolang OpenKAT de enige integratie is, is een leeg tabblad
      // "Integraties" geen informatie maar ruis.
      expect(
        nav(openKatRevealed: false),
        isNot(contains(SettingsSection.integrations)),
      );
    });

    test('met de module aan staat het er wel', () {
      expect(
        nav(openKatRevealed: true),
        contains(SettingsSection.integrations),
      );
    });
  });

  group('het instellingenvenster', () {
    Future<void> open(
      WidgetTester tester, {
      Map<String, Object> prefs = const {},
      SettingsSection section = SettingsSection.modules,
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
                  ref.watch(openKatProvider);
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
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('de kaart staat op Uitbreidingen en schakelt de tab bij', (
      tester,
    ) async {
      await open(tester);
      expect(find.byType(OpenKatModuleCard), findsOneWidget);
      // Uit: geen Integraties in de zijbalk.
      expect(find.text('Integraties'), findsNothing);

      // Vierde kaart op het tabblad: die staat onder de vouw.
      final schakelaar = find.descendant(
        of: find.byType(OpenKatModuleCard),
        matching: find.byType(SwitchListTile),
      );
      await tester.ensureVisible(schakelaar);
      await tester.pumpAndSettle();
      await tester.tap(schakelaar);
      await tester.pumpAndSettle();
      expect(find.text('Integraties'), findsOneWidget);
    });

    testWidgets('Integraties toont de rapportagemap', (tester) async {
      await open(
        tester,
        prefs: {
          'openkatModuleEnabled': true,
          'openkatReportDirectory': '/pad/naar/kat',
        },
        section: SettingsSection.integrations,
      );
      expect(find.text('/pad/naar/kat'), findsOneWidget);
      expect(find.text('Map kiezen…'), findsOneWidget);
    });

    testWidgets('zonder map zegt Integraties dat er niets gekozen is', (
      tester,
    ) async {
      await open(
        tester,
        prefs: {'openkatModuleEnabled': true},
        section: SettingsSection.integrations,
      );
      expect(find.text('Geen map gekozen'), findsOneWidget);
    });
  });

  testWidgets('de import gebruikt de ingestelde map zonder mapkiezer', (
    tester,
  ) async {
    // Dit is het verschil dat de module bruikbaar maakt bij dagelijks gebruik.
    // De mapkiezer laat zich onder `flutter test` niet aansturen en zou null
    // teruggeven; komt er tóch een deck uit, dan kwam de map uit de instelling.
    final tmp = Directory.systemTemp.createTempSync('ocikat-vaste-map-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(p.join(tmp.path, 'org1_20240601000000.json')).writeAsStringSync(
      jsonEncode({
        'organization_code': 'org1',
        'organization_name': 'Organisatie 1',
        'organization_tags': <String>[],
        'data': {
          'systems': {
            'services': {
              'Hostname|internet|example.com': {
                'hostnames': ['example.com'],
                'services': <dynamic>[],
              },
            },
          },
          'findings': {
            'finding_types': [
              {
                'finding_type': {
                  'id': 'KAT-001',
                  'name': 'Open poort',
                  'risk_severity': 'high',
                },
                'occurrences': [
                  {
                    'finding': {
                      'primary_key': 'f1',
                      'ooi': 'Hostname|internet|example.com',
                    },
                  },
                ],
              },
            ],
          },
          'total_systems': 1,
        },
      }),
    );

    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'openkatModuleEnabled': true,
      'openkatReportDirectory': tmp.path,
    });

    late BuildContext ctx;
    late WidgetRef reff;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ScaffoldMessenger(
            child: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  ref.watch(openKatProvider);
                  ctx = context;
                  reff = ref;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // runAsync: de import doet echte bestands-I/O.
    await tester.runAsync(() => importOpenKatReports(ctx, reff));
    await tester.pumpAndSettle();

    final deck = container
        .read(tabsProvider)
        .current
        ?.deckNotifier
        .currentState
        .deck;
    expect(
      deck,
      isNotNull,
      reason: 'de map uit Integraties is gebruikt zonder ernaar te vragen',
    );
  });
}
