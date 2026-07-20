import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  });

  // Regression: "A _RenderLayoutBuilder was mutated…" — reordering the slide
  // list (and resizing, which drives the list's settle detection) while it is
  // laid out used to crash. Reordering + resizing must now pump cleanly.
  testWidgets('reordering slides during layout/resize does not crash', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final deckNotifier = container.read(tabsProvider).current!.deckNotifier;
    deckNotifier.loadDeck(
      Deck(
        title: 'Deck',
        slides: [
          Slide.create(SlideType.title).copyWith(title: 'Een'),
          Slide.create(SlideType.bullets).copyWith(title: 'Twee'),
          Slide.create(SlideType.bullets).copyWith(title: 'Drie'),
          Slide.create(SlideType.section).copyWith(title: 'Vier'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Reorder, then immediately resize so the list rebuilds while settling.
    deckNotifier.reorderSlides(3, 0);
    await tester.pump();
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .state
          .deck!
          .slides
          .map((s) => s.title)
          .toList(),
      ['Vier', 'Een', 'Twee', 'Drie'],
    );
  });
}
