part of 'stats.dart';

// The seven Shewhart charts an improvement project uses, and the stage
// machinery that lets limits be recomputed after a deliberate change.
//
// Two things are deliberately absent. There is no stored limit — a limit is
// always derived from the data in its stage, because a UCL that survives a
// change to the data is a lie waiting to happen. And there is no chart from
// too little data: the factor tables happily produce a number from two
// subgroups, and this refuses instead.

/// Which chart pair was built.
enum ControlChartKind {
  /// Individuals and moving range — one observation per time point.
  individualsMovingRange,

  /// X̄ and R — subgroups, spread estimated from the range.
  xBarR,

  /// X̄ and s — subgroups, spread estimated from the sample sd.
  xBarS,

  /// Fraction nonconforming.
  p,

  /// Count nonconforming, constant subgroup size.
  np,

  /// Count of nonconformities, constant area of opportunity.
  c,

  /// Nonconformities per unit, varying area of opportunity.
  u,
}

/// Where a chart recomputes its limits, and what the period is called.
///
/// A stage is the honest way to show "we changed the process here": the limits
/// before and after are computed from their own data, so the improvement is
/// visible as a step in the limits rather than smeared into one wide band.
class ControlChartStageBreak {
  const ControlChartStageBreak({required this.from, this.label = ''});

  /// Index of the first point of this stage, in the sequence as given.
  final int from;

  /// What to call the period, e.g. `'After pilot'`. Free text, never parsed.
  final String label;
}

/// One period of a series, with the limits computed from that period alone.
class ControlChartStage {
  const ControlChartStage({
    required this.label,
    required this.from,
    required this.to,
    required this.centre,
    required this.upper,
    required this.lower,
  });

  final String label;

  /// Index of the first point, inclusive.
  final int from;

  /// Index one past the last point.
  final int to;

  /// The centre line.
  final double centre;

  /// Upper limit per point in `[from, to)`. A list and not a scalar because a
  /// p or u chart with unequal subgroup sizes has a limit that steps per
  /// point — drawing one average limit there hides which points were judged
  /// against what.
  final List<double> upper;

  /// Lower limit per point in `[from, to)`.
  final List<double> lower;

  /// Whether every point in this stage is judged against the same limits.
  bool get hasConstantLimits =>
      upper.every((double u) => u == upper.first) &&
      lower.every((double l) => l == lower.first);

  /// The single upper limit, for a stage that has one.
  double get upperLimit {
    _requireConstant();
    return upper.first;
  }

  /// The single lower limit, for a stage that has one.
  double get lowerLimit {
    _requireConstant();
    return lower.first;
  }

  /// Sigma of the plotted statistic at point [index] (absolute index, not
  /// relative to [from]), read back off the limit: the zones the run rules use
  /// have to be the zones the chart draws.
  double sigmaAt(int index) => (upper[index - from] - centre) / 3;

  void _requireConstant() {
    if (!hasConstantLimits) {
      throw const StatsRefusal(
        'a single control limit',
        'this stage has limits that vary per point (unequal subgroup sizes); '
            'read them per point instead',
      );
    }
  }
}

/// One plotted series — the X chart or the R chart, not both.
class ControlChartSeries {
  const ControlChartSeries({
    required this.label,
    required this.points,
    required this.stages,
  });

  /// What is plotted: `'X'`, `'MR'`, `'R'`, `'s'`, `'p'`, `'np'`, `'c'`, `'u'`.
  final String label;

  final List<double> points;

  final List<ControlChartStage> stages;

  /// The stage point [index] belongs to.
  ControlChartStage stageAt(int index) => stages.firstWhere(
    (ControlChartStage s) => index >= s.from && index < s.to,
  );

  double centreAt(int index) => stageAt(index).centre;

  double upperAt(int index) {
    final ControlChartStage stage = stageAt(index);
    return stage.upper[index - stage.from];
  }

  double lowerAt(int index) {
    final ControlChartStage stage = stageAt(index);
    return stage.lower[index - stage.from];
  }

