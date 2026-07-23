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

  Map<String, dynamic> rapport(String code, String datum) => {
    'organization': {'code': code, 'name': 'Organisatie $code'},
    'report_date': datum,
    'systems': [
      {'ooi': 'hostname|example.com'},
    ],
    'findings': [
      {
        'finding_type': {'id': 'KAT-001', 'name': 'Open poort'},
        'severity': 'high',
        'primary_key': 'f1',
        'ooi': 'hostname|example.com',
      },
    ],
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
      p.join(tmp.path, 'a.json'),
    ).writeAsStringSync(jsonEncode(rapport('org1', '2024-06-01T00:00:00Z')));

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
      p.join(tmp.path, 'a.json'),
    ).writeAsStringSync(jsonEncode(rapport('org1', '2024-06-01T00:00:00Z')));

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
      p.join(tmp.path, 'b.json'),
    ).writeAsStringSync(jsonEncode(rapport('org1', '2024-07-01T00:00:00Z')));
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
