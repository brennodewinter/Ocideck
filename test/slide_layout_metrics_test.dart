import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/bullet_pagination.dart';
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

    test('startNumber offsets only the top level, not nested items', () {
      final items = ['een', '\tsub', 'twee'];
      expect(
        bulletListMarker(items, 0, ListStyle.numbered, startNumber: 7),
        '7.',
      );
      // Nested items keep their own 1-based count regardless of the offset.
      expect(
        bulletListMarker(items, 1, ListStyle.numbered, startNumber: 7),
        '1.',
      );
      expect(
        bulletListMarker(items, 2, ListStyle.numbered, startNumber: 7),
        '8.',
      );
    });
  });

  group('numberedListStartFor', () {
    Slide numbered(List<String> bullets, {bool continueNumbering = false}) =>
        Slide.create(SlideType.bullets).copyWith(
          listStyle: ListStyle.numbered,
          continueNumbering: continueNumbering,
          bullets: bullets,
        );

    test('first slide and non-continuing slides start at 1', () {
      final slides = [
        numbered(['a', 'b']),
        numbered(['c']),
      ];
      expect(numberedListStartFor(slides, 0), 1);
      expect(numberedListStartFor(slides, 1), 1); // continueNumbering is false
    });

    test('a continuing slide resumes past the previous slide count', () {
      final slides = [
        numbered(['a', 'b', 'c']),
        numbered(['d', 'e'], continueNumbering: true),
      ];
      expect(numberedListStartFor(slides, 1), 4);
    });

    test('the offset accumulates along a chain of continuing slides', () {
      final slides = [
        numbered(['a', 'b']),
        numbered(['c', 'd', 'e'], continueNumbering: true),
        numbered(['f'], continueNumbering: true),
      ];
      expect(numberedListStartFor(slides, 2), 6); // 1 + 2 + 3
    });

    test('does not continue when the previous slide is not numbered', () {
      final slides = [
        Slide.create(SlideType.bullets).copyWith(bullets: ['a', 'b']),
        numbered(['c'], continueNumbering: true),
      ];
      expect(numberedListStartFor(slides, 1), 1);
    });
  });

  group('tableColumnFlexWeights', () {
    test(
      'weighs each column by its longest trimmed cell, clamped to [1,80]',
      () {
        final weights = tableColumnFlexWeights([
          ['Rol', 'Taken'],
          ['CISO', 'x' * 200],
          ['', ''],
        ], 2);
        expect(weights, hasLength(2));
        expect(weights[0], 4); // 'CISO'
        expect(weights[1], 80); // clamped from 200
      },
    );
  });

  group('tableFitCellSize', () {
    const w = kReferenceSlideWidth;
    final base = tableCellFontSize(w, rowCount: 6, colCount: 4);
    final min = tableCellFontMinimum(w);

    test('a sparse table keeps the density-based base size', () {
      final size = tableFitCellSize(
        rows: [
          ['A', 'B'],
          ['1', '2'],
        ],
        colCount: 2,
        tableWidth: w * 0.88,
        availH: w * 9 / 16,
        baseCellSize: base,
        minCellSize: min,
        font: 'Roboto',
      );
      expect(size, base);
    });

    test('a text-heavy table shrinks below base to fit the height', () {
      final paragraph = List.filled(6, 'lorem ipsum dolor sit amet').join(' ');
      final rows = [
        ['Rol', 'Taken', 'Verantwoordelijkheden', 'Bevoegdheden'],
        for (var i = 0; i < 5; i++)
          [paragraph, paragraph, paragraph, paragraph],
      ];
      final baseHeight = tableBlockHeight(
        rows: rows,
        colCount: 4,
        tableWidth: w * 0.88,
        cellSize: base,
        font: 'Roboto',
      );
      // A budget tighter than the base layout but reachable by shrinking.
      final availH = baseHeight * 0.7;
      final size = tableFitCellSize(
        rows: rows,
        colCount: 4,
        tableWidth: w * 0.88,
        availH: availH,
        baseCellSize: base,
        minCellSize: min,
        font: 'Roboto',
      );
      expect(size, lessThan(base));
      expect(size, greaterThanOrEqualTo(min));
      // The shrunk table actually fits the budget.
      final h = tableBlockHeight(
        rows: rows,
        colCount: 4,
        tableWidth: w * 0.88,
        cellSize: size,
        font: 'Roboto',
      );
      expect(h, lessThanOrEqualTo(availH));
    });

    test('never returns below the minimum even with an impossible budget', () {
      final paragraph = 'x' * 400;
      final size = tableFitCellSize(
        rows: [
          ['h', 'h'],
          [paragraph, paragraph],
        ],
        colCount: 2,
        tableWidth: w * 0.88,
        availH: 1,
        baseCellSize: base,
        minCellSize: min,
        font: 'Roboto',
      );
      expect(size, greaterThanOrEqualTo(min));
      expect(size, lessThanOrEqualTo(base));
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

  group('bulletPageCap', () {
    test('is the smaller of fit and limit, never below one', () {
      expect(bulletPageCap(3, 8), 3);
      expect(bulletPageCap(20, 8), 8);
      expect(bulletPageCap(0, 8), 1);
      expect(bulletPageCap(5, 0), 1);
    });
  });

  group('pageCountToFit', () {
    test('is ceil(len/cap) without headings, minimum two', () {
      expect(pageCountToFit(List.filled(10, 'x'), 8), 2); // 5/5
      expect(pageCountToFit(List.filled(16, 'x'), 8), 2);
      expect(pageCountToFit(List.filled(17, 'x'), 8), 3);
      expect(pageCountToFit(List.filled(30, 'x'), 8), 4);
      expect(pageCountToFit(List.filled(6, 'x'), 8), 2); // fits, still splits
      expect(pageCountToFit(List.filled(10, 'x'), 2), 5); // long bullets
    });

    test('keeps whole groups together, one page per group that fits', () {
      final items = <String>[
        for (final g in ['A', 'B', 'C']) ...[
          groupHeadingBullet(g),
          for (var i = 0; i < 4; i++) 'bullet',
        ],
      ]; // three groups of five, 15 items
      expect(pageCountToFit(items, 8), 3); // 5/5/5, not 8/7 across a group
    });

    test('cuts a single group larger than a page across pages', () {
      final items = <String>[
        groupHeadingBullet('Big'),
        for (var i = 0; i < 20; i++) 'b',
      ];
      expect(
        pageCountToFit(items, 8),
        3,
      ); // 21 items in one group -> ceil(21/8)
    });
  });

  group('paginateBulletsToFit', () {
    List<String> gen(int n) => [for (var i = 0; i < n; i++) 'bullet $i'];

    test('splits a full list into balanced pages that each fit', () {
      final pages = paginateBulletsToFit(gen(30), 8);
      expect(pages.map((p) => p.length).toList(), [8, 8, 7, 7]);
      expect(
        pages.expand((p) => p).toList(),
        gen(30),
      ); // nothing lost/reordered
      expect(pages.every((p) => p.length <= 8 && p.isNotEmpty), isTrue);
    });

    test('never peels off a lopsided tail when few bullets fit', () {
      // The reported bug: cap 2 used to give 2/8; now every page holds two.
      expect(paginateBulletsToFit(gen(10), 2).map((p) => p.length).toList(), [
        2,
        2,
        2,
        2,
        2,
      ]);
    });

    test('divides a fitting list evenly in two on request', () {
      expect(paginateBulletsToFit(gen(6), 8).map((p) => p.length).toList(), [
        3,
        3,
      ]);
    });

    test('breaks on group boundaries so a heading leads every page', () {
      final items = <String>[
        for (final g in ['Ochtend', 'Middag', 'Avond']) ...[
          groupHeadingBullet(g),
          for (var i = 0; i < 4; i++) 'bullet',
        ],
      ];
      final pages = paginateBulletsToFit(items, 8);
      expect(pages, hasLength(3));
      for (final page in pages) {
        expect(
          isGroupHeading(page.first),
          isTrue,
          reason: 'page leads with a heading',
        );
        expect(
          isGroupHeading(page.last),
          isFalse,
          reason: 'no heading stranded at the foot',
        );
      }
      expect(pages.expand((p) => p).toList(), items);
    });
  });

  group('spreadBulletsOverPages', () {
    test('pads with empty trailing pages when items run short', () {
      final pages = spreadBulletsOverPages(['a', 'b', 'c'], 5, 7);
      expect(pages, hasLength(5));
      expect(pages.expand((p) => p).toList(), ['a', 'b', 'c']);
      expect(pages.where((p) => p.isEmpty), hasLength(2));
    });
  });
}
