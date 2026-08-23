import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

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
  testWidgets('bulletsImage paints the image on the right panel', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('ocideck_test');
      final redPng = await _writeRedPng(dir.path);

      final slide = Slide(
        id: 'x',
        type: SlideType.bulletsImage,
        title: 'Een titel',
        bullets: const [
          'Eerste bullet met wat tekst',
          'Tweede bullet',
          'Derde bullet met veel tekst zodat de hoogte flink wordt gevuld',
          'Vierde bullet',
          'Vijfde bullet',
        ],
        imagePath: redPng.path,
        imageSize: 40,
      );

      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 800,
                  height: 450,
                  child: SlidePreviewWidget(slide: slide),
                ),
              ),
            ),
          ),
        ),
      );

      // Let the file image decode and paint.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();

      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();

      ({int r, int g, int b}) pixelAt(int x, int y) {
        final i = (y * image.width + x) * 4;
        return (r: bytes[i], g: bytes[i + 1], b: bytes[i + 2]);
      }

      // Right 40% panel must be the (red) image; left panel the white text bg.
      final right = pixelAt((image.width * 0.95).round(), image.height ~/ 2);
      final left = pixelAt((image.width * 0.05).round(), image.height ~/ 2);

      expect(
        right.r > 200 && right.g < 80 && right.b < 80,
        isTrue,
        reason: 'Image panel should be red but was $right',
      );
      expect(
        left.r,
        greaterThan(200),
        reason: 'Text panel background should be white',
      );

      dir.deleteSync(recursive: true);
    });
  });
}
