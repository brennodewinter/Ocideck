import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';

/// The report language (MIAUW EIS 2.3): agreed and recorded before the pentest,
/// so the deck has to be able to carry it — and carry it through a save/open
/// cycle, because a requirement that survives only in memory proves nothing.
Deck _deck({String language = ''}) => Deck(
  title: 'Rapport',
  language: language,
  slides: [
    Slide.create(SlideType.bullets).copyWith(bullets: const ['Een']),
  ],
);

Deck _roundTrip(Deck deck) {
  final markdown = MarkdownService().generateDeck(deck);
  final parsed = MarkdownService().parseDeck(markdown);
  expect(parsed, isNotNull, reason: 'deck failed to parse back');
  return parsed!;
}

void main() {
  test('a recorded report language survives the round-trip', () {
    expect(_roundTrip(_deck(language: 'nl')).language, 'nl');
    expect(_roundTrip(_deck(language: 'en')).language, 'en');
  });

  test('an unrecorded language writes no key and stays empty', () {
    final markdown = MarkdownService().generateDeck(_deck());
    expect(
      markdown.contains('language:'),
      isFalse,
      reason:
          'An empty language must stay out of the file entirely — the front '
          'matter only carries what was actually decided.',
    );
    expect(_roundTrip(_deck()).language, isEmpty);
  });
}
