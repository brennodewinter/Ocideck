import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';

import 'support/fastest_of.dart';

/// Prestatie- en schaalbaarheidstests voor grote presentaties.
///
/// De rest van de suite dekt gedrag functioneel af, maar duwde nooit een deck
/// van >100 slides door de serialise/parse-pijplijn. Deze tests bewaken twee
/// dingen die pas op schaal zichtbaar worden:
///
///  1. **Verliesvrijheid op schaal** — een deck van 150 slides moet volledig
///     round-trippen. Stil inhoudsverlies bij grote decks valt hier om.
///  2. **Geen kwadratisch gedrag** — een O(n²) regressie (bijvoorbeeld een
///     lineaire scan per slide over het hele document) is op 10 slides
///     onzichtbaar en op 500 slides fataal.
///
/// De tijdsbudgetten staan bewust ruim: ze vangen alleen catastrofale
/// algoritmische regressies, geen micro-timing. Metingen nemen het *minimum*
/// van meerdere runs, wat robuust is tegen planningsruis op een belaste
/// machine — een trager gemiddelde zegt niets, een trager minimum wel.

/// Bouwt een realistisch deck van [slideCount] slides, met een mix van
/// slidetypes zodat de meting niet op één serialiser-pad blijft hangen.
Deck buildLargeDeck(int slideCount) {
  final slides = <Slide>[
    Slide(
      id: 'slide-0',
      type: SlideType.title,
      title: 'Grootschalige presentatie',
      subtitle: 'Prestatiemeting',
    ),
  ];

  for (var i = 1; i < slideCount; i++) {
    slides.add(_slideForIndex(i));
  }

  return Deck(
    title: 'Prestatiedeck',
    author: 'OciDeck testsuite',
    organization: 'OciDeck',
    slides: slides,
  );
}

/// Eén slide per index, cyclisch over de gangbare types. De inhoud is bewust
/// niet triviaal: lege slides zouden de serialiser te makkelijk maken.
Slide _slideForIndex(int i) {
  switch (i % 6) {
    case 0:
      return Slide(
        id: 'slide-$i',
        type: SlideType.section,
        title: 'Hoofdstuk $i',
      );
    case 1:
      return Slide(
        id: 'slide-$i',
        type: SlideType.bullets,
        title: 'Bevindingen $i',
        bullets: List.generate(
          8,
          (b) => 'Punt $b van slide $i met wat aanvullende toelichting',
        ),
      );
    case 2:
      return Slide(
        id: 'slide-$i',
        type: SlideType.twoBullets,
        title: 'Vergelijking $i',
        columnTitle1: 'Voor',
        columnTitle2: 'Na',
        bullets: List.generate(5, (b) => 'Links $b op slide $i'),
        bullets2: List.generate(5, (b) => 'Rechts $b op slide $i'),
      );
    case 3:
      return Slide(
        id: 'slide-$i',
        type: SlideType.quote,
        quote: 'Een citaat op slide $i dat over meerdere woorden doorloopt.',
        quoteAuthor: 'Auteur $i',
      );
    case 4:
      return Slide(
        id: 'slide-$i',
        type: SlideType.table,
        title: 'Tabel $i',
        tableRows: [
          const ['Onderdeel', 'Status', 'Toelichting'],
          for (var r = 0; r < 6; r++)
            ['Rij $r', 'OK', 'Toelichting bij rij $r van slide $i'],
        ],
      );
    default:
      // `freeMarkdown` draagt géén `_class`-token: de parser leidt het type af
      // uit de inhoud (markdown_service_parse.dart). Een vrije-tekstslide
      // round-tript dus alleen als zodanig zonder kop of opsomming — met een
      // titel erbij is hij per ontwerp niet te onderscheiden van `bullets`.
      // Deze fixture houdt zich daar bewust aan.
      return Slide(
        id: 'slide-$i',
        type: SlideType.freeMarkdown,
        customMarkdown:
            'Een vrije alinea met **nadruk** en `code` op slide $i, '
            'lang genoeg om de serialiser echt werk te geven.',
      );
  }
}

void main() {
  final service = MarkdownService();

  group('Grote decks (>100 slides)', () {
    test('round-trip van 150 slides verliest geen enkele slide', () {
      final deck = buildLargeDeck(150);
      final markdown = service.generateDeck(deck);
      final parsed = service.parseDeck(markdown);

      expect(parsed, isNotNull, reason: 'een deck van 150 slides moet parsen');
      expect(parsed!.slides, hasLength(deck.slides.length));

      // Types en titels moeten één-op-één terugkomen; dit is de functionele
      // kern van de test, de timings hieronder zijn slechts de vangrail.
      expect(
        parsed.slides.map((s) => s.type).toList(),
        deck.slides.map((s) => s.type).toList(),
      );
      expect(
        parsed.slides.map((s) => s.title).toList(),
        deck.slides.map((s) => s.title).toList(),
      );
    });

    test('inhoud van een grote deck blijft op detailniveau intact', () {
      final deck = buildLargeDeck(150);
      final parsed = service.parseDeck(service.generateDeck(deck))!;

      // Steekproef over elk slidetype in de cyclus, aan het staartje van het
      // deck — juist daar zou een schaalbug als eerste toeslaan.
      final bullets = parsed.slides[145];
      expect(bullets.type, SlideType.bullets);
      expect(bullets.bullets, hasLength(8));

      final twoBullets = parsed.slides[146];
      expect(twoBullets.type, SlideType.twoBullets);
      expect(twoBullets.bullets, hasLength(5));
      expect(twoBullets.bullets2, hasLength(5));

      final table = parsed.slides[148];
      expect(table.type, SlideType.table);
      expect(table.tableRows, hasLength(7));
    });

    test('serialiseren en parsen blijft binnen een ruim tijdsbudget', () {
      final deck = buildLargeDeck(150);

      final serialise = fastestOf(3, () => service.generateDeck(deck));
      expect(
        serialise,
        lessThan(const Duration(seconds: 2)),
        reason: 'serialiseren van 150 slides duurde $serialise',
      );

      final markdown = service.generateDeck(deck);
      final parse = fastestOf(3, () => service.parseDeck(markdown));
      expect(
        parse,
        lessThan(const Duration(seconds: 2)),
        reason: 'parsen van 150 slides duurde $parse',
      );
    });

    test('parsen schaalt niet kwadratisch met het aantal slides', () {
      // Vier keer zoveel slides hoort ~4x zoveel tijd te kosten (lineair) en
      // ~16x bij kwadratisch gedrag. De drempel van 10x ligt daar ruim
      // tussenin, zodat ruis niet rood slaat maar een echte O(n²) wel.
      final smallMarkdown = service.generateDeck(buildLargeDeck(50));
      final largeMarkdown = service.generateDeck(buildLargeDeck(200));

      // Opwarmen: de eerste run betaalt eenmalige JIT- en cachekosten die de
      // verhouding anders vertekenen.
      service.parseDeck(smallMarkdown);
      service.parseDeck(largeMarkdown);

      final small = fastestOf(3, () => service.parseDeck(smallMarkdown));
      final large = fastestOf(3, () => service.parseDeck(largeMarkdown));

      expect(
        large.inMicroseconds,
        lessThan(small.inMicroseconds * 10),
        reason:
            'parsen ging van $small (50 slides) naar $large (200 slides); '
            'dat wijst op superlineair gedrag',
      );
    });
  });
}
