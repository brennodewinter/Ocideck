import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';

// #3109: een vrije-Markdown-dia schreef geen `_class`-token en las daarom
// terug als wat zijn body toevallig opleverde — bullets, of een titeldia —
// waarna de eerstvolgende opslag dat verlies vastlegde. De dia moet type én
// body verliesvrij rondreizen. Dek tevens het broedergeval: de eigen class
// van een auteur mocht het typetoken niet vervangen, want dan ging elk
// getypeerde dia met een eigen class hetzelfde verloren.
void main() {
  final md = MarkdownService();

  Deck roundTrip(Deck deck) => md.parseDeck(md.generateDeck(deck))!;

  test(
    'een vrije-Markdown-dia met bullet-achtige body blijft freeMarkdown',
    () {
      const body = '- aap\n- noot\n- mies';
      final result = roundTrip(
        Deck(
          title: 'Demo',
          slides: [
            Slide.create(SlideType.freeMarkdown).copyWith(customMarkdown: body),
          ],
        ),
      );

      expect(result.slides.single.type, SlideType.freeMarkdown);
      expect(result.slides.single.customMarkdown, body);
    },
  );

  test('een vrije-Markdown-dia met kop en proza blijft freeMarkdown', () {
    const body = '# Kop\n\nVrije tekst *met* **markdown**';
    final result = roundTrip(
      Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.freeMarkdown).copyWith(customMarkdown: body),
        ],
      ),
    );

    expect(result.slides.single.type, SlideType.freeMarkdown);
    expect(result.slides.single.customMarkdown, body);
  });

  test('een vrije-Markdown-dia schrijft het free-markdown-token', () {
    final markdown = md.generateDeck(
      Deck(
        title: 'Demo',
        slides: [
          Slide.create(
            SlideType.freeMarkdown,
          ).copyWith(customMarkdown: 'tekst'),
        ],
      ),
    );

    expect(markdown, contains('<!-- _class: free-markdown -->'));
  });

  test('een eigen class vervangt het typetoken niet', () {
    final result = roundTrip(
      Deck(
        title: 'Demo',
        slides: [
          Slide.create(
            SlideType.quote,
          ).copyWith(bullets: ['wijsheid'], cssClass: 'eigenklasse'),
        ],
      ),
    );

    expect(result.slides.single.type, SlideType.quote);
    expect(result.slides.single.cssClass, contains('eigenklasse'));
  });

  test('een vrije-Markdown-dia met eigen class houdt type én class', () {
    final result = roundTrip(
      Deck(
        title: 'Demo',
        slides: [
          Slide.create(
            SlideType.freeMarkdown,
          ).copyWith(customMarkdown: '- x', cssClass: 'eigenklasse'),
        ],
      ),
    );

    expect(result.slides.single.type, SlideType.freeMarkdown);
    expect(result.slides.single.cssClass, contains('eigenklasse'));
  });

  // #3278: de gedeelde schrijver plaatst de audiobijlage achter élke diabody —
  // ook achter een verbatim bewaarde vrije-Markdown-body. Las die regel terug
  // als bodytekst, dan groeide `customMarkdown` met elke opslag rond één
  // bijlage. De interactie tussen `customMarkdown` en `audioPath` moet
  // stabiel zijn: de gegenereerde regel gaat weer in het veld, de body van
  // de auteur blijft ongemoeid.
  test('een audiobijlage landt niet in de bewaarde vrije-Markdown-body', () {
    const body = 'Een **vrije** tekst';
    var deck = Deck(
      title: 'Demo',
      slides: [
        Slide.create(
          SlideType.freeMarkdown,
        ).copyWith(customMarkdown: body, audioPath: 'audio/base.mp3'),
      ],
    );

    for (var save = 0; save < 2; save++) {
      final markdown = md.generateDeck(deck);
      expect(
        '<audio'.allMatches(markdown).length,
        1,
        reason: 'opslag ${save + 1}: precies één bijlageregel',
      );
      deck = md.parseDeck(markdown)!;
      final slide = deck.slides.single;
      expect(slide.customMarkdown, body);
      expect(slide.audioPath, 'audio/base.mp3');
    }
  });

  test('door de auteur getypte audio-HTML blijft in de body staan', () {
    const authored = '<audio controls src="audio/eigen.mp3"></audio>';
    const body = 'Een tekst\n\n$authored\n\nNog een regel';
    var deck = Deck(
      title: 'Demo',
      slides: [
        Slide.create(SlideType.freeMarkdown).copyWith(customMarkdown: body),
      ],
    );

    for (var save = 0; save < 2; save++) {
      deck = roundTrip(deck);
      expect(deck.slides.single.customMarkdown, body);
    }
  });

  test('broedertypes met bewaarde body liften de bijlage óók', () {
    for (final type in [
      SlideType.title,
      SlideType.finding,
      SlideType.objective,
    ]) {
      const body = 'De bewaarde tekst';
      var deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(
            type,
          ).copyWith(customMarkdown: body, audioPath: 'audio/a.mp3'),
        ],
      );
      for (var save = 0; save < 2; save++) {
        deck = roundTrip(deck);
        expect(
          deck.slides.single.customMarkdown,
          isNot(contains('<audio')),
          reason: '${type.name} na opslag ${save + 1}',
        );
        expect(
          deck.slides.single.audioPath,
          'audio/a.mp3',
          reason: '${type.name} na opslag ${save + 1}',
        );
      }
    }
  });
}
