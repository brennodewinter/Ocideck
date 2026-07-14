import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/markdown_validator.dart';

void main() {
  final service = MarkdownService();
  final validator = MarkdownValidator();

  group('effectieve stand', () {
    test('de slide overschrijft het deck', () {
      // Anders dan bij TLP wint hier niet het strengste niveau. Een deck op
      // `accept` (de hele briefing is bekend) met één slide op `redact` (dit ene
      // gegeven mag niemand zien) moet gewoon werken: de auteur van die slide
      // weet het beter.
      expect(
        effectivePrivacyDisposition(
          deck: PrivacyDisposition.accept,
          slide: PrivacyDisposition.redact,
        ),
        PrivacyDisposition.redact,
      );
      expect(
        effectivePrivacyDisposition(
          deck: PrivacyDisposition.redact,
          slide: PrivacyDisposition.accept,
        ),
        PrivacyDisposition.accept,
      );
    });

    test('zonder slidestand geldt die van het deck', () {
      expect(
        effectivePrivacyDisposition(
          deck: PrivacyDisposition.shield,
          slide: null,
        ),
        PrivacyDisposition.shield,
      );
    });

    test('warn is de enige stand die niet als afgehandeld telt', () {
      expect(PrivacyDisposition.warn.isResolved, isFalse);
      for (final d in [
        PrivacyDisposition.accept,
        PrivacyDisposition.shield,
        PrivacyDisposition.redact,
      ]) {
        expect(d.isResolved, isTrue, reason: d.key);
      }
    });
  });

  group('markdown round-trip', () {
    test('de deckstand reist mee in de front matter', () {
      final deck = Deck(
        title: 'Briefing',
        privacy: PrivacyDisposition.accept,
        slides: [Slide.create(SlideType.bullets)],
      );
      final markdown = service.generateDeck(deck);
      expect(markdown, contains('privacy: accept'));

      final back = service.parseDeck(markdown)!;
      expect(back.privacy, PrivacyDisposition.accept);
    });

    test('de standaardstand wordt niet weggeschreven', () {
      // `warn` is de default; hem toch schrijven zou elke bestaande .md bij het
      // eerste opslaan een regel dikker maken zonder dat er iets veranderd is.
      final deck = Deck(title: 'D', slides: [Slide.create(SlideType.bullets)]);
      expect(service.generateDeck(deck), isNot(contains('privacy:')));
    });

    test('de slidestand reist mee als comment-directive', () {
      final deck = Deck(
        title: 'D',
        slides: [
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Kop', privacy: PrivacyDisposition.redact),
        ],
      );
      final markdown = service.generateDeck(deck);
      expect(markdown, contains('<!-- ocideck_privacy: redact -->'));

      final back = service.parseDeck(markdown)!;
      expect(back.slides.single.privacy, PrivacyDisposition.redact);
    });

    test('een slide zonder eigen stand houdt null (erft van het deck)', () {
      final deck = Deck(
        title: 'D',
        privacy: PrivacyDisposition.shield,
        slides: [Slide.create(SlideType.bullets).copyWith(title: 'Kop')],
      );
      final back = service.parseDeck(service.generateDeck(deck))!;
      expect(back.slides.single.privacy, isNull);
      expect(back.privacy, PrivacyDisposition.shield);
    });

    test('werkt ook op een gestructureerd slidetype (code)', () {
      // De fenced parsers hebben hun eigen route door de parser heen; de
      // dispositie wordt op één plek gezet, dus dit mag geen gat zijn.
      final deck = Deck(
        title: 'D',
        slides: [
          Slide.create(SlideType.code).copyWith(
            customMarkdown: 'print("hoi");',
            codeLanguage: 'dart',
            privacy: PrivacyDisposition.accept,
          ),
        ],
      );
      final back = service.parseDeck(service.generateDeck(deck))!;
      expect(back.slides.single.privacy, PrivacyDisposition.accept);
    });

    test('een onbekende waarde valt terug op warn', () {
      const markdown =
          '---\nmarp: true\ntheme: ocideck\nprivacy: onzin\n---\n\n# Kop\n';
      expect(service.parseDeck(markdown)!.privacy, PrivacyDisposition.warn);
    });
  });

  test('de validator kent de directive en klaagt niet', () {
    final deck = Deck(
      title: 'D',
      slides: [
        Slide.create(SlideType.bullets).copyWith(
          title: 'Kop',
          bullets: ['punt'],
          privacy: PrivacyDisposition.shield,
        ),
      ],
    );
    final result = validator.validate(service.generateDeck(deck));
    expect(result.isValid, isTrue);
    expect(
      result.issues.any((i) => i.message.toLowerCase().contains('privacy')),
      isFalse,
    );
  });
}
