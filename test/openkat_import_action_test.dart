@TestOn('vm')
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/openkat/openkat_reporting_models.dart';
import 'package:ocideck/models/openkat/openkat_wizard_models.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/openkat/openkat_directory_scanner.dart';
import 'package:ocideck/state/openkat_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/shell/openkat_import_action_io.dart';
import 'package:ocideck/widgets/shell/openkat_import_summary.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'openkat_wizard_test_fakes.dart';

class _RecordingGateway extends FakeOpenKatWizardGateway {
  String? preparedDirectory;

  _RecordingGateway();

  @override
  Future<OpenKatWizardScan> prepare(String directory) {
    preparedDirectory = directory;
    return super.prepare(directory);
  }
}

/// Het invoerpunt van de OpenKAT-import: mapkeuze → wizard → deck.
///
/// De mapkiezer zelf laat zich onder `flutter test` niet aansturen (statische
/// FilePicker). De actie krijgt daarom de echte wizardroute met een fake
/// headless gateway: alleen de IO-grens is vervangen.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  });

  Future<(ProviderContainer, BuildContext, WidgetRef)> pump(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext ctx;
    late WidgetRef reff;
    final container = ProviderContainer();
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

  Future<void> closeHarness(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump();
  }

  Future<void> finishNewWizard(WidgetTester tester) async {
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final family = find.byKey(const ValueKey('openkat-family-dataQuality'));
    await tester.ensureVisible(family);
    await tester.tap(family);
    await tester.pump(const Duration(milliseconds: 50));
    final dataQuality = find.byKey(
      const ValueKey('openkat-recipe-dataQuality'),
    );
    await tester.ensureVisible(dataQuality);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(dataQuality);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('openkat-primary-action')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Controleren'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('openkat-primary-action')));
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('de wizarduitkomst opent als deck in een nieuwe tab', (
    tester,
  ) async {
    final (container, ctx, ref) = await pump(tester);
    final gateway = FakeOpenKatWizardGateway();
    final future = importOpenKatReports(
      ctx,
      ref,
      directoryOverride: '/rapportages',
      gatewayOverride: gateway,
    );
    await finishNewWizard(tester);
    final outcome = await future;

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
    expect(outcome?.loaded, gateway.prepared.preview.reportCount);
    expect(
      container.read(openKatDirectoryProvider),
      gateway.prepared.directory,
      reason: 'pas de geslaagde build maakt de bron de nieuwe voorkeur',
    );
    final current = container.read(tabsProvider).current!;
    expect(
      container
          .read(openKatProvider.notifier)
          .sessionForDeck(current.recoveryId)
          ?.directory,
      gateway.prepared.directory,
    );
    await tester.pump();
    expect(find.textContaining('Rapport gemaakt'), findsOneWidget);
    await closeHarness(tester, container);
  });

  testWidgets('annuleren bewaart een nieuw gekozen bronpad niet', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'openkatReportDirectory': '/oude-bron',
    });
    final (container, ctx, ref) = await pump(tester);
    container.read(openKatProvider);
    await tester.pump(const Duration(milliseconds: 50));
    final future = importOpenKatReports(
      ctx,
      ref,
      directoryOverride: '/nieuwe-bron',
      gatewayOverride: FakeOpenKatWizardGateway(
        prepared: wizardScan(reportCount: 0),
      ),
    );
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.text('Annuleren'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(await future, isNull);
    expect(container.read(openKatDirectoryProvider), '/oude-bron');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('openkatReportDirectory'), '/oude-bron');
    await closeHarness(tester, container);
  });

  testWidgets('een lege scan opent geen deck en kan worden geannuleerd', (
    tester,
  ) async {
    final (container, ctx, ref) = await pump(tester);
    final future = importOpenKatReports(
      ctx,
      ref,
      directoryOverride: '/leeg',
      gatewayOverride: FakeOpenKatWizardGateway(
        prepared: wizardScan(reportCount: 0),
      ),
    );
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.text('Deze map bevat geen bruikbare rapportages'),
      findsOneWidget,
    );
    expect(
      container.read(tabsProvider).current?.deckNotifier.currentState.deck,
      isNull,
      reason: 'geen deck openen om niets',
    );
    await tester.tap(find.text('Annuleren'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(await future, isNull);
    await closeHarness(tester, container);
  });

  testWidgets('bijwerken houdt dezelfde tab en gebruikt de bevestigingsroute', (
    tester,
  ) async {
    final (container, ctx, ref) = await pump(tester);
    container.read(tabsProvider.notifier).newEmptyTab();
    container
        .read(tabsProvider)
        .current!
        .deckNotifier
        .loadDeck(
          const Deck(
            title: 'Bestaand OpenKAT',
            slides: [
              Slide(
                id: 'generated',
                type: SlideType.title,
                notes:
                    '<!-- ocideck_openkat_view: report.weekly-comparison.org.org-a.title -->',
              ),
            ],
          ),
        );
    final tabsVoor = container.read(tabsProvider).tabs.length;
    final gateway = FakeOpenKatWizardGateway();
    final future = importOpenKatReports(
      ctx,
      ref,
      directoryOverride: '/rapportages',
      gatewayOverride: gateway,
    );
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Rapport bijwerken'));
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final outcome = await future;

    expect(container.read(tabsProvider).tabs.length, tabsVoor);
    expect(outcome?.updatedDeck, isTrue);
    expect(gateway.lastExisting?.title, 'Bestaand OpenKAT');
    await closeHarness(tester, container);
  });

  testWidgets('A naar B naar A gebruikt weer de bron en het recept van A', (
    tester,
  ) async {
    final (container, ctx, ref) = await pump(tester);
    final tabs = container.read(tabsProvider.notifier);
    const generated = Deck(
      title: 'OpenKAT',
      slides: [
        Slide(
          id: 'generated',
          type: SlideType.title,
          notes:
              '<!-- ocideck_openkat_view: report.management-overview.title -->',
        ),
      ],
    );
    final tabA = container.read(tabsProvider).current!;
    tabA.deckNotifier.loadDeck(generated.copyWith(title: 'A'));
    final recipeA = OpenKatWizardRecipe(
      scenarioId: OpenKatWizardScenarioId.portfolio,
      currentAsOf: DateTime.utc(2026, 7, 1),
      language: OpenKatReportLanguage.dutch,
      title: 'Recept A',
    );
    container
        .read(openKatProvider.notifier)
        .rememberDeckSession(
          deckId: tabA.recoveryId,
          directory: '/bron-a',
          recipe: recipeA,
        );
    tabs.newEmptyTab();
    final tabB = container.read(tabsProvider).current!;
    tabB.deckNotifier.loadDeck(generated.copyWith(title: 'B'));
    final recipeB = OpenKatWizardRecipe(
      scenarioId: OpenKatWizardScenarioId.portfolio,
      currentAsOf: DateTime.utc(2026, 7, 1),
      language: OpenKatReportLanguage.english,
      title: 'Recipe B',
    );
    container
        .read(openKatProvider.notifier)
        .rememberDeckSession(
          deckId: tabB.recoveryId,
          directory: '/bron-b',
          recipe: recipeB,
        );
    tabs.selectTab(0);
    final gateway = _RecordingGateway();

    final future = importOpenKatReports(
      ctx,
      ref,
      gatewayOverride: gateway,
      announce: false,
    );
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Rapport bijwerken'));
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await future;

    expect(gateway.preparedDirectory, '/bron-a');
    expect(gateway.lastRecipe?.title, 'Recept A');
    expect(gateway.lastRecipe?.language, OpenKatReportLanguage.dutch);
    await closeHarness(tester, container);
  });

  testWidgets('met announce uit meldt de actie niets en geeft ze de uitkomst', (
    tester,
  ) async {
    // De route van het instellingenvenster: daar is een snackbar achter een
    // modale dialoog geen melding, dus meldt het paneel zelf — en dan moet de
    // actie de tellingen wél teruggeven.
    final (container, ctx, ref) = await pump(tester);
    final gateway = FakeOpenKatWizardGateway(
      prepared: wizardScan(reportCount: 1, skippedCount: 1),
    );
    final future = importOpenKatReports(
      ctx,
      ref,
      directoryOverride: '/rapportages',
      announce: false,
      gatewayOverride: gateway,
    );
    await finishNewWizard(tester);
    final uitkomst = await future;

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
    await closeHarness(tester, container);
  });

  test('de melding zegt per uitkomst iets anders', () {
    const l10n = AppLocalizations(Locale('nl'));
    String zin(
      ({int loaded, int skipped, bool updatedDeck, bool failed}) uitkomst,
    ) => openKatImportSummary(l10n, uitkomst);

    expect(
      zin((loaded: 0, skipped: 0, updatedDeck: false, failed: true)),
      contains('niet worden gemaakt'),
    );
    expect(
      zin((loaded: 0, skipped: 3, updatedDeck: false, failed: false)),
      allOf(contains('Geen OpenKAT-rapportages'), contains('3')),
    );
    expect(
      zin((loaded: 2, skipped: 1, updatedDeck: false, failed: false)),
      allOf(contains('Rapport gemaakt'), contains('2'), contains('1')),
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
