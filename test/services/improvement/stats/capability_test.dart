// Capability, sigma level, and the round trip between DPMO, yield and sigma.
//
// The sample used throughout is built so its own summary is exact: sixteen
// values symmetric about 100, with Σ(x − 100)² = 120 and therefore a sample
// standard deviation of exactly √8. Every index below can be checked with a
// pencil against that.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/improvement/stats/stats.dart';

/// Sixteen values: 100 ± 1, ± 2, ± 3 and ± 4, each pair twice.
final List<double> _symmetric = <double>[
  for (final double k in <double>[1, 2, 3, 4]) ...<double>[
    100 - k,
    100 + k,
    100 - k,
    100 + k,
  ],
];

void main() {
  group('the indices, against a sample whose summary is exact', () {
    test('Cp and Cpk use the within-subgroup spread that was handed in', () {
      final CapabilityAnalysis a = CapabilityAnalysis.of(
        _symmetric,
        lowerSpec: 88,
        upperSpec: 112,
        withinSigma: 2,
      );
      expect(a.count, 16);
      expect(a.mean, closeTo(100, 1e-13));
      expect(a.withinSigma, 2);
      expect(a.cp, closeTo(2, 1e-13));
      expect(a.cpk, closeTo(2, 1e-13));
      expect(a.cpu, closeTo(2, 1e-13));
      expect(a.cpl, closeTo(2, 1e-13));
    });

    test('Pp and Ppk use the overall spread, and say a different thing', () {
      final CapabilityAnalysis a = CapabilityAnalysis.of(
        _symmetric,
        lowerSpec: 88,
        upperSpec: 112,
        withinSigma: 2,
      );
      expect(a.overallSigma, closeTo(math.sqrt(8), 1e-13));
      // 24 / (6·√8) = √2.
      expect(a.pp, closeTo(math.sqrt2, 1e-12));
      expect(a.ppk, closeTo(math.sqrt2, 1e-12));
      expect(a.pp, lessThan(a.cp!));
    });

    test('an off-centre process loses on Cpk but not on Cp', () {
      final CapabilityAnalysis a = CapabilityAnalysis.of(
        <double>[for (final double x in _symmetric) x + 4],
        lowerSpec: 88,
        upperSpec: 112,
        withinSigma: 2,
      );
      expect(a.cp, closeTo(2, 1e-13));
      // Mean 104: (112 − 104)/6 = 4/3 against (104 − 88)/6 = 8/3.
      expect(a.cpk, closeTo(4 / 3, 1e-13));
      expect(a.cpu, closeTo(4 / 3, 1e-13));
      expect(a.cpl, closeTo(8 / 3, 1e-13));
    });

    test('Cpm penalises distance from the target, Cpk does not', () {
      final CapabilityAnalysis onTarget = CapabilityAnalysis.of(
        _symmetric,
        lowerSpec: 88,
        upperSpec: 112,
        target: 100,
        withinSigma: 2,
      );
      final CapabilityAnalysis offTarget = CapabilityAnalysis.of(
        _symmetric,
        lowerSpec: 88,
        upperSpec: 112,
        target: 98,
        withinSigma: 2,
      );
      expect(onTarget.cpm, closeTo(math.sqrt2, 1e-12));
      // 24 / (6·√(8 + 4)) = 2/√3.
      expect(offTarget.cpm, closeTo(2 / math.sqrt(3), 1e-12));
      expect(offTarget.cpk, onTarget.cpk);
    });

    test('a one-sided specification gives a one-sided index and no Cp', () {
      final CapabilityAnalysis a = CapabilityAnalysis.of(
        _symmetric,
        upperSpec: 112,
        withinSigma: 2,
      );
      expect(a.cp, isNull);
      expect(a.pp, isNull);
      expect(a.cpm, isNull);
      expect(a.cpl, isNull);
      expect(a.cpu, closeTo(2, 1e-13));
      expect(a.cpk, closeTo(2, 1e-13));
    });

    test('Cpk grows with the specification width and nothing else', () {
      double previous = 0;
      for (final double width in <double>[6, 9, 12, 18, 24]) {
        final CapabilityAnalysis a = CapabilityAnalysis.of(
          _symmetric,
          lowerSpec: 100 - width,
          upperSpec: 100 + width,
          withinSigma: 2,
        );
        expect(a.cpk, greaterThan(previous));
        previous = a.cpk;
      }
    });

    test('without a within-sigma it is estimated from the moving ranges', () {
      final List<double> series = <double>[
        10,
        11,
        10,
        12,
        11,
        13,
        12,
        11,
        10,
        12,
      ];
      final CapabilityAnalysis a = CapabilityAnalysis.of(
        series,
        lowerSpec: 5,
        upperSpec: 15,
      );
      final double byHand =
          Descriptives.of(movingRanges(series)).mean /
          ControlChartConstants.forSubgroupSize(2).d2;
      expect(a.withinSigma, closeTo(byHand, 1e-13));
    });
  });

  group('the normality verdict travels with every index', () {
    test('it is there whether the caller asked for it or not', () {
      final CapabilityAnalysis a = CapabilityAnalysis.of(
        _symmetric,
        lowerSpec: 88,
        upperSpec: 112,
        withinSigma: 2,
      );
      expect(a.normality.count, 16);
      expect(a.normality.pValue, inInclusiveRange(0, 1));
      expect(a.normality.statistic, greaterThan(0));
      expect(a.normality.adjustedStatistic, greaterThan(a.normality.statistic));
    });

    test('visibly non-normal data is flagged, not quietly indexed', () {
      final List<double> skewed = <double>[
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        2,
        2,
        2,
        2,
        3,
        3,
        4,
        20,
        25,
        40,
        60,
        90,
        140,
      ];
      final CapabilityAnalysis a = CapabilityAnalysis.of(
        skewed,
        lowerSpec: 0,
        upperSpec: 200,
      );
      expect(a.normalityRejected, isTrue);
      expect(a.normality.pValue, lessThan(0.05));
    });

    test('a symmetric sample of a normal process is not flagged', () {
      // A normal quantile sample: by construction as normal as data gets.
      final List<double> normalish = <double>[
        for (int i = 1; i <= 30; i++)
          100 + 5 * standardNormalQuantile((i - 0.5) / 30),
      ];
      final CapabilityAnalysis a = CapabilityAnalysis.of(
        normalish,
        lowerSpec: 80,
        upperSpec: 120,
      );
      expect(a.normalityRejected, isFalse);
    });

    test('a small sample is marked as one', () {
      expect(
        CapabilityAnalysis.of(
          _symmetric,
          lowerSpec: 88,
          upperSpec: 112,
          withinSigma: 2,
        ).isSmallSample,
        isTrue,
      );
      expect(
        CapabilityAnalysis.of(
          <double>[..._symmetric, ..._symmetric],
          lowerSpec: 88,
          upperSpec: 112,
          withinSigma: 2,
        ).isSmallSample,
        isFalse,
      );
    });
  });

  group('the expected and the observed are both reported', () {
    test('the expected fraction comes from the fitted normal', () {
      final CapabilityAnalysis a = CapabilityAnalysis.of(
        _symmetric,
        lowerSpec: 88,
        upperSpec: 112,
        withinSigma: 2,
      );
      final double z = 12 / math.sqrt(8);
      expect(
        a.expectedFractionOutOfSpec,
        closeTo(2 * (1 - standardNormalCdf(z)), 1e-12),
      );
      expect(a.dpmo, closeTo(a.expectedFractionOutOfSpec * 1e6, 1e-6));
      expect(a.expectedYield, closeTo(1 - a.expectedFractionOutOfSpec, 1e-15));
    });

    test('the observed DPMO is counted, not modelled', () {
      final CapabilityAnalysis a = CapabilityAnalysis.of(
        _symmetric,
        lowerSpec: 97.5,
        upperSpec: 112,
        withinSigma: 2,
      );
      // Four of sixteen values sit below 97.5 (the two 96s and the two 97s).
      expect(a.observedOutOfSpec, 4);
      expect(a.observedDpmo, closeTo(250000, 1e-9));
    });
  });

  group('the 1.5σ shift is off by default and always named', () {
    test('the default convention adds nothing and says so', () {
      final SigmaLevel level = sigmaLevelFromYield(0.99);
      expect(level.convention, SigmaShiftConvention.none);
      expect(level.convention.offset, 0);
      expect(level.value, closeTo(standardNormalQuantile(0.99), 1e-12));
      expect(level.toString(), contains('no 1.5σ shift'));
    });

    test('3.4 DPMO is 4.5σ unshifted and 6.0σ shifted', () {
      expect(sigmaLevelFromDpmo(3.4).value, closeTo(4.5001, 0.001));
      expect(
        sigmaLevelFromDpmo(3.4, convention: SigmaShiftConvention.shifted).value,
        closeTo(6.0001, 0.001),
      );
    });

    test('the shift is exactly 1.5 apart, whatever the yield', () {
      for (final double y in <double>[0.5, 0.9, 0.99, 0.999999]) {
        final SigmaLevel plain = sigmaLevelFromYield(y);
        final SigmaLevel shifted = sigmaLevelFromYield(
          y,
          convention: SigmaShiftConvention.shifted,
        );
        expect(shifted.value - plain.value, closeTo(1.5, 1e-12));
        expect(shifted.toString(), contains('1.5σ shift'));
      }
    });

    test('a capability analysis carries the convention it was asked for', () {
      final CapabilityAnalysis shifted = CapabilityAnalysis.of(
        _symmetric,
        lowerSpec: 88,
        upperSpec: 112,
        withinSigma: 2,
        shiftConvention: SigmaShiftConvention.shifted,
      );
      final CapabilityAnalysis plain = CapabilityAnalysis.of(
        _symmetric,
        lowerSpec: 88,
        upperSpec: 112,
        withinSigma: 2,
      );
      expect(
        shifted.sigmaLevel.value - plain.sigmaLevel.value,
        closeTo(1.5, 1e-12),
      );
      expect(shifted.sigmaLevel.convention, SigmaShiftConvention.shifted);
    });
  });

  group('DPMO, yield and sigma round-trip', () {
    test('yield → DPMO → yield', () {
      for (final double y in <double>[0.001, 0.5, 0.9, 0.99, 0.999997]) {
        expect(yieldFromDpmo(dpmoFromYield(y)), closeTo(y, 1e-12));
      }
    });

    test('DPMO → sigma → DPMO, in both conventions', () {
      for (final SigmaShiftConvention convention
          in SigmaShiftConvention.values) {
        for (final double dpmo in <double>[3.4, 233, 6210, 66807, 308537]) {
          final SigmaLevel level = sigmaLevelFromDpmo(
            dpmo,
            convention: convention,
          );
          expect(
            dpmoFromSigmaLevel(level),
            closeTo(dpmo, dpmo * 1e-9),
            reason: '$dpmo at ${convention.name}',
          );
        }
      }
    });

    test('sigma → yield → sigma', () {
      for (final double z in <double>[1, 2, 3, 4.5, 5]) {
        final SigmaLevel level = SigmaLevel(z, SigmaShiftConvention.none);
        expect(
          sigmaLevelFromYield(yieldFromSigmaLevel(level)).value,
          closeTo(z, 1e-9),
        );
      }
    });

    test('the familiar sigma table is reproduced', () {
      // The published long-term correspondence — the one that only holds with
      // the shift, which is exactly why the shift has to be named.
      const List<(double, double)> published = <(double, double)>[
        (2, 308537),
        (3, 66807),
        (4, 6210),
        (5, 233),
        (6, 3.4),
      ];
      for (final (double shiftedSigma, double dpmo) in published) {
        expect(
          dpmoFromSigmaLevel(
            SigmaLevel(shiftedSigma, SigmaShiftConvention.shifted),
          ),
          closeTo(dpmo, dpmo * 0.005),
          reason: '$shiftedSigma sigma',
        );
      }
    });

    test('rolled throughput yield is the product, and it stings', () {
      expect(
        rolledThroughputYield(<double>[0.99, 0.99, 0.99]),
        closeTo(0.970299, 1e-12),
      );
      expect(
        rolledThroughputYield(<double>[for (int i = 0; i < 20; i++) 0.99]),
        closeTo(math.pow(0.99, 20).toDouble(), 1e-12),
      );
    });
  });

  group('what capability refuses', () {
    test('no specification limit at all', () {
      expect(
        () => CapabilityAnalysis.of(_symmetric),
        throwsA(
          isA<StatsRefusal>().having(
            (StatsRefusal e) => e.reason,
            'reason',
            contains('nothing to be capable of'),
          ),
        ),
      );
    });

    test('a lower limit that is not below the upper one', () {
      expect(
        () => CapabilityAnalysis.of(_symmetric, lowerSpec: 112, upperSpec: 88),
        throwsA(isA<StatsRefusal>()),
      );
    });

    test('fewer than eight observations, because of the normality test', () {
      expect(
        () => CapabilityAnalysis.of(
          <double>[1, 2, 3, 4, 5, 6, 7],
          lowerSpec: 0,
          upperSpec: 10,
        ),
        throwsA(isA<StatsRefusal>()),
      );
    });

    test('a process with no spread has no capability index', () {
      expect(
        () => CapabilityAnalysis.of(
          List<double>.filled(10, 100),
          lowerSpec: 90,
          upperSpec: 110,
        ),
        throwsA(
          isA<StatsRefusal>().having(
            (StatsRefusal e) => e.reason,
            'reason',
            contains('spread is zero'),
          ),
        ),
      );
    });

    test('a yield of exactly 0 or 1 has no finite sigma level', () {
      expect(() => sigmaLevelFromYield(1), throwsA(isA<StatsRefusal>()));
      expect(() => sigmaLevelFromYield(0), throwsA(isA<StatsRefusal>()));
    });

    test('a yield or DPMO outside its own range', () {
      expect(() => dpmoFromYield(1.2), throwsA(isA<StatsRefusal>()));
      expect(() => yieldFromDpmo(-1), throwsA(isA<StatsRefusal>()));
      expect(
        () => rolledThroughputYield(<double>[0.9, 1.1]),
        throwsA(isA<StatsRefusal>()),
      );
    });

    test('a refusal names both what was asked for and why', () {
      try {
        CapabilityAnalysis.of(<double>[1, 2, 3], lowerSpec: 0);
        fail('expected a refusal');
      } on StatsRefusal catch (e) {
        expect(e.what, isNotEmpty);
        expect(e.reason, isNotEmpty);
        expect(e.toString(), contains(e.what));
        expect(e.toString(), contains(e.reason));
      }
    });
  });
}
