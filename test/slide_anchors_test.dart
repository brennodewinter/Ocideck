import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/slide_anchors.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// De ankerhelper en de deck-operatie achter de sprong-uit (#1162).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('slugifyAnchor', () {
    test('maakt een ASCII-veilige slug van een kop', () {
      expect(slugifyAnchor('Prijzen & Demo'), 'prijzen-demo');
      expect(slugifyAnchor('  Hoofd-Menu!  '), 'hoofd-menu');
    });

    test('valt terug op "dia" bij een lege of tekenloze kop', () {
      expect(slugifyAnchor(''), 'dia');
      expect(slugifyAnchor('小结'), 'dia');
    });
  });

  group('uniqueAnchor', () {
    test('laat een vrij anker ongemoeid', () {
      expect(uniqueAnchor('prijzen', {'menu'}), 'prijzen');
    });

    test('hangt een teller aan bij een botsing', () {
      expect(uniqueAnchor('dia', {'dia', 'dia-2'}), 'dia-3');
    });
  });

  group('setSlideJump', () {
    Deck deckWith(List<String> titles) => Deck(
      title: 'Demo',
      slides: [
        for (final t in titles)
          Slide.create(SlideType.bullets).copyWith(title: t, bullets: ['x']),
      ],
    );

    test('kent de doeldia een anker toe en wijst de brondia erheen', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(deckProvider.notifier);
      notifier.loadDeck(deckWith(['Menu', 'Tak A', 'Slot']));

      notifier.setSlideJump(1, 0); // Tak A -> Menu

      final slides = container.read(deckProvider).deck!.slides;
      expect(slides[0].anchor, isNotEmpty);
      expect(slides[1].nextAnchor, slides[0].anchor);
    });

    test('hergebruikt een bestaand anker i.p.v. het te vervangen', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(deckProvider.notifier);
      notifier.loadDeck(deckWith(['Menu', 'Tak A', 'Tak B']));

      notifier.setSlideJump(1, 0);
      final firstAnchor = container.read(deckProvider).deck!.slides[0].anchor;
      notifier.setSlideJump(2, 0); // tweede sprong naar dezelfde doeldia

      final slides = container.read(deckProvider).deck!.slides;
      expect(slides[0].anchor, firstAnchor, reason: 'anker is bevroren');
      expect(slides[2].nextAnchor, firstAnchor);
    });

    test('wist de sprong met een null-doel', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(deckProvider.notifier);
      notifier.loadDeck(deckWith(['Menu', 'Tak A']));

      notifier.setSlideJump(1, 0);
      expect(
        container.read(deckProvider).deck!.slides[1].nextAnchor,
        isNotEmpty,
      );

      notifier.setSlideJump(1, null);
      expect(container.read(deckProvider).deck!.slides[1].nextAnchor, isEmpty);
    });

    test('negeert een sprong naar zichzelf', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(deckProvider.notifier);
      notifier.loadDeck(deckWith(['Menu', 'Tak A']));

      notifier.setSlideJump(0, 0);

      final slides = container.read(deckProvider).deck!.slides;
      expect(slides[0].nextAnchor, isEmpty);
      expect(slides[0].anchor, isEmpty);
    });
  });
}
