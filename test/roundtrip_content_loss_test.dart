import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/utils/csv.dart';
import 'package:ocideck/utils/deck_markdown_dashes.dart';
import 'package:ocideck/utils/table_clipboard.dart';

/// Inhoud die bij het opslaan en weer inlezen stilzwijgend verdween.
///
/// Stuk voor stuk gevonden door de heenweg en de terugweg tegen elkaar aan te
/// leggen in plaats van elk apart te lezen: het bestand ís het document, dus
/// alles wat een gebruiker kan typen hoort er na een rondje nog te staan. Geen
/// van deze gevallen gaf een foutmelding — dat is precies wat ze gevaarlijk
/// maakte.
void main() {
  final md = MarkdownService();

  Slide roundTrip(Slide slide) => md
      .parseDeck(md.generateDeck(Deck(title: 'T', slides: [slide])))!
      .slides
      .first;

  Slide slideOf(SlideType type) => Slide.create(type);

  group('citaat', () {
    test('een meerregelig citaat overleeft', () {
      final out = roundTrip(
        slideOf(SlideType.quote).copyWith(quote: 'regel een\nregel twee'),
      );
      expect(out.quote, 'regel een\nregel twee');
    });

    test('een lege regel middenin blijft staan', () {
      final out = roundTrip(
        slideOf(SlideType.quote).copyWith(quote: 'boven\n\nonder'),
      );
      expect(out.quote, 'boven\n\nonder');
    });

    test('een citaat dat met een lege regel begint', () {
      final out = roundTrip(
        slideOf(SlideType.quote).copyWith(quote: '\nna de witregel'),
      );
      expect(out.quote, '\nna de witregel');
    });

    test('de auteur blijft los van het citaat', () {
      final out = roundTrip(
        slideOf(SlideType.quote).copyWith(quote: 'een\ntwee', quoteAuthor: 'K'),
      );
      expect(out.quote, 'een\ntwee');
      expect(out.quoteAuthor, 'K');
    });
  });

  group('tabel', () {
    test('een rij met alleen streepjes verderop blijft staan', () {
      // De gebruikelijke invulling voor "niet van toepassing" in een
      // bevindingen- of scopetabel.
      final out = roundTrip(
        slideOf(SlideType.table).copyWith(
          tableRows: [
            ['kop', 'kop2'],
            ['a', 'b'],
            ['-', '--'],
          ],
        ),
      );
      expect(out.tableRows, [
        ['kop', 'kop2'],
        ['a', 'b'],
        ['-', '--'],
      ]);
    });

    test('een streepje naast echte inhoud blijft staan', () {
      final out = roundTrip(
        slideOf(SlideType.table).copyWith(
          tableRows: [
            ['kop', 'kop2'],
            ['n.v.t.', '-'],
            ['x', 'y'],
          ],
        ),
      );
      expect(out.tableRows.length, 3);
      expect(out.tableRows[1], ['n.v.t.', '-']);
    });

    test('de scheidingsrij zelf verdwijnt nog steeds', () {
      final out = roundTrip(
        slideOf(SlideType.table).copyWith(
          tableRows: [
            ['kop', 'kop2'],
            ['a', 'b'],
          ],
        ),
      );
      expect(out.tableRows, [
        ['kop', 'kop2'],
        ['a', 'b'],
      ]);
    });
  });

  group('vrije tekst', () {
    test('een door de auteur getypte <div>-regel blijft staan', () {
      final out = roundTrip(
        slideOf(SlideType.bullets).copyWith(
          listStyle: ListStyle.richText,
          customMarkdown: 'voor\n<div class="kader">inhoud</div>\nna',
        ),
      );
      expect(out.customMarkdown, contains('<div class="kader">inhoud</div>'));
      expect(out.customMarkdown, contains('voor'));
      expect(out.customMarkdown, contains('na'));
    });

    test('een zero-width space van de auteur blijft staan', () {
      // Geplakte web- en CJK-tekst zit er vol mee; hij wordt ook als expliciete
      // afbreekhint gebruikt.
      final out = roundTrip(
        slideOf(SlideType.freeMarkdown).copyWith(customMarkdown: 'voor​na'),
      );
      expect(out.customMarkdown, 'voor​na');
    });

    test('een streepjesregel scheurt de slide nog steeds niet', () {
      final deck = md.parseDeck(
        md.generateDeck(
          Deck(
            title: 'T',
            slides: [
              slideOf(
                SlideType.freeMarkdown,
              ).copyWith(customMarkdown: 'boven\n---\nonder'),
            ],
          ),
        ),
      )!;
      expect(deck.slides.length, 1);
      expect(deck.slides.first.customMarkdown, 'boven\n---\nonder');
    });
  });

  group('dash-ontsnapping', () {
    test('draait alleen terug wat hij zelf heeft ingevoegd', () {
      const authored = 'tekst met ​ midden erin';
      expect(unescapeDeckMarkdownDashLines(authored), authored);

      final escaped = escapeDeckMarkdownDashLines('boven\n---\nonder');
      expect(escaped, isNot(contains('\n---\n')));
      expect(unescapeDeckMarkdownDashLines(escaped), 'boven\n---\nonder');
    });
  });

  group('csv en plakken', () {
    test('een afsluitend scheidingsteken levert een leeg veld', () {
      expect(parseCsvLine('a,'), ['a', '']);
      expect(parseCsvRows('a,b\nc,'), [
        ['a', 'b'],
        ['c', ''],
      ]);
    });

    test('een plakactie met een lege laatste cel wordt herkend', () {
      expect(parseClipboardTable('a,b\nc,'), [
        ['a', 'b'],
        ['c', ''],
      ]);
    });

    test('een ontsnapte pijp blijft één cel', () {
      expect(
        parseClipboardTable(
          r'| a\|b | c |'
          '\n| --- | --- |\n| 1 | 2 |',
        ),
        [
          ['a|b', 'c'],
          ['1', '2'],
        ],
      );
    });
  });
}