  double sigmaAt(int index) => stageAt(index).sigmaAt(index);

  /// The points that fall outside their own limits.
  List<int> get outOfControlPoints => <int>[
    for (int i = 0; i < points.length; i++)
      if (points[i] > upperAt(i) || points[i] < lowerAt(i)) i,
  ];
}

/// A chart pair with its limits, plus the process sigma it implies.
class ControlChart {
  const ControlChart({
    required this.kind,
    required this.series,
    required this.withinSubgroupSigma,
  });

  final ControlChartKind kind;

  /// The plotted series, location first where there are two.
  final List<ControlChartSeries> series;

  /// The short-term (within-subgroup) sigma this chart estimates, or null for
  /// the attribute charts, where the count distribution fixes the spread and
  /// there is no separate estimate to make.
  final double? withinSubgroupSigma;

  /// The location series (X, X̄, p, np, c, u).
  ControlChartSeries get primary => series.first;

  /// The dispersion series (MR, R, s), or null for an attribute chart.
  ControlChartSeries? get dispersion => series.length > 1 ? series[1] : null;

  /// Individuals and moving range from a single stream of observations.
  ///
  /// σ̂ = MR̄/d2(2). The sample standard deviation is deliberately *not* used:
  /// it absorbs the very drift the chart exists to show, and a chart whose
  /// limits widen to accommodate a trend cannot detect one.
  static ControlChart individualsMovingRange(
    List<double> values, {
    List<ControlChartStageBreak> stageBreaks = const <ControlChartStageBreak>[],
  }) {
    const String what = 'individuals/moving-range limits';
    _requireAtLeast(what, 'observations', values.length, 2);
    final List<_Range> ranges = _stageRanges(what, values.length, stageBreaks);

    final ControlChartConstants k = ControlChartConstants.forSubgroupSize(2);
    final List<double> allMovingRanges = movingRanges(values);
    final List<ControlChartStage> xStages = <ControlChartStage>[];
    final List<ControlChartStage> mrStages = <ControlChartStage>[];
    double weightedSigma = 0;
    int weight = 0;

    for (final _Range r in ranges) {
      final List<double> slice = values.sublist(r.from, r.to);
      _requireAtLeast(
        what,
        'observations in stage "${r.label}"',
        slice.length,
        2,
      );
      final List<double> mr = movingRanges(slice);
      final double meanRange = mean(mr);
      final double sigma = meanRange / k.d2;
      final double centre = mean(slice);
      xStages.add(
        _constantStage(r, centre, centre + 3 * sigma, centre - 3 * sigma),
      );
      // The MR series is one shorter than the X series, and its first point
      // belongs to the second observation; the stage offsets follow that.
      mrStages.add(
        _constantStage(
          _Range(math.max(0, r.from - 1), math.max(0, r.to - 1), r.label),
          meanRange,
          k.rangeUpperFactor * meanRange,
          k.rangeLowerFactor * meanRange,
        ),
      );
      weightedSigma += sigma * slice.length;
      weight += slice.length;
    }

    return ControlChart(
      kind: ControlChartKind.individualsMovingRange,
      withinSubgroupSigma: weightedSigma / weight,
      series: <ControlChartSeries>[
        ControlChartSeries(label: 'X', points: values, stages: xStages),
        ControlChartSeries(
          label: 'MR',
          points: allMovingRanges,
          stages: mrStages,
        ),
      ],
    );
  }

  /// X̄ and R from equally sized subgroups. σ̂ = R̄/d2(n).
  static ControlChart xBarR(
    List<List<double>> subgroups, {
    List<ControlChartStageBreak> stageBreaks = const <ControlChartStageBreak>[],
  }) => _subgroupChart(
    kind: ControlChartKind.xBarR,
    what: 'X-bar/R limits',
    subgroups: subgroups,
    dispersionLabel: 'R',
    dispersionOf: (List<double> g) => Descriptives.of(g).range,
    unbias: (ControlChartConstants k) => k.d2,
    meanFactor: (ControlChartConstants k) => k.meanFactorFromRange,
    lowerFactor: (ControlChartConstants k) => k.rangeLowerFactor,
    upperFactor: (ControlChartConstants k) => k.rangeUpperFactor,
    stageBreaks: stageBreaks,
  );

