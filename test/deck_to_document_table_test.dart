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
}
