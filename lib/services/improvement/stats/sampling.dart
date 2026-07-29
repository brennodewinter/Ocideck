part of 'stats.dart';

// How many measurements the study needs, and what a study of the size it can
// afford will actually be able to see.
//
// This file exists because of the question that ends most improvement
// projects badly: *"we measured twenty parts before and twenty after, the
// means differ, is it real?"* — asked after the data was collected, when the
// only honest answer left is sometimes "this study could never have shown
// that". Every calculator here also runs the other way round, so that answer
// can be given while it is still cheap.
//
// Two habits of the field are refused.
//
//   * The normal approximation dressed up as exact. A t test's power follows
//     the *noncentral* t distribution, and the z-based shortcut understates
//     the sample size at exactly the sizes an improvement project works at
//     (n < 30). The noncentral t is implemented here and used for every mean.
//     Where a normal approximation genuinely is the published method — the
//     proportion tests — the result says so in [PowerAnalysis.method].
//   * A sample size without the power it achieves. Rounding a required n up
//     to a whole number changes the power, and "n = 34" alone cannot be
//     checked by anyone. Every plan reports what it actually buys.

/// The largest sample the planners will search up to.
///
/// Not an arithmetic limit. A plan that comes back with half a million
/// measurements is not a plan, and returning the number would be a worse
/// answer than saying the study as framed cannot be run.
const int maximumPlannableSampleSize = 1000000;

/// Cumulative probability of the noncentral t distribution.
///
/// Lenth's AS 243 (1989): a Poisson-weighted mixture of incomplete beta
/// functions, which is why this engine needed a good
/// [regularizedIncompleteBeta] before it could offer power at all.
///
/// It lives here rather than in `distributions.dart` because nothing but
/// power uses it: a *report* never quotes a noncentral t, it quotes what the
/// study can detect.
double noncentralTCdf(double t, double degreesOfFreedom, double noncentrality) {
  const String what = 'the noncentral t distribution';
  if (degreesOfFreedom <= 0) {
    throw StatsRefusal(what, 'needs positive degrees of freedom');
  }
  // The series is stated for t >= 0; the other half follows by reflecting both
  // the value and the noncentrality.
  if (t < 0) return 1 - noncentralTCdf(-t, degreesOfFreedom, -noncentrality);

  final double delta = noncentrality;
  final double belowZero = standardNormalCdf(-delta);
  final double x = t * t / (t * t + degreesOfFreedom);
  if (x <= 0) return belowZero;

  final double lambda = delta * delta;
  final double b = 0.5 * degreesOfFreedom;
  final double logBeta = lnBeta(0.5, b);
  final double rxb = math.pow(1 - x, b).toDouble();

  double a = 0.5;
  double p = 0.5 * math.exp(-0.5 * lambda);
  double q = math.sqrt(2 / math.pi) * p * delta;
  double remainingMass = 0.5 - p;
  double xOdd = regularizedIncompleteBeta(0.5, b, x);
  double xEven = 1 - rxb;
  double gOdd = 2 * rxb * math.exp(0.5 * math.log(x) - logBeta);
  double gEven = b * x * rxb;
  double sum = p * xOdd + q * xEven;

  for (int j = 1; j <= _maxIterations; j++) {
    a += 1;
    xOdd -= gOdd;
    xEven -= gEven;
    gOdd *= x * (a + b - 1) / a;
    gEven *= x * (a + b - 0.5) / (a + 0.5);
    p *= lambda / (2 * j);
    q *= lambda / (2 * j + 1);
    remainingMass -= p;
    sum += p * xOdd + q * xEven;
    if ((2 * remainingMass * (xOdd - gOdd)).abs() < 1e-13) break;
  }
  return math.min(1, math.max(0, sum + belowZero));
}

