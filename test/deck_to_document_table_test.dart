// Presentatie → document mag de tabel van een tabelgedragen dia niet weggooien
// (#1588).
//
// `_slideBody` las de `tableRows` alleen voor `SlideType.table`. De negen andere
// `backedByTable`-types dragen hun inhoud óók daar — hun `customMarkdown` blijft
// per ontwerp leeg — dus ze vielen door naar de terugval "titel + bullets" en de
// hele tabel verdween stil uit het document. Voor een pentestrapport betekende
// dat: elke checklist, de scopematrix en het bevindingenoverzicht weg; voor een
// ISO-deck de beheersmaatregelstatus; voor een verbeterproject de matrix en de
// gantt.
//
// De test loopt over `slideTypeMeta` en niet over een handgeschreven lijst. Dat
// is het punt: het volgende tabelgedragen type dat erbij komt is dan meteen
// gedekt, in plaats van dat iemand eraan moet denken deze test bij te werken —
// precies de les die `usesScaffoldMarkdownBody` in `slide.dart` al opschrijft.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/document_deck_bridge.dart';
import 'package:ocideck/services/markdown_service.dart';

void main() {
  const rows = [
    ['Kop A', 'Kop B'],
    ['waarde een', 'waarde twee'],
  ];

  final tabelTypes = [
    for (final type in SlideType.values)
      if (type.backedByTable) type,
  ];

  test('er zijn tabelgedragen types om te toetsen', () {
    // Een lege lijst zou elke assertie hieronder stilzwijgend laten slagen.
    expect(tabelTypes, isNotEmpty);
  });

  for (final type in tabelTypes) {
    test('${type.name}: de tabel overleeft het omzetten naar document', () {
      final deck = Deck(
        title: 'T',
        slides: [
          Slide.create(
            type,
          ).copyWith(title: 'Een kop', tableRows: const [...rows]),
        ],
      );

      final out = DocumentDeckBridge.deckToDocumentMarkdown(deck);

      for (final row in rows) {
        for (final cel in row) {
          expect(
            out,
            contains(cel),
            reason: 'cel "$cel" ontbreekt in de omgezette ${type.name}',
          );
        }
      }
      // En de kop van de dia gaat niet verloren; een document leest op koppen.
      expect(out, contains('Een kop'));
    });
  }

  test('een tabel zonder kop levert geen lege kopregel op', () {
    // De documentkant maakt tabellen zónder titel (`documentToDeck` zet er geen),
    // en die moeten byte-identiek terugkomen — zonder een `##` dat nergens over
    // gaat.
    final deck = Deck(
      title: 'T',
      slides: [
        Slide.create(SlideType.table).copyWith(tableRows: const [...rows]),
      ],
    );

    final out = DocumentDeckBridge.deckToDocumentMarkdown(deck);

    expect(out.trimLeft(), startsWith('|'));
    expect(out, isNot(contains('#')));
  });

  // Een tabelgedragen dia draagt méér dan zijn tabel, en dat is geen bedacht
  // geval: de ontleder zet `bullets` voor élk type, en `_parsedCustomMarkdown`
  // levert een lichaam voor elke richText-dia ongeacht type. Een handgeschreven
  // deckbron — de broneditor is een volwaardig oppervlak in OciDeck — levert die
  // dia dus mét opsomming én tabel. Alleen kop + tabel wegschrijven verloor de
  // opsomming stil: dezelfde fout als hierboven, één veld verderop.
  group('een tabelgedragen dia draagt meer dan zijn tabel', () {
    test('een opsomming naast de tabel overleeft het omzetten', () {
      const bron =
          '---\nmarp: true\n---\n\n'
          '<!-- _class: checklist -->\n'
          '# Uitvoering WSTG\n'
          '\n'
          '- Alleen de webtoepassing, niet de API\n'
          '- Aftekening door de opdrachtgever op 3 juni\n'
          '\n'
          '| ID | Test | Status |\n'
          '| --- | --- | --- |\n'
          '| WSTG-01 | Informatievergaring | uitgevoerd |\n';
      final deck = MarkdownService().parseDeck(bron)!;
      final slide = deck.slides.single;

      // Eerst de aanname zelf: zonder deze twee is de test hieronder leeg.
      expect(slide.type, SlideType.checklist);
      expect(slide.bullets, hasLength(2));
      expect(slide.tableRows, isNotEmpty);

      final out = DocumentDeckBridge.deckToDocumentMarkdown(deck);

      expect(out, contains('Alleen de webtoepassing, niet de API'));
      expect(out, contains('Aftekening door de opdrachtgever op 3 juni'));
      expect(out, contains('| WSTG-01 | Informatievergaring | uitgevoerd |'));
      // Volgorde: kop, dan de opsomming, dan de tabel — zoals de dia leest.
      expect(
        out.indexOf('Alleen de webtoepassing'),
        lessThan(out.indexOf('| WSTG-01')),
      );
    });

    test('een richText-lichaam naast de tabel overleeft het omzetten', () {
      // `listStyle: richText` vult `customMarkdown` ongeacht het dia-type.
      final deck = Deck(
        title: 'T',
        slides: [
          Slide.create(SlideType.findingsSummary).copyWith(
            title: 'Bevindingen',
            customMarkdown: 'Twee bevindingen zijn tijdens de test hersteld.',
            tableRows: const [...rows],
          ),
        ],
      );

      final out = DocumentDeckBridge.deckToDocumentMarkdown(deck);

      expect(out, contains('Twee bevindingen zijn tijdens de test hersteld.'));
      expect(out, contains('waarde een'));
    });
  });
}
