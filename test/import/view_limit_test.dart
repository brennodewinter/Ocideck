import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/display_window_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/import/deck_builder.dart';
import 'package:ocideck/services/import/models/body_block.dart';
import 'package:ocideck/services/import/models/source_deck.dart';
import 'package:ocideck/services/import/models/source_slide.dart';
import 'package:ocideck/services/import/models/source_table.dart';
import 'package:ocideck/services/import/pipeline/slide_classifier.dart';

/// De herijking op #672: een import snijdt niets weg.
///
/// Keiko moest data definitief verwijderen om een leesbare dia te maken. OciDeck
/// heeft daar sinds #672 niet-destructieve weergavelimieten voor, dus de import
/// zet een limiet op de *weergave* en laat de gegevens staan. Deze tests
/// bewaken precies dat onderscheid: de volledige inhoud blijft in het deck, en
/// alleen wat er getoond wordt is begrensd.
void main() {
  Slide buildOne(SourceSlide s) {
    final built = DeckBuilder().build(SourceDeck(slides: [s]), [
      classifySlide(s),
    ], title: 'Test');
    return built.deck.slides.first;
  }

  List<BodyBlock> bullets(int n) => [
    for (var i = 0; i < n; i++)
      BodyBlock(kind: BodyBlockKind.bullet, text: 'punt $i', order: i),
  ];

  group('bullets', () {
    test('een korte lijst krijgt geen limiet', () {
      final slide = buildOne(SourceSlide(index: 0, bodyBlocks: bullets(5)));
      expect(slide.bullets.length, 5);
      expect(slide.viewLimit, isNull);
    });

    test('een lange lijst houdt alle punten, maar toont er acht', () {
      final slide = buildOne(SourceSlide(index: 0, bodyBlocks: bullets(30)));
      // Niets weggegooid: alle dertig staan in het deck.
      expect(slide.bullets.length, 30);
      // Alleen de weergave is begrensd, mét telling zodat de rest zichtbaar is.
      expect(slide.viewLimit, isNotNull);
      expect(slide.viewLimit!.limit, kImportedBulletLimit);
      expect(slide.viewLimit!.mode, DisplayWindowMode.first);
      expect(slide.viewLimit!.showCount, isTrue);
    });
  });

  group('tabellen', () {
    SourceSlide tableOf(int dataRows) => SourceSlide(
      index: 0,
      table: SourceTable(
        header: const ['naam', 'aantal'],
        rows: [
          for (var i = 0; i < dataRows; i++) ['rij $i', '$i'],
        ],
      ),
    );

    test('een kleine tabel krijgt geen limiet', () {
      final slide = buildOne(tableOf(4));
      expect(slide.tableRows.length, 5); // kop + 4
      expect(slide.viewLimit, isNull);
    });

    test('een lange tabel houdt alle rijen, maar toont er twaalf', () {
      final slide = buildOne(tableOf(500));
      expect(slide.tableRows.length, 501); // kop + 500, niets gesneuveld
      expect(slide.viewLimit!.limit, kImportedTableRowLimit);
    });
  });
}
