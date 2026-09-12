import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/import/deck_builder.dart';
import 'package:ocideck/services/import/logo_detection.dart';
import 'package:ocideck/services/import/models/body_block.dart';
import 'package:ocideck/services/import/models/source_deck.dart';
import 'package:ocideck/services/import/models/source_image.dart';
import 'package:ocideck/services/import/models/source_slide.dart';
import 'package:ocideck/services/import/models/source_theme.dart';
import 'package:ocideck/services/import/pipeline/slide_classifier.dart';
import 'package:ocideck/services/import/presentation_import_service.dart';
import 'package:ocideck/services/web_asset_store.dart';

SourceImage _image(
  List<int> bytes, {
  required double left,
  required double top,
  required double width,
  required double height,
  String name = 'logo.png',
}) => SourceImage(
  bytes: Uint8List.fromList(bytes),
  ext: 'png',
  name: name,
  placement: SourceImagePlacement(
    left: left,
    top: top,
    width: width,
    height: height,
  ),
);

SourceSlide _slide(int index, List<SourceImage> images) =>
    SourceSlide(index: index, title: 'Dia ${index + 1}', images: images);

void main() {
  setUp(WebAssetStore.clear);
  tearDown(WebAssetStore.clear);

  group('detectImportLogoCandidates', () {
    test('vindt hetzelfde kleine randbeeld op twee van vier dia\'s', () {
      const logoBytes = [1, 2, 3, 4];
      final deck = SourceDeck(
        slides: [
          _slide(0, [
            _image(logoBytes, left: .82, top: .03, width: .12, height: .08),
          ]),
          _slide(1, const []),
          _slide(2, [
            _image(
              logoBytes,
              left: .82,
              top: .03,
              width: .12,
              height: .08,
              name: 'ander-archiefpad.png',
            ),
          ]),
          _slide(3, const []),
        ],
      );

      final candidates = detectImportLogoCandidates(deck);

      expect(candidates, hasLength(1));
      expect(candidates.single.slideIndexes, [0, 2]);
      expect(candidates.single.occurrenceCount, 2);
      expect(candidates.single.edge, ImportLogoEdge.top);
    });

    test('een herhaald beeld in het midden is geen logo', () {
      const bytes = [5, 6, 7];
      final deck = SourceDeck(
        slides: [
          _slide(0, [_image(bytes, left: .4, top: .4, width: .1, height: .1)]),
          _slide(1, [_image(bytes, left: .4, top: .4, width: .1, height: .1)]),
        ],
      );

      expect(detectImportLogoCandidates(deck), isEmpty);
    });

    test('tweemaal op slechts een dia telt niet als herhaling', () {
      const bytes = [8, 9, 10];
      final first = _image(bytes, left: .05, top: .85, width: .1, height: .08);
      final second = _image(bytes, left: .85, top: .85, width: .1, height: .08);

      expect(
        detectImportLogoCandidates(
          SourceDeck(
            slides: [
              _slide(0, [first, second]),
              _slide(1, const []),
            ],
          ),
        ),
        isEmpty,
      );
    });

    test('een grote herhaalde randafbeelding is geen logo', () {
      const bytes = [11, 12, 13];
      final deck = SourceDeck(
        slides: [
          _slide(0, [_image(bytes, left: .1, top: .8, width: .8, height: .2)]),
          _slide(1, [_image(bytes, left: .1, top: .8, width: .8, height: .2)]),
        ],
      );

      expect(detectImportLogoCandidates(deck), isEmpty);
    });
  });

  test(
    'bevestigd logo wordt verwijderd, opnieuw geclassificeerd en als profiel gezet',
    () {
      const logoBytes = [20, 21, 22];
      SourceImage logo() =>
          _image(logoBytes, left: .82, top: .86, width: .12, height: .08);
      SourceImage photo(int marker) => _image(
        [marker],
        left: .1,
        top: .2,
        width: .6,
        height: .6,
        name: 'foto-$marker.png',
      );
      final slides = [
        SourceSlide(
          index: 0,
          title: 'Eerste',
          bodyBlocks: const [
            BodyBlock(kind: BodyBlockKind.bullet, text: 'Inhoud'),
          ],
          images: [logo(), photo(31)],
        ),
        SourceSlide(
          index: 1,
          title: 'Tweede',
          bodyBlocks: const [
            BodyBlock(kind: BodyBlockKind.bullet, text: 'Meer inhoud'),
          ],
          images: [logo(), photo(32)],
        ),
        const SourceSlide(
          index: 2,
          title: 'Derde',
          bodyBlocks: [
            BodyBlock(kind: BodyBlockKind.bullet, text: 'Zonder logo'),
          ],
        ),
        const SourceSlide(
          index: 3,
          title: 'Vierde',
          bodyBlocks: [
            BodyBlock(kind: BodyBlockKind.bullet, text: 'Ook zonder logo'),
          ],
        ),
      ];
      final source = SourceDeck(
        title: 'Brondeck',
        theme: const SourceTheme(accentColor: '#123456', fontFamily: 'Arial'),
        slides: slides,
      );
      final classified = classifySourceSlides(slides);
      expect(
        classified.where((slide) => slide.type == SlideType.image),
        hasLength(2),
        reason: 'zonder logoresolutie worden de tweede beelden overflow-dia\'s',
      );
      final prepared = PreparedImport(
        const [],
        source,
        classified,
        'Brondeck',
        DeckBuilder(),
      );
      final candidate = prepared.logoCandidates.single;
      final profile = importedLogoProfile(
        deck: source,
        candidate: candidate,
        logoPath: 'mem:bevestigd-logo',
        name: 'Bronstijl',
      );

      final built = prepared.build(
        logo: ImportLogoResolution(candidate: candidate, profile: profile),
      );

      expect(built.deck.slides, hasLength(4));
      expect(
        built.deck.slides.take(2).map((slide) => slide.type),
        everyElement(SlideType.bulletsImage),
      );
      expect(
        built.deck.slides.take(2).map((slide) => slide.imagePath),
        everyElement(startsWith('mem:')),
        reason: 'de echte foto blijft behouden',
      );
      expect(built.deck.slides.map((slide) => slide.showLogo), [
        true,
        true,
        false,
        false,
      ], reason: 'het logo verschijnt alleen waar het in de bron stond');
      expect(built.deck.themeProfile.name, 'Bronstijl');
      expect(built.deck.themeProfile.logoPath, 'mem:bevestigd-logo');
      expect(built.deck.themeProfile.logoPosition, 'bottom-right');
      expect(built.deck.themeProfile.accentColor, '#123456');
    },
  );
}
