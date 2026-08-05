@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/state/openkat_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:ocideck/widgets/shell/openkat_import_action.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_until.dart';
import 'support/temp_dir.dart';

/// De integratie OpenKAT (#767, #772, #1158): een koppeling naar buiten met een
/// eigen schakelaar op het tabblad Integraties. Tot #1158 hing OpenKAT aan de
/// module Importeren (#772, B1); sinds #1158 is de koppeling losgemaakt zodat ze
/// los in en uit te schakelen is, en gaat de module Importeren alleen nog over
/// presentatie-import.
///
/// De drie regels die deze koppeling deelt met de modules, en waar ze hier
/// bewaakt worden:
///
///  1. **Standaard uit** — een nieuwe installatie ziet er niets van.
///  2. **Tonen zodra de inhoud er is** — wie een rapportagemap heeft
///     aangewezen houdt het invoerpunt, ook met de schakelaar uit, zodat een
///     bestaand OpenKAT-deck bij te werken blijft.
///  3. **Het tabblad zelf is er zodra de koppeling beschikbaar is** — anders is
///     er geen plek om de schakelaar aan te zetten; op web valt OpenKAT weg
///     omdat de mapkiezer daar niet bestaat.
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
      expect(c.read(openKatIntegrationEnabledProvider), isFalse);
      expect(c.read(openKatIntegrationRevealProvider), isFalse);
      expect(c.read(openKatDirectoryProvider), isNull);
    });

    test('de keuze van de gebruiker wordt bewaard', () async {
      final c = await vers();
      await c.read(openKatProvider.notifier).setEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('openkatIntegrationEnabled'), isTrue);
      expect(c.read(openKatIntegrationRevealProvider), isTrue);
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

    test(
      'een map houdt de koppeling bereikbaar met de schakelaar uit',
      () async {
        // De vaste regel van dit project. Zonder deze poort zou uitzetten een
        // bestaand OpenKAT-deck onbijwerkbaar maken.
        final c = await vers(
          prefs: {
            'openkatIntegrationEnabled': false,
            'openkatReportDirectory': '/pad/naar/kat',
          },
        );
        expect(c.read(openKatIntegrationEnabledProvider), isFalse);
        expect(c.read(openKatIntegrationRevealProvider), isTrue);
      },
    );

    test('een lege map telt als geen map', () async {
      final c = await vers(prefs: {'openkatReportDirectory': ''});
      expect(c.read(openKatDirectoryProvider), isNull);
      expect(c.read(openKatIntegrationRevealProvider), isFalse);
    });
  });

  group('het tabblad Integraties', () {
    List<SettingsSection> nav({required bool integrationsAvailable}) =>
        SettingsSection.navItems(
          infoSafetyRevealed: false,
          hasChecklists: false,
          aiRevealed: false,
          libreplanRevealed: false,
          integrationsAvailable: integrationsAvailable,
          collaborationRevealed: false,
        );

    test('op desktop staat het tabblad er, ook met de koppeling uit', () {
      // De schakelaar per integratie leeft óp dit tabblad; het moet er dus zijn
      // zodra er iets aan te zetten valt, niet pas nadat het aan staat.
      expect(
        nav(integrationsAvailable: true),
        contains(SettingsSection.integrations),
      );
    });

    test('zonder beschikbare integratie valt het tabblad weg', () {
      // Op web bestaat de mapkiezer van OpenKAT niet; een leeg tabblad
      // "Integraties" is dan geen informatie maar ruis.
      expect(
        nav(integrationsAvailable: false),
        isNot(contains(SettingsSection.integrations)),
      );
    });
  });

  group('het instellingenvenster', () {
    Future<void> open(
      WidgetTester tester, {
      Map<String, Object> prefs = const {},
      SettingsSection section = SettingsSection.integrations,
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

    testWidgets('Integraties staat op desktop in de zijbalk', (tester) async {
      await open(tester, section: SettingsSection.modules);
      expect(find.text('Integraties'), findsWidgets);
    });

    testWidgets('de OpenKAT-schakelaar onthult de map-instellingen', (
      tester,
    ) async {
      // Uit: alleen de schakelkaart, geen mapkiezer.
      await open(tester);
      expect(find.text('Map kiezen…'), findsNothing);

      final schakelaar = find.byType(SwitchListTile).first;
      await tester.ensureVisible(schakelaar);
      await tester.pumpAndSettle();
      await tester.tap(schakelaar);
      await tester.pumpAndSettle();
      expect(find.text('Map kiezen…'), findsOneWidget);
    });

    testWidgets('Integraties toont de rapportagemap', (tester) async {
      await open(
        tester,
        prefs: {
          'openkatIntegrationEnabled': true,
          'openkatReportDirectory': '/pad/naar/kat',
        },
      );
      expect(find.text('/pad/naar/kat'), findsOneWidget);
      expect(find.text('Map kiezen…'), findsOneWidget);
    });

    testWidgets('het OpenKAT-logo staat bij de sectie', (tester) async {
      // Een verkeerd assetpad rendert stil een foutvak in plaats van te falen,
      // en op een instellingentabblad valt dat niemand op. Vandaar dat het pad
      // zelf de bewering is, en niet alleen "er staat een plaatje".
      await open(tester);
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
      await open(tester, prefs: {'openkatIntegrationEnabled': true});
      expect(find.text('Geen map gekozen'), findsOneWidget);
    });

    testWidgets('zonder map is rapportages controleren uitgeschakeld', (
      tester,
    ) async {
      // Een knop die zichtbaar níets kan doen is beter dan een knop die stil
      // een tweede mapkiezer opent naast de knop ernaast.
      await open(tester, prefs: {'openkatIntegrationEnabled': true});
      final knop = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Rapportages controleren…'),
      );
      expect(knop.onPressed, isNull);
    });

    testWidgets('"Alles inschakelen" zet de koppeling aan', (tester) async {
      // De bulkbediening (#1158): met alles uit is "Alles inschakelen" de weg om
      // in één handeling elke integratie aan te zetten.
      await open(tester);
      expect(find.text('Map kiezen…'), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Alles inschakelen'));
      await tester.pumpAndSettle();
      expect(find.text('Map kiezen…'), findsOneWidget);
    });

    testWidgets('"Alles uitschakelen" zet de koppeling uit', (tester) async {
      await open(tester, prefs: {'openkatIntegrationEnabled': true});
      expect(find.text('Map kiezen…'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Alles uitschakelen'));
      await tester.pumpAndSettle();
      expect(find.text('Map kiezen…'), findsNothing);
    });

    testWidgets('met een map opent de knop dezelfde rapportwizard', (
      tester,
    ) async {
      // Instellingen, welkom en menu horen geen afwijkende importroutes te
      // hebben: deze knop opent dezelfde wizard met de ingestelde map.
      final tmp = Directory.systemTemp.createTempSync('ocikat-knop-');
      addTearDown(() => deleteTempDir(tmp));
      Directory(p.join(tmp.path, 'raw-data')).createSync();
      File(
        p.join(tmp.path, 'raw-data', 'org1_20240601000000.json'),
      ).writeAsStringSync(jsonEncode(rapportage('org1')));

      await open(
        tester,
        prefs: {
          'openkatIntegrationEnabled': true,
          'openkatReportDirectory': tmp.path,
        },
      );
      // De knop zit onder de schakelkaart en de bulkbediening, dus verder naar
      // beneden dan vroeger; scroll hem in beeld voordat de tik hem kan raken.
      final knop = find.widgetWithText(
        FilledButton,
        'Rapportages controleren…',
      );
      await tester.ensureVisible(knop);
      await tester.pumpAndSettle();
      await tester.tap(knop);

      // De scan doet echte bestands-I/O: die futures komen onder de
      // testbinding alleen aan in een runAsync-beurt, en één pomp is te vroeg.
      await pumpUntil(
        tester,
        () => find
            .text('Welke organisaties vragen aandacht?')
            .evaluate()
            .isNotEmpty,
        reason: 'de wizard opende niet na een tik op de knop',
      );

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

    testWidgets('met de koppeling uit staat OpenKAT er niet', (tester) async {
      await openscherm(tester);
      expect(find.text('OpenKAT-rapport maken…'), findsNothing);
    });

    testWidgets('met de koppeling aan begin je hier met een OpenKAT-uitdraai', (
      tester,
    ) async {
      // Wie met OpenKAT werkt komt juist op dit scherm terug om het overzicht
      // te verversen; dan is drie stappen door een menu er één te veel.
      await openscherm(tester, prefs: {'openkatIntegrationEnabled': true});
      expect(find.text('OpenKAT-rapport maken…'), findsOneWidget);
    });

    testWidgets('een ingestelde map houdt de ingang met de koppeling uit', (
      tester,
    ) async {
      await openscherm(tester, prefs: {'openkatReportDirectory': '/pad/kat'});
      expect(find.text('OpenKAT-rapport maken…'), findsOneWidget);
    });
  });

  testWidgets('de rapportwizard gebruikt de ingestelde map zonder mapkiezer', (
    tester,
  ) async {
    // Dit is het verschil dat de koppeling bruikbaar maakt bij dagelijks
    // gebruik. De mapkiezer laat zich onder `flutter test` niet aansturen en zou
    // null teruggeven; verschijnen de scenario's, dan kwam de map uit de
    // instelling.
    final tmp = Directory.systemTemp.createTempSync('ocikat-vaste-map-');
    addTearDown(() => deleteTempDir(tmp));
    Directory(p.join(tmp.path, 'raw-data')).createSync();
    File(
      p.join(tmp.path, 'raw-data', 'org1_20240601000000.json'),
    ).writeAsStringSync(jsonEncode(rapportage('org1')));

    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'openkatIntegrationEnabled': true,
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
    await pumpUntil(
      tester,
      () => find
          .text('Welke organisaties vragen aandacht?')
          .evaluate()
          .isNotEmpty,
      reason: 'de wizard opende niet vanuit de ingestelde map',
    );

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
