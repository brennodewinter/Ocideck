// Hypothesis tests and the distributions behind them.
//
// The samples are chosen so the arithmetic is checkable by hand: two groups of
// 1..5 and 6..10 have a difference of exactly 5 and a standard error of
// exactly 1, three groups of three consecutive integers give an F of exactly
// 48, and a 2 × 2 table of 10/20/20/10 has every expected count at 15. The
// quantiles are the ones printed in every statistical table.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/improvement/stats/stats.dart';

void main() {
  group('the distributions, against the printed tables', () {
    test("Student's t", () {
      expect(StudentTDistribution(10).quantile(0.975), closeTo(2.228139, 1e-6));
      expect(StudentTDistribution(10).quantile(0.95), closeTo(1.812461, 1e-6));
      expect(StudentTDistribution(1).quantile(0.975), closeTo(12.70620, 1e-5));
      expect(StudentTDistribution(30).quantile(0.975), closeTo(2.042272, 1e-6));
      expect(StudentTDistribution(10).quantile(0.5), 0);
      expect(StudentTDistribution(10).cdf(0), closeTo(0.5, 1e-12));
      // Symmetric: the lower quantile mirrors the upper one.
      expect(
        StudentTDistribution(10).quantile(0.025),
        closeTo(-2.228139, 1e-6),
      );
      expect(StudentTDistribution(10).twoSidedP(2.228139), closeTo(0.05, 1e-6));
    });

    test('chi-squared', () {
      expect(ChiSquaredDistribution(1).quantile(0.95), closeTo(3.841459, 1e-6));
      expect(
        ChiSquaredDistribution(10).quantile(0.95),
        closeTo(18.307038, 1e-5),
      );
      expect(ChiSquaredDistribution(1).survival(3.841459), closeTo(0.05, 1e-7));
      expect(ChiSquaredDistribution(4).cdf(0), 0);
      expect(ChiSquaredDistribution(4).survival(0), 1);
    });

    test('F', () {
      expect(FDistribution(3, 10).quantile(0.95), closeTo(3.708265, 1e-5));
      expect(FDistribution(1, 1).quantile(0.95), closeTo(161.4476, 1e-2));
      expect(FDistribution(3, 10).survival(3.708265), closeTo(0.05, 1e-7));
      expect(
        FDistribution(3, 10).cdf(2) + FDistribution(3, 10).survival(2),
        closeTo(1, 1e-13),
      );
      expect(FDistribution(3, 10).cdf(0), 0);
    });

    test('the normal distribution moves with its own parameters', () {
      const NormalDistribution d = NormalDistribution(
        mean: 100,
        standardDeviation: 15,
      );
      expect(d.cdf(100), closeTo(0.5, 1e-14));
      expect(d.quantile(0.975), closeTo(100 + 15 * 1.959964, 1e-6));
      expect(d.survival(100), closeTo(0.5, 1e-14));
      expect(d.pdf(100), closeTo(standardNormalPdf(0) / 15, 1e-15));
    });
  });

  group('t tests', () {
    test('one sample, against a hypothesised mean', () {
      final TTestResult t = oneSampleT(<double>[
        4.8,
        4.9,
        5.0,
        5.1,
        5.2,
      ], hypothesizedMean: 4.9);
      // Mean 5.0, Σ(x − 5)² = 0.10, so s = √0.025 and se = s/√5 = 0.0707107.
      expect(t.estimate, closeTo(5, 1e-14));
      expect(t.standardError, closeTo(0.07071068, 1e-8));
      expect(t.statistic, closeTo(1.4142136, 1e-6));
      expect(t.degreesOfFreedom, 4);
      expect(t.pValue, closeTo(0.2302, 0.0005));
      expect(t.oneSidedPValue, closeTo(t.pValue / 2, 1e-15));
      expect(t.confidenceInterval.contains(5), isTrue);
      expect(t.confidenceInterval.level, 0.95);
      expect(
        t.confidenceInterval.width,
        closeTo(2 * 2.776445 * 0.07071068, 1e-6),
      );
    });

    test(
      'two samples, with a difference and a standard error of exactly one',
      () {
        final TTestResult t = twoSampleT(
          <double>[1, 2, 3, 4, 5],
          <double>[6, 7, 8, 9, 10],
        );
        expect(t.estimate, closeTo(5, 1e-14));
        expect(t.standardError, closeTo(1, 1e-14));
        expect(t.statistic, closeTo(5, 1e-13));
        // Equal spreads and equal sizes, so Welch lands on the pooled df of 8.
        expect(t.degreesOfFreedom, closeTo(8, 1e-12));
        expect(t.confidenceInterval.low, closeTo(5 - 2.306004, 1e-6));
        expect(t.confidenceInterval.high, closeTo(5 + 2.306004, 1e-6));
        expect(t.pValue, lessThan(0.002));
      },
    );

    test('Welch and the pooled test agree when the spreads are equal', () {
      final TTestResult welch = twoSampleT(
        <double>[1, 2, 3, 4, 5],
        <double>[6, 7, 8, 9, 10],
      );
      final TTestResult pooled = twoSampleT(
        <double>[1, 2, 3, 4, 5],
        <double>[6, 7, 8, 9, 10],
        pooled: true,
      );
      expect(pooled.statistic, closeTo(welch.statistic, 1e-12));
      expect(pooled.degreesOfFreedom, closeTo(welch.degreesOfFreedom, 1e-12));
    });

    test('Welch parts company when the spreads do not match', () {
      final TTestResult welch = twoSampleT(
        <double>[10, 10.1, 9.9, 10.05, 9.95],
        <double>[1, 20, 5, 15, 9],
      );
      final TTestResult pooled = twoSampleT(
        <double>[10, 10.1, 9.9, 10.05, 9.95],
        <double>[1, 20, 5, 15, 9],
        pooled: true,
      );
      expect(welch.degreesOfFreedom, lessThan(pooled.degreesOfFreedom));
    });

    test('the paired test is the one-sample test on the differences', () {
      final List<double> before = <double>[10, 12, 14, 11, 13];
      final List<double> after = <double>[9, 10, 13, 11, 10];
      final TTestResult paired = pairedT(before, after);
      final TTestResult onDifferences = oneSampleT(<double>[
        for (int i = 0; i < 5; i++) after[i] - before[i],
      ]);
      expect(paired.statistic, onDifferences.statistic);
      expect(paired.estimate, onDifferences.estimate);
      // The pairing is the whole point: ignoring it costs the significance.
      final TTestResult unpaired = twoSampleT(before, after);
      expect(paired.pValue, lessThan(unpaired.pValue));
    });

    test('what the t tests refuse', () {
      expect(() => oneSampleT(<double>[1]), throwsA(isA<StatsRefusal>()));
      expect(() => oneSampleT(<double>[5, 5, 5]), throwsA(isA<StatsRefusal>()));
      expect(
        () => pairedT(<double>[1, 2, 3], <double>[1, 2]),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => twoSampleT(<double>[1], <double>[1, 2, 3]),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => oneSampleT(<double>[1, 2, 3], confidenceLevel: 1.5),
        throwsA(isA<StatsRefusal>()),
      );
    });
  });

  group('ANOVA and Levene', () {
    final List<List<double>> groups = <List<double>>[
      <double>[1, 2, 3],
      <double>[4, 5, 6],
      <double>[7, 8, 9],
    ];

    test('the sums of squares are the ones the definition gives', () {
      final AnovaResult a = oneWayAnova(groups);
      // Group means 2, 5 and 8 against a grand mean of 5: between-groups
      // 3·(9 + 0 + 9) = 54, within-groups 2 + 2 + 2 = 6.
      expect(a.betweenSumOfSquares, closeTo(54, 1e-12));
      expect(a.withinSumOfSquares, closeTo(6, 1e-12));
      expect(a.totalSumOfSquares, closeTo(60, 1e-12));
      expect(a.numeratorDf, 2);
      expect(a.denominatorDf, 6);
      expect(a.betweenMeanSquare, closeTo(27, 1e-12));
      expect(a.withinMeanSquare, closeTo(1, 1e-12));
      expect(a.fStatistic, closeTo(27, 1e-12));
      expect(a.etaSquared, closeTo(0.9, 1e-12));
      // F(2, 6) = 27 lands, by coincidence, on a p of almost exactly 0.001.
      expect(a.pValue, closeTo(0.001, 1e-6));
      expect(a.groupCount, 3);
      expect(a.totalCount, 9);
    });

    test('groups that differ in nothing produce no F at all', () {
      final AnovaResult a = oneWayAnova(<List<double>>[
        <double>[1, 2, 3],
        <double>[1, 2, 3],
        <double>[1, 2, 3],
      ]);
      expect(a.fStatistic, closeTo(0, 1e-24));
      expect(a.pValue, closeTo(1, 1e-12));
    });

    test('Levene sees equal spreads, whatever the centres are', () {
      final AnovaResult levene = leveneTest(groups);
      expect(levene.fStatistic, closeTo(0, 1e-24));
      expect(levene.pValue, closeTo(1, 1e-12));
    });

    test('Levene sees unequal spreads', () {
      final AnovaResult levene = leveneTest(<List<double>>[
        <double>[5, 5.1, 4.9, 5, 5.05],
        <double>[1, 9, 3, 8, 4],
      ]);
      expect(levene.pValue, lessThan(0.05));
    });

    test('the centre Levene measures around is a stated choice', () {
      final List<List<double>> skewed = <List<double>>[
        <double>[1, 1, 1, 1, 40],
        <double>[2, 2, 2, 2, 3],
      ];
      expect(
        leveneTest(skewed, centre: LeveneCentre.median).fStatistic,
        isNot(
          closeTo(
            leveneTest(skewed, centre: LeveneCentre.mean).fStatistic,
            1e-6,
          ),
        ),
      );
    });

    test('the F test for variances is the ratio it says it is', () {
      final VarianceRatioResult f = fTestForVariances(
        <double>[1, 3, 5, 7, 9],
        <double>[3, 4, 5, 6, 7],
      );
      // Variances 10 and 2.5.
      expect(f.statistic, closeTo(4, 1e-12));
      expect(f.numeratorDf, 4);
      expect(f.denominatorDf, 4);
      expect(f.pValue, inInclusiveRange(0, 1));
    });

    test('what they refuse', () {
      expect(
        () => oneWayAnova(<List<double>>[
          <double>[1, 2, 3],
        ]),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => oneWayAnova(<List<double>>[
          <double>[1],
          <double>[2, 3],
        ]),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => oneWayAnova(<List<double>>[
          <double>[1, 1, 1],
          <double>[1, 1, 1],
        ]),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => fTestForVariances(<double>[1, 2, 3], <double>[5, 5, 5]),
        throwsA(isA<StatsRefusal>()),
      );
    });
  });

  group('chi-squared', () {
    test('goodness of fit against a flat expectation', () {
      final ChiSquaredResult r = chiSquaredGoodnessOfFit(
        <int>[10, 20, 30, 40],
        <double>[25, 25, 25, 25],
      );
      expect(r.statistic, closeTo(20, 1e-12));
      expect(r.degreesOfFreedom, 3);
      expect(r.smallestExpected, 25);
      expect(r.approximationHolds, isTrue);
      expect(r.pValue, lessThan(0.001));
    });

    test('an estimated parameter costs a degree of freedom', () {
      expect(
        chiSquaredGoodnessOfFit(
          <int>[10, 20, 30, 40],
          <double>[25, 25, 25, 25],
          estimatedParameters: 1,
        ).degreesOfFreedom,
        2,
      );
    });

    test('independence over a 2 × 2 table', () {
      final ChiSquaredResult r = chiSquaredIndependence(<List<int>>[
        <int>[10, 20],
        <int>[20, 10],
      ]);
      // Every expected count is 15, so the statistic is 4 · 25/15.
      expect(r.statistic, closeTo(20 / 3, 1e-12));
      expect(r.degreesOfFreedom, 1);
      expect(r.smallestExpected, closeTo(15, 1e-12));
      expect(r.pValue, closeTo(0.00982, 0.0002));
    });

    test('a thin table reports that its approximation is thin', () {
      final ChiSquaredResult r = chiSquaredIndependence(<List<int>>[
        <int>[1, 2],
        <int>[2, 1],
      ]);
      expect(r.approximationHolds, isFalse);
      expect(r.smallestExpected, lessThan(5));
    });

    test('what it refuses', () {
      expect(
        () => chiSquaredGoodnessOfFit(<int>[1, 2], <double>[1]),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => chiSquaredGoodnessOfFit(<int>[1, 2], <double>[0, 3]),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => chiSquaredGoodnessOfFit(
          <int>[1, 2],
          <double>[1.5, 1.5],
          estimatedParameters: 1,
        ),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => chiSquaredIndependence(<List<int>>[
          <int>[1, 2],
          <int>[1],
        ]),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => chiSquaredIndependence(<List<int>>[
          <int>[0, 0],
          <int>[0, 0],
        ]),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => chiSquaredIndependence(<List<int>>[
          <int>[-1, 2],
          <int>[1, 2],
        ]),
        throwsA(isA<StatsRefusal>()),
      );
    });
  });

  group('proportions', () {
    test('one proportion, with the Wilson interval', () {
      final ProportionTestResult r = oneProportionZ(60, 100);
      expect(r.estimate, 0.6);
      expect(r.standardError, closeTo(0.05, 1e-15));
      expect(r.statistic, closeTo(2, 1e-13));
      expect(r.pValue, closeTo(0.0455, 0.0005));
      // The published Wilson interval for 60/100 at 95%.
      expect(r.confidenceInterval.low, closeTo(0.5020, 0.0005));
      expect(r.confidenceInterval.high, closeTo(0.6906, 0.0005));
    });

    test('Wilson stays inside 0..1 where Wald would not', () {
      final ProportionTestResult perfect = oneProportionZ(
        20,
        20,
        hypothesized: 0.5,
      );
      expect(perfect.confidenceInterval.low, greaterThan(0));
      expect(perfect.confidenceInterval.high, lessThanOrEqualTo(1));
      expect(perfect.confidenceInterval.width, greaterThan(0));
    });

    test('two proportions, pooled for the test and not for the interval', () {
      final ProportionTestResult r = twoProportionZ(40, 100, 60, 100);
      expect(r.estimate, closeTo(0.2, 1e-15));
      // Pooled p̄ = 0.5, so the standard error is √(0.25 · 0.02).
      expect(r.standardError, closeTo(0.07071068, 1e-8));
      expect(r.statistic, closeTo(2.8284271, 1e-6));
      expect(r.pValue, closeTo(0.00468, 0.0001));
      expect(r.confidenceInterval.contains(0.2), isTrue);
      expect(r.confidenceInterval.contains(0), isFalse);
    });

    test('what they refuse', () {
      expect(() => oneProportionZ(5, 0), throwsA(isA<StatsRefusal>()));
      expect(() => oneProportionZ(11, 10), throwsA(isA<StatsRefusal>()));
      expect(
        () => oneProportionZ(5, 10, hypothesized: 0),
        throwsA(isA<StatsRefusal>()),
      );
      expect(() => twoProportionZ(0, 10, 0, 10), throwsA(isA<StatsRefusal>()));
    });
  });

  group('Anderson-Darling', () {
    test('a normal-shaped sample is not rejected', () {
      final List<double> quantiles = <double>[
        for (int i = 1; i <= 40; i++) standardNormalQuantile((i - 0.5) / 40),
      ];
      final AndersonDarlingResult r = andersonDarlingNormality(quantiles);
      expect(r.count, 40);
      expect(r.pValue, greaterThan(0.05));
      expect(r.toString(), contains('Anderson-Darling'));
    });

    test('a heavily skewed sample is rejected', () {
      // A long right tail is what Anderson-Darling is built to catch; an
      // evenly spread sample of the same size would not be rejected, because
      // it is light in exactly the tails the test weights most heavily.
      final List<double> skewed = <double>[
        for (int i = 0; i < 40; i++) 1.0,
        for (int i = 1; i <= 20; i++) 1.0 + i * i * 3.0,
      ];
      expect(andersonDarlingNormality(skewed).pValue, lessThan(0.05));

      final List<double> uniform = <double>[
        for (int i = 0; i < 60; i++) i.toDouble(),
      ];
      expect(andersonDarlingNormality(uniform).pValue, greaterThan(0.05));
    });

    test('the adjustment for sample size only ever raises the statistic', () {
      final List<double> sample = <double>[
        for (int i = 1; i <= 12; i++) standardNormalQuantile(i / 13),
      ];
      final AndersonDarlingResult r = andersonDarlingNormality(sample);
      expect(r.adjustedStatistic, greaterThan(r.statistic));
    });

    test('below eight observations, and on constant data, it refuses', () {
      expect(
        () => andersonDarlingNormality(<double>[1, 2, 3, 4, 5, 6, 7]),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => andersonDarlingNormality(List<double>.filled(10, 3)),
        throwsA(isA<StatsRefusal>()),
      );
    });
  });
}
