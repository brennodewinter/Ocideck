import 'dart:convert';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

import 'support/pump_until.dart';

void main() {
  for (final overlay in [true, false]) {
    test('quote veil $overlay survives saving and controls Marp opacity', () {
      final slide = Slide.create(SlideType.quote).copyWith(
        quote: 'Kennis is macht',
        imagePath: 'images/bg.png',
        titleImageOverlay: overlay,
      );
      final service = MarkdownService();
      final markdown = service.generateDeck(
        Deck(title: 'Test', slides: [slide]),
      );
      expect(markdown.contains('opacity:.45'), overlay);
      expect(markdown.contains('ocideck_title_image_overlay: false'), !overlay);
      final result = service.parseDeck(markdown)!.slides.single;
      expect(result.titleImageOverlay, overlay);
      expect(result.quote, slide.quote);
      expect(result.imagePath, slide.imagePath);
    });

    testWidgets('quote veil $overlay changes the rendered image', (
      tester,
    ) async {
      final path = WebAssetStore.put(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEUlEQVR4nGP4wLAAjhiI4wAAj1IZAeWg4cwAAAAASUVORK5CYII=',
        ),
        name: 'quote.png',
      );
      addTearDown(() => WebAssetStore.retain(const {}));
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 640,
                  height: 360,
                  child: SlidePreviewWidget(
                    slide: Slide.create(SlideType.quote).copyWith(
                      quote: 'Kennis is macht',
                      imagePath: path,
                      titleImageOverlay: overlay,
                      imageSize: 0,
                      showLogo: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await pumpUntil(
        tester,
        () => tester
            .widgetList<RawImage>(find.byType(RawImage))
            .any((image) => image.image != null),
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => boundary.toImage());
      final data = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      image!.dispose();
      final bytes = data!.buffer.asUint8List();
      final offset = (2 * 640 + 2) * 4;
      expect(bytes[offset], overlay ? lessThan(130) : 240);
      expect(bytes[offset + 1], 0);
      expect(bytes[offset + 2], overlay ? lessThan(90) : 160);
      expect(tester.takeException(), isNull);
    });
  }
}
