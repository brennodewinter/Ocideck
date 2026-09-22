import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/bullet_pagination.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/rich_text_layout.dart'
    show logoSafeReserveEdges;
import 'package:ocideck/services/slide_layout_metrics.dart';
import 'package:ocideck/services/split_run.dart';
import 'package:ocideck/utils/bullet_fixes.dart';
import 'package:ocideck/widgets/slides/inline_markdown.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// Regressie voor #1279 én de vervolgklacht over ruimtebenutting: "Splits slide"
/// op een bullets+afbeelding-slide moet pagina's maken die passen bij de smalle
/// tekstkolom naast het beeld (eerste pagina), én vervolgpagina's die hun volle
/// breedte benutten in plaats van het beeld te herhalen — pagina's gevuld op
/// gemeten hoogte in plaats van een vast aantal bullets.

Future<File> _writeRedPng(String dir) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 8, 8),
    Paint()..color = const Color(0xFFFF0000),
  );
  final picture = recorder.endRecording();
  final img = await picture.toImage(8, 8);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  final file = File('$dir/red.png');
  file.writeAsBytesSync(data!.buffer.asUint8List());
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const profile = ThemeProfile(fontFamily: 'Roboto');
  final font = profile.fontFamily;

  setUpAll(() async {
    final bytes = File('assets/fonts/Roboto-Variable.ttf').readAsBytesSync();
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
  });

  Slide bulletsImage(
    List<String> items, {
    int imageSize = 40,
    ListStyle? listStyle,
  }) => Slide.create(SlideType.bulletsImage).copyWith(
    bullets: items,
    imagePath: 'foto.png',
    imageSize: imageSize,
    listStyle: listStyle,
  );

  List<String> longBullets(int n) => List.generate(
    n,
    (i) =>
        'Een behoorlijk lange bullet nummer $i die als volzin over meerdere '
        'regels van de tekstkolom heen loopt en flink wat hoogte vraagt.',
  );

  List<String> shortBullets(int n) => List.generate(n, (i) => 'Kort punt $i');

  List<int> pageSizes(Slide slide) => [
    for (final page in splitBulletSlidePages(slide, font: font)!)
      page.bullets.length,
  ];

  group('splitBulletSlidePages naast een afbeelding (#1279)', () {
    test('schaalt het aantal-plafond mee met de smalle tekstkolom', () {
      final items = shortBullets(20);
      // Volle breedte: het bekende plafond van acht per pagina.
      final plain = Slide.create(SlideType.bullets).copyWith(bullets: items);
      expect(pageSizes(plain), [8, 8, 4]);
      // Naast een 40%-afbeelding is de eerste kolom ~61% zo breed → plafond
      // vijf; de vervolgpagina's hebben geen beeld en dus het volle plafond.
      expect(pageSizes(bulletsImage(items)), [5, 8, 7]);
    });

    test('een bredere afbeelding verlaagt het plafond, tot de pagina-vloer', () {
      // 70% beeld laat een sliver tekstkolom over; het plafond zakt niet onder
      // kMinPageBullets, want een pagina van twee bullets is geen slide.
      expect(pageSizes(bulletsImage(shortBullets(9), imageSize: 70)), [3, 6]);
    });

    test('een smalle afbeelding houdt het volle-breedte-plafond', () {
      // 10% beeld: de kolom is vrijwel volle breedte, het plafond blijft acht.
      expect(pageSizes(bulletsImage(shortBullets(16), imageSize: 10)), [8, 8]);
    });

    test('een checklist naast een afbeelding schaalt haar ruimere optimum', () {
      final slide = bulletsImage([
        for (var i = 0; i < 14; i++) '[ ] Taak nummer $i om af te vinken',
      ], listStyle: ListStyle.checklist);
      expect(pageSizes(slide), [7, 7]);
    });
  });

  group('splitBulletSlidePages op gemeten hoogte', () {
    test('verdeelt lange bullets op hoogte in plaats van op aantal', () {
      // Acht heel lange bullets: puur op aantal valt de lijst binnen het
      // plafond in twee helften van vier — waarvan elke pagina op de
      // doelschaal ruim overloopt. Op hoogte gepakt krijgt elke pagina precies
      // zoveel bullets als er echt passen.
      final items = [
        for (var i = 0; i < 8; i++)
          '${List.filled(30, 'heel veel tekst ').join()}$i',
      ];
      final pages = splitBulletSlidePages(
        Slide.create(SlideType.bullets).copyWith(bullets: items),
        font: font,
      )!;
      expect(pages.length, greaterThan(2));
      expect(pages.expand((p) => p.bullets).toList(), items);
      for (final p in pages) {
        expect(
          bulletsPageFitsAtScale(
            slide: p,
            pageBullets: p.bullets,
            scale: kSplitPageTargetScale,
            font: font,
          ),
          isTrue,
        );
      }
    });

    test('raakt geen bullet kwijt en houdt de volgorde', () {
      final items = longBullets(23);
      final pages = splitBulletSlidePages(bulletsImage(items), font: font)!;
      expect(pages.expand((p) => p.bullets).toList(), items);
    });

    test(
      'elke pagina met afzonderlijk passende bullets past op de doelschaal',
      () {
        final pages = splitBulletSlidePages(
          bulletsImage(longBullets(30)),
          font: font,
        )!;
        for (final page in pages) {
          expect(
            bulletsPageFitsAtScale(
              slide: page,
              pageBullets: page.bullets,
              scale: kSplitPageTargetScale,
              font: font,
            ),
            isTrue,
            reason:
                'een pagina die op de doelschaal niet past trekt de gedeelde '
                'run-schaal alsnog onder die doelschaal',
          );
        }
      },
    );

    test('reserveert logoruimte links, rechts, boven en onder', () {
      final slide = bulletsImage(
        longBullets(30),
      ).copyWith(title: 'Volle reeks met huisstijl');
      for (final position in ThemeProfile.logoPositions) {
        final themed = ThemeProfile(
          fontFamily: font,
          logoPath: 'logo.png',
          logoPosition: position,
          logoSize: 240,
        );
        final pages = splitBulletSlidePages(slide, font: font, theme: themed)!;
        for (var i = 0; i < pages.length; i++) {
          final page = pages[i];
          final (top, bottom) = logoSafeReserveEdges(
            kReferenceSlideWidth,
            themed,
            splitText: i == 0,
          );
          expect(
            bulletsPageFitsAtScale(
              slide: page,
              pageBullets: page.bullets,
              scale: kSplitPageTargetScale,
              font: font,
              extraVReserve: top + bottom,
            ),
            isTrue,
            reason: '$position, pagina ${i + 1}',
          );
        }
      }
    });

    test('showLogo false laat het themalogo buiten de paginering', () {
      final slide = bulletsImage(longBullets(30)).copyWith(showLogo: false);
      const themed = ThemeProfile(
        fontFamily: 'Roboto',
        logoPath: 'logo.png',
        logoPosition: 'top-left',
        logoSize: 240,
      );
      final plain = splitBulletSlidePages(slide, font: font)!;
      final withTheme = splitBulletSlidePages(
        slide,
        font: font,
        theme: themed,
      )!;
      expect(withTheme.map((p) => p.bullets), plain.map((p) => p.bullets));
    });
  });

  group('splitBulletSlidePages: vervolgpagina\'s op volle breedte', () {
    test('laat het beeld op de eerste pagina, vervolgen zijn bulletslides', () {
      final source = bulletsImage(longBullets(20)).copyWith(
        imagePath2: 'tweede.png',
        imageCaption: 'Bijschrift',
        imageCaption2: 'Tweede bijschrift',
        imageAltText: 'Alt',
        imageAltText2: 'Tweede alt',
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.5, 0.5)],
            description: 'Midden',
          ),
        ],
        cssClass: 'custom keep-me split',
      );
      final pages = splitBulletSlidePages(source, font: font)!;
      expect(pages.first.type, SlideType.bulletsImage);
      expect(pages.first.imagePath, 'foto.png');
      for (final page in pages.skip(1)) {
        expect(page.type, SlideType.bullets);
        expect(page.imagePath, isEmpty);
        expect(page.imagePath2, isEmpty);
        expect(page.imageCaption, isEmpty);
        expect(page.imageCaption2, isEmpty);
        expect(page.imageAltText, isEmpty);
        expect(page.imageAltText2, isEmpty);
        expect(page.callouts, isEmpty);
        expect(page.cssClass, 'custom keep-me');
        expect(page.continuesSplit, isTrue);
      }

      final reparsed = MarkdownService().parseDeck(
        MarkdownService().generateDeck(Deck(title: 'T', slides: pages)),
      )!;
      for (final page in reparsed.slides.skip(1)) {
        expect(page.type, SlideType.bullets);
        expect(page.imagePath, isEmpty);
        expect(page.imagePath2, isEmpty);
        expect(page.callouts, isEmpty);
        expect(page.cssClass, 'custom keep-me');
      }
    });

    test('een vervolg-bulletslide blijft in dezelfde run', () {
      final pages = splitBulletSlidePages(
        bulletsImage(longBullets(20)),
        font: font,
      )!;
      // De run loopt van de split-pagina tot en met de laatste bulletslide;
      // zonder de bulletsImage→bullets-overgang zou elke vervolgpagina een
      // eigen (of geen) reeks vormen en niet meeschalen.
      expect(splitRunRange(pages, 0), (0, pages.length - 1));
      expect(sharedSplitFitScale(pages, 0, profile, font), isNotNull);
    });

    test('de gesplitste reeks overleeft opslaan en opnieuw inlezen', () {
      // De vervolgpagina's zijn bulletslides; hun `ocideck_continue_split` moet
      // na de Markdown-heen-en-weer nog bij de split-pagina aansluiten.
      final service = MarkdownService();
      final pages = splitBulletSlidePages(
        bulletsImage(longBullets(20)),
        font: font,
      )!;
      final reparsed = service.parseDeck(
        service.generateDeck(Deck(title: 'T', slides: pages)),
      )!;
      expect(reparsed.slides.length, pages.length);
      expect(reparsed.slides.first.type, SlideType.bulletsImage);
      for (final page in reparsed.slides.skip(1)) {
        expect(page.type, SlideType.bullets);
        expect(page.continuesSplit, isTrue);
      }
      expect(splitRunRange(reparsed.slides, 0), (0, pages.length - 1));
    });

    test('de gedeelde run-schaal stijgt boven die van de oude splitsing', () {
      final slide = bulletsImage(longBullets(20));
      final newPages = splitBulletSlidePages(slide, font: font)!;
      // De splitsing zoals hij was: een vast aantal bullets per pagina, en het
      // beeld (de smalle kolom) op élke vervolgpagina.
      final oldChunks = splitBulletsIntoPages(slide.bullets, 8);
      final oldPages = [
        for (var i = 0; i < oldChunks.length; i++)
          (i == 0 ? slide : Slide.duplicate(slide)).copyWith(
            bullets: oldChunks[i],
            continuesSplit: i != 0,
          ),
      ];

      final sharedNew = sharedSplitFitScale(newPages, 0, profile, font);
      final sharedOld = sharedSplitFitScale(oldPages, 0, profile, font);
      expect(sharedNew, isNotNull);
      expect(sharedOld, isNotNull);
      expect(
        sharedNew,
        greaterThan(sharedOld!),
        reason:
            'volle breedte op vervolgpagina\'s plus hoogte-paginering moet de '
            'volste pagina — en dus de gedeelde schaal — laten groeien',
      );
    });

    testWidgets('alle pagina\'s renderen werkelijk op minstens de doelschaal', (
      tester,
    ) async {
      // Repo-regel: een meetheuristiek wordt tegen de echte widget gepind. Dit
      // controleert zowel de smalle eerste beeldpagina als alle volle-breedte
      // vervolgen, met titel en een echt geladen themalogo.
      await tester.runAsync(() async {
        final dir = Directory.systemTemp.createTempSync('ocideck_test');
        final redPng = await _writeRedPng(dir.path);
        addTearDown(() => dir.deleteSync(recursive: true));

        final slide = bulletsImage(
          longBullets(20),
        ).copyWith(imagePath: redPng.path, title: 'Volle reeks met huisstijl');
        final branded = profile.copyWith(
          logoPath: redPng.path,
          logoPosition: 'top-left',
          logoSize: 160,
        );
        final pages = splitBulletSlidePages(slide, font: font, theme: branded)!;
        final shared = sharedSplitFitScale(pages, 0, branded, font)!;

        for (var i = 0; i < pages.length; i++) {
          final page = pages[i];
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 800,
                    height: 450,
                    child: SlidePreviewWidget(
                      slide: page,
                      themeProfile: branded,
                      fitScaleOverride: shared,
                    ),
                  ),
                ),
              ),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          final renderedBullets = tester
              .widgetList<InlineMarkdownText>(find.byType(InlineMarkdownText))
              .where((w) => page.bullets.contains(w.text))
              .toList();
          expect(renderedBullets, isNotEmpty, reason: 'pagina ${i + 1}');
          final baseSize =
              800 * (page.type == SlideType.bulletsImage ? 0.031 : 0.026);
          for (final bullet in renderedBullets) {
            expect(
              bullet.style.fontSize!,
              greaterThanOrEqualTo(baseSize * kSplitPageTargetScale - 0.01),
              reason: 'pagina ${i + 1}: ${bullet.text}',
            );
          }
        }
      });
    });
  });
}
