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

  group('memoizedRenderLayout', () {
    // Guards the slide-preview fit-scale cache: a hit must skip recompute, and
    // every keyed input must invalidate it. If a future change makes the real
    // fit depend on an input not in the key, this is the test that should fail
    // — the golden tests only ever exercise the cold (first-compute) path.
    test('a hit returns the cached value without recomputing', () {
      final slide = Slide.create(SlideType.bullets);
      var calls = 0;
      double run() => memoizedRenderLayout<double>(
        slide: slide,
        font: 'Roboto',
        width: 100,
        availW: 80,
        availH: 60,
        compute: () {
          calls++;
          return 1.5;
        },
      );
      expect(run(), 1.5);
      expect(run(), 1.5);
      expect(calls, 1, reason: 'second call must hit the cache');
    });

    test('each keyed input invalidates the cache', () {
      final slide = Slide.create(SlideType.bullets);
      final other = Slide.create(SlideType.bullets);
      var calls = 0;
      double run({
        Slide? s,
        String font = 'Roboto',
        double width = 100,
        double availW = 80,
        double availH = 60,
      }) => memoizedRenderLayout<double>(
        slide: s ?? slide,
        font: font,
        width: width,
        availW: availW,
        availH: availH,
        compute: () {
          calls++;
          return calls.toDouble();
        },
      );
      run(); // 1: warm
      run(s: other); // 2: different slide identity
      run(font: 'Inter'); // 3: different font
      run(width: 101); // 4: different width
      run(availW: 81); // 5: different available width
      run(availH: 61); // 6: different available height
      expect(calls, 6, reason: 'every distinct key must miss and recompute');
    });
  });
}