/// Cumulative probability of the noncentral F distribution — the same Poisson
/// mixture, and what the power of an ANOVA is read off.
double noncentralFCdf(
  double x,
  double numeratorDf,
  double denominatorDf,
  double noncentrality,
) {
  const String what = 'the noncentral F distribution';
  if (numeratorDf <= 0 || denominatorDf <= 0) {
    throw StatsRefusal(what, 'needs positive degrees of freedom');
  }
  if (noncentrality < 0) {
    throw StatsRefusal(what, 'the noncentrality cannot be negative');
  }
  if (noncentrality > 1400) {
    throw StatsRefusal(
      what,
      'a noncentrality of $noncentrality would underflow the Poisson weights; '
      'a study this far past its own detection threshold does not need a '
      'power figure',
    );
  }
  if (x <= 0) return 0;

  final double y = numeratorDf * x / (numeratorDf * x + denominatorDf);
  final double half = 0.5 * noncentrality;
  double weight = math.exp(-half);
  double unaccounted = 1;
  double sum = 0;
  for (int j = 0; j <= _maxIterations; j++) {
    if (j > 0) weight *= half / j;
    sum +=
        weight *
        regularizedIncompleteBeta(
          0.5 * numeratorDf + j,
          0.5 * denominatorDf,
          y,
        );
    unaccounted -= weight;
    if (unaccounted < 1e-14) break;
  }
  return math.min(1, math.max(0, sum));
}

/// What a study of a given size can see, or what size it would take to see it.
class PowerAnalysis {
  const PowerAnalysis({
    required this.power,
    required this.sampleSize,
    required this.groupCount,
    required this.alpha,
    required this.oneSided,
    required this.effectSize,
    required this.method,
    this.requestedPower,
  });

  /// The chance of detecting the effect, if the effect is really there.
  final double power;

  /// Observations **per group**. For a one-sample or paired test the study has
  /// one group, so this is the whole study.
  final int sampleSize;

  final int groupCount;

  /// The false-positive rate the test is run at.
  final double alpha;

  final bool oneSided;

  /// The standardised effect the calculation was for: Cohen's d for means,
  /// Cohen's h for proportions, Cohen's f for an ANOVA. Standardised because
  /// that is the only thing a sample size can depend on — it is the difference
  /// measured in standard deviations, never in the units of the process.
  final double effectSize;

  /// Which approximation produced the number, e.g. `'noncentral t'`. English
  /// and data, not a `d(...)` string: the UI layer decides how to word it.
  final String method;

  /// The power that was asked for, when this came from a sample-size
  /// calculation. [power] is what the whole-number sample size actually
  /// achieves, and it is the larger of the two.
  final double? requestedPower;

  /// Observations in the whole study.
  int get totalSampleSize => sampleSize * groupCount;

  PowerAnalysis _asPlanFor(double requested) => PowerAnalysis(
    power: power,
    sampleSize: sampleSize,
    groupCount: groupCount,
    alpha: alpha,
    oneSided: oneSided,
    effectSize: effectSize,
    method: method,
    requestedPower: requested,
  );

  @override
  String toString() =>
      'n = $sampleSize per group ($groupCount group(s)), power = '
      '${power.toStringAsFixed(3)} at α = $alpha ($method)';
}

/// Power of a one-sample t test — and, with the differences as input, of a
/// paired t test, which is the same test.
///
/// [standardDeviation] is the spread of the measurements (of the *differences*,
/// in the paired case). Getting a usable value for it before the study is the
/// hard part of every sample-size calculation, and there is no arithmetic that
/// can rescue a guess: it comes from a pilot, from the historical data, or
/// from the measurement system study.
PowerAnalysis powerForOneMean({
  required double difference,
  required double standardDeviation,
  required int sampleSize,
  double alpha = 0.05,
  bool oneSided = false,
}) {
  const String what = 'the power of a one-sample t test';
  _checkAlpha(what, alpha);
  _checkSpread(what, standardDeviation);
  _requireAtLeast(what, 'observations', sampleSize, 2);
  final double d = difference.abs() / standardDeviation;
  return PowerAnalysis(
    power: _tPower(
      d * math.sqrt(sampleSize),
      (sampleSize - 1).toDouble(),
      alpha,
      oneSided,
    ),
    sampleSize: sampleSize,
    groupCount: 1,
    alpha: alpha,
    oneSided: oneSided,
    effectSize: d,
    method: 'noncentral t',
  );
}

