import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/provider_warmup.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/panels/slide_list_panel.dart';

// De melding uit het veld: "setState() or markNeedsBuild() called during build",
// gegooid vanuit SlideThumbnail.build. Een afgeleide provider die niemand leest
// raakt bij een deckwijziging vuil zonder geplande verversing; de eerste widget
// die hem daarna leest doet die verversing middenin de build, en dat mag niet.
//
// Deze test bouwt precies die situatie na: de rail verdwijnt (niemand leest de
// keten meer), het deck verandert, de rail komt terug en de thumbnail is de
// eerste lezer. Zonder de warmhouder in het tabblad gooit dit.
void main() {
  Deck deckWith(int slides) => Deck(
    title: 'T',
    slides: [
      for (var i = 0; i < slides; i++)
        Slide.create(SlideType.bullets).copyWith(
          title: 'Slide $i',
          bullets: [for (var b = 0; b < 6; b++) 'Bullet $b met wat tekst'],
        ),
    ],
  );

  /// Staat voor _TabContent: leeft zolang het tabblad leeft en houdt de keten aan.
  Widget tabRoot(Widget child) => _Warm(child: child);

  testWidgets('een rail die terugkomt na een deckwijziging gooit niet', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(deckProvider.notifier).loadDeck(deckWith(3));

    Widget app({required bool showRail}) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: tabRoot(
            showRail
                ? const SizedBox(
                    width: 320,
                    child: SlideListPanel(railWidth: 320),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(showRail: true));
    await tester.pump();

    // Rail weg: zonder de warmhouder leest niemand de keten meer.
    await tester.pumpWidget(app(showRail: false));
    await tester.pump();

    // Deck verandert terwijl er geen thumbnail luistert.
    container.read(deckProvider.notifier).loadDeck(deckWith(5));

    // Rail terug: de thumbnail leest de keten midden in zijn eigen build.
    await tester.pumpWidget(app(showRail: true));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

class _Warm extends ConsumerWidget {
  final Widget child;
  const _Warm({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    warmTabDerivedProviders(ref);
    return child;
  }
}
