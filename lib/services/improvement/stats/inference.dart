part of 'stats.dart';

// Hypothesis tests. Every result carries the statistic, its degrees of
// freedom and the p-value together, because a p-value on its own cannot be
// checked by anyone and is the single easiest number in a report to get wrong.
//
// No test here decides anything. There is no `significant` boolean and no
// built-in α: choosing the threshold is the analyst's job, and a library that
// picks 0.05 for them is quietly making a methodological decision on their
// behalf.

/// A two-sided interval and the confidence attached to it.
class ConfidenceInterval {
  const ConfidenceInterval({
    required this.low,
    required this.high,
    required this.level,
  });

  final double low;
  final double high;

  /// e.g. 0.95.
  final double level;

  double get width => high - low;

  /// Whether [value] lies inside — the interval's version of a test.
  bool contains(double value) => value >= low && value <= high;
}

/// The outcome of a t test.
class TTestResult {
  const TTestResult({
    required this.statistic,
    required this.degreesOfFreedom,
    required this.estimate,
    required this.standardError,
    required this.confidenceInterval,
  });

  /// The t statistic.
  final double statistic;

  final double degreesOfFreedom;

  /// What was estimated: a mean, or a difference of means.
  final double estimate;

  final double standardError;

  final ConfidenceInterval confidenceInterval;

  /// Two-sided p-value.
  double get pValue =>
      StudentTDistribution(degreesOfFreedom).twoSidedP(statistic);

  /// One-sided p-value in the direction the statistic points.
  double get oneSidedPValue => pValue / 2;
}

ConfidenceInterval _tInterval(
  double estimate,
  double standardError,
  double df,
  double level,
) {
  if (level <= 0 || level >= 1) {
    throw StatsRefusal('confidence interval', 'the level must lie in 0..1');
  }
  final double critical = StudentTDistribution(
    df,
  ).quantile(1 - (1 - level) / 2);
  return ConfidenceInterval(
    low: estimate - critical * standardError,
    high: estimate + critical * standardError,
    level: level,
  );
}

/// One-sample t test of the mean of [values] against [hypothesizedMean].
TTestResult oneSampleT(
  List<double> values, {
  double hypothesizedMean = 0,
  double confidenceLevel = 0.95,
}) {
  _requireAtLeast('one-sample t test', 'observations', values.length, 2);
  final Descriptives s = Descriptives.of(values);
  final double se = s.standardError;
  if (se == 0) {
    throw const StatsRefusal(
      'one-sample t test',
      'every observation is identical, so the standard error is zero',
    );
  }
  final double df = (s.count - 1).toDouble();
  return TTestResult(
    statistic: (s.mean - hypothesizedMean) / se,
    degreesOfFreedom: df,
    estimate: s.mean,
    standardError: se,
    confidenceInterval: _tInterval(s.mean, se, df, confidenceLevel),
  );
}

/// Paired t test — the same units measured twice.
///
/// A separate function rather than a flag on [twoSampleT] because the mistake
/// it prevents is the common one: analysing before/after measurements of the
/// same twenty parts as two independent samples throws away the pairing, which
/// is the whole reason the study was designed that way.
TTestResult pairedT(
  List<double> before,
  List<double> after, {
  double confidenceLevel = 0.95,
}) {
  if (before.length != after.length) {
    throw StatsRefusal(
      'paired t test',
      'got ${before.length} and ${after.length} observations; a pair needs '
          'both halves',
    );
  }
  return oneSampleT(<double>[
    for (int i = 0; i < before.length; i++) after[i] - before[i],
  ], confidenceLevel: confidenceLevel);
}

