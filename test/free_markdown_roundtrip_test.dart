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
}