/// How many observations a one-sample or paired t test needs.
PowerAnalysis sampleSizeForOneMean({
  required double difference,
  required double standardDeviation,
  double alpha = 0.05,
  double power = 0.80,
  bool oneSided = false,
}) {
  const String what = 'a sample size for a one-sample t test';
  _checkPower(what, power);
  _checkDifference(what, difference);
  return _smallestReaching(
    what,
    2,
    power,
    (int n) => powerForOneMean(
      difference: difference,
      standardDeviation: standardDeviation,
      sampleSize: n,
      alpha: alpha,
      oneSided: oneSided,
    ),
  );
}

/// Power of a two-sample t test with [sampleSize] observations in each group.
///
/// Equal groups, and pooled spread. Unequal groups are not offered: for a
/// fixed total number of measurements, splitting them evenly is the most
/// powerful arrangement there is, so an unequal plan is only ever a
/// consequence of what the process allows — not something to design toward.
PowerAnalysis powerForTwoMeans({
  required double difference,
  required double standardDeviation,
  required int sampleSize,
  double alpha = 0.05,
  bool oneSided = false,
}) {
  const String what = 'the power of a two-sample t test';
  _checkAlpha(what, alpha);
  _checkSpread(what, standardDeviation);
  _requireAtLeast(what, 'observations per group', sampleSize, 2);
  final double d = difference.abs() / standardDeviation;
  return PowerAnalysis(
    power: _tPower(
      d * math.sqrt(sampleSize / 2),
      (2 * sampleSize - 2).toDouble(),
      alpha,
      oneSided,
    ),
    sampleSize: sampleSize,
    groupCount: 2,
    alpha: alpha,
    oneSided: oneSided,
    effectSize: d,
    method: 'noncentral t',
  );
}

/// How many observations **per group** a two-sample t test needs.
PowerAnalysis sampleSizeForTwoMeans({
  required double difference,
  required double standardDeviation,
  double alpha = 0.05,
  double power = 0.80,
  bool oneSided = false,
}) {
  const String what = 'a sample size for a two-sample t test';
  _checkPower(what, power);
  _checkDifference(what, difference);
  return _smallestReaching(
    what,
    2,
    power,
    (int n) => powerForTwoMeans(
      difference: difference,
      standardDeviation: standardDeviation,
      sampleSize: n,
      alpha: alpha,
      oneSided: oneSided,
    ),
  );
}

/// Power of a one-proportion test of [alternative] against [baseline].
///
/// The normal approximation, which is the published method and is also where
/// this calculator is weakest: at a defect rate of a few per thousand it needs
/// a sample far larger than the approximation is stated to hold for. That is
/// not a flaw in the arithmetic but the actual difficulty — proving a rare
/// defect got rarer takes an enormous sample, and the number is honest about
/// how enormous.
PowerAnalysis powerForOneProportion({
  required double baseline,
  required double alternative,
  required int sampleSize,
  double alpha = 0.05,
  bool oneSided = false,
}) {
  const String what = 'the power of a one-proportion test';
  _checkAlpha(what, alpha);
  _checkProportion(what, baseline);
  _checkProportion(what, alternative);
  _requireAtLeast(what, 'observations', sampleSize, 1);
  final double critical = standardNormalQuantile(
    1 - (oneSided ? alpha : alpha / 2),
  );
  final double n = sampleSize.toDouble();
  final double z =
      ((alternative - baseline).abs() * math.sqrt(n) -
          critical * math.sqrt(baseline * (1 - baseline))) /
      math.sqrt(alternative * (1 - alternative));
  return PowerAnalysis(
    power: standardNormalCdf(z),
    sampleSize: sampleSize,
    groupCount: 1,
    alpha: alpha,
    oneSided: oneSided,
    effectSize: cohensH(baseline, alternative),
    method: 'normal approximation',
  );
}

