import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';

Slide _roundTrip(Slide slide) {
  final service = MarkdownService();
  final markdown = service.generateDeck(Deck(title: 'Demo', slides: [slide]));
  final deck = service.parseDeck(markdown);
  expect(deck, isNotNull, reason: 'parseDeck gaf null voor:\n$markdown');
  return deck!.slides.single;
}

String _markdownOf(Slide slide) =>
    MarkdownService().generateDeck(Deck(title: 'Demo', slides: [slide]));

Slide _bullets({bool isDetail = false}) => Slide.create(
  SlideType.bullets,
).copyWith(title: 'Kop', bullets: const ['een'], isDetail: isDetail);

void main() {
  group('verdiepingsvlag round-trip', () {
    test('een verdiepingsslide houdt zijn vlag', () {
      expect(_roundTrip(_bullets(isDetail: true)).isDetail, isTrue);
    });

    test('een gewone slide blijft gewoon', () {
      expect(_roundTrip(_bullets()).isDetail, isFalse);
    });

    test('een deck dat de vlag niet gebruikt schrijft er niets over', () {
      // Anders zou elke bestaande presentatie bij de eerste keer opslaan
      // veranderen, puur door deze functie te introduceren.
      expect(_markdownOf(_bullets()), isNot(contains('ocideck_detail')));
      expect(_markdownOf(_bullets(isDetail: true)), contains('ocideck_detail'));
    });

    test('de vlag staat los van overslaan', () {
      final out = _roundTrip(_bullets(isDetail: true).copyWith(skipped: true));
      expect(out.isDetail, isTrue);
      expect(out.skipped, isTrue);
    });
  });

  group('slideReachesAudience', () {
    Slide plain() => Slide.create(SlideType.bullets);

    test('een gewone slide bereikt het publiek', () {
      expect(
        slideReachesAudience(
          plain(),
          presentationTlp: TlpLevel.none,
          includeDetail: true,
        ),
        isTrue,
      );
    });

    test('een verdiepingsslide valt weg in de beknopte versie', () {
      final deep = plain().copyWith(isDetail: true);
      expect(
        slideReachesAudience(
          deep,
          presentationTlp: TlpLevel.none,
          includeDetail: false,
        ),
        isFalse,
      );
      expect(
        slideReachesAudience(
          deep,
          presentationTlp: TlpLevel.none,
          includeDetail: true,
        ),
        isTrue,
      );
    });

    test('overslaan wint, ook in de volledige versie', () {
      expect(
        slideReachesAudience(
          plain().copyWith(skipped: true),
          presentationTlp: TlpLevel.none,
          includeDetail: true,
        ),
        isFalse,
      );
    });

    test('TLP wint, ook als de verdieping meegaat', () {
      expect(
        slideReachesAudience(
          plain().copyWith(tlp: TlpLevel.red),
          presentationTlp: TlpLevel.green,
          includeDetail: true,
        ),
        isFalse,
      );
    });

    test('de drie assen staan los van elkaar', () {
      // Een slide mag tegelijk openbaar én verdieping zijn: TLP vraagt wie het
      // mag zien, verdieping hoeveel detail de lezer wil. Zou dat één veld
      // zijn, dan kon dit geval niet bestaan.
      final publicDeep = plain().copyWith(tlp: TlpLevel.clear, isDetail: true);
      expect(
        slideReachesAudience(
          publicDeep,
          presentationTlp: TlpLevel.red,
          includeDetail: true,
        ),
        isTrue,
      );
      expect(
        slideReachesAudience(
          publicDeep,
          presentationTlp: TlpLevel.red,
          includeDetail: false,
        ),
        isFalse,
      );
    });
  });

  group('de beknopte versie', () {
    Deck deckWith(List<Slide> slides) => Deck(title: 'Demo', slides: slides);

    test('laat de verdiepingsslides weg en houdt de rest', () {
      final deck = deckWith([
        Slide.create(SlideType.bullets).copyWith(title: 'Verhaal'),
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Detail', isDetail: true),
        Slide.create(SlideType.bullets).copyWith(title: 'Slot'),
      ]);
      final brief = deck.slides
          .where(
            (s) => slideReachesAudience(
              s,
              presentationTlp: deck.tlp,
              includeDetail: false,
            ),
          )
          .map((s) => s.title)
          .toList();
      expect(brief, ['Verhaal', 'Slot']);
    });

    test('de volledige versie houdt alles', () {
      final deck = deckWith([
        Slide.create(SlideType.bullets).copyWith(title: 'Verhaal'),
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Detail', isDetail: true),
      ]);
      final full = deck.slides
          .where(
            (s) => slideReachesAudience(
              s,
              presentationTlp: deck.tlp,
              includeDetail: true,
            ),
          )
          .length;
      expect(full, 2);
    });
  });
}
