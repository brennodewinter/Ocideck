import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Future<File> _writeSolidPng(String dir, String name, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = color);
  final picture = recorder.endRecording();
  final img = await picture.toImage(8, 8);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  final file = File('$dir/$name');
  file.writeAsBytesSync(data!.buffer.asUint8List());
  return file;
}

Future<({int width, int height, Uint8List bytes})> _capture(
  WidgetTester tester,
  GlobalKey key,
  Widget child,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(width: 800, height: 450, child: child),
          ),
        ),
      ),
    ),
  );
  // Let the file images decode and paint before capturing a single frame.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await tester.pump();

  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.0);
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();
  return (width: image.width, height: image.height, bytes: bytes);
}

void main() {
  testWidgets('a missing small logo does not overflow its bounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            child: SlidePreviewWidget(
              slide: Slide.create(SlideType.bullets),
              themeProfile: const ThemeProfile(
                logoPath: '/path/that/does/not/exist.png',
                logoSize: 36,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('an unresolvable theme logo vanishes instead of drawing the '
      'missing-file placeholder (#1174)', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              // Large enough that the placeholder would render its full
              // icon-and-label form (it collapses to an icon below 48 px).
              width: 1200,
              child: SlidePreviewWidget(
                slide: Slide.create(SlideType.bullets),
                themeProfile: const ThemeProfile(
                  logoPath: '/no/such/theme-logo.png',
                  logoSize: 128,
                ),
              ),
            ),
          ),
        ),
      );
      // Let the (failing) file image decode so the errorBuilder runs.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();

      // A brand overlay that can't resolve must fall away silently — no
      // broken-image placeholder stamped onto every slide (and every export).
      expect(find.text('Bestand niet gevonden'), findsNothing);
      expect(find.text('Buiten de presentatie'), findsNothing);
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
    });
  });

  testWidgets('a missing *content* image still shows the placeholder '
      '(the theme-logo fix must not swallow it, #1174)', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              child: SlidePreviewWidget(
                slide: Slide(
                  id: 'c',
                  type: SlideType.image,
                  imagePath: '/no/such/content-image.png',
                ),
              ),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('Bestand niet gevonden'), findsOneWidget);
    });
  });

  testWidgets('twoImages paints both the left and right images', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('ocideck_two');
      final red = await _writeSolidPng(
        dir.path,
        'red.png',
        const Color(0xFFFF0000),
      );
      final blue = await _writeSolidPng(
        dir.path,
        'blue.png',
        const Color(0xFF0000FF),
      );

      final slide = Slide(
        id: 'x',
        type: SlideType.twoImages,
        imagePath: red.path,
        imagePath2: blue.path,
      );

      final key = GlobalKey();
      final cap = await _capture(tester, key, SlidePreviewWidget(slide: slide));

      ({int r, int g, int b}) pixelAt(double fx, double fy) {
        final x = (cap.width * fx).round().clamp(0, cap.width - 1);
        final y = (cap.height * fy).round().clamp(0, cap.height - 1);
        final i = (y * cap.width + x) * 4;
        return (r: cap.bytes[i], g: cap.bytes[i + 1], b: cap.bytes[i + 2]);
      }

      final left = pixelAt(0.25, 0.5);
      final right = pixelAt(0.75, 0.5);

      expect(
        left.r > 200 && left.b < 80,
        isTrue,
        reason: 'Left panel should be the red image but was $left',
      );
      expect(
        right.b > 200 && right.r < 80,
        isTrue,
        reason: 'Right panel should be the blue image but was $right',
      );

      dir.deleteSync(recursive: true);
    });
  });

  testWidgets('zoomed (scaled) image still paints in the frame', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('ocideck_zoom');
      final red = await _writeSolidPng(
        dir.path,
        'red.png',
        const Color(0xFFFF0000),
      );

      // imageSize 150 = zoomed in past contain; the picture must still render
      // (regression: the old Transform.scale rendered blank in toImage).
      final slide = Slide(
        id: 'z',
        type: SlideType.image,
        imagePath: red.path,
        imageSize: 150,
      );

      final key = GlobalKey();
      final cap = await _capture(tester, key, SlidePreviewWidget(slide: slide));

      final cx = cap.width ~/ 2;
      final cy = cap.height ~/ 2;
      final i = (cy * cap.width + cx) * 4;
      final r = cap.bytes[i];
      final g = cap.bytes[i + 1];
      final b = cap.bytes[i + 2];

      expect(
        r > 200 && g < 80 && b < 80,
        isTrue,
        reason: 'Center of a zoomed image should be red but was ($r,$g,$b)',
      );

      dir.deleteSync(recursive: true);
    });
  });

  testWidgets('zoomed-out image with a title anchors to the top', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('ocideck_top');
      final red = await _writeSolidPng(
        dir.path,
        'red.png',
        const Color(0xFFFF0000),
      );

      // Zoomed out (60%) with a title: the image should sit at the top so the
      // bottom title banner does not overlap it.
      final slide = Slide(
        id: 't',
        type: SlideType.image,
        title: 'Onderschrift',
        imagePath: red.path,
        imageSize: 60,
      );

      final key = GlobalKey();
      final cap = await _capture(tester, key, SlidePreviewWidget(slide: slide));

      ({int r, int g, int b}) pixelAt(double fx, double fy) {
        final x = (cap.width * fx).round().clamp(0, cap.width - 1);
        final y = (cap.height * fy).round().clamp(0, cap.height - 1);
        final idx = (y * cap.width + x) * 4;
        return (
          r: cap.bytes[idx],
          g: cap.bytes[idx + 1],
          b: cap.bytes[idx + 2],
        );
      }

      final top = pixelAt(0.5, 0.08);
      final bottom = pixelAt(0.5, 0.92);

      expect(
        top.r > 200 && top.g < 80 && top.b < 80,
        isTrue,
        reason: 'Top of a top-anchored image should be red but was $top',
      );
      expect(
        bottom.r > 200 && bottom.g < 80 && bottom.b < 80,
        isFalse,
        reason: 'Bottom should be free for the title, not the image ($bottom)',
      );

      dir.deleteSync(recursive: true);
    });
  });
}
