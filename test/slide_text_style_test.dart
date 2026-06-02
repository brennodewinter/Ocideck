import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

void main() {
  // Regression: when the slide is rendered outside a Material (as the export
  // rasterizer does, mounting it in a bare Overlay), text used to fall back to
  // Flutter's broken default style — red letters with a yellow underline.
  // SlidePreviewWidget now supplies its own DefaultTextStyle so this can never
  // happen again.
  testWidgets('bullets render without yellow underline outside a Material', (
    tester,
  ) async {
    const profile = ThemeProfile(
      slideBackgroundColor: '#FFFFFF',
      textColor: '#1C2B47', // navy
      accentColor: '#1C2B47',
    );

    final slide = Slide(
      id: 'b',
      type: SlideType.bullets,
      title: 'Titel',
      bullets: const ['Eerste bullet', 'Tweede bullet', 'Derde bullet'],
    );

    await tester.runAsync(() async {
      final key = GlobalKey();
      // Deliberately NO MaterialApp / DefaultTextStyle here — only the minimal
      // View that pumpWidget provides — to mimic the export overlay subtree.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 800,
                height: 450,
                child: SlidePreviewWidget(slide: slide, themeProfile: profile),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();

      var yellowCount = 0;
      var navyCount = 0;
      for (var i = 0; i + 3 < bytes.length; i += 4) {
        final r = bytes[i];
        final g = bytes[i + 1];
        final b = bytes[i + 2];
        // Yellow = high red + high green + low blue (broken-default underline).
        if (r > 180 && g > 180 && b < 100) yellowCount++;
        // Navy-ish dark blue text.
        if (r < 80 && g < 90 && b > 50 && b < 160) navyCount++;
      }

      expect(
        yellowCount,
        lessThan(20),
        reason: 'Found $yellowCount yellow pixels — broken default text style?',
      );
      expect(
        navyCount,
        greaterThan(50),
        reason: 'Expected navy text pixels; found $navyCount',
      );
    });
  });
}
