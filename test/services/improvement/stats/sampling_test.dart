// Sample size and power.
//
// The expected numbers below are the ones every reference and every general
// statistics package agrees on for these textbook cases — n = 64 per group for
// a half-standard-deviation difference at 80% power, n = 26 for a large one,
// n = 385 for a ±5% survey. They are quoted here as an oracle: the engine has
// to land on the same integers, not on the ones a normal approximation would
// give (which are 63 and 25, and short).
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/improvement/stats/stats.dart';

void main() {
  group('the noncentral distributions the power rests on', () {
    test('the noncentral t is the ordinary t when nothing is off-centre', () {
      for (final double df in <double>[1, 5, 10, 30, 120]) {
        for (final double t in <double>[-3, -1, 0, 0.5, 2, 4]) {
          expect(
            noncentralTCdf(t, df, 0),
            closeTo(StudentTDistribution(df).cdf(t), 1e-12),
            reason: 't = $t on $df df',
          );
        }
      }
    });

    test('the noncentral F is the ordinary F when nothing is off-centre', () {
      for (final double x in <double>[0.5, 1, 2, 5]) {
        expect(
          noncentralFCdf(x, 3, 20, 0),
          closeTo(FDistribution(3, 20).cdf(x), 1e-12),
          reason: 'F = $x',
        );
      }
    });

    test('both are proper distribution functions', () {
      double previous = 0;
      for (double t = -4; t <= 6; t += 0.5) {
        final double p = noncentralTCdf(t, 12, 2);
        expect(p, inInclusiveRange(0, 1));
        expect(p, greaterThanOrEqualTo(previous - 1e-15));
        previous = p;
      }
      expect(noncentralFCdf(0, 2, 10, 5), 0);
      expect(noncentralFCdf(1e6, 2, 10, 5), closeTo(1, 1e-6));
    });

    test('shifting the noncentrality shifts the mass', () {
      expect(noncentralTCdf(2, 20, 3), lessThan(noncentralTCdf(2, 20, 1)));
      expect(
        noncentralFCdf(3, 2, 20, 10),
        lessThan(noncentralFCdf(3, 2, 20, 1)),
      );
    });

    test('they refuse impossible arguments', () {
      expect(() => noncentralTCdf(1, 0, 1), throwsA(isA<StatsRefusal>()));
      expect(() => noncentralFCdf(1, 0, 5, 1), throwsA(isA<StatsRefusal>()));
      expect(() => noncentralFCdf(1, 2, 5, -1), throwsA(isA<StatsRefusal>()));
      expect(() => noncentralFCdf(1, 2, 5, 5000), throwsA(isA<StatsRefusal>()));
    });
  });

  group('means', () {
    test('the textbook two-sample sizes come out exactly', () {
      expect(
        sampleSizeForTwoMeans(difference: 0.5, standardDeviation: 1).sampleSize,
        64,
      );
      expect(
        sampleSizeForTwoMeans(difference: 0.8, standardDeviation: 1).sampleSize,
        26,
      );
      expect(
        sampleSizeForTwoMeans(difference: 0.2, standardDeviation: 1).sampleSize,
        394,
      );
    });

    test('the textbook one-sample size comes out exactly', () {
      expect(
        sampleSizeForOneMean(difference: 0.5, standardDeviation: 1).sampleSize,
        34,
      );
    });

    test('the power of a known design matches the published figure', () {
      expect(
        powerForTwoMeans(
          difference: 1,
          standardDeviation: 1,
          sampleSize: 20,
        ).power,
        closeTo(0.8689, 0.0005),
      );
    });

    test('only the ratio of difference to spread matters', () {
      final PowerAnalysis coded = sampleSizeForTwoMeans(
        difference: 0.5,
        standardDeviation: 1,
      );
      final PowerAnalysis inMinutes = sampleSizeForTwoMeans(
        difference: 7.5,
        standardDeviation: 15,
      );
      expect(inMinutes.sampleSize, coded.sampleSize);
      expect(inMinutes.effectSize, closeTo(0.5, 1e-15));
    });

    test('a plan reports what the whole-number size actually buys', () {
      final PowerAnalysis plan = sampleSizeForTwoMeans(
        difference: 0.5,
        standardDeviation: 1,
      );
      expect(plan.requestedPower, 0.80);
      expect(plan.power, greaterThanOrEqualTo(0.80));
      expect(plan.power, lessThan(0.82));
      expect(plan.groupCount, 2);
      expect(plan.totalSampleSize, 128);
      expect(plan.method, 'noncentral t');
      expect(plan.toString(), contains('noncentral t'));
      // One observation fewer would not have reached it — this really is the
      // smallest sample that does.
      expect(
        powerForTwoMeans(
          difference: 0.5,
          standardDeviation: 1,
          sampleSize: plan.sampleSize - 1,
        ).power,
        lessThan(0.80),
      );
    });

    test('power rises with the sample and with the effect', () {
      double previous = 0;
      for (final int n in <int>[5, 10, 20, 40, 80]) {
        final double power = powerForTwoMeans(
          difference: 0.5,
          standardDeviation: 1,
          sampleSize: n,
        ).power;
        expect(power, greaterThan(previous));
        previous = power;
      }
      expect(
        sampleSizeForTwoMeans(difference: 1, standardDeviation: 1).sampleSize,
        lessThan(
          sampleSizeForTwoMeans(
            difference: 0.5,
            standardDeviation: 1,
          ).sampleSize,
        ),
      );
    });

    test('a one-sided test needs fewer observations than a two-sided one', () {
      expect(
        sampleSizeForTwoMeans(
          difference: 0.5,
          standardDeviation: 1,
          oneSided: true,
        ).sampleSize,
        lessThan(
          sampleSizeForTwoMeans(
            difference: 0.5,
            standardDeviation: 1,
          ).sampleSize,
        ),
      );
    });

    test('with no effect at all, power falls back to α', () {
      expect(
        powerForOneMean(
          difference: 0,
          standardDeviation: 1,
          sampleSize: 30,
        ).power,
        closeTo(0.05, 1e-9),
      );
    });
  });

  group('proportions', () {
    test('the two-proportion size follows the published formula', () {
      // 10% against 5%, 80% power, two-sided: 435 per group.
      expect(
        sampleSizeForTwoProportions(first: 0.10, second: 0.05).sampleSize,
        435,
      );
    });

    test('the effect size reported is Cohen’s h, not the raw difference', () {
      final PowerAnalysis wide = sampleSizeForTwoProportions(
        first: 0.05,
        second: 0.10,
      );
      final PowerAnalysis narrow = sampleSizeForTwoProportions(
        first: 0.50,
        second: 0.55,
      );
      expect(wide.effectSize, greaterThan(narrow.effectSize));
      // The same five points, and a much smaller study, near the extremes.
      expect(wide.sampleSize, lessThan(narrow.sampleSize));
      expect(cohensH(0.5, 0.5), 0);
      expect(cohensH(0.05, 0.10), closeTo(0.1925, 0.0005));
    });

    test('the one-proportion test says how hard proving a rare defect is', () {
      final PowerAnalysis plan = sampleSizeForOneProportion(
        baseline: 0.02,
        alternative: 0.01,
      );
      expect(plan.method, 'normal approximation');
      expect(plan.sampleSize, greaterThan(1000));
      expect(plan.power, greaterThanOrEqualTo(0.80));
    });

    test('a proportion of exactly 0 or 1 is refused', () {
      expect(
        () => powerForOneProportion(
          baseline: 0,
          alternative: 0.1,
          sampleSize: 100,
        ),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => sampleSizeForTwoProportions(first: 0.3, second: 0.3),
        throwsA(isA<StatsRefusal>()),
      );
    });
  });

  group('one-way ANOVA', () {
    test('a medium effect over four groups needs 45 each', () {
      final PowerAnalysis plan = sampleSizeForOneWayAnova(
        groupCount: 4,
        effectSize: 0.25,
      );
      expect(plan.sampleSize, 45);
      expect(plan.totalSampleSize, 180);
      expect(plan.method, 'noncentral F');
      expect(plan.power, closeTo(0.804, 0.002));
    });

    test('the effect size is the spread of the means over the noise', () {
      // Means 9, 10, 11 with σ = 1: the population spread of the means is
      // √(2/3), so f = 0.8165.
      expect(
        anovaEffectSize(<double>[9, 10, 11], 1),
        closeTo(0.81649658, 1e-8),
      );
      expect(anovaEffectSize(<double>[10, 10, 10], 2), 0);
      expect(
        anovaEffectSize(<double>[9, 10, 11], 2),
        closeTo(0.81649658 / 2, 1e-8),
      );
    });

    test(
      'more groups at the same effect size still needs more measurements',
      () {
        final PowerAnalysis three = sampleSizeForOneWayAnova(
          groupCount: 3,
          effectSize: 0.4,
        );
        final PowerAnalysis six = sampleSizeForOneWayAnova(
          groupCount: 6,
          effectSize: 0.4,
        );
        expect(six.totalSampleSize, greaterThan(three.totalSampleSize));
      },
    );

    test('it refuses a single group or a non-existent effect', () {
      expect(
        () =>
            powerForOneWayAnova(groupCount: 1, sampleSize: 10, effectSize: 0.3),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => powerForOneWayAnova(groupCount: 3, sampleSize: 10, effectSize: 0),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => anovaEffectSize(<double>[1], 1),
        throwsA(isA<StatsRefusal>()),
      );
    });
  });

  group('sizing an estimate rather than a test', () {
    test('a ±5% survey at 95% confidence is 385 units', () {
      expect(sampleSizeForProportionEstimate(marginOfError: 0.05), 385);
      expect(sampleSizeForProportionEstimate(marginOfError: 0.03), 1068);
    });

    test('a known rate needs a smaller sample than an unknown one', () {
      expect(
        sampleSizeForProportionEstimate(
          marginOfError: 0.05,
          expectedProportion: 0.1,
        ),
        lessThan(sampleSizeForProportionEstimate(marginOfError: 0.05)),
      );
    });

    test('a finite population makes the sample smaller, never larger', () {
      expect(
        sampleSizeForProportionEstimate(
          marginOfError: 0.05,
          populationSize: 1000,
        ),
        279,
      );
      // Never more units than the population holds.
      expect(
        sampleSizeForProportionEstimate(
          marginOfError: 0.01,
          populationSize: 40,
        ),
        40,
      );
    });

    test('sizing a mean solves against the t quantile, not the normal one', () {
      // The z-based shortcut answers 97; the honest answer is larger.
      expect(
        sampleSizeForMeanEstimate(marginOfError: 2, standardDeviation: 10),
        99,
      );
      expect(
        sampleSizeForMeanEstimate(marginOfError: 1, standardDeviation: 10),
        387,
      );
      expect(
        sampleSizeForMeanEstimate(
          marginOfError: 2,
          standardDeviation: 10,
          populationSize: 200,
        ),
        lessThan(99),
      );
    });

    test('what the estimators refuse', () {
      expect(
        () =>
            sampleSizeForMeanEstimate(marginOfError: 0, standardDeviation: 10),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => sampleSizeForMeanEstimate(marginOfError: 1, standardDeviation: 0),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => sampleSizeForProportionEstimate(
          marginOfError: 0.05,
          expectedProportion: 1,
        ),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => sampleSizeForProportionEstimate(
          marginOfError: 0.05,
          populationSize: 0,
        ),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => sampleSizeForMeanEstimate(
          marginOfError: 1,
          standardDeviation: 1,
          confidenceLevel: 1,
        ),
        throwsA(isA<StatsRefusal>()),
      );
    });
  });

  group('what the planners refuse', () {
    test('an α or a power outside 0..1', () {
      expect(
        () => powerForOneMean(
          difference: 1,
          standardDeviation: 1,
          sampleSize: 10,
          alpha: 0,
        ),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () =>
            sampleSizeForOneMean(difference: 1, standardDeviation: 1, power: 1),
        throwsA(isA<StatsRefusal>()),
      );
    });

    test('a difference of zero, which no sample size can detect', () {
      expect(
        () => sampleSizeForOneMean(difference: 0, standardDeviation: 1),
        throwsA(
          isA<StatsRefusal>().having(
            (StatsRefusal e) => e.reason,
            'reason',
            contains('cannot be detected'),
          ),
        ),
      );
    });

    test('a spread that is not a positive, finite number', () {
      expect(
        () => powerForTwoMeans(
          difference: 1,
          standardDeviation: -1,
          sampleSize: 10,
        ),
        throwsA(isA<StatsRefusal>()),
      );
    });

    test('an effect too small to prove with any sensible study', () {
      expect(
        () => sampleSizeForTwoMeans(difference: 1, standardDeviation: 1000000),
        throwsA(
          isA<StatsRefusal>().having(
            (StatsRefusal e) => e.reason,
            'reason',
            contains('too small to prove'),
          ),
        ),
      );
    });
  });
}
