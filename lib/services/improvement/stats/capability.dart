part of 'stats.dart';

// Capability, and the three habits that make published capability figures
// untrustworthy — each refused here.
//
//   * Cpk on visibly non-normal data. Every result carries the
//     Anderson-Darling verdict; there is no way to obtain one without the
//     other, because a caller who has to ask for the normality test is a
//     caller who will forget.
//   * Cp/Cpk (within-subgroup, "what the process could do") quietly reported
//     as Pp/Ppk (overall, "what it did"). Both are computed, both are named.
//   * A sigma level with an unstated 1.5σ shift. The shift is off by default
//     and every [SigmaLevel] states which convention produced it.

/// Whether a sigma level includes the conventional 1.5σ shift.
///
/// The shift is an industry convention for allowing long-term drift, not a
/// property of the data, and the field is genuinely split on it. OciDeck
/// therefore takes no position beyond this: it is **off unless asked for**,
/// and it is always named.
enum SigmaShiftConvention {
  /// No shift: the sigma level of the distribution as measured.
  none('no 1.5σ shift'),

  /// The conventional 1.5σ shift added, so that 3.4 DPMO reads as "six sigma".
  shifted('with the conventional 1.5σ shift');

  const SigmaShiftConvention(this.statement);

  /// How the convention should be named next to the number. Data, not a
  /// `d(...)` string — the UI layer decides how to word and translate it.
  final String statement;

  /// What the convention adds to the standard-normal quantile.
  double get offset => this == SigmaShiftConvention.shifted ? 1.5 : 0;
}

/// A sigma level that cannot be quoted without its convention.
class SigmaLevel {
  const SigmaLevel(this.value, this.convention);

  final double value;
  final SigmaShiftConvention convention;

  @override
  String toString() => '${value.toStringAsFixed(2)}σ (${convention.statement})';
}

/// Defects per million opportunities from a first-pass yield.
double dpmoFromYield(double firstPassYield) {
  if (firstPassYield < 0 || firstPassYield > 1) {
    throw StatsRefusal('DPMO', 'a yield outside 0..1 was given');
  }
  return (1 - firstPassYield) * 1e6;
}

/// First-pass yield from defects per million opportunities.
double yieldFromDpmo(double dpmo) {
  if (dpmo < 0 || dpmo > 1e6) {
    throw StatsRefusal('yield', 'DPMO outside 0..1000000 was given');
  }
  return 1 - dpmo / 1e6;
}

/// The sigma level a yield corresponds to.
SigmaLevel sigmaLevelFromYield(
  double firstPassYield, {
  SigmaShiftConvention convention = SigmaShiftConvention.none,
}) {
  if (firstPassYield <= 0 || firstPassYield >= 1) {
    throw StatsRefusal(
      'sigma level',
      'a yield of exactly 0 or 1 has no finite sigma level; report the '
          'sample size instead',
    );
  }
  return SigmaLevel(
    standardNormalQuantile(firstPassYield) + convention.offset,
    convention,
  );
}

/// The yield a sigma level corresponds to — the inverse of
/// [sigmaLevelFromYield], in the same convention.
double yieldFromSigmaLevel(SigmaLevel level) =>
    standardNormalCdf(level.value - level.convention.offset);

/// The sigma level a DPMO figure corresponds to.
SigmaLevel sigmaLevelFromDpmo(
  double dpmo, {
  SigmaShiftConvention convention = SigmaShiftConvention.none,
}) => sigmaLevelFromYield(yieldFromDpmo(dpmo), convention: convention);

/// The DPMO a sigma level corresponds to.
double dpmoFromSigmaLevel(SigmaLevel level) =>
    dpmoFromYield(yieldFromSigmaLevel(level));