/// Two-sample t test of the difference `mean(b) − mean(a)`.
///
/// Welch's version by default: it does not assume the two spreads are equal,
/// and when they happen to be, it costs almost nothing. Set [pooled] to get
/// Student's original.
TTestResult twoSampleT(
  List<double> a,
  List<double> b, {
  bool pooled = false,
  double confidenceLevel = 0.95,
}) {
  _requireAtLeast(
    'two-sample t test',
    'observations in the first sample',
    a.length,
    2,
  );
  _requireAtLeast(
    'two-sample t test',
    'observations in the second sample',
    b.length,
    2,
  );
  final Descriptives sa = Descriptives.of(a);
  final Descriptives sb = Descriptives.of(b);
  final double va = sa.variance;
  final double vb = sb.variance;
  final double na = sa.count.toDouble();
  final double nb = sb.count.toDouble();
  final double difference = sb.mean - sa.mean;

  final double se;
  final double df;
  if (pooled) {
    final double pooledVariance =
        (sa.sumOfSquaredDeviations + sb.sumOfSquaredDeviations) / (na + nb - 2);
    se = math.sqrt(pooledVariance * (1 / na + 1 / nb));
    df = na + nb - 2;
  } else {
    final double termA = va / na;
    final double termB = vb / nb;
    se = math.sqrt(termA + termB);
    // Welch–Satterthwaite.
    df =
        (termA + termB) *
        (termA + termB) /
        (termA * termA / (na - 1) + termB * termB / (nb - 1));
  }
  if (se == 0) {
    throw const StatsRefusal(
      'two-sample t test',
      'both samples are constant, so the standard error is zero',
    );
  }
  return TTestResult(
    statistic: difference / se,
    degreesOfFreedom: df,
    estimate: difference,
    standardError: se,
    confidenceInterval: _tInterval(difference, se, df, confidenceLevel),
  );
}

/// The outcome of an F-ratio test — one-way ANOVA and Levene both report this.
class AnovaResult {
  const AnovaResult({
    required this.betweenSumOfSquares,
    required this.withinSumOfSquares,
    required this.numeratorDf,
    required this.denominatorDf,
    required this.groupCount,
    required this.totalCount,
  });

  final double betweenSumOfSquares;
  final double withinSumOfSquares;
  final double numeratorDf;
  final double denominatorDf;
  final int groupCount;
  final int totalCount;

  double get totalSumOfSquares => betweenSumOfSquares + withinSumOfSquares;

  double get betweenMeanSquare => betweenSumOfSquares / numeratorDf;

  double get withinMeanSquare => withinSumOfSquares / denominatorDf;

  double get fStatistic => betweenMeanSquare / withinMeanSquare;

  double get pValue =>
      FDistribution(numeratorDf, denominatorDf).survival(fStatistic);

  /// The share of the total variation the grouping accounts for.
  double get etaSquared => betweenSumOfSquares / totalSumOfSquares;
}

/// One-way ANOVA over [groups], which need not be the same size.
AnovaResult oneWayAnova(List<List<double>> groups) {
  const String what = 'one-way ANOVA';
  _requireAtLeast(what, 'groups', groups.length, 2);
  int total = 0;
  double grandSum = 0;
  for (final List<double> group in groups) {
    _requireAtLeast(what, 'observations per group', group.length, 2);
    total += group.length;
    for (final double x in group) {
      grandSum += x;
    }
  }
  final double grandMean = grandSum / total;

  double between = 0;
  double within = 0;
  for (final List<double> group in groups) {
    final Descriptives s = Descriptives.of(group);
    final double delta = s.mean - grandMean;
    between += group.length * delta * delta;
    within += s.sumOfSquaredDeviations;
  }
  final double denominatorDf = (total - groups.length).toDouble();
  if (within <= 0) {
    throw const StatsRefusal(
      what,
      'there is no variation within the groups, so the F ratio is undefined',
    );
  }
  return AnovaResult(
    betweenSumOfSquares: between,
    withinSumOfSquares: within,
    numeratorDf: (groups.length - 1).toDouble(),
    denominatorDf: denominatorDf,
    groupCount: groups.length,
    totalCount: total,
  );
}

/// Which centre Levene's test measures spread around.
enum LeveneCentre {
  /// The median — Brown & Forsythe's variant, and the default: it holds its
  /// nerve when the data is skewed, which is when a spread test is usually
  /// being run in the first place.
  median,

  /// The mean — Levene's original.
  mean,
}

