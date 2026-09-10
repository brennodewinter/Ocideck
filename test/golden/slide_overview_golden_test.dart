@Tags(['golden'])
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
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

Future<void> _pumpOverview(
  WidgetTester tester,
  ProviderContainer container,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final baseTheme = AppTheme.light;
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
    final container = _deck();
    addTearDown(container.dispose);
    await _pumpOverview(tester, container, const Size(1200, 800));

    await expectLater(
      find.byKey(_surfaceKey),
      matchesGoldenFile('goldens/slide_overview_wide.png'),
    );
  });

  testWidgets('smal slide-overzicht met dropdoel', (tester) async {
    final container = _deck();
    addTearDown(container.dispose);
    await _pumpOverview(tester, container, const Size(520, 800));

    final source = tester.getCenter(find.byIcon(Icons.drag_indicator).first);
    final target = tester.getCenter(find.byType(DragTarget<int>).at(1));
    final gesture = await tester.startGesture(source);
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump(const Duration(milliseconds: 150));
    final targetCard = find.descendant(
      of: find.byType(DragTarget<int>).at(1),
      matching: find.byType(AnimatedContainer),
    );
    final decoration =
        tester.widget<AnimatedContainer>(targetCard).decoration
            as BoxDecoration;
    expect((decoration.border! as Border).top.width, 3);

    await expectLater(
      find.byKey(_surfaceKey),
      matchesGoldenFile('goldens/slide_overview_narrow_drop_target.png'),
    );

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