/// How many observations a one-proportion test needs.
PowerAnalysis sampleSizeForOneProportion({
  required double baseline,
  required double alternative,
  double alpha = 0.05,
  double power = 0.80,
  bool oneSided = false,
}) {
  const String what = 'a sample size for a one-proportion test';
  _checkPower(what, power);
  if (baseline == alternative) {
    throw StatsRefusal(what, 'the two proportions given are the same');
  }
  return _smallestReaching(
    what,
    1,
    power,
    (int n) => powerForOneProportion(
      baseline: baseline,
      alternative: alternative,
      sampleSize: n,
      alpha: alpha,
      oneSided: oneSided,
    ),
  );
}

/// Power of a two-proportion test with [sampleSize] observations per group.
PowerAnalysis powerForTwoProportions({
  required double first,
  required double second,
  required int sampleSize,
  double alpha = 0.05,
  bool oneSided = false,
}) {
  const String what = 'the power of a two-proportion test';
  _checkAlpha(what, alpha);
  _checkProportion(what, first);
  _checkProportion(what, second);
  _requireAtLeast(what, 'observations per group', sampleSize, 1);
  final double pooled = 0.5 * (first + second);
  final double critical = standardNormalQuantile(
    1 - (oneSided ? alpha : alpha / 2),
  );
  final double n = sampleSize.toDouble();
  final double z =
      ((second - first).abs() * math.sqrt(n) -
          critical * math.sqrt(2 * pooled * (1 - pooled))) /
      math.sqrt(first * (1 - first) + second * (1 - second));
  return PowerAnalysis(
    power: standardNormalCdf(z),
    sampleSize: sampleSize,
    groupCount: 2,
    alpha: alpha,
    oneSided: oneSided,
    effectSize: cohensH(first, second),
    method: 'normal approximation',
  );
}

/// How many observations **per group** a two-proportion test needs.
PowerAnalysis sampleSizeForTwoProportions({
  required double first,
  required double second,
  double alpha = 0.05,
  double power = 0.80,
  bool oneSided = false,
}) {
  const String what = 'a sample size for a two-proportion test';
  _checkPower(what, power);
  if (first == second) {
    throw StatsRefusal(what, 'the two proportions given are the same');
  }
  return _smallestReaching(
    what,
    1,
    power,
    (int n) => powerForTwoProportions(
      first: first,
      second: second,
      sampleSize: n,
      alpha: alpha,
      oneSided: oneSided,
    ),
  );
}

/// Cohen's h — the difference between two proportions on the arcsine scale.
///
/// A plain difference of proportions is not a usable effect size, because a
/// move from 0.50 to 0.55 and one from 0.01 to 0.06 are the same five points
/// and nothing like the same difficulty to prove.
double cohensH(double first, double second) =>
    (2 * math.asin(math.sqrt(second)) - 2 * math.asin(math.sqrt(first))).abs();

/// Cohen's f for a set of group means against a common spread — the effect
/// size a one-way ANOVA's power depends on.
double anovaEffectSize(List<double> groupMeans, double standardDeviation) {
  const String what = 'an ANOVA effect size';
  _requireAtLeast(what, 'groups', groupMeans.length, 2);
  _checkSpread(what, standardDeviation);
  final Descriptives summary = Descriptives.of(groupMeans);
  // The population spread of the means (divisor k, not k − 1): these are the
  // means being planned for, not a sample of some larger set of them.
  return math.sqrt(summary.sumOfSquaredDeviations / groupMeans.length) /
      standardDeviation;
}