/// Levene's test for equal spread across [groups].
AnovaResult leveneTest(
  List<List<double>> groups, {
  LeveneCentre centre = LeveneCentre.median,
}) {
  _requireAtLeast("Levene's test", 'groups', groups.length, 2);
  final List<List<double>> deviations = <List<double>>[
    for (final List<double> group in groups)
      () {
        final Descriptives s = Descriptives.of(group);
        final double c = centre == LeveneCentre.median ? s.median : s.mean;
        return <double>[for (final double x in group) (x - c).abs()];
      }(),
  ];
  return oneWayAnova(deviations);
}

/// The outcome of a chi-squared test.
class ChiSquaredResult {
  const ChiSquaredResult({
    required this.statistic,
    required this.degreesOfFreedom,
    required this.smallestExpected,
  });

  final double statistic;
  final double degreesOfFreedom;

  /// The smallest expected count. Reported because the chi-squared
  /// approximation is the thing that breaks first: below about five, the
  /// p-value is not to be trusted, and that fact belongs next to the number
  /// rather than in a footnote nobody reads.
  final double smallestExpected;

  double get pValue =>
      ChiSquaredDistribution(degreesOfFreedom).survival(statistic);

  /// Whether every expected count reaches the conventional floor of five.
  bool get approximationHolds => smallestExpected >= 5;
}

/// Chi-squared goodness of fit of [observed] against [expected] counts.
ChiSquaredResult chiSquaredGoodnessOfFit(
  List<int> observed,
  List<double> expected, {
  int estimatedParameters = 0,
}) {
  const String what = 'chi-squared goodness of fit';
  _requireAtLeast(what, 'categories', observed.length, 2);
  if (observed.length != expected.length) {
    throw StatsRefusal(
      what,
      'got ${observed.length} observed and ${expected.length} expected counts',
    );
  }
  double statistic = 0;
  double smallest = double.infinity;
  for (int i = 0; i < observed.length; i++) {
    if (expected[i] <= 0) {
      throw StatsRefusal(
        what,
        'category ${i + 1} expects no observations at all, so its '
        'contribution is undefined',
      );
    }
    final double delta = observed[i] - expected[i];
    statistic += delta * delta / expected[i];
    if (expected[i] < smallest) smallest = expected[i];
  }
  final double df = (observed.length - 1 - estimatedParameters).toDouble();
  if (df < 1) {
    throw StatsRefusal(what, 'no degrees of freedom are left');
  }
  return ChiSquaredResult(
    statistic: statistic,
    degreesOfFreedom: df,
    smallestExpected: smallest,
  );
}

/// Chi-squared test of independence over a contingency [table] (rows first).
ChiSquaredResult chiSquaredIndependence(List<List<int>> table) {
  const String what = 'chi-squared test of independence';
  _requireAtLeast(what, 'rows', table.length, 2);
  final int columns = table.first.length;
  _requireAtLeast(what, 'columns', columns, 2);
  final List<double> rowTotals = <double>[];
  final List<double> columnTotals = List<double>.filled(columns, 0);
  double grandTotal = 0;
  for (final List<int> row in table) {
    if (row.length != columns) {
      throw StatsRefusal(what, 'the rows are not all the same length');
    }
    double rowTotal = 0;
    for (int j = 0; j < columns; j++) {
      if (row[j] < 0) {
        throw StatsRefusal(what, 'the table holds a negative count');
      }
      rowTotal += row[j];
      columnTotals[j] += row[j];
    }
    rowTotals.add(rowTotal);
    grandTotal += rowTotal;
  }
  if (grandTotal <= 0) {
    throw StatsRefusal(what, 'the table is empty');
  }

  double statistic = 0;
  double smallest = double.infinity;
  for (int i = 0; i < table.length; i++) {
    for (int j = 0; j < columns; j++) {
      final double expected = rowTotals[i] * columnTotals[j] / grandTotal;
      if (expected <= 0) {
        throw StatsRefusal(
          what,
          'row ${i + 1} or column ${j + 1} is entirely empty',
        );
      }
      final double delta = table[i][j] - expected;
      statistic += delta * delta / expected;
      if (expected < smallest) smallest = expected;
    }
  }
  return ChiSquaredResult(
    statistic: statistic,
    degreesOfFreedom: ((table.length - 1) * (columns - 1)).toDouble(),
    smallestExpected: smallest,
  );
}

