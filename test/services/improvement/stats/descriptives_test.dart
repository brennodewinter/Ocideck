// Descriptive statistics: the Welford accumulator, the quartile convention,
// and the properties that hold whatever the data is.
//
// The NIST StRD datasets that check the accumulator against certified values
// live in nist_strd_test.dart; what is checked here is the behaviour that no
// published dataset covers — invariances, the stated hinge method, and the
// refusals.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/improvement/stats/stats.dart';

void main() {
  group('the one-pass summary', () {
    test('mean, variance and range of a hand-checkable sample', () {
      final Descriptives s = Descriptives.of(<double>[2, 4, 4, 4, 5, 5, 7, 9]);
      expect(s.count, 8);
      expect(s.mean, closeTo(5, 1e-15));
      // Σ(x − 5)² = 9 + 1 + 1 + 1 + 0 + 0 + 4 + 16 = 32.
      expect(s.sumOfSquaredDeviations, closeTo(32, 1e-13));
      expect(s.variance, closeTo(32 / 7, 1e-14));
      expect(s.standardDeviation, closeTo(math.sqrt(32 / 7), 1e-14));
      expect(s.standardError, closeTo(math.sqrt(32 / 7) / math.sqrt(8), 1e-14));
      expect(s.minimum, 2);
      expect(s.maximum, 9);
      expect(s.range, 7);
    });

    test('a tight spread on a large offset keeps its digits', () {
      // The case the textbook Σx² − (Σx)²/n shortcut destroys: the sum of
      // squares is ~1e16 and the variance is 1. Welford must still return it.
      final List<double> values = <double>[
        for (int i = 0; i < 9; i++) 100000000 + (i - 4).toDouble(),
      ];
      final Descriptives s = Descriptives.of(values);
      expect(s.mean, 100000000);
      expect(s.variance, closeTo(60 / 8, 1e-9));
    });

    test('the third and fourth moments match their definitions', () {
      final Descriptives s = Descriptives.of(<double>[1, 2, 3, 4, 5]);
      expect(s.skewness, closeTo(0, 1e-14));
      // m2 = 2, m4 = 6.8, so g2 = 6.8/4 − 3 = −1.3.
      expect(s.excessKurtosis, closeTo(-1.3, 1e-13));
    });

    test('skewness has the sign of the long tail', () {
      expect(
        Descriptives.of(<double>[1, 1, 1, 1, 2, 9]).skewness,
        greaterThan(0),
      );
      expect(Descriptives.of(<double>[1, 8, 9, 9, 9, 9]).skewness, lessThan(0));
    });
  });

  group("the quartiles use Tukey's hinges, and say so", () {
    test('1..9 gives Q1 = 3 and Q3 = 7', () {
      final Descriptives s = Descriptives.of(<double>[
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
      ]);
      expect(s.median, 5);
      expect(s.firstQuartile, 3);
      expect(s.thirdQuartile, 7);
      expect(s.interquartileRange, 4);
    });

    test('1..8 splits into two halves of four', () {
      final Descriptives s = Descriptives.of(<double>[1, 2, 3, 4, 5, 6, 7, 8]);
      expect(s.median, 4.5);
      expect(s.firstQuartile, 2.5);
      expect(s.thirdQuartile, 6.5);
    });

    test(
      'the sample is held in ascending order whatever order it arrived in',
      () {
        final Descriptives s = Descriptives.of(<double>[5, 1, 4, 2, 3]);
        expect(s.sorted, <double>[1, 2, 3, 4, 5]);
        expect(s.median, 3);
      },
    );
  });

  group('properties that hold for any sample', () {
    final List<double> sample = <double>[
      3.2,
      1.7,
      4.9,
      2.2,
      8.1,
      5.5,
      6.3,
      2.9,
      7.4,
      4.1,
    ];

    test('shifting the data shifts the centre and leaves the spread', () {
      const double shift = 1000;
      final Descriptives base = Descriptives.of(sample);
      final Descriptives moved = Descriptives.of(<double>[
        for (final double x in sample) x + shift,
      ]);
      expect(moved.mean, closeTo(base.mean + shift, 1e-10));
      expect(moved.median, closeTo(base.median + shift, 1e-10));
      expect(moved.standardDeviation, closeTo(base.standardDeviation, 1e-10));
      expect(moved.skewness, closeTo(base.skewness, 1e-8));
    });

    test(
      'scaling the data scales the centre and the spread by the same factor',
      () {
        const double factor = 7.5;
        final Descriptives base = Descriptives.of(sample);
        final Descriptives scaled = Descriptives.of(<double>[
          for (final double x in sample) x * factor,
        ]);
        expect(scaled.mean, closeTo(base.mean * factor, 1e-12));
        expect(
          scaled.standardDeviation,
          closeTo(base.standardDeviation * factor, 1e-12),
        );
        expect(
          scaled.interquartileRange,
          closeTo(base.interquartileRange * factor, 1e-12),
        );
        // Skewness is dimensionless, so it must not move at all.
        expect(scaled.skewness, closeTo(base.skewness, 1e-12));
        expect(scaled.excessKurtosis, closeTo(base.excessKurtosis, 1e-12));
      },
    );

    test('the order of the observations does not change the summary', () {
      final Descriptives base = Descriptives.of(sample);
      final math.Random random = math.Random(20260728);
      for (int trial = 0; trial < 20; trial++) {
        final List<double> shuffled = List<double>.of(sample)..shuffle(random);
        final Descriptives permuted = Descriptives.of(shuffled);
        expect(permuted.mean, closeTo(base.mean, 1e-12));
        expect(
          permuted.standardDeviation,
          closeTo(base.standardDeviation, 1e-12),
        );
        expect(permuted.median, base.median);
      }
    });

    test('the top-level shorthands agree with the summary they wrap', () {
      final Descriptives s = Descriptives.of(sample);
      expect(mean(sample), s.mean);
      expect(median(sample), s.median);
      expect(standardDeviation(sample), s.standardDeviation);
    });
  });

  group('what it refuses', () {
    test('an empty sample has no summary', () {
      expect(
        () => Descriptives.of(const <double>[]),
        throwsA(isA<StatsRefusal>()),
      );
    });

    test('one observation has no spread, and 0 would read as consistency', () {
      final Descriptives s = Descriptives.of(<double>[42]);
      expect(s.mean, 42);
      expect(() => s.variance, throwsA(isA<StatsRefusal>()));
    });

    test('skewness needs three observations and kurtosis four', () {
      expect(
        () => Descriptives.of(<double>[1, 2]).skewness,
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => Descriptives.of(<double>[1, 2, 3]).excessKurtosis,
        throwsA(isA<StatsRefusal>()),
      );
    });

    test('identical observations have no shape', () {
      final Descriptives s = Descriptives.of(<double>[5, 5, 5, 5]);
      expect(s.variance, 0);
      expect(() => s.skewness, throwsA(isA<StatsRefusal>()));
      expect(() => s.excessKurtosis, throwsA(isA<StatsRefusal>()));
    });

    test('a value that is not a finite number stops the whole summary', () {
      expect(
        () => Descriptives.of(<double>[1, 2, double.nan]),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => Descriptives.of(<double>[1, 2, double.infinity]),
        throwsA(isA<StatsRefusal>()),
      );
    });
  });

  group('moving ranges', () {
    test('span two is the successive absolute difference', () {
      expect(movingRanges(<double>[10, 12, 11, 15]), <double>[2, 1, 4]);
    });

    test('a wider span is the range of the window', () {
      expect(movingRanges(<double>[10, 12, 11, 15], span: 3), <double>[2, 4]);
    });

    test('a span below two, or more span than data, is refused', () {
      expect(
        () => movingRanges(<double>[1, 2, 3], span: 1),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => movingRanges(<double>[1, 2], span: 3),
        throwsA(isA<StatsRefusal>()),
      );
    });
  });
}
