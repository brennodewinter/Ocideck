// De kwaliteitsdispositie: een slide waarvan de auteur zegt "dit is zo bedoeld".
//
// De tegenhanger van `privacy_disposition_test.dart`, en met opzet dezelfde
// vorm: een directive die round-trippt, een standaard die niets wegschrijft, en
// een filter dat alleen de meldingen van een afgehandelde slide onderdrukt.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/quality_disposition.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_quality_provider.dart';

void main() {
  final service = MarkdownService();

  Deck deckWith(List<QualityDisposition> dispositions) => Deck(
    title: 'Test',
    slides: [
      for (final d in dispositions)
        Slide.create(SlideType.bullets).copyWith(title: 'Slide', quality: d),
    ],
  );

  group('sleutels', () {
    test('elke waarde heeft een sleutel en leest terug', () {
      for (final value in QualityDisposition.values) {
        expect(QualityDispositionX.fromKey(value.key), value);
      }
    });

    test('een onbekende sleutel valt terug op warn, niet op accept', () {
      // Een deck uit een nieuwere versie met een stand die wij niet kennen mag
      // niet stilletjes als afgehandeld gelden — dan onderdrukt een oudere
      // OciDeck meldingen die hij niet begrijpt.
      expect(QualityDispositionX.fromKey('zwevend'), QualityDisposition.warn);
      expect(QualityDispositionX.fromKey(''), QualityDisposition.warn);
      expect(QualityDispositionX.fromKey('ACCEPT'), QualityDisposition.accept);
    });

    test('alleen accept geldt als afgehandeld', () {
      expect(QualityDisposition.warn.isResolved, isFalse);
      expect(QualityDisposition.accept.isResolved, isTrue);
    });
  });

  group('markdown', () {
    test('accept reist mee door schrijven en teruglezen', () {
      final deck = deckWith([QualityDisposition.accept]);
      final markdown = service.generateDeck(deck);

      expect(markdown, contains('<!-- ocideck_quality: accept -->'));
      final parsed = service.parseDeck(markdown);
      expect(parsed!.slides.single.quality, QualityDisposition.accept);
    });

    test('de standaard schrijft niets weg', () {
      // Anders zou elke bestaande .md bij het eerste opslaan dikker worden
      // zonder dat er iets veranderd is.
      final markdown = service.generateDeck(
        deckWith([QualityDisposition.warn]),
      );
      expect(markdown, isNot(contains('ocideck_quality')));
    });

    test('een deck zonder de directive leest als warn', () {
      final parsed = service.parseDeck(
        '---\nmarp: true\n---\n\n# Slide\n\n- Punt\n',
      );
      expect(parsed!.slides.single.quality, QualityDisposition.warn);
    });
  });

  group('filteren', () {
    SlideQualityIssue issueOn(int slideIndex) => SlideQualityIssue(
      slideIndex: slideIndex,
      kind: SlideQualityIssueKind.bulletCountHigh,
      category: SlideQualityCategory.content,
      severity: MarkdownValidationSeverity.warning,
    );

    test('alleen de geaccepteerde slide telt als afgehandeld', () {
      final deck = deckWith([
        QualityDisposition.accept,
        QualityDisposition.warn,
      ]);

      expect(isQualityAccepted(deck, 0), isTrue);
      expect(isQualityAccepted(deck, 1), isFalse);
    });

    test('een deckbrede melding is nooit geaccepteerd', () {
      // Die hoort bij geen enkele slide; je zet hem recht in de instellingen.
      final deck = deckWith([QualityDisposition.accept]);
      expect(
        isQualityAccepted(deck, issueOn(kDeckWideSlideIndex).slideIndex),
        isFalse,
      );
    });

    test('een index buiten het deck geeft geen acceptatie', () {
      final deck = deckWith([QualityDisposition.accept]);
      expect(isQualityAccepted(deck, 5), isFalse);
    });
  });
}
