// Een opslag die de grafiekcijfers niet kwijt kon, moet de gebruiker bereiken.
//
// Het opslaan haalt de cijfers uit de markdown en zet ze in `data/`. Mislukt dat
// tweede deel, dan bestaan ze alleen nog in het venster — en zonder melding leest
// de gebruiker een geslaagde opslag. De keten heeft twee schakels, en die worden
// hier apart getoetst: de opslag zet het signaal, en de shell toont het.
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() async {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
    temp = await Directory.systemTemp.createTemp('ocideck_chartsave_');
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  /// Een grafiek die haar cijfers buiten de projectmap wil parkeren. Dat mag
  /// niet (insluiting), dus het databestand wordt nooit geschreven — precies het
  /// geval waarin de cijfers na het opslaan nergens meer staan.
  Deck deckWithUnwritableChart() => Deck(
    title: 'Cijfers',
    slides: [
      Slide.create(SlideType.chart).copyWith(
        customMarkdown: const ChartSpec(
          type: ChartType.line,
          title: 'Omzet',
          source: '../geheim.json',
          x: ['Jan', 'Feb'],
          series: [
            ChartSeries(name: 'Omzet', data: [120, 138]),
          ],
        ).toBlock(),
      ),
    ],
  );

  test('een opslag die de cijfers niet kwijt kan, zet het signaal', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final tab = container.read(tabsProvider).current!;
    final project = Directory(p.join(temp.path, 'project'));
    await project.create();
    tab.deckNotifier
      ..loadDeck(
        deckWithUnwritableChart(),
        filePath: p.join(project.path, 'deck.md'),
      )
      ..markDirty();

    expect(await tab.deckNotifier.save(), isTrue);

    final warning = container.read(chartDataWarningProvider);
    expect(warning, isNotNull);
    expect(warning!.sources, ['../geheim.json']);
    // Opslaan, niet lezen: dat verschil bepaalt welke zin de gebruiker krijgt.
    expect(warning.whileSaving, isTrue);
  });

  test('een opslag die de cijfers niet kwijt kan, houdt ze inline in de .md '
      'en laat het tabblad vuil (#1950)', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final tab = container.read(tabsProvider).current!;
    final project = Directory(p.join(temp.path, 'project'));
    await project.create();
    tab.deckNotifier
      ..loadDeck(
        deckWithUnwritableChart(),
        filePath: p.join(project.path, 'deck.md'),
      )
      ..markDirty();

    expect(await tab.deckNotifier.save(), isTrue);

    // De cijfers staan nog in de .md — geen verwijzing naar een leeg bestand.
    final md = await File(p.join(project.path, 'deck.md')).readAsString();
    expect(md, contains('"data"'));
    expect(md, contains('120'));
    expect(md, contains('138'));

    // Het tabblad is niet schoon: de opslag is niet compleet.
    expect(tab.deckNotifier.state.isDirty, isTrue);
  });

  test('een schone opslag zet geen signaal', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final tab = container.read(tabsProvider).current!;
    tab.deckNotifier
      ..loadDeck(
        Deck(
          title: 'Gewoon',
          slides: [Slide.create(SlideType.title).copyWith(title: 'Gewoon')],
        ),
        filePath: p.join(temp.path, 'deck.md'),
      )
      ..markDirty();

    expect(await tab.deckNotifier.save(), isTrue);
    expect(container.read(chartDataWarningProvider), isNull);
  });

  testWidgets('de shell toont de opslagklacht als foutmelding', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    // Begrensd doorpompen in plaats van `pumpAndSettle`: de shell houdt
    // achtergrondscans warm die blijven herplannen, en dan komt settle nooit
    // tot rust. Een handvol frames is genoeg voor de snackbar-animatie.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );

    container.read(chartDataWarningProvider.notifier).state = ChartDataWarning(
      const ['data/omzet.json'],
      whileSaving: true,
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Zegt dat de cijfers níét zijn opgeslagen — niet dat een grafiek leeg
    // blijft; dat laatste is het lees-geval en vraagt iets anders van de lezer.
    expect(
      find.textContaining('Grafiekcijfers zijn niet opgeslagen'),
      findsOneWidget,
    );
    expect(find.textContaining('data/omzet.json'), findsOneWidget);
  });
}
