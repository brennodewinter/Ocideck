import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/git/deck_merge.dart';

/// Driewegs-merge van één deck (§8.6). Wat OciDeck zelf mag beslissen beslist
/// het; wat het niet mag beslissen komt als conflict terug. De harde eis eromheen
/// is P2: er verdwijnt nooit werk — niet dat van ons, en niet dat van de ander.
void main() {
  Slide bullets(String title, List<String> items) =>
      Slide.create(SlideType.bullets).copyWith(title: title, bullets: items);

  Deck deckOf(List<Slide> slides, {TlpLevel tlp = TlpLevel.none}) =>
      Deck(title: 'Kwartaal', slides: slides, tlp: tlp);

  final one = bullets('Eén', const ['a']);
  final two = bullets('Twee', const ['b']);
  final three = bullets('Drie', const ['c']);

  group('mergeDeckVersions — wat het zelf beslist', () {
    test('niemand raakte iets aan: schoon, deck ongewijzigd', () {
      final base = deckOf([one, two]);
      final result = mergeDeckVersions(
        base,
        deckOf([one, two]),
        deckOf([one, two]),
      );

      expect(result.isClean, isTrue);
      expect(result.merged.slides.map((s) => s.title), ['Eén', 'Twee']);
    });

    test('alleen wij bewerkten een slide: onze versie, geen conflict', () {
      final ourTwo = bullets('Twee', const ['b bijgewerkt']);
      final result = mergeDeckVersions(
        deckOf([one, two]),
        deckOf([one, ourTwo]),
        deckOf([one, two]),
      );

      expect(result.isClean, isTrue);
      expect(result.merged.slides[1].bullets, const ['b bijgewerkt']);
    });

    test('alleen de ander bewerkte een slide: hún versie komt erin', () {
      final theirTwo = bullets('Twee', const ['b van hen']);
      final result = mergeDeckVersions(
        deckOf([one, two]),
        deckOf([one, two]),
        deckOf([one, theirTwo]),
      );

      expect(result.isClean, isTrue);
      expect(result.merged.slides[1].bullets, const ['b van hen']);
    });

    test('beide kanten maakten dezelfde wijziging: niets te kiezen', () {
      final edited = bullets('Twee', const ['zelfde nieuwe tekst']);
      final result = mergeDeckVersions(
        deckOf([one, two]),
        deckOf([one, edited]),
        deckOf([one, edited]),
      );

      expect(result.isClean, isTrue);
      expect(result.merged.slides[1].bullets, const ['zelfde nieuwe tekst']);
    });

    test('allebei dezelfde slide weggegooid: weg, en geen conflict', () {
      final result = mergeDeckVersions(
        deckOf([one, two]),
        deckOf([one]),
        deckOf([one]),
      );

      expect(result.isClean, isTrue);
      expect(result.merged.slides.map((s) => s.title), ['Eén']);
    });

    test('allebei een eigen slide toegevoegd: allebei behouden', () {
      final ourNew = bullets('Onze nieuwe', const ['x']);
      final theirNew = bullets('Hun nieuwe', const ['y']);
      final result = mergeDeckVersions(
        deckOf([one]),
        deckOf([one, ourNew]),
        deckOf([one, theirNew]),
      );

      expect(result.isClean, isTrue);
      expect(result.merged.slides.map((s) => s.title), [
        'Eén',
        'Onze nieuwe',
        'Hun nieuwe',
      ]);
    });

    test('onze volgorde is de ruggengraat', () {
      final result = mergeDeckVersions(
        deckOf([one, two, three]),
        deckOf([three, one, two]), // wij hebben herschikt
        deckOf([one, two, three]),
      );

      expect(result.isClean, isTrue);
      expect(result.merged.slides.map((s) => s.title), ['Drie', 'Eén', 'Twee']);
    });
  });

  group('mergeDeckVersions — wat het niet mag beslissen', () {
    test('beide kanten bewerkten dezelfde slide anders: conflict', () {
      final ourTwo = bullets('Twee', const ['onze tekst']);
      final theirTwo = bullets('Twee', const ['hun tekst']);
      final result = mergeDeckVersions(
        deckOf([one, two]),
        deckOf([one, ourTwo]),
        deckOf([one, theirTwo]),
      );

      expect(result.isClean, isFalse);
      final conflict = result.conflicts.single;
      expect(conflict.baseIndex, 1);
      expect(conflict.ours!.bullets, const ['onze tekst']);
      expect(conflict.theirs!.bullets, const ['hun tekst']);
      expect(conflict.isDeleteAgainstEdit, isFalse);
      // Voorlopig staat ónze kant erin — nooit stil die van de ander.
      expect(result.merged.slides[1].bullets, const ['onze tekst']);
    });

    test(
      'wij gooiden weg, zij bewerkten: conflict, hun werk blijft zichtbaar',
      () {
        final theirTwo = bullets('Twee', const ['hun tekst']);
        final result = mergeDeckVersions(
          deckOf([one, two]),
          deckOf([one]), // wij verwijderden slide 2
          deckOf([one, theirTwo]),
        );

        expect(result.isClean, isFalse);
        final conflict = result.conflicts.single;
        expect(conflict.ours, isNull);
        expect(conflict.theirs, isNotNull);
        expect(conflict.isDeleteAgainstEdit, isTrue);
        // P2: hun bewerking verdwijnt niet stil omdat wij toevallig wisten.
        expect(
          result.merged.slides.map((s) => s.title),
          contains('Twee'),
          reason: 'andermans werk blijft staan tot er gekozen is',
        );
      },
    );

    test('verplaatsen botst niet met bewerken', () {
      // Wij schoven hem op, zij pasten de tekst aan: dat is geen echt conflict.
      final theirTwo = bullets('Twee', const ['hun tekst']);
      final result = mergeDeckVersions(
        deckOf([one, two, three]),
        deckOf([two, one, three]), // alleen verplaatst
        deckOf([one, theirTwo, three]),
      );

      expect(result.isClean, isTrue);
      expect(
        result.merged.slides.firstWhere((s) => s.title == 'Twee').bullets,
        const ['hun tekst'],
      );
    });
  });

  group('mergeDeckVersions — classificatie is fail-safe', () {
    test('de strengste TLP van de twee wint', () {
      // Zij verhoogden naar RED, wij niet. Onze metadata blindelings nemen zou
      // die verhoging stil weggooien; dat mag niet.
      final result = mergeDeckVersions(
        deckOf([one], tlp: TlpLevel.none),
        deckOf([one], tlp: TlpLevel.green),
        deckOf([one], tlp: TlpLevel.red),
      );

      expect(result.merged.tlp, TlpLevel.red);
    });

    test('onze hogere classificatie blijft ook staan', () {
      final result = mergeDeckVersions(
        deckOf([one], tlp: TlpLevel.none),
        deckOf([one], tlp: TlpLevel.amber),
        deckOf([one], tlp: TlpLevel.none),
      );

      expect(result.merged.tlp, TlpLevel.amber);
    });
  });
}
