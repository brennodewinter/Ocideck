import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/utils/image_limits.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Future<Uint8List> _redPngBytes() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 8, 8),
    Paint()..color = const Color(0xFFFF0000),
  );
  final img = await recorder.endRecording().toImage(8, 8);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  tearDown(WebAssetStore.clear);

  test('bewaart bytes onder een mem:-pad en vindt ze terug', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final path = WebAssetStore.put(bytes, name: 'foto.png');

    expect(WebAssetStore.isMemPath(path), isTrue);
    expect(WebAssetStore.bytesFor(path), same(bytes));
    expect(WebAssetStore.nameFor(path), 'foto.png');
    // Twee puts delen nooit een pad.
    expect(WebAssetStore.put(bytes, name: 'foto.png'), isNot(path));
  });

  test('onbekende of niet-mem-paden leveren niets op', () {
    expect(WebAssetStore.isMemPath('images/foto.png'), isFalse);
    expect(WebAssetStore.bytesFor('mem:bestaat-niet'), isNull);
    expect(WebAssetStore.bytesFor('images/foto.png'), isNull);
  });

  testWidgets('een slide met mem:-pad rendert uit de store', (tester) async {
    await tester.runAsync(() async {
      final bytes = await _redPngBytes();
      final memPath = WebAssetStore.put(bytes, name: 'rood.png');

      final slide = Slide(
        id: 'x',
        type: SlideType.image,
        title: 'In-memory afbeelding',
        imagePath: memPath,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: SlidePreviewWidget(slide: slide),
            ),
          ),
        ),
      );
      await tester.pump();

      // De preview moet een echte Image tekenen (geen placeholder-icoon)
      // waarvan de capped provider onze bytes als cache-sleutel draagt.
      final images = tester
          .widgetList<Image>(find.byType(Image))
          .where(
            (w) =>
                w.image is CappedImage &&
                identical((w.image as CappedImage).cacheKey, bytes),
          );
      expect(images, isNotEmpty, reason: 'mem:-afbeelding moet renderen');
      expect(find.byIcon(Icons.image_outlined), findsNothing);
    });
  });
}