/// The outcome of a z test on proportions.
class ProportionTestResult {
  const ProportionTestResult({
    required this.statistic,
    required this.estimate,
    required this.standardError,
    required this.confidenceInterval,
  });

  final double statistic;

  /// The proportion, or the difference between two of them.
  final double estimate;

  final double standardError;
  final ConfidenceInterval confidenceInterval;

  /// Two-sided p-value from the normal approximation.
  double get pValue => 2 * (1 - standardNormalCdf(statistic.abs()));
}

ConfidenceInterval _zInterval(
  double estimate,
  double standardError,
  double level,
) {
  final double critical = standardNormalQuantile(1 - (1 - level) / 2);
  return ConfidenceInterval(
    low: estimate - critical * standardError,
    high: estimate + critical * standardError,
    level: level,
  );
}

/// One-proportion z test of [successes] out of [trials] against [hypothesized].
///
/// The interval reported is Wilson's, not the textbook Wald interval: Wald
/// runs off the end of 0..1 and collapses to zero width when nothing failed,
/// which is exactly the situation an improvement project reaches when it is
/// going well.
ProportionTestResult oneProportionZ(
  int successes,
  int trials, {
  double hypothesized = 0.5,
  double confidenceLevel = 0.95,
}) {
  const String what = 'one-proportion z test';
  _requireAtLeast(what, 'trials', trials, 1);
  if (successes < 0 || successes > trials) {
    throw StatsRefusal(what, 'the successes do not fit in the trials');
  }
  if (hypothesized <= 0 || hypothesized >= 1) {
    throw StatsRefusal(what, 'the hypothesised proportion must lie in 0..1');
  }
  final double n = trials.toDouble();
  final double observed = successes / n;
  final double se = math.sqrt(hypothesized * (1 - hypothesized) / n);
  final double critical = standardNormalQuantile(1 - (1 - confidenceLevel) / 2);
  final double zz = critical * critical;
  final double denominator = 1 + zz / n;
  final double centre = (observed + zz / (2 * n)) / denominator;
  final double halfWidth =
      critical *
      math.sqrt(observed * (1 - observed) / n + zz / (4 * n * n)) /
      denominator;
  return ProportionTestResult(
    statistic: (observed - hypothesized) / se,
    estimate: observed,
    standardError: se,
    confidenceInterval: ConfidenceInterval(
      low: math.max(0, centre - halfWidth),
      high: math.min(1, centre + halfWidth),
      level: confidenceLevel,
    ),
  );
}

/// Two-proportion z test of `p2 − p1`, pooled under the null.
ProportionTestResult twoProportionZ(
  int successes1,
  int trials1,
  int successes2,
  int trials2, {
  double confidenceLevel = 0.95,
}) {
  const String what = 'two-proportion z test';
  _requireAtLeast(what, 'trials in the first group', trials1, 1);
  _requireAtLeast(what, 'trials in the second group', trials2, 1);
  final double n1 = trials1.toDouble();
  final double n2 = trials2.toDouble();
  final double p1 = successes1 / n1;
  final double p2 = successes2 / n2;
  final double pooled = (successes1 + successes2) / (n1 + n2);
  final double pooledSe = math.sqrt(pooled * (1 - pooled) * (1 / n1 + 1 / n2));
  if (pooledSe == 0) {
    throw StatsRefusal(
      what,
      'both groups are entirely success or entirely failure, so the test '
      'has nothing to compare',
    );
  }
  // The test pools under the null; the interval must not, or it would report
  // a spread that assumes the answer.
  final double unpooledSe = math.sqrt(p1 * (1 - p1) / n1 + p2 * (1 - p2) / n2);
  return ProportionTestResult(
    statistic: (p2 - p1) / pooledSe,
    estimate: p2 - p1,
    standardError: pooledSe,
    confidenceInterval: _zInterval(p2 - p1, unpooledSe, confidenceLevel),
  );
}

/// The outcome of an F test comparing two variances.
class VarianceRatioResult {
  const VarianceRatioResult({
    required this.statistic,
    required this.numeratorDf,
    required this.denominatorDf,
  });

  final double statistic;
  final double numeratorDf;
  final double denominatorDf;

