@Tags(['golden'])
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/presentation_timing.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/panels/preview_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _surfaceKey = ValueKey('slide-overview-golden-surface');

ProviderContainer _deck() {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer();
  final notifier = container.read(deckProvider.notifier);
  notifier.newDeck('Kwartaalpresentatie');
  notifier.insertSlides([
    Slide.create(SlideType.section).copyWith(title: 'Resultaten'),
    Slide.create(SlideType.bullets).copyWith(
      title: 'Hoofdpunten',
      bullets: const ['Eerste punt', 'Tweede punt', 'Derde punt'],
    ),
    Slide.create(SlideType.quote).copyWith(
      title: 'Wat gebruikers zeggen',
      quote: 'Een helder overzicht maakt ordenen eenvoudig.',
    ),
    Slide.create(SlideType.table).copyWith(
      title: 'Planning',
      tableRows: const [
        ['Onderdeel', 'Status'],
        ['Ontwerp', 'Gereed'],
        ['Uitvoering', 'Bezig'],
      ],
    ),
    Slide.create(SlideType.section).copyWith(title: 'Vragen'),
  ]);
  return container;
}

ProviderContainer _igniteDeck() {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer();
  final notifier = container.read(deckProvider.notifier);
  notifier.newDeck(
    'Ignite',
    slides: List.generate(
      20,
      (index) => Slide.create(
        SlideType.section,
      ).copyWith(title: 'Ignite ${index + 1}'),
    ),
  );
  notifier.loadDeck(
    container
        .read(deckProvider)
        .deck!
        .copyWith(
          presentationTiming: const PresentationTimingConfig.ignitePreset(),
        ),
    preserveThemeProfile: true,
  );
  return container;
}

Future<void> _pumpOverview(
  WidgetTester tester,
  ProviderContainer container,
  Size size, {
  bool dark = false,
}) async {
  AppTheme.isDark = dark;
  addTearDown(() => AppTheme.isDark = false);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final baseTheme = AppTheme.fromProfile(
    dark ? AppAppearanceProfile.dark : AppAppearanceProfile.basic,
  );
  final deck = container.read(deckProvider).deck!;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: baseTheme.copyWith(
          textTheme: baseTheme.textTheme.apply(fontFamily: 'Ahem'),
        ),
        home: RepaintBoundary(
          key: _surfaceKey,
          child: FullDeckPreview(
            deck: deck,
            themeProfile: deck.themeProfile,
            editable: true,
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 150));
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('breed slide-overzicht', (tester) async {
    for (final dark in [false, true]) {
      final container = _deck();
      addTearDown(container.dispose);
      await _pumpOverview(tester, container, const Size(1200, 800), dark: dark);
      // MaterialApp animeert de thema-wissel over 200ms; de opname moet wachten
      // tot de ColorScheme-lerp afgelopen is of de golden legt een mengbeeld
      // van licht én donker vast.
      await tester.pump(const Duration(milliseconds: 250));

      await expectLater(
        find.byKey(_surfaceKey),
        matchesGoldenFile(
          'goldens/slide_overview_wide${dark ? '_dark' : ''}.png',
        ),
      );
    }
  });

  testWidgets('smal slide-overzicht met invoegmarkering', (tester) async {
    final container = _deck();
    addTearDown(container.dispose);
    await _pumpOverview(tester, container, const Size(520, 800));

    // Het merklogo in elke dia decodeert asynchroon; onder last verschilt het
    // moment waarop hij er staat. Vooraf precachen maakt de opname stabiel.
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/librekat-logo.png'),
        tester.element(find.byType(FullDeckPreview)),
      ),
    );
    await tester.pump();

    // Sleep de tweede kaart over de linkerhelft van de eerste: de markering
    // toont slot 0 als accentlijn vóór die kaart, de kaart zelf kleurt niet
    // als doel (#2362).
    final source = tester.getCenter(find.byIcon(Icons.drag_indicator).at(1));
    final target = tester.getRect(find.byType(DragTarget<int>).at(0));
    final gesture = await tester.startGesture(source);
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    await gesture.moveTo(
      Offset(target.left + target.width * 0.2, target.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('insert-marker')), findsOneWidget);

    await expectLater(
      find.byKey(_surfaceKey),
      matchesGoldenFile('goldens/slide_overview_narrow_insert_marker.png'),
    );

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('ingezoomd slide-overzicht toont grotere tegels', (tester) async {
    final container = _deck();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).setSlideOverviewZoom(2);
    await _pumpOverview(tester, container, const Size(1200, 800));

    expect(find.text('200%'), findsOneWidget);
    await expectLater(
      find.byKey(_surfaceKey),
      matchesGoldenFile('goldens/slide_overview_zoomed.png'),
    );
  });

  testWidgets('Ignite-storyboard toont twintig dia\'s en vijf minuten', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      final container = _igniteDeck();
      addTearDown(container.dispose);
      await _pumpOverview(tester, container, const Size(1200, 800), dark: dark);
      // Zelfde thematransitie als bij het brede overzicht: eerst laten uitlopen.
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Ignite-storyboard'), findsOneWidget);
      expect(find.textContaining('5:00'), findsOneWidget);
      expect(find.text('20 / 20'), findsOneWidget);
      await expectLater(
        find.byKey(_surfaceKey),
        matchesGoldenFile(
          'goldens/slide_overview_ignite${dark ? '_dark' : ''}.png',
        ),
      );
    }
  });
}
