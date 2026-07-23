import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/display_window_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';

Slide _roundTrip(Slide slide) {
  final service = MarkdownService();
  final markdown = service.generateDeck(Deck(title: 'Demo', slides: [slide]));
  final deck = service.parseDeck(markdown);
  expect(deck, isNotNull, reason: 'parseDeck returned null for:\n$markdown');
  expect(deck!.slides, hasLength(1));
  return deck.slides.single;
}

void main() {
  group('DisplayWindowSpec markdown round-trip', () {
    test('een misvormd view-commentaar gijzelt het bestand niet', () {
      // Bewaker-bevinding op #672: `ocideck_view_limit` zónder dubbele punt
      // gooide een RangeError, parseDeck ving die en gaf null — het hele
      // bestand weigerde te openen om een optioneel, negeerbaar aanwijzinkje.
      final md = '''
---
marp: true
---

## Titel

<!-- ocideck_view_limit -->
<!-- ocideck_view_mode -->

- een
- twee
''';
      final deck = MarkdownService().parseDeck(md);
      expect(
        deck,
        isNotNull,
        reason:
            'een kapot commentaar mag nooit het '
            'hele deck onleesbaar maken',
      );
      expect(deck!.slides.single.bullets, ['een', 'twee']);
      expect(deck.slides.single.viewLimit, isNull);
    });

    test('bullets slide stores and restores view limit comments', () {
      final original = Slide(
        id: 's1',
        type: SlideType.bullets,
        title: 'Top issues',
        bullets: const ['a', 'b', 'c', 'd'],
        viewLimit: const DisplayWindowSpec(
          limit: 3,
          mode: DisplayWindowMode.top,
          remainder: DisplayWindowRemainder.other,
          showCount: false,
        ),
      );
      final out = _roundTrip(original);
      expect(out.viewLimit?.limit, 3);
      expect(out.viewLimit?.mode, DisplayWindowMode.top);
      expect(out.viewLimit?.remainder, DisplayWindowRemainder.other);
      expect(out.viewLimit?.showCount, false);
      expect(out.bullets, ['a', 'b', 'c', 'd']);
    });

    test('table slide stores and restores view limit comments', () {
      final original = Slide(
        id: 's2',
        type: SlideType.table,
        title: 'Risks',
        tableRows: const [
          ['Risk', 'Score'],
          ['x', '10'],
          ['y', '5'],
        ],
        viewLimit: const DisplayWindowSpec(
          limit: 5,
          mode: DisplayWindowMode.bottom,
          key: '1',
        ),
      );
      final out = _roundTrip(original);
      expect(out.viewLimit?.limit, 5);
      expect(out.viewLimit?.mode, DisplayWindowMode.bottom);
      expect(out.viewLimit?.key, '1');
      expect(out.tableRows.length, 3);
    });

    test('export applies the view limit to the generated markdown', () {
      final slide = Slide(
        id: 's3',
        type: SlideType.bullets,
        title: 'Items',
        bullets: const ['one', 'two', 'three', 'four'],
        viewLimit: const DisplayWindowSpec(
          limit: 2,
          mode: DisplayWindowMode.first,
        ),
      );
      final service = MarkdownService();
      final markdown = service.generateDeck(
        Deck(title: 'Demo', slides: [slide]),
        forExport: true,
      );
      // Het geëxporteerde .md is wat de ontvanger ziet — zonder verborgen
      // hendel. Reisde het directief mee, dan vuurde de limiet bij de
      // ontvanger opnieuw, over het ingebakken bijschrift heen (dat dan als
      // item meetelt en het bijschrift laat liegen) — bewaker-bevinding #672.
      expect(
        markdown,
        isNot(contains('ocideck_view_')),
        reason: 'een al-toegepaste projectie mag geen levend directief dragen',
      );
      // The exported markdown should only show the first two bullets plus the caption.
      expect(markdown, contains('one'));
      expect(markdown, contains('two'));
      expect(markdown, isNot(contains('three')));
      expect(markdown, contains('Eerste 2 van 4 punten'));
    });

    test(
      'saved markdown preserves all data and only the view limit metadata',
      () {
        final slide = Slide(
          id: 's4',
          type: SlideType.bullets,
          title: 'Items',
          bullets: const ['one', 'two', 'three', 'four'],
          viewLimit: const DisplayWindowSpec(
            limit: 2,
            mode: DisplayWindowMode.first,
          ),
        );
        final service = MarkdownService();
        final markdown = service.generateDeck(
          Deck(title: 'Demo', slides: [slide]),
        );
        // Saved markdown must keep all four bullets.
        expect(markdown, contains('one'));
        expect(markdown, contains('two'));
        expect(markdown, contains('three'));
        expect(markdown, contains('four'));
        expect(markdown, contains('ocideck_view_limit: 2'));
      },
    );
  });
}
