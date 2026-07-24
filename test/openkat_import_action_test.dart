@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/openkat/openkat_directory_scanner.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/shell/openkat_import_action.dart';
import 'package:ocideck/widgets/shell/openkat_import_summary.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Het invoerpunt van de OpenKAT-import (#767): mapkiezer → scanner → deck.
///
/// De mapkiezer zelf laat zich onder `flutter test` niet aansturen (statische
/// FilePicker), dus de tests gaan door de `directoryOverride`-route — dat is
/// dezelfde code op één regel na.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  });

  /// Een OpenKAT-organisatierapport in de envelop die de exportknop werkelijk
  /// oplevert. De datum zit in de bestandsnaam, niet in de inhoud — zo doet
  /// OpenKAT dat ook.
  Map<String, dynamic> rapport(String code) => {
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
              'object_type': 'KATFindingType',
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

  Future<(ProviderContainer, BuildContext, WidgetRef)> pump(
    WidgetTester tester,
  ) async {
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
    return (container, ctx, reff);
  }

  testWidgets('een map met rapportages opent als deck in een nieuwe tab', (
    tester,
  ) async {
    final tmp = Directory.systemTemp.createTempSync('ocikat-actie-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(
      p.join(tmp.path, 'org1_20240601000000.json'),
    ).writeAsStringSync(jsonEncode(rapport('org1')));

    final (container, ctx, ref) = await pump(tester);
    // runAsync: de import doet echte bestands-I/O, en die futures komen onder
    // de testbinding anders nooit aan (zelfde les als de schijfscan-dialogen).
    await tester.runAsync(
      () => importOpenKatReports(ctx, ref, directoryOverride: tmp.path),
    );
    await tester.pumpAndSettle();

    final deck = container
        .read(tabsProvider)
        .current
        ?.deckNotifier
        .currentState
        .deck;
    expect(deck, isNotNull);
    expect(
      deck!.slides.any((s) => s.notes.contains('<!-- ocideck_openkat_view:')),
      isTrue,
      reason: 'de gegenereerde dia\'s dragen de OpenKAT-markering',
    );
    expect(find.textContaining('geïmporteerd'), findsOneWidget);
  });

  testWidgets('een lege map meldt dat er niets gevonden is', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('ocikat-leeg-');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final (container, ctx, ref) = await pump(tester);
    await tester.runAsync(
      () => importOpenKatReports(ctx, ref, directoryOverride: tmp.path),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Geen OpenKAT-rapportages'), findsOneWidget);
    expect(
      container.read(tabsProvider).current?.deckNotifier.currentState.deck,
      isNull,
      reason: 'geen deck openen om niets',
    );
  });

  testWidgets('een herimport werkt het actieve OpenKAT-deck bij', (
    tester,
  ) async {
    final tmp = Directory.systemTemp.createTempSync('ocikat-her-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(
      p.join(tmp.path, 'org1_20240601000000.json'),
    ).writeAsStringSync(jsonEncode(rapport('org1')));

    final (container, ctx, ref) = await pump(tester);
    await tester.runAsync(
      () => importOpenKatReports(ctx, ref, directoryOverride: tmp.path),
    );
    await tester.pumpAndSettle();
    final eerste = container
        .read(tabsProvider)
        .current!
        .deckNotifier
        .currentState
        .deck!;
    final tabsVoor = container.read(tabsProvider).tabs.length;

    // Tweede run met een extra maand: zelfde tab, bijgewerkt deck.
    File(
      p.join(tmp.path, 'org1_20240701000000.json'),
    ).writeAsStringSync(jsonEncode(rapport('org1')));
    await tester.runAsync(
      () => importOpenKatReports(ctx, ref, directoryOverride: tmp.path),
    );
    await tester.pumpAndSettle();

    expect(container.read(tabsProvider).tabs.length, tabsVoor);
    final tweede = container
        .read(tabsProvider)
        .current!
        .deckNotifier
        .currentState
        .deck!;
    expect(tweede.slides, isNot(equals(eerste.slides)));
    // Geen snackbar-assert hier: de eerste melding draait op een échte timer
    // (runAsync) en houdt de wachtrij bezet, dus 'bijgewerkt' komt binnen de
    // testtijd niet aan de beurt. Het gedrag — zelfde tab, bijgewerkt deck —
    // staat hierboven; de meldingsoppervlakken toetsen de andere twee tests.
  });

  testWidgets('met announce uit meldt de actie niets en geeft ze de uitkomst', (
    tester,
  ) async {
    // De route van het instellingenvenster: daar is een snackbar achter een
    // modale dialoog geen melding, dus meldt het paneel zelf — en dan moet de
    // actie de tellingen wél teruggeven.
    final tmp = Directory.systemTemp.createTempSync('ocikat-stil-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(
      p.join(tmp.path, 'org1_20240601000000.json'),
    ).writeAsStringSync(jsonEncode(rapport('org1')));
    File(p.join(tmp.path, 'geen-rapport.json')).writeAsStringSync('{"a":1}');

    final (container, ctx, ref) = await pump(tester);
    final uitkomst = await tester.runAsync(
      () => importOpenKatReports(
        ctx,
        ref,
        directoryOverride: tmp.path,
        announce: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(uitkomst, isNotNull);
    expect(uitkomst!.loaded, 1);
    expect(uitkomst.skipped, 1, reason: 'het bestand dat geen rapport is');
    expect(uitkomst.failed, isFalse);
    expect(uitkomst.updatedDeck, isFalse);
    expect(find.byType(SnackBar), findsNothing);
    expect(
      container.read(tabsProvider).current?.deckNotifier.currentState.deck,
      isNotNull,
      reason: 'zwijgen is niet hetzelfde als niets doen',
    );
  });

  test('de melding zegt per uitkomst iets anders', () {
    const l10n = AppLocalizations(Locale('nl'));
    String zin(
      ({int loaded, int skipped, bool updatedDeck, bool failed}) uitkomst,
    ) => openKatImportSummary(l10n, uitkomst);

    expect(
      zin((loaded: 0, skipped: 0, updatedDeck: false, failed: true)),
      contains('mislukt'),
    );
    expect(
      zin((loaded: 0, skipped: 3, updatedDeck: false, failed: false)),
      allOf(contains('Geen OpenKAT-rapportages'), contains('3')),
    );
    expect(
      zin((loaded: 2, skipped: 1, updatedDeck: false, failed: false)),
      allOf(contains('geïmporteerd'), contains('2'), contains('1')),
    );
    expect(
      zin((loaded: 2, skipped: 0, updatedDeck: true, failed: false)),
      contains('bijgewerkt'),
    );
  });

  test(
    'de scanner weigert een te groot bestand, met een eerlijk manifest',
    () async {
      // De invoerpoort (P5-lijn): de map komt van buiten. Een bestand boven de
      // grens wordt niet eens gelezen, en het manifest zegt wat er is
      // overgeslagen in plaats van stil te slagen.
      final tmp = Directory.systemTemp.createTempSync('ocikat-groot-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final f = File(p.join(tmp.path, 'te-groot.json'));
      final raf = f.openSync(mode: FileMode.write);
      raf.truncateSync(OpenKatDirectoryScanner.maxReportBytes + 1);
      raf.closeSync();

      final uitkomst = await const OpenKatDirectoryScanner().scan(tmp.path);
      expect(uitkomst.groups, isEmpty);
      expect(
        uitkomst.manifest.entries.single.status,
        startsWith('error: too large'),
      );
    },
  );
}