  /// X̄ and s from equally sized subgroups. σ̂ = s̄/c4(n).
  ///
  /// Preferred over [xBarR] from about n = 10 upward: the range throws away
  /// everything between the two extremes, and by then that is most of the
  /// subgroup.
  static ControlChart xBarS(
    List<List<double>> subgroups, {
    List<ControlChartStageBreak> stageBreaks = const <ControlChartStageBreak>[],
  }) => _subgroupChart(
    kind: ControlChartKind.xBarS,
    what: 'X-bar/s limits',
    subgroups: subgroups,
    dispersionLabel: 's',
    dispersionOf: (List<double> g) => Descriptives.of(g).standardDeviation,
    unbias: (ControlChartConstants k) => k.c4,
    meanFactor: (ControlChartConstants k) => k.meanFactorFromSd,
    lowerFactor: (ControlChartConstants k) => k.sdLowerFactor,
    upperFactor: (ControlChartConstants k) => k.sdUpperFactor,
    stageBreaks: stageBreaks,
  );

  /// A p chart: the fraction nonconforming, subgroup sizes may differ.
  static ControlChart p(
    List<int> nonconforming,
    List<int> subgroupSizes, {
    List<ControlChartStageBreak> stageBreaks = const <ControlChartStageBreak>[],
  }) => _attributeChart(
    kind: ControlChartKind.p,
    what: 'p-chart limits',
    label: 'p',
    counts: nonconforming,
    exposure: subgroupSizes,
    centreOf: (int c, int n) => c / n,
    // p̄ ± 3√(p̄(1−p̄)/nᵢ), and a proportion cannot leave [0, 1].
    spreadOf: (double pBar, int n) => math.sqrt(pBar * (1 - pBar) / n),
    ceiling: 1,
    stageBreaks: stageBreaks,
  );

  /// An np chart: the count nonconforming, constant subgroup size.
  static ControlChart np(
    List<int> nonconforming,
    int subgroupSize, {
    List<ControlChartStageBreak> stageBreaks = const <ControlChartStageBreak>[],
  }) {
    const String what = 'np-chart limits';
    if (subgroupSize < 1) {
      throw StatsRefusal(what, 'the subgroup size must be positive');
    }
    final List<int> sizes = List<int>.filled(
      nonconforming.length,
      subgroupSize,
    );
    return _attributeChart(
      kind: ControlChartKind.np,
      what: what,
      label: 'np',
      counts: nonconforming,
      exposure: sizes,
      centreOf: (int c, int n) => c.toDouble(),
      centreScale: (double pBar, int n) => pBar * n,
      spreadOf: (double pBar, int n) => math.sqrt(n * pBar * (1 - pBar)),
      proportionCentre: true,
      stageBreaks: stageBreaks,
    );
  }

  /// A c chart: counts of nonconformities over a constant area of opportunity.
  static ControlChart c(
    List<int> counts, {
    List<ControlChartStageBreak> stageBreaks = const <ControlChartStageBreak>[],
  }) => _attributeChart(
    kind: ControlChartKind.c,
    what: 'c-chart limits',
    label: 'c',
    counts: counts,
    exposure: List<int>.filled(counts.length, 1),
    centreOf: (int count, int n) => count.toDouble(),
    spreadOf: (double cBar, int n) => math.sqrt(cBar),
    stageBreaks: stageBreaks,
  );