/// Power of a one-way ANOVA with [groupCount] groups of [sampleSize] each.
PowerAnalysis powerForOneWayAnova({
  required int groupCount,
  required int sampleSize,
  required double effectSize,
  double alpha = 0.05,
}) {
  const String what = 'the power of a one-way ANOVA';
  _checkAlpha(what, alpha);
  _requireAtLeast(what, 'groups', groupCount, 2);
  _requireAtLeast(what, 'observations per group', sampleSize, 2);
  if (effectSize <= 0) {
    throw StatsRefusal(what, 'the effect size must be positive');
  }
  final double numeratorDf = (groupCount - 1).toDouble();
  final double denominatorDf = (groupCount * (sampleSize - 1)).toDouble();
  final double critical = FDistribution(
    numeratorDf,
    denominatorDf,
  ).quantile(1 - alpha);
  return PowerAnalysis(
    power:
        1 -
        noncentralFCdf(
          critical,
          numeratorDf,
          denominatorDf,
          effectSize * effectSize * groupCount * sampleSize,
        ),
    sampleSize: sampleSize,
    groupCount: groupCount,
    alpha: alpha,
    oneSided: false,
    effectSize: effectSize,
    method: 'noncentral F',
  );
}

/// How many observations **per group** a one-way ANOVA needs.
PowerAnalysis sampleSizeForOneWayAnova({
  required int groupCount,
  required double effectSize,
  double alpha = 0.05,
  double power = 0.80,
}) {
  const String what = 'a sample size for a one-way ANOVA';
  _checkPower(what, power);
  return _smallestReaching(
    what,
    2,
    power,
    (int n) => powerForOneWayAnova(
      groupCount: groupCount,
      sampleSize: n,
      effectSize: effectSize,
      alpha: alpha,
    ),
  );
}

/// How many measurements it takes to pin a mean down to ±[marginOfError].
///
/// Estimation, not testing: this is the calculator for "how long does the step
/// take" rather than "did the step get shorter". It solves against the t
/// quantile rather than the normal one, so it does not understate itself at
/// the sizes where it matters, and it accepts a [populationSize] because a
/// process improvement often samples a finite batch — sampling 400 out of 500
/// invoices is more informative than sampling 400 out of a million, and the
/// textbook formula does not know that.
int sampleSizeForMeanEstimate({
  required double marginOfError,
  required double standardDeviation,
  double confidenceLevel = 0.95,
  int? populationSize,
}) {
  const String what = 'a sample size for estimating a mean';
  _checkSpread(what, standardDeviation);
  _checkLevel(what, confidenceLevel);
  if (marginOfError <= 0) {
    throw StatsRefusal(what, 'the margin of error must be positive');
  }
  final double tail = 1 - (1 - confidenceLevel) / 2;
  final double ratio = standardDeviation / marginOfError;
  int n = math.max(
    2,
    (math.pow(standardNormalQuantile(tail) * ratio, 2)).ceil(),
  );
  for (int i = 0; i < 100; i++) {
    final double critical = StudentTDistribution(
      (n - 1).toDouble(),
    ).quantile(tail);
    final int next = math.max(2, math.pow(critical * ratio, 2).ceil());
    if (next == n) break;
    n = next;
  }
  return _correctedForPopulation(what, n, populationSize);
}

/// How many units it takes to pin a proportion down to ±[marginOfError].
///
/// [expectedProportion] defaults to 0.5, the value that needs the largest
/// sample: with no prior idea of the rate, planning for the worst case is the
/// only choice that cannot come up short.
int sampleSizeForProportionEstimate({
  required double marginOfError,
  double expectedProportion = 0.5,
  double confidenceLevel = 0.95,
  int? populationSize,
}) {
  const String what = 'a sample size for estimating a proportion';
  _checkLevel(what, confidenceLevel);
  if (expectedProportion < 0 || expectedProportion > 1) {
    throw StatsRefusal(what, 'the expected proportion must lie in 0..1');
  }
  if (marginOfError <= 0 || marginOfError >= 1) {
    throw StatsRefusal(what, 'the margin of error must lie in 0..1');
  }
  final double critical = standardNormalQuantile(1 - (1 - confidenceLevel) / 2);
  final double spread = expectedProportion * (1 - expectedProportion);
  if (spread <= 0) {
    throw StatsRefusal(
      what,
      'an expected proportion of exactly 0 or 1 leaves nothing to estimate',
    );
  }
  final int n = (critical * critical * spread / (marginOfError * marginOfError))
      .ceil();
  return _correctedForPopulation(what, n, populationSize);
}

