// Known-answer tests for the control-chart factor table
// (lib/services/improvement/stats/constants.dart).
//
// The table below is the classical factor table as it is printed in the
// standard references (Montgomery, *Introduction to Statistical Quality
// Control*, Appendix VI; ASTM E2587). It is transcribed here from the printed
// page on purpose: this file is the oracle, and an oracle that is derived from
// the code it checks proves nothing.
//
// Only d2 and d3 are stored by the engine; every other factor is computed from
// them and from c4. That is exactly what these tests exercise — the published
// A2, A3, B3, B4, D1..D4 must fall out of the arithmetic, to the last digit the
// tables carry.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/improvement/stats/stats.dart';

/// The published table to three decimals, by subgroup size.
const Map<int, Map<String, double>> _published = <int, Map<String, double>>{
  2: <String, double>{
    'd2': 1.128,
    'd3': 0.853,
    'A2': 1.880,
    'A3': 2.659,
    'B3': 0,
    'B4': 3.267,
    'D3': 0,
    'D4': 3.267,
  },
  3: <String, double>{
    'd2': 1.693,
    'd3': 0.888,
    'A2': 1.023,
    'A3': 1.954,
    'B3': 0,
    'B4': 2.568,
    'D3': 0,
    'D4': 2.574,
  },
  4: <String, double>{
    'd2': 2.059,
    'd3': 0.880,
    'A2': 0.729,
    'A3': 1.628,
    'B3': 0,
    'B4': 2.266,
    'D3': 0,
    'D4': 2.282,
  },
  5: <String, double>{
    'd2': 2.326,
    'd3': 0.864,
    'A2': 0.577,
    'A3': 1.427,
    'B3': 0,
    'B4': 2.089,
    'D3': 0,
    'D4': 2.114,
  },
  6: <String, double>{
    'd2': 2.534,
    'd3': 0.848,
    'A2': 0.483,
    'A3': 1.287,
    'B3': 0.030,
    'B4': 1.970,
    'D3': 0,
    'D4': 2.004,
  },
  7: <String, double>{
    'd2': 2.704,
    'd3': 0.833,
    'A2': 0.419,
    'A3': 1.182,
    'B3': 0.118,
    'B4': 1.882,
    'D3': 0.076,
    'D4': 1.924,
  },
  8: <String, double>{
    'd2': 2.847,
    'd3': 0.820,
    'A2': 0.373,
    'A3': 1.099,
    'B3': 0.185,
    'B4': 1.815,
    'D3': 0.136,
    'D4': 1.864,
  },
  9: <String, double>{
    'd2': 2.970,
    'd3': 0.808,
    'A2': 0.337,
    'A3': 1.032,
    'B3': 0.239,
    'B4': 1.761,
    'D3': 0.184,
    'D4': 1.816,
  },
  10: <String, double>{
    'd2': 3.078,
    'd3': 0.797,
    'A2': 0.308,
    'A3': 0.975,
    'B3': 0.284,
    'B4': 1.716,
    'D3': 0.223,
    'D4': 1.777,
  },
};

/// c4 to four decimals, as printed.
const Map<int, double> _publishedC4 = <int, double>{
  2: 0.7979,
  3: 0.8862,
  4: 0.9213,
  5: 0.9400,
  6: 0.9515,
  7: 0.9594,
  8: 0.9650,
  9: 0.9693,
  10: 0.9727,
  25: 0.9896,
};

void main() {
  group('the published factor table is reproduced', () {
    _published.forEach((int n, Map<String, double> expected) {
      test('subgroup size $n', () {
        final Map<String, double> actual =
            ControlChartConstants.forSubgroupSize(n).bySymbol;
        expected.forEach((String symbol, double value) {
          // A thousandth: the tables themselves are printed to three decimals,
          // so agreement past that would be agreement with a rounding.
          expect(
            actual[symbol],
            closeTo(value, 0.001),
            reason: '$symbol at n = $n',
          );
        });
      });
    });

    test('c4 is computed from the gamma function, not tabulated', () {
      _publishedC4.forEach((int n, double value) {
        expect(c4For(n), closeTo(value, 0.0001), reason: 'c4 at n = $n');
      });
    });

    test('the sigma-known factors D1, D2, B5 and B6 follow too', () {
      final Map<String, double> two = ControlChartConstants.forSubgroupSize(
        2,
      ).bySymbol;
      expect(two['D1'], closeTo(0, 0.001));
      expect(two['D2'], closeTo(3.686, 0.001));
      final Map<String, double> five = ControlChartConstants.forSubgroupSize(
        5,
      ).bySymbol;
      expect(five['D1'], closeTo(0, 0.001));
      expect(five['D2'], closeTo(4.918, 0.001));
      expect(five['B5'], closeTo(0, 0.001));
      expect(five['B6'], closeTo(1.964, 0.001));
      final Map<String, double> six = ControlChartConstants.forSubgroupSize(
        6,
      ).bySymbol;
      expect(six['B5'], closeTo(0.029, 0.001));
      expect(six['B6'], closeTo(1.874, 0.001));
    });
  });

  group('the table refuses what it does not cover', () {
    test('below the smallest published subgroup', () {
      expect(
        () => ControlChartConstants.forSubgroupSize(1),
        throwsA(isA<StatsRefusal>()),
      );
    });

    test('beyond the largest published subgroup', () {
      expect(
        () => ControlChartConstants.forSubgroupSize(26),
        throwsA(
          isA<StatsRefusal>().having(
            (StatsRefusal e) => e.reason,
            'reason',
            contains('extrapolating'),
          ),
        ),
      );
    });

    test('the covered range is 2..25 and is what the module card counts', () {
      expect(minimumSubgroupSize, 2);
      expect(maximumSubgroupSize, 25);
      expect(improvementStatsFactorRows, 24);
    });
  });

  group('the derived factors keep their own relations', () {
    test('the lower range limit is clamped away below n = 7', () {
      for (int n = 2; n <= 6; n++) {
        expect(
          ControlChartConstants.forSubgroupSize(n).rangeLowerFactor,
          0,
          reason: 'D3 at n = $n',
        );
      }
      expect(
        ControlChartConstants.forSubgroupSize(7).rangeLowerFactor,
        greaterThan(0),
      );
    });

    test('c4 rises toward one as the subgroup grows', () {
      double previous = 0;
      for (int n = 2; n <= 25; n++) {
        final double c4 = c4For(n);
        expect(c4, greaterThan(previous));
        expect(c4, lessThan(1));
        previous = c4;
      }
    });

    test('D3 and D4 straddle one, and D1/D2 straddle d2', () {
      for (int n = 2; n <= 25; n++) {
        final ControlChartConstants k = ControlChartConstants.forSubgroupSize(
          n,
        );
        expect(k.rangeLowerFactor, lessThan(1));
        expect(k.rangeUpperFactor, greaterThan(1));
        expect(k.rangeUpperKnownSigma, greaterThan(k.d2));
        expect(k.rangeLowerKnownSigma, lessThan(k.d2));
      }
    });
  });
}
