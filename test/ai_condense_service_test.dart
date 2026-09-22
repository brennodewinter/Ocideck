import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/ai_condense_service.dart';
import 'package:ocideck/services/markdown_service.dart';

Slide _richTextSlide({String body = 'Lange tekst.', String notes = ''}) =>
    Slide(
      id: 's1',
      type: SlideType.bulletsImage,
      title: 'Titel',
      listStyle: ListStyle.richText,
      customMarkdown: body,
      imagePath: 'images/foto.png',
      notes: notes,
    );

void main() {
  group('parseCondensePoints', () {
    test('accepteert streepjes, nummering en checkboxen', () {
      final raw = '- een\n* twee\n3. drie\n- [x] vier\n• vijf';
      expect(parseCondensePoints(raw), ['een', 'twee', 'drie', 'vier', 'vijf']);
    });

    test('accepteert kale regels (zoals de prompt vraagt)', () {
      expect(parseCondensePoints('alfa\nbeta\n\ngamma'), [
        'alfa',
        'beta',
        'gamma',
      ]);
    });

    test('knipt hard af op acht punten', () {
      final raw = List.generate(12, (i) => '- punt $i').join('\n');
      expect(parseCondensePoints(raw).length, kAiCondenseMaxPoints);
    });

    test('slaat koppen en fenceregels over, behoudt de inhoud', () {
      // Een model dat zijn hele antwoord in ``` wikkelt mag geen leeg
      // resultaat opleveren; koppen blijven wél ruis.
      final raw = '# Kop\n```\n- een punt\n```\n- nog een punt';
      expect(parseCondensePoints(raw), ['een punt', 'nog een punt']);
    });

    test('lege of onbruikbare output levert een lege lijst', () {
      expect(parseCondensePoints(''), isEmpty);
      expect(parseCondensePoints('   \n\n### alleen koppen\n'), isEmpty);
    });
  });

  group('cleanCondenseSummary', () {
    test('platte tekst komt ongemoeid terug', () {
      expect(cleanCondenseSummary('Kort en bondig.'), 'Kort en bondig.');
    });

    test('stript fences, koppen, quotes en witruimte', () {
      final raw = '```\n# Kop\n"Alles   staat\nhier samen."\n```';
      expect(cleanCondenseSummary(raw), 'Alles staat hier samen.');
    });

    test('knipt af op de laatste zinsgrens binnen het maximum', () {
      final long =
          '${'Een hele lange zin met veel woorden erin. ' * 20}Nog meer tekst die er niet meer bij kan.';
      final out = cleanCondenseSummary(long);
      expect(out.length, lessThanOrEqualTo(kAiCondenseSummaryMaxChars));
      expect(out.endsWith('.'), isTrue);
    });
  });

  group('applyCondenseToSlide', () {
    test('samenvatting vervangt de tekst en zet origineel in de notities', () {
      final slide = _richTextSlide(body: 'De volledige lange tekst.');
      final result = applyCondenseToSlide(
        slide,
        const AiCondenseResult(mode: AiCondenseMode.summary, summary: 'Kort.'),
        notesHeading: 'Oorspronkelijke tekst',
      );
      expect(result.customMarkdown, 'Kort.');
      expect(result.listStyle, ListStyle.richText);
      expect(result.notes, contains('De volledige lange tekst.'));
      expect(result.notes, contains('Oorspronkelijke tekst'));
      expect(result.imagePath, 'images/foto.png');
    });

    test('kernpunten wisselt de lijststijl en behoudt het origineel', () {
      final slide = _richTextSlide(body: 'Origineel proza.');
      final result = applyCondenseToSlide(
        slide,
        const AiCondenseResult(
          mode: AiCondenseMode.keyPoints,
          listStyle: ListStyle.checklist,
          points: ['eerste', 'tweede'],
        ),
        notesHeading: 'Oorspronkelijke tekst',
      );
      expect(result.listStyle, ListStyle.checklist);
      expect(result.bullets, ['[ ] eerste', '[ ] tweede']);
      expect(result.customMarkdown, isEmpty);
      expect(result.notes, contains('Origineel proza.'));
    });

    test('bestaande notities blijven behouden vóór de originele tekst', () {
      final slide = _richTextSlide(body: 'Nieuw', notes: 'Bestaande notitie.');
      final result = applyCondenseToSlide(
        slide,
        const AiCondenseResult(
          mode: AiCondenseMode.keyPoints,
          listStyle: ListStyle.numbered,
          points: ['punt'],
        ),
        notesHeading: 'Oorspronkelijke tekst',
      );
      expect(result.notes.indexOf('Bestaande notitie.'), 0);
      expect(result.notes, contains('Nieuw'));
    });
  });

  group('round-trip', () {
    test('de verwerkte dia overleeft serialize → parse intact', () {
      final slide = applyCondenseToSlide(
        _richTextSlide(body: 'Alles wat er stond.'),
        const AiCondenseResult(
          mode: AiCondenseMode.keyPoints,
          listStyle: ListStyle.numbered,
          points: ['eerste punt', 'tweede punt'],
        ),
        notesHeading: 'Oorspronkelijke tekst',
      );
      final deck = Deck(title: 'D', slides: [slide]);
      final service = MarkdownService();
      final md = service.generateDeck(deck);
      final reparsed = service.parseDeck(md)!.slides.single;
      expect(reparsed.listStyle, ListStyle.numbered);
      expect(reparsed.bullets.length, 2);
      expect(reparsed.notes, contains('Alles wat er stond.'));
      expect(reparsed.imagePath, 'images/foto.png');
    });
  });
}
