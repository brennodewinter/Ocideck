import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/import/deck_builder.dart';
import 'package:ocideck/services/import/models/body_block.dart';
import 'package:ocideck/services/import/models/conversion_issue.dart';
import 'package:ocideck/services/import/models/source_chart.dart';
import 'package:ocideck/services/import/models/source_deck.dart';
import 'package:ocideck/services/import/models/source_image.dart';
import 'package:ocideck/services/import/models/source_slide.dart';
import 'package:ocideck/services/import/models/source_table.dart';
import 'package:ocideck/services/import/models/source_video.dart';
import 'package:ocideck/services/import/pipeline/slide_classifier.dart';
import 'package:ocideck/services/web_asset_store.dart';

/// Classify [slides] and build a deck from them the way the pipeline does.
BuiltDeck _build(
  List<SourceSlide> slides, {
  String title = 'Deck',
  String author = '',
  List<ConversionIssue> issues = const [],
}) {
  final deck = SourceDeck(
    slides: slides,
    title: title,
    author: author,
    issues: issues,
  );
  final classified = [for (final s in slides) classifySlide(s)];
  return DeckBuilder().build(deck, classified, title: title);
}

BodyBlock _bullet(String text, {int level = 0}) =>
    BodyBlock(kind: BodyBlockKind.bullet, text: text, level: level);

SourceImage _img(
  List<int> bytes, {
  String? name,
  String ext = 'png',
  String? caption,
}) => SourceImage(
  bytes: Uint8List.fromList(bytes),
  ext: ext,
  name: name,
  caption: caption,
);