  /// Two-sided p-value.
  double get pValue {
    final FDistribution f = FDistribution(numeratorDf, denominatorDf);
    final double upper = f.survival(statistic);
    return 2 * math.min(upper, 1 - upper);
  }
}

/// F test of `var(a) / var(b)`.
///
/// Kept next to [leveneTest] and used far less: the F test assumes both
/// samples are normal and is badly misled when they are not, which is why
/// Levene is the default recommendation for comparing spreads.
VarianceRatioResult fTestForVariances(List<double> a, List<double> b) {
  const String what = 'F test for equal variances';
  _requireAtLeast(what, 'observations in the first sample', a.length, 2);
  _requireAtLeast(what, 'observations in the second sample', b.length, 2);
  final Descriptives sa = Descriptives.of(a);
  final Descriptives sb = Descriptives.of(b);
  if (sb.variance == 0) {
    throw StatsRefusal(what, 'the second sample has no variation');
  }
  return VarianceRatioResult(
    statistic: sa.variance / sb.variance,
    numeratorDf: (sa.count - 1).toDouble(),
    denominatorDf: (sb.count - 1).toDouble(),
  );
}

/// The Anderson-Darling normality verdict.
class AndersonDarlingResult {
  const AndersonDarlingResult({
    required this.statistic,
    required this.adjustedStatistic,
    required this.pValue,
    required this.count,
  });

  /// A², the raw statistic.
  final double statistic;

  /// A*², adjusted for the sample size — the figure the p-value is read from.
  final double adjustedStatistic;

  final double pValue;
  final int count;

  @override
  String toString() =>
      'Anderson-Darling A² = ${statistic.toStringAsFixed(4)}, '
      'p = ${pValue.toStringAsFixed(4)} (n = $count)';
}

/// Anderson-Darling test of [values] against a normal distribution whose mean
/// and spread are estimated from the same data.
///
/// The p-value uses D'Agostino & Stephens' approximation for the
/// estimated-parameter case. It is the right test for capability work because
/// it weights the tails, and the tails are where a Cpk lives.
AndersonDarlingResult andersonDarlingNormality(List<double> values) {
  const String what = 'Anderson-Darling normality test';
  // Below eight the published p-value approximation is not stated to hold, and
  // a normality verdict that cannot be trusted is worse than none: it gets
  // quoted as clearance.
  _requireAtLeast(what, 'observations', values.length, 8);
  final Descriptives s = Descriptives.of(values);
  if (s.standardDeviation <= 0) {
    throw const StatsRefusal(
      what,
      'every observation is identical, so there is no distribution to test',
    );
  }
  final int n = s.count;
  double sum = 0;
  for (int i = 0; i < n; i++) {
    final double lower = _clampProbability(
      standardNormalCdf((s.sorted[i] - s.mean) / s.standardDeviation),
    );
    final double upper = _clampProbability(
      standardNormalCdf((s.sorted[n - 1 - i] - s.mean) / s.standardDeviation),
    );
    sum += (2 * (i + 1) - 1) * (math.log(lower) + math.log(1 - upper));
  }
  final double a2 = -n - sum / n;
  final double adjusted = a2 * (1 + 0.75 / n + 2.25 / (n * n));
  return AndersonDarlingResult(
    statistic: a2,
    adjustedStatistic: adjusted,
    pValue: _andersonDarlingP(adjusted),
    count: n,
  );
}

/// Keeps a probability off 0 and 1 so its logarithm stays finite. An
/// observation far into the tail is a real observation, not an error.
double _clampProbability(double p) => math.min(math.max(p, 1e-300), 1 - 1e-16);

/// D'Agostino & Stephens' piecewise approximation of the A*² p-value.
double _andersonDarlingP(double adjusted) {
  final double a = adjusted;
  final double aa = a * a;
  if (a >= 0.6) {
    return math.exp(1.2937 - 5.709 * a + 0.0186 * aa);
  }
  if (a > 0.34) {
    return math.exp(0.9177 - 4.279 * a - 1.38 * aa);
  }
  if (a > 0.2) {
    return 1 - math.exp(-8.318 + 42.796 * a - 59.938 * aa);
  }
  return 1 - math.exp(-13.436 + 101.14 * a - 223.73 * aa);
}
