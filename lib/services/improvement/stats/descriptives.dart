part of 'stats.dart';

/// The univariate summary of one sample, computed in a single pass.
///
/// Variance comes from Welford's online algorithm and the third and fourth
/// moments from its higher-order extension. The textbook shortcut
/// (Σx² − (Σx)²/n) is not a style choice we declined: on measurement data —
/// a tight spread around a large value, which is what a process produces —
/// it subtracts two nearly equal large numbers and can return a *negative*
/// variance. NIST publishes datasets (`NumAcc*`) built to expose exactly that,
/// and they are in the test suite.
class Descriptives {
  const Descriptives._({
    required this.count,
    required this.mean,
    required this.sumOfSquaredDeviations,
    required this.thirdMoment,
    required this.fourthMoment,
    required this.minimum,
    required this.maximum,
    required this.sorted,
  });

  /// Summarises [values] in one pass. Refuses an empty sample.
  factory Descriptives.of(Iterable<double> values) {
    final List<double> data = List<double>.of(values);
    _requireAtLeast('descriptive summary', 'observations', data.length, 1);

    int n = 0;
    double mean = 0;
    double m2 = 0;
    double m3 = 0;
    double m4 = 0;
    double minimum = data.first;
    double maximum = data.first;

    for (final double x in data) {
      if (x.isNaN || x.isInfinite) {
        throw StatsRefusal(
          'descriptive summary',
          'the sample contains a value that is not a finite number',
        );
      }
      final int previous = n;
      n += 1;
      final double delta = x - mean;
      final double deltaOverN = delta / n;
      final double deltaOverNSquared = deltaOverN * deltaOverN;
      final double term = delta * deltaOverN * previous;
      mean += deltaOverN;
      m4 +=
          term * deltaOverNSquared * (n * n - 3 * n + 3) +
          6 * deltaOverNSquared * m2 -
          4 * deltaOverN * m3;
      m3 += term * deltaOverN * (n - 2) - 3 * deltaOverN * m2;
      m2 += term;
      if (x < minimum) minimum = x;
      if (x > maximum) maximum = x;
    }

    return Descriptives._(
      count: n,
      mean: mean,
      sumOfSquaredDeviations: m2,
      thirdMoment: m3,
      fourthMoment: m4,
      minimum: minimum,
      maximum: maximum,
      sorted: List<double>.unmodifiable(data..sort()),
    );
  }

  /// Number of observations.
  final int count;

  /// Arithmetic mean.
  final double mean;

  /// Σ(x − x̄)², the Welford accumulator. Public because the pooled estimates
  /// in [inference] add these up rather than re-reading the samples.
  final double sumOfSquaredDeviations;

  /// Σ(x − x̄)³.
  final double thirdMoment;

  /// Σ(x − x̄)⁴.
  final double fourthMoment;

  final double minimum;
  final double maximum;

  /// The sample in ascending order.
  final List<double> sorted;

  /// Sample variance, divisor n − 1. Refuses a single observation: one point
  /// has no spread, and returning 0 would read as "perfectly consistent".
  double get variance {
    _requireAtLeast('sample variance', 'observations', count, 2);
    return sumOfSquaredDeviations / (count - 1);
  }

  /// Sample standard deviation, divisor n − 1.
  double get standardDeviation => math.sqrt(variance);

  /// Standard error of the mean.
  double get standardError => standardDeviation / math.sqrt(count);

  /// maximum − minimum.
  double get range => maximum - minimum;

  /// The median (the 0.5 hinge).
  double get median => _medianOf(sorted, 0, sorted.length);

  /// The lower hinge, Q1.
  ///
  /// **Tukey's hinge method**, stated because there is no single definition of
  /// a quartile and two tools disagreeing on Q1 is a familiar waste of an
  /// afternoon. The sample is split at the median; when n is odd the median
  /// *belongs to both halves*, and Q1 and Q3 are the medians of those halves.
  /// For 1..9 that gives Q1 = 3 and Q3 = 7. This is the convention behind the
  /// box plot as Tukey drew it, and the one a box-and-whisker slide will show.
  double get firstQuartile {
    final int n = sorted.length;
    final int upperOfLowerHalf = n.isOdd ? n ~/ 2 + 1 : n ~/ 2;
    return _medianOf(sorted, 0, upperOfLowerHalf);
  }

  /// The upper hinge, Q3. See [firstQuartile] for the method.
  double get thirdQuartile =>
      _medianOf(sorted, sorted.length ~/ 2, sorted.length);

  /// Q3 − Q1.
  double get interquartileRange => thirdQuartile - firstQuartile;

  /// Moment coefficient of skewness, g1 = m3 / m2^(3/2).
  ///
  /// The biased (population-moment) form, not the bias-corrected G1. Which one
  /// is meant is stated because they differ by a factor that matters at the
  /// sample sizes an improvement project actually collects.
  double get skewness {
    _requireAtLeast('skewness', 'observations', count, 3);
    final double m2 = sumOfSquaredDeviations / count;
    if (m2 == 0) {
      throw const StatsRefusal('skewness', 'every observation is identical');
    }
    final double m3 = thirdMoment / count;
    return m3 / math.pow(m2, 1.5);
  }

  /// Excess kurtosis, g2 = m4 / m2² − 3. Zero for a normal distribution.
  double get excessKurtosis {
    _requireAtLeast('kurtosis', 'observations', count, 4);
    final double m2 = sumOfSquaredDeviations / count;
    if (m2 == 0) {
      throw const StatsRefusal('kurtosis', 'every observation is identical');
    }
    final double m4 = fourthMoment / count;
    return m4 / (m2 * m2) - 3;
  }
}

/// The median of `values[from..to)`, which must already be sorted.
double _medianOf(List<double> values, int from, int to) {
  final int n = to - from;
  if (n <= 0) {
    throw const StatsRefusal('median', 'the half is empty');
  }
  final int middle = from + n ~/ 2;
  return n.isOdd ? values[middle] : 0.5 * (values[middle - 1] + values[middle]);
}

/// Arithmetic mean of [values].
double mean(Iterable<double> values) => Descriptives.of(values).mean;

/// Median of [values].
double median(Iterable<double> values) => Descriptives.of(values).median;

/// Sample standard deviation of [values], divisor n − 1.
double standardDeviation(Iterable<double> values) =>
    Descriptives.of(values).standardDeviation;

/// The successive absolute differences |xᵢ − xᵢ₋₁|, the moving ranges of span
/// two that an individuals chart and its within-subgroup sigma rest on.
List<double> movingRanges(List<double> values, {int span = 2}) {
  if (span < 2) {
    throw StatsRefusal('moving ranges', 'span must be at least 2, got $span');
  }
  _requireAtLeast('moving ranges', 'observations', values.length, span);
  return <double>[
    for (int i = span - 1; i < values.length; i++)
      _spanRange(values, i - span + 1, i + 1),
  ];
}

double _spanRange(List<double> values, int from, int to) {
  double lo = values[from];
  double hi = values[from];
  for (int i = from + 1; i < to; i++) {
    if (values[i] < lo) lo = values[i];
    if (values[i] > hi) hi = values[i];
  }
  return hi - lo;
}
