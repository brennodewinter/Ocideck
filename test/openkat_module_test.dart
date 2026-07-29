@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/state/import_module_provider.dart';
import 'package:ocideck/state/openkat_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/dialogs/settings/import_module_card.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:ocideck/widgets/shell/openkat_import_action.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// De module Importeren (#772, besluit B1): materiaal uit andere systemen
/// binnenhalen als uitbreiding, standaard uit. OpenKAT is de eerste importeur;
/// zijn rapportagemap staat onder Integraties.
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
    c.read(importModuleProvider);
    // De voorkeuren laden asynchroon; één beurt is genoeg.
    await Future<void>.delayed(Duration.zero);
    return c;
  }

  group('de stand en de poort', () {
    test('een nieuwe installatie start uit', () async {
      final c = await vers();
      expect(c.read(importModuleEnabledProvider), isFalse);
      expect(c.read(importModuleRevealProvider), isFalse);
      expect(c.read(openKatDirectoryProvider), isNull);
    });

    test('de keuze van de gebruiker wordt bewaard', () async {
      final c = await vers();
      await c.read(importModuleProvider.notifier).setEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('importModuleEnabled'), isTrue);
      expect(c.read(importModuleRevealProvider), isTrue);
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
          'importModuleEnabled': false,
          'openkatReportDirectory': '/pad/naar/kat',
        },
      );
      expect(c.read(importModuleEnabledProvider), isFalse);
      expect(c.read(importModuleRevealProvider), isTrue);
    });

    test('een lege map telt als geen map', () async {
      final c = await vers(prefs: {'openkatReportDirectory': ''});
      expect(c.read(openKatDirectoryProvider), isNull);
      expect(c.read(importModuleRevealProvider), isFalse);
    });
  });

  group('het tabblad Integraties', () {
    List<SettingsSection> nav({
      required bool importRevealed,
      bool openKatAvailable = true,
    }) => SettingsSection.navItems(
      infoSafetyRevealed: false,
      hasChecklists: false,
      aiRevealed: false,
      importRevealed: importRevealed,
      openKatAvailable: openKatAvailable,
    );

    test('met de module uit staat het tabblad er niet', () {
      // Zolang OpenKAT de enige integratie is, is een leeg tabblad
      // "Integraties" geen informatie maar ruis.
      expect(
        nav(importRevealed: false),
        isNot(contains(SettingsSection.integrations)),
      );
    });

    test('met de module aan staat het er wel', () {
      expect(nav(importRevealed: true), contains(SettingsSection.integrations));
    });

    test('op web valt het weg, ook met de module aan', () {
      // Het tabblad ís OpenKAT, en dat leest een map van schijf — op web
      // bestaat die bron niet. De module kan daar wél aan staan (voor de
      // presentatie-import, die op bytes werkt), maar dan zonder Integraties.
      expect(
        nav(importRevealed: true, openKatAvailable: false),
        isNot(contains(SettingsSection.integrations)),
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
                  ref.watch(importModuleProvider);
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
      expect(find.byType(ImportModuleCard), findsOneWidget);
      // Uit: geen Integraties in de zijbalk.
      expect(find.text('Integraties'), findsNothing);

      // Vierde kaart op het tabblad: die staat onder de vouw.
      final schakelaar = find.descendant(
        of: find.byType(ImportModuleCard),
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
          'importModuleEnabled': true,
          'openkatReportDirectory': '/pad/naar/kat',
        },
        section: SettingsSection.integrations,
      );
      expect(find.text('/pad/naar/kat'), findsOneWidget);
      expect(find.text('Map kiezen…'), findsOneWidget);
    });

    testWidgets('het OpenKAT-logo staat bij de sectie', (tester) async {
      // Een verkeerd assetpad rendert stil een foutvak in plaats van te falen,
      // en op een instellingentabblad valt dat niemand op. Vandaar dat het pad
      // zelf de bewering is, en niet alleen "er staat een plaatje".
      await open(
        tester,
        prefs: {'importModuleEnabled': true},
        section: SettingsSection.integrations,
      );
      final logo = tester.widgetList<Image>(find.byType(Image)).where((i) {
        final provider = i.image;
        return provider is AssetImage &&
            provider.assetName == 'assets/images/openkat-logo.png';
      });
      expect(logo, hasLength(1));
    });

    testWidgets('zonder map zegt Integraties dat er niets gekozen is', (
      tester,
    ) async {
      await open(
        tester,
        prefs: {'importModuleEnabled': true},
        section: SettingsSection.integrations,
      );
      expect(find.text('Geen map gekozen'), findsOneWidget);
    });

    testWidgets('zonder map is rapportages controleren uitgeschakeld', (
      tester,
    ) async {
      // Een knop die zichtbaar níets kan doen is beter dan een knop die stil
      // een tweede mapkiezer opent naast de knop ernaast.
      await open(
        tester,
        prefs: {'importModuleEnabled': true},
        section: SettingsSection.integrations,
      );
      final knop = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Rapportages controleren…'),
      );
      expect(knop.onPressed, isNull);
    });

    testWidgets('met een map opent de knop dezelfde rapportwizard', (
      tester,
    ) async {
      // Instellingen, welkom en menu horen geen afwijkende importroutes te
      // hebben: deze knop opent dezelfde wizard met de ingestelde map.
      final tmp = Directory.systemTemp.createTempSync('ocikat-knop-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      Directory(p.join(tmp.path, 'raw-data')).createSync();
      File(
        p.join(tmp.path, 'raw-data', 'org1_20240601000000.json'),
      ).writeAsStringSync(jsonEncode(rapportage('org1')));

      await open(
        tester,
        prefs: {
          'importModuleEnabled': true,
          'openkatReportDirectory': tmp.path,
        },
        section: SettingsSection.integrations,
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Rapportages controleren…'),
      );

      // De scan doet echte bestands-I/O: die futures komen onder de
      // testbinding alleen aan in een runAsync-beurt, en één pomp is te vroeg.
      for (var i = 0; i < 40; i++) {
        if (find
            .text('Welke organisaties vragen aandacht?')
            .evaluate()
            .isNotEmpty) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }

      expect(find.text('OpenKAT-rapport maken'), findsOneWidget);
      expect(
        find.text('Welke organisaties vragen aandacht?'),
        findsAtLeastNWidgets(1),
      );
      await tester.tap(find.widgetWithText(TextButton, 'Annuleren').last);
      await tester.pumpAndSettle();
    });
  });

  group('het openscherm', () {
    Future<void> openscherm(
      WidgetTester tester, {
      Map<String, Object> prefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues({
        'app_consent_accepted': true,
        ...prefs,
      });
      await tester.binding.setSurfaceSize(const Size(1400, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
      await tester.pumpAndSettle();
    }

    testWidgets('met de module uit staat OpenKAT er niet', (tester) async {
      await openscherm(tester);
      expect(find.text('OpenKAT-rapport maken…'), findsNothing);
    });

    testWidgets('met de module aan begin je hier met een OpenKAT-uitdraai', (
      tester,
    ) async {
      // Wie met OpenKAT werkt komt juist op dit scherm terug om het overzicht
      // te verversen; dan is drie stappen door een menu er één te veel.
      await openscherm(tester, prefs: {'importModuleEnabled': true});
      expect(find.text('OpenKAT-rapport maken…'), findsOneWidget);
    });

    testWidgets('een ingestelde map houdt de ingang met de module uit', (
      tester,
    ) async {
      await openscherm(tester, prefs: {'openkatReportDirectory': '/pad/kat'});
      expect(find.text('OpenKAT-rapport maken…'), findsOneWidget);
    });
  });

  testWidgets('de rapportwizard gebruikt de ingestelde map zonder mapkiezer', (
    tester,
  ) async {
    // Dit is het verschil dat de module bruikbaar maakt bij dagelijks gebruik.
    // De mapkiezer laat zich onder `flutter test` niet aansturen en zou null
    // teruggeven; verschijnen de scenario's, dan kwam de map uit de instelling.
    final tmp = Directory.systemTemp.createTempSync('ocikat-vaste-map-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    Directory(p.join(tmp.path, 'raw-data')).createSync();
    File(
      p.join(tmp.path, 'raw-data', 'org1_20240601000000.json'),
    ).writeAsStringSync(jsonEncode(rapportage('org1')));

    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'importModuleEnabled': true,
      'openkatReportDirectory': tmp.path,
    });

    late BuildContext ctx;
    late WidgetRef reff;
    final container = ProviderContainer();
    var containerDisposed = false;
    addTearDown(() {
      if (!containerDisposed) container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ScaffoldMessenger(
            child: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  ref.watch(openKatProvider);
                  ref.watch(importModuleProvider);
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

    final wizard = importOpenKatReports(ctx, reff);
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      if (find
          .text('Welke organisaties vragen aandacht?')
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(
      find.text('Welke organisaties vragen aandacht?'),
      findsAtLeastNWidgets(1),
      reason: 'de ingestelde map is direct gescand zonder een mapkiezer',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Annuleren').last);
    await tester.pumpAndSettle();
    expect(await wizard, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    containerDisposed = true;
  });
}

/// Eén organisatierapport in de envelop die de exportknop van OpenKAT
/// werkelijk oplevert; de datum zit in de bestandsnaam, niet in de inhoud.
Map<String, dynamic> rapportage(String code) => {
  'organization_code': code,
  'organization_name': 'Organisatie $code',
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
};
