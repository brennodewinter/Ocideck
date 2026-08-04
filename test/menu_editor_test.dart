import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/menu_blocks.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/widgets/editors/menu_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Fase 3 van #1162: de editor van het keuze-menu-diatype. Getoetst zoals de
// gebruiker hem bedient — een blok toevoegen, een label typen, een doeldia kiezen.
Widget _host(ProviderContainer container, DeckNotifier notifier) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            child: Consumer(
              builder: (context, ref, _) {
                final slide = ref.watch(deckProvider).deck!.slides[0];
                return MenuEditor(
                  slide: slide,
                  onUpdate: (s) => notifier.updateSlide(0, s),
                  imageService: ImageService(),
                );
              },
            ),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ({ProviderContainer container, DeckNotifier notifier}) boot() {
    final container = ProviderContainer();
    final notifier = container.read(deckProvider.notifier);
    notifier.loadDeck(
      Deck(
        title: 'D',
        slides: [
          Slide.create(SlideType.menu).copyWith(title: 'Menu'),
          Slide.create(SlideType.bullets).copyWith(title: 'Prijzen'),
        ],
      ),
    );
    return (container: container, notifier: notifier);
  }

  testWidgets('een blok toevoegen en labelen', (tester) async {
    final b = boot();
    addTearDown(b.container.dispose);
    await tester.pumpWidget(_host(b.container, b.notifier));

    await tester.tap(find.text('Blok toevoegen'));
    await tester.pumpAndSettle();
    expect(b.container.read(deckProvider).deck!.slides[0].bullets.length, 1);

    await tester.enterText(find.byType(TextField).first, 'Prijzen');
    await tester.pumpAndSettle();
    final blocks = menuBlocksFor(
      b.container.read(deckProvider).deck!.slides[0].bullets,
    );
    expect(blocks.first.label, 'Prijzen');
    expect(blocks.first.hasTarget, isFalse);
  });

  testWidgets('een doeldia kiezen kent de doeldia een anker toe', (
    tester,
  ) async {
    final b = boot();
    addTearDown(b.container.dispose);
    await tester.pumpWidget(_host(b.container, b.notifier));

    await tester.tap(find.text('Blok toevoegen'));
    await tester.pumpAndSettle();

    // Kies dia 2 ("Prijzen") als doel via de keuzelijst.
    await tester.tap(find.text('Geen sprong'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2. Prijzen').last);
    await tester.pumpAndSettle();

    final deck = b.container.read(deckProvider).deck!;
    expect(
      deck.slides[1].anchor,
      isNotEmpty,
      reason: 'doeldia kreeg een anker',
    );
    final block = menuBlocksFor(deck.slides[0].bullets).first;
    expect(block.targetAnchor, deck.slides[1].anchor);
  });
}