/// The finite-population correction, applied only when a population was named.
int _correctedForPopulation(String what, int n, int? populationSize) {
  if (populationSize == null) return n;
  if (populationSize < 1) {
    throw StatsRefusal(what, 'the population size must be positive');
  }
  if (n >= populationSize) return populationSize;
  final double corrected = n / (1 + (n - 1) / populationSize);
  return math.min(populationSize, corrected.ceil());
}

/// Power of a t test with noncentrality [delta] on [df] degrees of freedom.
///
/// The two-sided case adds the far tail rather than ignoring it. That term is
/// negligible at any power worth planning for, and is kept because leaving it
/// out makes the function disagree with itself at small effects — where power
/// should approach α, not half of it.
double _tPower(double delta, double df, double alpha, bool oneSided) {
  final StudentTDistribution t = StudentTDistribution(df);
  if (oneSided) {
    return 1 - noncentralTCdf(t.quantile(1 - alpha), df, delta);
  }
  final double critical = t.quantile(1 - alpha / 2);
  return 1 -
      noncentralTCdf(critical, df, delta) +
      noncentralTCdf(-critical, df, delta);
}

/// The smallest sample size at which [at] reaches [wanted].
///
/// Found by doubling and then bisecting rather than by counting upward: power
/// rises with n, so the bracket is sound, and a rare effect can need tens of
/// thousands of observations that nobody should wait for one at a time.
PowerAnalysis _smallestReaching(
  String what,
  int minimum,
  double wanted,
  PowerAnalysis Function(int) at,
) {
  PowerAnalysis best = at(minimum);
  if (best.power >= wanted) return best._asPlanFor(wanted);
  int low = minimum;
  int high = minimum * 2;
  while (true) {
    if (high > maximumPlannableSampleSize) {
      throw StatsRefusal(
        what,
        'even $maximumPlannableSampleSize observation(s) would not reach a '
        'power of $wanted; the effect asked about is too small to prove '
        'with a study of any sensible size',
      );
    }
    best = at(high);
    if (best.power >= wanted) break;
    low = high;
    high *= 2;
  }
  while (high - low > 1) {
    final int middle = low + (high - low) ~/ 2;
    final PowerAnalysis candidate = at(middle);
    if (candidate.power >= wanted) {
      high = middle;
      best = candidate;
    } else {
      low = middle;
    }
  }
  return best._asPlanFor(wanted);
}

void _checkAlpha(String what, double alpha) {
  if (alpha <= 0 || alpha >= 1) {
    throw StatsRefusal(what, 'α must lie strictly between 0 and 1, got $alpha');
  }
}

void _checkPower(String what, double power) {
  if (power <= 0 || power >= 1) {
    throw StatsRefusal(
      what,
      'the power asked for must lie strictly between 0 and 1; a study that is '
      'certain to detect an effect does not exist',
    );
  }
}

void _checkLevel(String what, double level) {
  if (level <= 0 || level >= 1) {
    throw StatsRefusal(what, 'the confidence level must lie in 0..1');
  }
}

void _checkSpread(String what, double standardDeviation) {
  if (standardDeviation <= 0 || !standardDeviation.isFinite) {
    throw StatsRefusal(
      what,
      'needs a positive, finite standard deviation to plan against',
    );
  }
}

void _checkProportion(String what, double p) {
  if (p <= 0 || p >= 1) {
    throw StatsRefusal(
      what,
      'a proportion of exactly 0 or 1 has no spread for the normal '
      'approximation to work with',
    );
  }
}

void _checkDifference(String what, double difference) {
  if (difference == 0 || !difference.isFinite) {
    throw StatsRefusal(
      what,
      'a difference of zero cannot be detected by any sample size',
    );
  }
}
