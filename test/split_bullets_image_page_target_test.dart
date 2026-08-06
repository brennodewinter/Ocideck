import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/bullet_pagination.dart';
import 'package:ocideck/utils/bullet_fixes.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// Regressie voor #1279: "Splits slide" op een bullets+afbeelding-slide moet
/// pagina's maken die passen bij de smalle tekstkolom naast het beeld. Met het
/// volle-breedte-paginadoel bleven de deel-slides op de lage gedeelde
/// run-schaal hangen en bleef de vrijgekomen ruimte onbenut.

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
        'regels van de smalle tekstkolom naast de afbeelding heen loopt.',
  );

  List<int> pageSizes(Slide slide) => [
    for (final page in splitBulletSlidePages(slide)!) page.bullets.length,
  ];

  group('splitBulletSlidePages naast een afbeelding (#1279)', () {
    test('schaalt het paginadoel mee met de smalle tekstkolom', () {
      final items = longBullets(20);
      // Volle breedte: het bekende doel van acht per pagina.
      final plain = Slide.create(SlideType.bullets).copyWith(bullets: items);
      expect(pageSizes(plain), [8, 8, 4]);
      // Naast een 40%-afbeelding is de kolom ~61% zo breed → doel vijf.
      expect(pageSizes(bulletsImage(items)), [5, 5, 5, 5]);
    });

    test('een bredere afbeelding verlaagt het doel, tot de pagina-vloer', () {
      // 70% beeld laat een sliver tekstkolom over; het doel zakt niet onder
      // kMinPageBullets, want een pagina van twee bullets is geen slide.
      expect(pageSizes(bulletsImage(longBullets(9), imageSize: 70)), [3, 3, 3]);
    });

    test('een smalle afbeelding houdt het volle-breedte-doel', () {
      // 10% beeld: de kolom is vrijwel volle breedte, het doel blijft acht.
      expect(pageSizes(bulletsImage(longBullets(16), imageSize: 10)), [8, 8]);
    });

    test('een checklist naast een afbeelding schaalt haar ruimere optimum', () {
      final slide = bulletsImage([
        for (var i = 0; i < 14; i++) '[ ] Taak nummer $i om af te vinken',
      ], listStyle: ListStyle.checklist);
      expect(pageSizes(slide), [7, 7]);
    });

    test('de gedeelde run-schaal stijgt boven die van de oude splitsing', () {
      final slide = bulletsImage(longBullets(20));
      final newPages = splitBulletSlidePages(slide)!;
      // De splitsing zoals hij vóór #1279 was: het volle-breedte-doel van acht.
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
            'minder bullets per pagina moet de volste pagina — en dus de '
            'gedeelde schaal — laten groeien',
      );
    });

    testWidgets('een vervolgpagina rendert zijn tekst werkelijk groter', (
      tester,
    ) async {
      // Repo-regel: een heuristiek die een renderafmeting voorspelt, wordt
      // tegen de echte render gepind — hier de effectieve fontSize in de boom.
      await tester.runAsync(() async {
        final dir = Directory.systemTemp.createTempSync('ocideck_test');
        final redPng = await _writeRedPng(dir.path);
        addTearDown(() => dir.deleteSync(recursive: true));

        final slide = bulletsImage(
          longBullets(20),
        ).copyWith(imagePath: redPng.path);
        final newPages = splitBulletSlidePages(slide)!;
        final oldChunks = splitBulletsIntoPages(slide.bullets, 8);
        final oldPages = [
          for (var i = 0; i < oldChunks.length; i++)
            (i == 0 ? slide : Slide.duplicate(slide)).copyWith(
              bullets: oldChunks[i],
              continuesSplit: i != 0,
            ),
        ];

        Future<double> maxBulletFontSize(List<Slide> pages) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 800,
                    height: 450,
                    child: SlidePreviewWidget(
                      slide: pages[1],
                      themeProfile: profile,
                      fitScaleOverride: sharedSplitFitScale(
                        pages,
                        1,
                        profile,
                        font,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          var max = 0.0;
          for (final text in tester.widgetList<Text>(find.byType(Text))) {
            final size = text.style?.fontSize;
            if (size != null && size > max) max = size;
          }
          expect(max, greaterThan(0));
          return max;
        }

        final sizeNew = await maxBulletFontSize(newPages);
        final sizeOld = await maxBulletFontSize(oldPages);
        expect(
          sizeNew,
          greaterThan(sizeOld),
          reason:
              'de vervolgpagina van de nieuwe splitsing moet zichtbaar '
              'groter renderen dan die van de oude acht-per-pagina-splitsing',
        );
      });
    });
  });
}
