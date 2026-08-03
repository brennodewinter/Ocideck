import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';

// Fase 1 van #1162: het navigatiefundament. Een stabiel dia-anker
// (`ocideck_slide_anchor`) en de per-dia sprong-uit (`ocideck_next`) moeten
// verliesvrij door serialiser + parser reizen, en een deck dat niet vertakt
// mag er geen enkele regel bij krijgen.
void main() {
  final md = MarkdownService();

  Deck roundTrip(Deck deck) => md.parseDeck(md.generateDeck(deck))!;

  test('anchor en sprong-uit reizen verliesvrij door de round-trip', () {
    final deck = Deck(
      title: 'Menu-demo',
      slides: [
        Slide.create(SlideType.bullets).copyWith(
          title: 'Hoofdmenu',
          anchor: 'hoofdmenu',
        ),
        Slide.create(SlideType.bullets).copyWith(
          title: 'Prijzen',
          anchor: 'prijzen',
          nextAnchor: 'hoofdmenu',
        ),
      ],
    );

    final result = roundTrip(deck);

    expect(result.slides[0].anchor, 'hoofdmenu');
    expect(result.slides[0].nextAnchor, isEmpty);
    expect(result.slides[1].anchor, 'prijzen');
    expect(result.slides[1].nextAnchor, 'hoofdmenu');
  });

  test('een dia zonder anker of sprong schrijft geen navigatie-comment', () {
    final markdown = md.generateDeck(
      Deck(
        title: 'Gewoon',
        slides: [Slide.create(SlideType.bullets).copyWith(title: 'Dia')],
      ),
    );

    expect(markdown.contains('ocideck_slide_anchor'), isFalse);
    expect(markdown.contains('ocideck_next'), isFalse);
  });

  test('de comments staan letterlijk in de uitvoer als ze gezet zijn', () {
    final markdown = md.generateDeck(
      Deck(
        title: 'Menu',
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            title: 'Prijzen',
            anchor: 'prijzen',
            nextAnchor: 'hoofdmenu',
          ),
        ],
      ),
    );

    expect(markdown, contains('<!-- ocideck_slide_anchor: prijzen -->'));
    expect(markdown, contains('<!-- ocideck_next: hoofdmenu -->'));
  });
}
