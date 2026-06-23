import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/slide_layout_metrics.dart';

void main() {
  group('bulletLevelScale', () {
    test('top level is full size, deeper levels shrink monotonically', () {
      expect(bulletLevelScale(0), 1.0);
      expect(bulletLevelScale(-1), 1.0);
      expect(bulletLevelScale(1), lessThan(bulletLevelScale(0)));
      expect(bulletLevelScale(2), lessThan(bulletLevelScale(1)));
      expect(bulletLevelScale(5), lessThanOrEqualTo(bulletLevelScale(2)));
    });
  });

  group('bulletScaleCap', () {
    test('is bounded by the layout growth cap', () {
      // A tiny layout cap wins over the font-fraction cap.
      expect(bulletScaleCap(1000, 30, 0.5), 0.5);
    });

    test('falls back to the font-fraction cap when layout allows more', () {
      final cap = bulletScaleCap(1000, 30, kBulletsMaxScale);
      expect(cap, closeTo(kBulletMaxFontFraction * 1000 / 30, 1e-9));
      expect(cap, lessThan(kBulletsMaxScale));
    });
  });

  group('bulletListMarker', () {
    test('bullet markers vary by indentation level', () {
      final items = ['top', '\tchild', '\t\tgrandchild'];
      expect(bulletListMarker(items, 0, ListStyle.bullets), '•');
      expect(bulletListMarker(items, 1, ListStyle.bullets), '◦');
      expect(bulletListMarker(items, 2, ListStyle.bullets), '▪');
    });

    test('numbered markers count within a level and reset on outdent', () {
      final items = ['een', 'twee', '\tsub', 'drie'];
      expect(bulletListMarker(items, 0, ListStyle.numbered), '1.');
      expect(bulletListMarker(items, 1, ListStyle.numbered), '2.');
      expect(bulletListMarker(items, 2, ListStyle.numbered), '1.');
      expect(bulletListMarker(items, 3, ListStyle.numbered), '3.');
    });
  });

  group('tightenVerticalFitScale', () {
    test('shrinks an oversized block until it fits', () {
      // Linear height model: height == scale * 1000.
      final scale = tightenVerticalFitScale(
        scale: 1.0,
        availH: 500,
        measure: (s) => s * 1000,
      );
      expect(scale, lessThan(1.0));
      expect(scale * 1000, lessThanOrEqualTo(500));
    });

    test('leaves a block that already fits unchanged', () {
      final scale = tightenVerticalFitScale(
        scale: 1.0,
        availH: 5000,
        measure: (s) => s * 1000,
      );
      expect(scale, 1.0);
    });
  });

  group('growVerticalFitScale', () {
    test('grows a small block toward the available height', () {
      final scale = growVerticalFitScale(
        scale: 1.0,
        availH: 2000,
        maxScale: 3.0,
        measure: (s) => s * 1000,
      );
      expect(scale, greaterThan(1.0));
      expect(scale, lessThanOrEqualTo(3.0));
    });

    test('never exceeds the maximum scale', () {
      final scale = growVerticalFitScale(
        scale: 1.0,
        availH: 100000,
        maxScale: 2.5,
        measure: (s) => s * 1000,
      );
      expect(scale, lessThanOrEqualTo(2.5));
    });
  });
}