/// The rolled throughput yield of a chain of steps: the chance a unit passes
/// every step untouched. The number that makes a "99% at each of twenty steps"
/// process look the way it actually feels.
double rolledThroughputYield(Iterable<double> stepYields) {
  final List<double> steps = List<double>.of(stepYields);
  _requireAtLeast('rolled throughput yield', 'steps', steps.length, 1);
  double product = 1;
  for (final double y in steps) {
    if (y < 0 || y > 1) {
      throw StatsRefusal('rolled throughput yield', 'a step yield left 0..1');
    }
    product *= y;
  }
  return product;
}

/// Capability and performance for one measured characteristic.
///
/// "Within" (Cp, Cpk) uses the short-term spread the process shows between
/// consecutive units; "overall" (Pp, Ppk) uses the total spread of everything
/// measured. The gap between the two pairs *is* the drift, and reporting only
/// one of them is how that drift disappears from a report.
class CapabilityAnalysis {
  const CapabilityAnalysis._({
    required this.count,
    required this.mean,
    required this.withinSigma,
    required this.overallSigma,
    required this.lowerSpec,
    required this.upperSpec,
    required this.target,
    required this.normality,
    required this.shiftConvention,
    required this.observedOutOfSpec,
  });

  /// Analyses [values] against the spec limits given.
  ///
  /// At least one spec limit is required — capability against nothing is not a
  /// number. [withinSigma] should come from the control chart that established
  /// stability (`ControlChart.withinSubgroupSigma`); when it is omitted the
  /// short-term spread is estimated from the moving ranges of the sequence as
  /// given, which assumes the values are in the order they were produced.
  static CapabilityAnalysis of(
    List<double> values, {
    double? lowerSpec,
    double? upperSpec,
    double? target,
    double? withinSigma,
    SigmaShiftConvention shiftConvention = SigmaShiftConvention.none,
  }) {
    const String what = 'capability';
    if (lowerSpec == null && upperSpec == null) {
      throw const StatsRefusal(
        what,
        'no specification limit was given, so there is nothing to be capable '
        'of',
      );
    }
    if (lowerSpec != null && upperSpec != null && lowerSpec >= upperSpec) {
      throw const StatsRefusal(
        what,
        'the lower specification limit is not below the upper one',
      );
    }
    // Eight is where the Anderson-Darling p-value approximation is stated to
    // hold, and capability without a normality verdict is exactly the
    // malpractice this class exists to prevent — so eight is the floor for
    // both, together.
    _requireAtLeast(what, 'observations', values.length, 8);

    final Descriptives summary = Descriptives.of(values);
    // `Descriptives.of(...).mean` and not the top-level `mean(...)`: this class
    // has a field of that name, which wins the lookup even here.
    final double within =
        withinSigma ??
        Descriptives.of(movingRanges(values)).mean /
            ControlChartConstants.forSubgroupSize(2).d2;
    if (within <= 0 || summary.standardDeviation <= 0) {
      throw const StatsRefusal(
        what,
        'the spread is zero — every observation is identical, so no '
        'capability index is defined',
      );
    }

    int outOfSpec = 0;
    for (final double x in values) {
      if ((lowerSpec != null && x < lowerSpec) ||
          (upperSpec != null && x > upperSpec)) {
        outOfSpec++;
      }
    }

    return CapabilityAnalysis._(
      count: summary.count,
      mean: summary.mean,
      withinSigma: within,
      overallSigma: summary.standardDeviation,
      lowerSpec: lowerSpec,
      upperSpec: upperSpec,
      target: target,
      normality: andersonDarlingNormality(values),
      shiftConvention: shiftConvention,
      observedOutOfSpec: outOfSpec,
    );
  }

  final int count;
  final double mean;

  /// Short-term spread — within subgroups, or from moving ranges.
  final double withinSigma;

  /// Total spread of everything measured.
  final double overallSigma;

  final double? lowerSpec;
  final double? upperSpec;
  final double? target;

  /// The normality verdict that travels with every index below. Not optional,
  /// and not something a caller has to remember to ask for.
  final AndersonDarlingResult normality;