  /// A u chart: nonconformities per unit, area of opportunity may differ.
  static ControlChart u(
    List<int> counts,
    List<int> unitsInspected, {
    List<ControlChartStageBreak> stageBreaks = const <ControlChartStageBreak>[],
  }) => _attributeChart(
    kind: ControlChartKind.u,
    what: 'u-chart limits',
    label: 'u',
    counts: counts,
    exposure: unitsInspected,
    centreOf: (int count, int n) => count / n,
    spreadOf: (double uBar, int n) => math.sqrt(uBar / n),
    stageBreaks: stageBreaks,
  );
}

/// A stage's index span plus its name, before any limits are known.
class _Range {
  const _Range(this.from, this.to, this.label);

  final int from;
  final int to;
  final String label;

  int get length => to - from;
}

/// Splits `[0, count)` at [breaks], validating them.
List<_Range> _stageRanges(
  String what,
  int count,
  List<ControlChartStageBreak> breaks,
) {
  if (breaks.isEmpty) {
    return <_Range>[_Range(0, count, '')];
  }
  final List<ControlChartStageBreak> sorted =
      List<ControlChartStageBreak>.of(breaks)..sort(
        (ControlChartStageBreak a, ControlChartStageBreak b) =>
            a.from.compareTo(b.from),
      );
  if (sorted.first.from != 0) {
    sorted.insert(0, const ControlChartStageBreak(from: 0));
  }
  final List<_Range> ranges = <_Range>[];
  for (int i = 0; i < sorted.length; i++) {
    final int from = sorted[i].from;
    final int to = i + 1 < sorted.length ? sorted[i + 1].from : count;
    if (from < 0 || from >= count || to <= from) {
      throw StatsRefusal(
        what,
        'stage break at $from does not start a period inside the '
        '$count point(s) given',
      );
    }
    ranges.add(_Range(from, to, sorted[i].label));
  }
  return ranges;
}

/// A stage whose limits are the same for every point in it.
ControlChartStage _constantStage(
  _Range r,
  double centre,
  double upper,
  double lower,
) => ControlChartStage(
  label: r.label,
  from: r.from,
  to: r.to,
  centre: centre,
  upper: List<double>.filled(r.length, upper),
  lower: List<double>.filled(r.length, lower),
);

/// The shared body of the X̄-R and X̄-s charts: they differ only in which
/// dispersion statistic is plotted and which factors unbias it.
ControlChart _subgroupChart({
  required ControlChartKind kind,
  required String what,
  required List<List<double>> subgroups,
  required String dispersionLabel,
  required double Function(List<double>) dispersionOf,
  required double Function(ControlChartConstants) unbias,
  required double Function(ControlChartConstants) meanFactor,
  required double Function(ControlChartConstants) lowerFactor,
  required double Function(ControlChartConstants) upperFactor,
  List<ControlChartStageBreak> stageBreaks = const <ControlChartStageBreak>[],
}) {
  _requireAtLeast(what, 'subgroups', subgroups.length, 2);
  final int size = subgroups.first.length;
  for (final List<double> group in subgroups) {
    if (group.length != size) {
      throw StatsRefusal(
        what,
        'the subgroups are not all the same size (found $size and '
        '${group.length}); unequal subgroups need their own factors per '
        'point, which this chart does not guess at',
      );
    }
  }
  final ControlChartConstants k = ControlChartConstants.forSubgroupSize(size);

  final List<double> means = <double>[
    for (final List<double> g in subgroups) mean(g),
  ];
  final List<double> spreads = <double>[
    for (final List<double> g in subgroups) dispersionOf(g),
  ];

  final List<_Range> ranges = _stageRanges(what, subgroups.length, stageBreaks);
  final List<ControlChartStage> locationStages = <ControlChartStage>[];
  final List<ControlChartStage> dispersionStages = <ControlChartStage>[];
  double weightedSigma = 0;
  int weight = 0;

  for (final _Range r in ranges) {
    _requireAtLeast(what, 'subgroups in stage "${r.label}"', r.length, 2);
    final double grandMean = mean(means.sublist(r.from, r.to));
    final double meanSpread = mean(spreads.sublist(r.from, r.to));
    locationStages.add(
      _constantStage(
        r,
        grandMean,
        grandMean + meanFactor(k) * meanSpread,
        grandMean - meanFactor(k) * meanSpread,
      ),
    );
    dispersionStages.add(
      _constantStage(
        r,
        meanSpread,
        upperFactor(k) * meanSpread,
        lowerFactor(k) * meanSpread,
      ),
    );
    weightedSigma += (meanSpread / unbias(k)) * r.length;
    weight += r.length;
  }

  return ControlChart(
    kind: kind,
    withinSubgroupSigma: weightedSigma / weight,
    series: <ControlChartSeries>[
      ControlChartSeries(label: 'X-bar', points: means, stages: locationStages),
      ControlChartSeries(
        label: dispersionLabel,
        points: spreads,
        stages: dispersionStages,
      ),
    ],
  );
}