void main() {
  setUp(WebAssetStore.clear);
  tearDown(() {
    WebAssetStore.clear();
    WebAssetStore.overrideTotalBudgetForTest(null);
  });

  group('DeckBuilder maps slide types onto the real model', () {
    test('a first title-only slide becomes a title slide', () {
      final built = _build([
        const SourceSlide(
          index: 0,
          title: 'Kwartaalcijfers',
          subtitle: 'Q3 2026',
        ),
      ]);
      final slide = built.deck.slides.single;
      expect(slide.type, SlideType.title);
      expect(slide.title, 'Kwartaalcijfers');
      expect(slide.subtitle, 'Q3 2026');
    });

    test('bullets carry nesting as leading tabs', () {
      final built = _build([
        SourceSlide(
          index: 1,
          title: 'Agenda',
          bodyBlocks: [_bullet('Top'), _bullet('Kind', level: 1)],
        ),
      ]);
      final slide = built.deck.slides.single;
      expect(slide.type, SlideType.bullets);
      expect(slide.bullets, ['Top', '\tKind']);
      expect(bulletLevel(slide.bullets[1]), 1);
    });

    test('a single image with bullets becomes bulletsImage', () {
      final built = _build([
        SourceSlide(
          index: 1,
          title: 'Cijfers',
          bodyBlocks: [_bullet('Groei 12%')],
          images: [
            _img([1, 2, 3], caption: 'Grafiek'),
          ],
        ),
      ]);
      final slide = built.deck.slides.single;
      expect(slide.type, SlideType.bulletsImage);
      expect(slide.bullets, ['Groei 12%']);
      expect(slide.imagePath, startsWith('mem:'));
      expect(slide.imageCaption, 'Grafiek');
    });

    test('two images become a twoImages slide with both paths', () {
      final built = _build([
        SourceSlide(
          index: 1,
          title: 'Voor & na',
          images: [
            _img([1]),
            _img([2]),
          ],
        ),
      ]);
      final slide = built.deck.slides.single;
      expect(slide.type, SlideType.twoImages);
      expect(slide.imagePath, startsWith('mem:'));
      expect(slide.imagePath2, startsWith('mem:'));
      expect(slide.imagePath, isNot(slide.imagePath2));
    });

    test('drie of meer afbeeldingen met bullets worden bulletsImage', () {
      // Een Keynote-dia met 6 afbeeldingen (inhoud + master-slide-logo's)
      // plus bullets. Vroeger viel dit door naar `bullets` en dropte alle
      // afbeeldingen stil; nu wordt het bulletsImage (eerste afbeelding).
      final built = _build([
        SourceSlide(
          index: 1,
          title: 'Overzicht',
          bodyBlocks: [_bullet('Punt een'), _bullet('Punt twee')],
          images: [
            _img([1]),
            _img([2]),
            _img([3]),
            _img([4]),
            _img([5]),
            _img([6]),
          ],
        ),
      ]);
      // De extra afbeeldingen genereren een notitiedia; de eerste is de inhoud.
      final slide = built.deck.slides.first;
      expect(slide.type, SlideType.bulletsImage);
      expect(slide.imagePath, startsWith('mem:'));
      expect(slide.bullets, ['Punt een', 'Punt twee']);
    });

    test('drie of meer afbeeldingen zonder bullets worden twoImages', () {
      final built = _build([
        SourceSlide(
          index: 1,
          title: 'Galerij',
          images: [
            _img([1]),
            _img([2]),
            _img([3]),
          ],
        ),
      ]);
      // De derde afbeelding wordt op de notitiedia gemeld; de eerste is de inhoud.
      final slide = built.deck.slides.first;
      expect(slide.type, SlideType.twoImages);
      expect(slide.imagePath, startsWith('mem:'));
      expect(slide.imagePath2, startsWith('mem:'));
    });

    test('een budgetfout laat geen half gebouwd deck in de store achter', () {
      WebAssetStore.overrideTotalBudgetForTest(1);

      expect(
        () => _build([
          SourceSlide(
            index: 1,
            title: 'Eén',
            images: [
              _img([1]),
            ],
          ),
          SourceSlide(
            index: 2,
            title: 'Twee',
            images: [
              _img([2]),
            ],
          ),
        ]),
        throwsA(isA<WebAssetBudgetExceeded>()),
      );
      expect(WebAssetStore.isEmpty, isTrue);
      expect(WebAssetStore.totalBytes, 0);
    });

    test('a quote block becomes a quote slide with the title as author', () {
      final built = _build([
        SourceSlide(
          index: 1,
          title: 'Ada Lovelace',
          bodyBlocks: [
            const BodyBlock(
              kind: BodyBlockKind.quote,
              text: 'That brain of mine.',
            ),
          ],
        ),
      ]);
      final slide = built.deck.slides.single;
      expect(slide.type, SlideType.quote);
      expect(slide.quote, 'That brain of mine.');
      expect(slide.quoteAuthor, 'Ada Lovelace');
    });

    test('a table maps header + rows into tableRows with the header first', () {
      final built = _build([
        SourceSlide(
          index: 1,
          title: 'Budget',
          table: const SourceTable(
            header: ['Post', 'Bedrag'],
            rows: [
              ['Reis', '100'],
              ['Eten', '50'],
            ],
          ),
        ),
      ]);
      final slide = built.deck.slides.single;
      expect(slide.type, SlideType.table);
      expect(slide.tableRows.first, ['Post', 'Bedrag']);
      expect(slide.tableRows.length, 3);
      expect(slide.tableRows[1], ['Reis', '100']);
    });

    test('a chart maps into a round-trippable chart block', () {
      final built = _build([
        SourceSlide(
          index: 1,
          title: 'Omzet',
          chart: const SourceChart(
            type: SourceChartType.line,
            x: ['Jan', 'Feb'],
            series: [
              SourceChartSeries(name: 'A', data: [1, 2]),
            ],
            title: 'Per maand',
          ),
        ),
      ]);
      final slide = built.deck.slides.single;
      expect(slide.type, SlideType.chart);
      final spec = ChartSpec.parse(slide.customMarkdown);
      expect(spec.type, ChartType.line);
      expect(spec.x, ['Jan', 'Feb']);
      expect(spec.series.single.name, 'A');
      expect(spec.series.single.data, [1, 2]);
    });

    test('a video slide takes its path from the source ref', () {
      final built = _build([
        const SourceSlide(
          index: 1,
          title: 'Demo',
          video: SourceVideo(
            kind: SourceVideoKind.youtube,
            ref: 'https://youtu.be/abc',
          ),
        ),
      ]);
      final slide = built.deck.slides.single;
      expect(slide.type, SlideType.video);
      expect(slide.videoPath, 'https://youtu.be/abc');
    });

    test('two positioned text columns become a twoBullets slide', () {
      final built = _build([
        const SourceSlide(
          index: 1,
          title: 'Voor / Tegen',
          positionedTexts: [
            PositionedText(
              text: 'Voordeel',
              left: 0.1,
              top: 0.2,
              width: 0.3,
              height: 0.1,
            ),
            PositionedText(
              text: 'Nadeel',
              left: 0.6,
              top: 0.2,
              width: 0.3,
              height: 0.1,
            ),
          ],
        ),
      ]);
      final slide = built.deck.slides.first;
      expect(slide.type, SlideType.twoBullets);
      expect(slide.bullets, ['Voordeel']);
      expect(slide.bullets2, ['Nadeel']);
    });

    test('a section-divider slide keeps its title', () {
      final built = _build([
        const SourceSlide(index: 1, title: 'Deel II', isSection: true),
      ]);
      final slide = built.deck.slides.first;
      expect(slide.type, SlideType.section);
      expect(slide.title, 'Deel II');
    });

    test('a marker :: title bullet list becomes a timeline', () {
      final built = _build([
        SourceSlide(
          index: 1,
          title: 'Historie',
          bodyBlocks: [_bullet('2019 :: Start'), _bullet('2023 :: Groei')],
        ),
      ]);
      final slide = built.deck.slides.single;
      expect(slide.type, SlideType.timeline);
      expect(slide.bullets, ['2019 :: Start', '2023 :: Groei']);
    });
  });

  group('DeckBuilder salvage & notes', () {
    test('speaker notes ride onto every slide', () {
      final built = _build([
        SourceSlide(
          index: 1,
          title: 'X',
          bodyBlocks: [_bullet('een')],
          notes: 'zeg dit',
        ),
      ]);
      expect(built.deck.slides.first.notes, 'zeg dit');
    });

    test('hyperlinks are appended as inline bullet links', () {
      final built = _build([
        SourceSlide(
          index: 1,
          title: 'Links',
          bodyBlocks: [_bullet('Zie ook')],
          hyperlinks: const [(text: 'OWASP', url: 'https://owasp.org')],
        ),
      ]);
      expect(built.deck.slides.first.bullets, [
        'Zie ook',
        '[OWASP](https://owasp.org)',
      ]);
    });

    test('a dangerous hyperlink scheme is neutralised', () {
      final built = _build([
        SourceSlide(
          index: 1,
          title: 'Links',
          bodyBlocks: [_bullet('klik')],
          hyperlinks: const [(text: 'x', url: 'javascript:alert(1)')],
        ),
      ]);
      expect(built.deck.slides.first.bullets.last, '[x](https://invalid)');
    });

    test(
      'a slide with audio carries the not-converted note in its speaker notes',
      () {
        final built = _build([
          SourceSlide(
            index: 1,
            title: 'Met geluid',
            bodyBlocks: [_bullet('punt')],
            audioFileName: 'intro.mp3',
          ),
        ]);
        expect(built.deck.slides.length, 1);
        final slide = built.deck.slides.single;
        expect(slide.type, SlideType.bullets);
        expect(slide.notes, contains('Niet overgenomen van slide 2'));
        expect(slide.notes, contains('intro.mp3'));
        // A real (non-salvaged) loss surfaces as a problem slide.
        expect(built.problemSlides.single.sourceSlideNumber, 2);
        expect(built.problemSlides.single.hadImage, isFalse);
      },
    );

    test('deck-wide issues append one trailing note slide', () {
      final built = _build(
        [
          SourceSlide(index: 0, title: 'A', bodyBlocks: [_bullet('x')]),
        ],
        issues: const [
          ConversionIssue(
            slideIndex: -1,
            feature: 'SmartArt',
            description: 'niet ondersteund',
          ),
        ],
      );
      final note = built.deck.slides.last;
      expect(note.type, SlideType.freeMarkdown);
      expect(
        note.customMarkdown,
        contains('Niet overgenomen van dit document'),
      );
      expect(note.customMarkdown, contains('SmartArt'));
    });
  });

  group('DeckBuilder image materialisation', () {
    test('identical image bytes share one mem: path (content de-dup)', () {
      final built = _build([
        SourceSlide(
          index: 0,
          title: 'Logo A',
          images: [
            _img([9, 9, 9]),
          ],
        ),
        SourceSlide(
          index: 1,
          title: 'Logo B',
          images: [
            _img([9, 9, 9]),
          ],
        ),
      ]);
      final a = built.deck.slides[0];
      final b = built.deck.slides[1];
      expect(a.imagePath, startsWith('mem:'));
      expect(a.imagePath, b.imagePath);
      // The bytes are parked in the store for FileService.saveDeck to materialise.
      expect(
        WebAssetStore.bytesFor(a.imagePath),
        Uint8List.fromList([9, 9, 9]),
      );
    });

    test('the deck title falls through from the source deck', () {
      final built = _build([
        SourceSlide(index: 0, title: 'A', bodyBlocks: [_bullet('x')]),
      ], title: 'Mijn presentatie');
      expect(built.deck.title, 'Mijn presentatie');
    });
  });
}
