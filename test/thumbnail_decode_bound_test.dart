// Een slidestrook-thumbnail is ongeveer 180 px breed. Tot #612 decodeerde hij
// de afbeelding op ware grootte: een telefoonfoto van 4032×3024 kost dan bijna
// 49 MiB, en tien zichtbare thumbnails met verschillende foto's zijn een halve
// gigabyte aan lévende bitmaps die de cache niet weggooit zolang ze in beeld
// staan.
//
// Op desktop is dat een geheugengrafiek die niemand ziet. Op web valt de tab
// om, en web is de demo-route.
//
// Wat hier bewaakt wordt is de grens én zijn beperktheid: alléén de strook
// verkleint. Preview, presentatiemodus en de rasteraar tekenen op ware grootte,
// want daar ís de resolutie het product — een export op 512 px zou een
// stilzwijgende kwaliteitsval zijn die veel erger is dan het geheugen dat we
// besparen.

import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/utils/image_limits.dart';
import 'package:ocideck/widgets/slides/previews/retrying_image.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

import 'support/temp_dir.dart';

void main() {
  test('de gebonden variant vraagt echt een kleinere decode', () {
    // De decodeEdge draagt de grens; zonder deze assertie zou een
    // implementatiewissel naar de ongebonden vorm stil doorgaan.
    final bounded = boundedFileImage(File('assets/images/cat-keiko.jpg'), 512);
    expect(bounded, isA<CappedImage>());
    final capped = bounded as CappedImage;
    expect(capped.decodeEdge, 512);
  });

  test('512 is fors kleiner dan de gewone decode-cap', () {
    // De verhouding is het punt: de cap bestaat tegen een decodeerbom, niet
    // tegen geheugen per zichtbare thumbnail. 4096 vs 512 is een factor 64 in
    // pixels.
    expect(kMaxImageDecodeDimension, greaterThanOrEqualTo(512 * 8));
  });

  group('decodeEdgeForDisplay — de weergave-grens (#2625)', () {
    test('rondt de fysieke pixelmaat omhoog af op een vaste trede', () {
      // De trede is de cachesleutel: een scherm van 1840 px en een van
      // 1900 px delen dan dezelfde decode i.p.v. elk een eigen entry.
      expect(decodeEdgeForDisplay(500, 1), 1024);
      expect(decodeEdgeForDisplay(800, 2), 2048); // preview, retina
      expect(decodeEdgeForDisplay(1920, 1), 2048); // presentatie, FHD
      expect(decodeEdgeForDisplay(1024, 1), 1024); // exact op een trede
      expect(decodeEdgeForDisplay(3000, 1), 4096);
      expect(decodeEdgeForDisplay(5000, 1), 4096); // plafond
    });

    test('valt terug op het plafond bij een onmeetbare breedte', () {
      expect(
        decodeEdgeForDisplay(double.infinity, 1),
        kMaxImageDecodeDimension,
      );
      expect(decodeEdgeForDisplay(0, 2), kMaxImageDecodeDimension);
    });
  });

  testWidgets(
    'een preview op 800 logische px bij DPR 2 decodeert hooguit 2048',
    (tester) async {
      // Een echt projectpad is nodig: zonder projectgrens weigert
      // resolveSlideAssetPath elk bestandspad en staat er alleen een
      // placeholder — geen provider om de grens op te meten.
      final project = await tester.runAsync(
        () => Directory.systemTemp.createTemp('ocideck-2625'),
      );
      if (project == null) return;
      addTearDown(() => deleteTempDir(project));
      final slide = Slide.create(
        SlideType.image,
      ).copyWith(title: 'T', imagePath: 'foto.png');
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 2),
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 450,
                child: SlidePreviewWidget(
                  slide: slide,
                  themeProfile: const ThemeProfile(),
                  projectPath: project.path,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final image = tester
          .widgetList<RetryingImage>(find.byType(RetryingImage))
          .map((w) => w.image)
          .whereType<CappedImage>()
          .first;
      expect(
        image.decodeEdge,
        2048,
        reason:
            'de preview moet op de weergave-trede decoderen, niet op de '
            '4096-decodeerbom-grens — dat was 45 MB per foto per oppervlak',
      );
    },
  );

  testWidgets('een expliciete strook-grens wint van de weergave-maat', (
    tester,
  ) async {
    final project = await tester.runAsync(
      () => Directory.systemTemp.createTemp('ocideck-2625'),
    );
    if (project == null) return;
    addTearDown(() => deleteTempDir(project));
    final slide = Slide.create(
      SlideType.image,
    ).copyWith(title: 'T', imagePath: 'foto.png');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 450,
            child: SlidePreviewWidget(
              slide: slide,
              themeProfile: const ThemeProfile(),
              projectPath: project.path,
              decodeMaxEdge: 512,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final image = tester
        .widgetList<RetryingImage>(find.byType(RetryingImage))
        .map((w) => w.image)
        .whereType<CappedImage>()
        .first;
    expect(image.decodeEdge, 512);
  });
}
