import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/import/deck_builder.dart';
import 'package:ocideck/services/import/models/body_block.dart';
import 'package:ocideck/services/import/models/source_deck.dart';
import 'package:ocideck/services/import/models/source_image.dart';
import 'package:ocideck/services/import/models/source_slide.dart';
import 'package:ocideck/services/import/models/source_table.dart';
import 'package:ocideck/services/import/models/source_video.dart';
import 'package:ocideck/services/import/pipeline/slide_classifier.dart';
import 'package:ocideck/services/web_asset_store.dart';

/// De belofte waarop deze functie verkocht wordt: **niets verdwijnt stil**.
///
/// De classifier meldde al wat híj niet kwijt kon, maar de deck-builder gooide
/// daarna zélf nog inhoud weg — een inleidende alinea boven een bullet-lijst,
/// de derde afbeelding, opsommingspunten naast een tabel — zonder één woord.
/// Een gebruiker die zijn dia terugzag zonder die alinea had geen enkele
/// aanwijzing dat de import hem had laten vallen. Deze tests bewaken dat elk
/// van die gevallen op de notitiedia terechtkomt.
///
/// Even belangrijk is de andere kant: verlies *melden* dat er niet is, stuurt
/// de gebruiker op zoek naar iets wat gewoon op zijn dia staat. Daarom staat er
/// bij elk geval ook een tegenproef.
void main() {
  setUp(WebAssetStore.clear);
  tearDown(WebAssetStore.clear);

  ({Slide slide, String notes}) buildOne(SourceSlide s) {
    final built = DeckBuilder().build(SourceDeck(slides: [s]), [
      classifySlide(s),
    ], title: 'Test');
    // Niet-overgenomen inhoud zit nu in de notities van de dia zelf, of —
    // bij overslaan — in een aparte freeMarkdown-dia.
    final notes = built.deck.slides
        .map(
          (sl) =>
              sl.type == SlideType.freeMarkdown ? sl.customMarkdown : sl.notes,
        )
        .join('\n');
    return (slide: built.deck.slides.first, notes: notes);
  }

  SourceImage img(int seed) => SourceImage(
    bytes: Uint8List.fromList([seed, seed + 1, seed + 2]),
    ext: 'png',
    name: 'plaat$seed.png',
  );

  BodyBlock bullet(String t, [int order = 0]) =>
      BodyBlock(kind: BodyBlockKind.bullet, text: t, order: order);
  BodyBlock para(String t, [int order = 0]) =>
      BodyBlock(kind: BodyBlockKind.paragraph, text: t, order: order);

  group('wat de bouwer laat vallen komt op de notitiedia', () {
    test('een alinea boven een bullet-lijst', () {
      final r = buildOne(
        SourceSlide(
          index: 0,
          title: 'Plan',
          bodyBlocks: [
            para('Inleiding', 0),
            bullet('Een', 1),
            bullet('Twee', 2),
          ],
        ),
      );
      expect(r.slide.type, SlideType.bullets);
      expect(r.notes, contains('Alinea'));
    });

    test('maar een bullet-dia zonder alinea meldt niets', () {
      final r = buildOne(
        SourceSlide(index: 0, bodyBlocks: [bullet('Een'), bullet('Twee')]),
      );
      expect(r.notes, isNot(contains('Alinea')));
    });

    test('de derde afbeelding naast twee getoonde', () {
      final r = buildOne(
        SourceSlide(index: 0, images: [img(1), img(2), img(3)]),
      );
      // Drie afbeeldingen zonder bullets worden twoImages (eerste twee getoond);
      // de derde valt weg en wordt op de notitiedia gemeld.
      expect(r.slide.type, SlideType.twoImages);
      expect(r.notes, contains('1 afbeelding'));
    });

    test('maar twee afbeeldingen op een twoImages-dia melden niets', () {
      final r = buildOne(SourceSlide(index: 0, images: [img(1), img(2)]));
      expect(r.notes, isNot(contains('afbeelding')));
    });

    test('opsommingspunten naast een tabel', () {
      final r = buildOne(
        SourceSlide(
          index: 0,
          bodyBlocks: [bullet('Toelichting')],
          table: const SourceTable(
            header: ['a', 'b'],
            rows: [
              ['1', '2'],
            ],
          ),
        ),
      );
      expect(r.slide.type, SlideType.table);
      expect(r.notes, contains('opsommingspunt'));
    });
  });

  group('een onveilige koppeling laat een spoor na', () {
    test('het oorspronkelijke doel staat in de notitie', () {
      final r = buildOne(
        SourceSlide(
          index: 0,
          bodyBlocks: [bullet('Punt')],
          hyperlinks: const [(text: 'Klik', url: 'javascript:alert(1)')],
        ),
      );
      // Het schema is onschadelijk gemaakt …
      expect(r.slide.bullets.join(), contains('https://invalid'));
      // … maar de gebruiker kan zien wát er stond.
      expect(r.notes, contains('javascript:alert(1)'));
    });

    test('een gewone koppeling blijft ongemoeid en meldt niets', () {
      final r = buildOne(
        SourceSlide(
          index: 0,
          bodyBlocks: [bullet('Punt')],
          hyperlinks: const [(text: 'Site', url: 'https://example.org')],
        ),
      );
      expect(r.slide.bullets.join(), contains('https://example.org'));
      expect(r.notes, isNot(contains('onschadelijk')));
    });
  });

  group('ingebedde media reist mee in plaats van te verdampen', () {
    test('video-bytes worden een mem:-pad met de bytes erin', () {
      final movie = Uint8List.fromList([9, 8, 7, 6]);
      final r = buildOne(
        SourceSlide(
          index: 0,
          video: SourceVideo(
            kind: SourceVideoKind.local,
            ref: 'media/clip.mp4',
            bytes: movie,
          ),
        ),
      );
      expect(r.slide.type, SlideType.video);
      expect(WebAssetStore.isMemPath(r.slide.videoPath), isTrue);
      expect(WebAssetStore.bytesFor(r.slide.videoPath), movie);
    });

    test('een URL-video blijft gewoon zijn verwijzing', () {
      final r = buildOne(
        SourceSlide(
          index: 0,
          video: const SourceVideo(
            kind: SourceVideoKind.youtube,
            ref: 'https://youtu.be/abc',
          ),
        ),
      );
      expect(r.slide.videoPath, 'https://youtu.be/abc');
    });

    test('een uitvoerbaar ogende bijlagenaam wordt onschadelijk gemaakt', () {
      // Een bronarchief bepaalt zelf hoe zijn bijlagen heten; `.command` hoort
      // niet in de projectmap van de gebruiker terecht te komen.
      final r = buildOne(
        SourceSlide(
          index: 0,
          images: [
            SourceImage(
              bytes: Uint8List.fromList([1, 2, 3]),
              ext: 'png',
              name: 'rapport.pdf.command',
            ),
          ],
        ),
      );
      final name = WebAssetStore.nameFor(r.slide.imagePath)!;
      expect(name, isNot(endsWith('.command')));
      expect(name, endsWith('.png'));
    });
  });
}