  final SigmaShiftConvention shiftConvention;

  /// How many of the measured values actually fell outside the spec.
  final int observedOutOfSpec;

  /// Whether the sample is large enough for the indices to be worth much.
  ///
  /// Below about 25 observations the confidence interval around Cpk is wide
  /// enough to cover two different verdicts, so the figure is reported with
  /// this flag rather than withheld — the number is not wrong, it is just not
  /// yet worth arguing about.
  bool get isSmallSample => count < 25;

  /// Whether the normality test rejects at the 5% level. When true, every
  /// index below is being read off a model the data does not fit.
  bool get normalityRejected => normality.pValue < 0.05;

  /// Cp — the spread the specification allows against the spread the process
  /// has, ignoring where the process is centred. Needs both limits.
  double? get cp => _twoSided(withinSigma);

  /// Pp — Cp with the overall spread.
  double? get pp => _twoSided(overallSigma);

  /// CPU — capability against the upper limit alone.
  double? get cpu =>
      upperSpec == null ? null : (upperSpec! - mean) / (3 * withinSigma);

  /// CPL — capability against the lower limit alone.
  double? get cpl =>
      lowerSpec == null ? null : (mean - lowerSpec!) / (3 * withinSigma);

  /// PPU — [cpu] with the overall spread.
  double? get ppu =>
      upperSpec == null ? null : (upperSpec! - mean) / (3 * overallSigma);

  /// PPL — [cpl] with the overall spread.
  double? get ppl =>
      lowerSpec == null ? null : (mean - lowerSpec!) / (3 * overallSigma);

  /// Cpk — the worse of [cpu] and [cpl], so off-centring counts against you.
  double get cpk => _worst(cpu, cpl);

  /// Ppk — Cpk with the overall spread.
  double get ppk => _worst(ppu, ppl);

  /// Cpm — Taguchi's index, which penalises distance from the target rather
  /// than only distance from the nearest limit. Needs both limits and a target.
  double? get cpm {
    final double? l = lowerSpec;
    final double? u = upperSpec;
    final double? t = target;
    if (l == null || u == null || t == null) return null;
    final double offTarget = mean - t;
    return (u - l) /
        (6 * math.sqrt(overallSigma * overallSigma + offTarget * offTarget));
  }

  /// The fraction expected outside the spec if the process really is normal
  /// with the overall spread. This is the figure the DPMO and sigma level
  /// below are derived from.
  double get expectedFractionOutOfSpec {
    final NormalDistribution fitted = NormalDistribution(
      mean: mean,
      standardDeviation: overallSigma,
    );
    double below = 0;
    double above = 0;
    if (lowerSpec != null) below = fitted.cdf(lowerSpec!);
    if (upperSpec != null) above = 1 - fitted.cdf(upperSpec!);
    return below + above;
  }

  /// Expected defects per million opportunities.
  double get dpmo => expectedFractionOutOfSpec * 1e6;

  /// The DPMO actually observed in the sample — reported next to [dpmo]
  /// because the two disagreeing is the loudest available warning that the
  /// normal model does not fit.
  double get observedDpmo => observedOutOfSpec / count * 1e6;

  /// Expected first-pass yield.
  double get expectedYield => 1 - expectedFractionOutOfSpec;

  /// The sigma level, in the convention this analysis was asked for.
  SigmaLevel get sigmaLevel =>
      sigmaLevelFromYield(expectedYield, convention: shiftConvention);

  double? _twoSided(double sigma) {
    final double? l = lowerSpec;
    final double? u = upperSpec;
    return (l == null || u == null) ? null : (u - l) / (6 * sigma);
  }

  double _worst(double? upper, double? lower) {
    if (upper != null && lower != null) return math.min(upper, lower);
    final double? single = upper ?? lower;
    if (single == null) {
      throw const StatsRefusal('Cpk', 'no specification limit was given');
    }
    return single;
  }
}