/// The shared body of the p, np, c and u charts.
///
/// All four are one plotted statistic against a centre line and a
/// three-sigma band whose width follows from the count distribution; they
/// differ in what the statistic is and how the spread scales with the area of
/// opportunity. A lower limit below zero is clamped away, because a count
/// cannot be negative and a drawn-but-unreachable limit reads as a signal that
/// can never fire.
ControlChart _attributeChart({
  required ControlChartKind kind,
  required String what,
  required String label,
  required List<int> counts,
  required List<int> exposure,
  required double Function(int count, int exposure) centreOf,
  required double Function(double centre, int exposure) spreadOf,
  double Function(double centre, int exposure)? centreScale,
  bool proportionCentre = false,
  double? ceiling,
  List<ControlChartStageBreak> stageBreaks = const <ControlChartStageBreak>[],
}) {
  _requireAtLeast(what, 'subgroups', counts.length, 2);
  if (exposure.length != counts.length) {
    throw StatsRefusal(
      what,
      'got ${counts.length} count(s) and ${exposure.length} subgroup size(s)',
    );
  }
  for (int i = 0; i < counts.length; i++) {
    if (counts[i] < 0 || exposure[i] < 1) {
      throw StatsRefusal(
        what,
        'subgroup ${i + 1} has a negative count or an empty subgroup',
      );
    }
  }

  final List<double> points = <double>[
    for (int i = 0; i < counts.length; i++) centreOf(counts[i], exposure[i]),
  ];
  final List<_Range> ranges = _stageRanges(what, counts.length, stageBreaks);
  final List<ControlChartStage> stages = <ControlChartStage>[];

  for (final _Range r in ranges) {
    _requireAtLeast(what, 'subgroups in stage "${r.label}"', r.length, 2);
    int totalCount = 0;
    int totalExposure = 0;
    for (int i = r.from; i < r.to; i++) {
      totalCount += counts[i];
      totalExposure += exposure[i];
    }
    // The pooled rate, always computed from the totals rather than as the mean
    // of the per-point rates: a small subgroup must not count as heavily as a
    // large one.
    final double pooled = totalCount / totalExposure;
    final List<double> upper = <double>[];
    final List<double> lower = <double>[];
    double centreSum = 0;
    for (int i = r.from; i < r.to; i++) {
      final double centre = centreScale == null
          ? pooled
          : centreScale(pooled, exposure[i]);
      final double spread = spreadOf(
        proportionCentre ? pooled : centre,
        exposure[i],
      );
      double up = centre + 3 * spread;
      if (ceiling != null && up > ceiling) up = ceiling;
      upper.add(up);
      lower.add(math.max(0, centre - 3 * spread));
      centreSum += centre;
    }
    stages.add(
      ControlChartStage(
        label: r.label,
        from: r.from,
        to: r.to,
        centre: centreSum / r.length,
        upper: upper,
        lower: lower,
      ),
    );
  }

  return ControlChart(
    kind: kind,
    withinSubgroupSigma: null,
    series: <ControlChartSeries>[
      ControlChartSeries(label: label, points: points, stages: stages),
    ],
  );
}
