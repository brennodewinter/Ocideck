import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/import/core/result.dart';
import 'package:ocideck/services/import/deck_builder.dart';
import 'package:ocideck/services/import/importers/pptx/pptx_importer.dart';
import 'package:ocideck/services/import/logo_detection.dart';
import 'package:ocideck/services/import/models/body_block.dart';
import 'package:ocideck/services/import/models/source_deck.dart';
import 'package:ocideck/services/import/models/source_image.dart';
import 'package:ocideck/services/import/models/source_slide.dart';
import 'package:ocideck/services/import/models/source_theme.dart';
import 'package:ocideck/services/import/pipeline/slide_classifier.dart';
import 'package:ocideck/services/import/presentation_import_service.dart';
import 'package:ocideck/services/web_asset_store.dart';

import 'helpers/pptx_fixture.dart';

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
    test(
      'haalt een compact hoeklogo uit een geerfde brede merkstrook',
      () async {
        final imported = await PptxImporter().importBytes(
          pptxBrandFixture(),
          path: 'merkdeck.pptx',
        );
        expect(imported.isOk, isTrue);

        final candidates = detectImportLogoCandidates(imported.okValue!);

        expect(candidates, hasLength(1));
        final candidate = candidates.single;
        expect(candidate.slideIndexes, [0, 1, 2]);
        expect(candidate.edge, ImportLogoEdge.bottom);
        expect(candidate.brandStrip, isNotNull);
        expect(candidate.brandStrip!.placement!.left, 0);
        expect(candidate.brandStrip!.placement!.width, 1);
        expect(
          candidate.brandStrip!.placement!.top,
          closeTo(5969000 / 6858000, .0001),
        );
        expect(
          candidate.brandStrip!.placement!.height,
          closeTo(889000 / 6858000, .0001),
        );
        expect(candidate.image.placement?.left, closeTo(1000 / 1280, .001));
        expect(
          candidate.image.placement?.top,
          closeTo((5969000 + 889000 * .1) / 6858000, .001),
        );
        expect(candidate.image.placement?.width, closeTo(180 / 1280, .001));
        expect(
          candidate.image.placement?.height,
          closeTo((889000 * .6) / 6858000, .001),
        );
        final decoded = img.decodeImage(candidate.image.bytes);
        expect(decoded, isNotNull);
        expect([decoded!.width, decoded.height], [180, 60]);

        final profile = importedLogoProfile(
          deck: imported.okValue!,
          candidate: candidate,
          logoPath: 'mem:merklogo',
          brandStripPath: 'mem:merkstrook',
          name: 'Merkstijl',
        );
        expect(profile.logoPosition, 'bottom-right');
        expect(profile.logoSize, 180);
        expect(profile.brandStripPath, 'mem:merkstrook');
        expect(profile.brandStripHeight, closeTo(889000 / 6858000, .0001));
        expect(profile.titleSubtitleInBrandStrip, isTrue);
        expect(profile.logoSize, greaterThan(const ThemeProfile().logoSize));
        expect(profile.accentColor, '#00A1DB');
        expect(profile.textColor, '#000000');
        expect(profile.fontFamily, 'Arial');
      },
    );

    test('bouwt omslag, slotbeeld en bronstijl na logobevestiging', () async {
      final imported = await PptxImporter().importBytes(
        pptxBrandFixture(),
        path: 'merkdeck.pptx',
      );
      final source = imported.okValue!;
      final prepared = PreparedImport(
        const [],
        source,
        classifySourceSlides(source.slides),
        'Merkworkshop',
        DeckBuilder(),
      );
      final candidate = prepared.logoCandidates.single;
      final profile = importedLogoProfile(
        deck: source,
        candidate: candidate,
        logoPath: 'mem:merklogo',
        brandStripPath: 'mem:merkstrook',
        name: 'Merkstijl',
      );

      final built = prepared.build(
        logo: ImportLogoResolution(candidate: candidate, profile: profile),
      );

      expect(built.problemSlides, isEmpty);
      expect(built.deck.slides.map((slide) => slide.type), [
        SlideType.title,
        SlideType.image,
        SlideType.title,
      ]);
      expect(built.deck.slides.first.subtitle, 'Samen aan de slag');
      expect(
        built.deck.slides.first.imagePath,
        startsWith('mem:'),
        reason: 'de geerfde omslagafbeelding blijft op de titeldia staan',
      );
      expect(
        built.deck.slides.last.imagePath,
        startsWith('mem:'),
        reason: 'ook de geerfde slotachtergrond blijft behouden',
      );
      expect(built.deck.slides.map((slide) => slide.showLogo), [
        true,
        true,
        true,
      ]);
      expect(built.deck.themeProfile.name, 'Merkstijl');
      expect(built.deck.themeProfile.logoSize, 180);
      expect(built.deck.themeProfile.logoPosition, 'bottom-right');
      expect(built.deck.themeProfile.brandStripPath, 'mem:merkstrook');
      expect(
        built.deck.themeProfile.brandStripHeight,
        closeTo(889000 / 6858000, .0001),
      );
      expect(built.deck.themeProfile.titleSubtitleInBrandStrip, isTrue);
    });

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

  test(
    'genegeerd logo verdwijnt zonder profiel terwijl gewone foto\'s blijven',
    () {
      const logoBytes = [40, 41, 42];
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
          images: [logo(), photo(51)],
        ),
        SourceSlide(
          index: 1,
          title: 'Tweede',
          bodyBlocks: const [
            BodyBlock(kind: BodyBlockKind.bullet, text: 'Meer inhoud'),
          ],
          images: [logo(), photo(52)],
        ),
        const SourceSlide(
          index: 2,
          title: 'Derde',
          bodyBlocks: [
            BodyBlock(kind: BodyBlockKind.bullet, text: 'Zonder logo'),
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
        reason: 'vóór negeren leiden de extra logo-afbeeldingen tot overflow',
      );
      final prepared = PreparedImport(
        const [],
        source,
        classified,
        'Brondeck',
        DeckBuilder(),
      );
      final candidate = prepared.logoCandidates.single;

      final built = prepared.build(
        logo: ImportLogoResolution.ignored(candidate),
      );

      expect(built.deck.slides, hasLength(3));
      expect(
        built.deck.slides.take(2).map((slide) => slide.type),
        everyElement(SlideType.bulletsImage),
        reason:
            'na verwijderen worden de oorspronkelijke dia\'s opnieuw bepaald',
      );
      final photoPaths = built.deck.slides
          .take(2)
          .map((slide) => slide.imagePath)
          .toList();
      expect(photoPaths, everyElement(startsWith('mem:')));
      expect(WebAssetStore.bytesFor(photoPaths[0]), Uint8List.fromList([51]));
      expect(WebAssetStore.bytesFor(photoPaths[1]), Uint8List.fromList([52]));
      expect(
        WebAssetStore.totalBytes,
        2,
        reason: 'geen enkele kandidaatvoorkomst wordt als asset opgebouwd',
      );
      expect(built.deck.themeProfile.logoPath, isNull);
      expect(built.deck.themeProfile.accentColor, isNot('#123456'));
    },
  );
}
