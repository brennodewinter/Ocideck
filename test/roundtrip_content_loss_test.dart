import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/utils/csv.dart';
import 'package:ocideck/utils/deck_markdown_dashes.dart';
import 'package:ocideck/utils/markdown_paste_cleanup.dart';
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

  group('codefence', () {
    test('een ``` in een codevoorbeeld kapt de code niet af', () {
      final out = roundTrip(
        slideOf(
          SlideType.code,
        ).copyWith(codeLanguage: 'md', customMarkdown: 'a\n```\nx\n```\nb'),
      );
      expect(out.customMarkdown, 'a\n```\nx\n```\nb');
      expect(out.codeLanguage, 'md');
    });

    test('en scheurt de slide ook niet in tweeën', () {
      final deck = md.parseDeck(
        md.generateDeck(
          Deck(
            title: 'T',
            slides: [
              slideOf(
                SlideType.code,
              ).copyWith(codeLanguage: 'md', customMarkdown: 'a\n```\n---\nb'),
            ],
          ),
        ),
      )!;
      expect(deck.slides.length, 1);
      expect(deck.slides.first.customMarkdown, 'a\n```\n---\nb');
    });

    test('code zonder backticks houdt de gewone fence van drie', () {
      final text = md.generateDeck(
        Deck(
          title: 'T',
          slides: [
            slideOf(
              SlideType.code,
            ).copyWith(codeLanguage: 'dart', customMarkdown: 'final x = 1;'),
          ],
        ),
      );
      expect(text, contains('```dart'));
      expect(text, isNot(contains('````')));
    });
  });

  group('notities en opmerkingen', () {
    test(
      'Marp-richtlijnen die OciDeck niet toepast blijven behouden (#1436)',
      () {
        const source = '''
---
marp: true
---

<!-- _class: section -->
<!-- _header: Vertrouwelijk -->
<!-- fit -->

![bg 35%](images/laag-een.png)
![bg contain blur:2px](images/laag-twee.png)
![bg](images/laag-drie.png)

# Kop

Samenvatting

<!-- Echte notitie -->
''';
        final parsed = md.parseDeck(source)!;

        expect(parsed.slides.single.type, SlideType.freeMarkdown);
        expect(
          parsed.slides.single.customMarkdown,
          contains('<!-- Echte notitie -->'),
        );

        final saved = md.generateDeck(parsed);
        expect(saved, contains('<!-- _header: Vertrouwelijk -->'));
        expect(saved, contains('<!-- fit -->'));
        expect(saved, contains('![bg contain blur:2px](images/laag-twee.png)'));
        expect(saved, contains('![bg](images/laag-drie.png)'));
        expect(saved, contains('<!-- Echte notitie -->'));

        final reopened = md.parseDeck(saved)!;
        expect(reopened.slides.single.type, SlideType.freeMarkdown);
        expect(md.generateDeck(reopened), saved);
      },
    );

    test('een opmerking van de auteur blijft in de tekst staan', () {
      final out = roundTrip(
        slideOf(
          SlideType.freeMarkdown,
        ).copyWith(customMarkdown: 'tekst\n<!-- interne opmerking -->\nmeer'),
      );
      expect(out.customMarkdown, contains('<!-- interne opmerking -->'));
      expect(out.notes, isEmpty, reason: 'het zijn geen sprekersnotities');
    });

    test('een notitie die als een richtlijn leest, overleeft', () {
      // Deze vier werden opgegeten door de richtlijnenketen.
      for (final note in [
        'skip',
        'tlp: rood',
        'advance: nu',
        '_cursief_ punt',
      ]) {
        final out = roundTrip(
          slideOf(SlideType.bullets).copyWith(bullets: ['x'], notes: note),
        );
        expect(out.notes, note, reason: 'notitie "$note" ging verloren');
        expect(
          out.skipped,
          isFalse,
          reason: 'en werd als richtlijn uitgevoerd',
        );
      }
    });

    test('de echte richtlijn werkt nog wél, naast een notitie', () {
      final out = roundTrip(
        slideOf(
          SlideType.bullets,
        ).copyWith(bullets: ['x'], skipped: true, notes: 'let op'),
      );
      expect(out.skipped, isTrue);
      expect(out.notes, 'let op');
    });

    test('meerregelige notities blijven meerregelig', () {
      final out = roundTrip(
        slideOf(
          SlideType.bullets,
        ).copyWith(bullets: ['x'], notes: 'regel een\nregel twee'),
      );
      expect(out.notes, 'regel een\nregel twee');
    });
  });

  group('ontsnappingen', () {
    test('blijven in de opslag staan en veranderen niet van betekenis', () {
      const src = r'Prijs 100\% en \*niet cursief\* en \- geen lijst';
      final out = roundTrip(
        slideOf(SlideType.freeMarkdown).copyWith(customMarkdown: src),
      );
      expect(out.customMarkdown, src);

      // Tweemaal opslaan verandert er nog steeds niets aan.
      final twice = roundTrip(out);
      expect(twice.customMarkdown, src);
    });

    test('maar op het scherm zie je ze niet', () {
      expect(normalizeRichTextMarkdown(r'\- geen lijst'), '- geen lijst');
    });
  });
}
