part of 'stats.dart';

// The control-chart factor table — the counterpart of the CVSS MacroVector
// lookup in lib/services/cvss/cvss4_lookup.dart, and treated the same way: it
// is reference data, so it is transcribed, not invented.
//
// Only d2 and d3 are stored. They are the expected value and the standard
// deviation of the relative range W = R/σ for a normal sample of size n, both
// of which come from an integral with no closed form; the published tables are
// where they live. Everything else in the classical A/B/C/D family is an
// arithmetic consequence of d2, d3 and c4, and is derived here rather than
// copied — a copied number can disagree with its own formula, and a table with
// two versions of D4 in it is worse than no table.
//
// c4 is not stored either, because unlike d2 and d3 it *does* have a closed
// form: c4(n) = sqrt(2/(n−1)) · Γ(n/2) / Γ((n−1)/2). It is computed exactly
// from [lnGamma] and checked against the published four-decimal values in the
// test suite.

/// The subgroup sizes the factor table covers.
///
/// Two is the smallest subgroup that has a range at all; twenty-five is where
/// the published tables stop, and beyond it a rational subgroup has usually
/// stopped being rational. Asking for a size outside this range is refused
/// rather than extrapolated.
const int minimumSubgroupSize = 2;
const int maximumSubgroupSize = 25;

/// d2 and d3 by subgroup size, as published (four decimals).
///
/// Four decimals and not more: the classical A2/D3/D4 tables were themselves
/// computed from these figures, so carrying more precision here would make
/// this engine disagree with every printed table in the third decimal while
/// being no more correct about the process.
const Map<int, (double d2, double d3)> _controlChartFactors = {
  2: (1.1284, 0.8525),
  3: (1.6926, 0.8884),
  4: (2.0588, 0.8798),
  5: (2.3259, 0.8641),
  6: (2.5344, 0.8480),
  7: (2.7044, 0.8332),
  8: (2.8472, 0.8198),
  9: (2.9700, 0.8078),
  10: (3.0775, 0.7971),
  11: (3.1729, 0.7873),
  12: (3.2585, 0.7785),
  13: (3.3360, 0.7704),
  14: (3.4068, 0.7630),
  15: (3.4718, 0.7562),
  16: (3.5320, 0.7499),
  17: (3.5879, 0.7441),
  18: (3.6401, 0.7386),
  19: (3.6890, 0.7335),
  20: (3.7350, 0.7287),
  21: (3.7783, 0.7242),
  22: (3.8194, 0.7199),
  23: (3.8583, 0.7159),
  24: (3.8953, 0.7121),
  25: (3.9306, 0.7084),
};

/// The unbiasing constant c4(n) = sqrt(2/(n−1)) · Γ(n/2) / Γ((n−1)/2).
///
/// The expected value of the sample standard deviation of a normal sample of
/// size n is c4·σ, so s/c4 is the unbiased estimate of σ. Computed, not
/// tabulated.
double c4For(int subgroupSize) {
  _requireSubgroupSize(subgroupSize);
  final double n = subgroupSize.toDouble();
  return math.sqrt(2 / (n - 1)) *
      math.exp(lnGamma(n / 2) - lnGamma((n - 1) / 2));
}

/// The classical control-chart factors for one subgroup size.
///
/// Field names spell the factor out; the doc comment names the symbol the
/// published tables use, because that is what a reviewer will be holding.
class ControlChartConstants {
  const ControlChartConstants._({
    required this.subgroupSize,
    required this.d2,
    required this.d3,
    required this.c4,
  });

  /// The factors for subgroup size [n], for 2 <= n <= 25.
  factory ControlChartConstants.forSubgroupSize(int n) {
    _requireSubgroupSize(n);
    final (double d2, double d3) = _controlChartFactors[n]!;
    return ControlChartConstants._(
      subgroupSize: n,
      d2: d2,
      d3: d3,
      c4: c4For(n),
    );
  }

  final int subgroupSize;

  /// **d2** — E[R/σ]. Turns a mean range into an estimate of σ: σ̂ = R̄/d2.
  final double d2;

  /// **d3** — the standard deviation of R/σ.
  final double d3;

  /// **c4** — E[s/σ]. Turns a mean sample sd into σ̂ = s̄/c4.
  final double c4;

  /// **A** — the X̄ limit factor when σ is known: 3/√n.
  double get meanFactorKnownSigma => 3 / math.sqrt(subgroupSize);

  /// **A2** — the X̄ limit factor from the mean range: 3/(d2√n).
  double get meanFactorFromRange => 3 / (d2 * math.sqrt(subgroupSize));

  /// **A3** — the X̄ limit factor from the mean sd: 3/(c4√n).
  double get meanFactorFromSd => 3 / (c4 * math.sqrt(subgroupSize));

  /// **D1** — the lower R limit when σ is known: max(0, d2 − 3d3).
  double get rangeLowerKnownSigma => math.max(0, d2 - 3 * d3);

  /// **D2** — the upper R limit when σ is known: d2 + 3d3.
  double get rangeUpperKnownSigma => d2 + 3 * d3;

  /// **D3** — the lower R limit from the mean range: max(0, 1 − 3d3/d2).
  ///
  /// Clamped at zero rather than allowed to go negative, and that clamp is the
  /// honest half of the story: below n = 7 the range chart simply has no lower
  /// limit, so a point cannot signal by being *too consistent*.
  double get rangeLowerFactor => math.max(0, 1 - 3 * d3 / d2);

  /// **D4** — the upper R limit from the mean range: 1 + 3d3/d2.
  double get rangeUpperFactor => 1 + 3 * d3 / d2;

  /// **B5** — the lower s limit when σ is known: max(0, c4 − 3√(1 − c4²)).
  double get sdLowerKnownSigma => math.max(0, c4 - 3 * _sdSpread);

  /// **B6** — the upper s limit when σ is known: c4 + 3√(1 − c4²).
  double get sdUpperKnownSigma => c4 + 3 * _sdSpread;

  /// **B3** — the lower s limit from the mean sd: max(0, 1 − 3√(1 − c4²)/c4).
  double get sdLowerFactor => math.max(0, 1 - 3 * _sdSpread / c4);

  /// **B4** — the upper s limit from the mean sd: 1 + 3√(1 − c4²)/c4.
  double get sdUpperFactor => 1 + 3 * _sdSpread / c4;

  double get _sdSpread => math.sqrt(1 - c4 * c4);

  /// Every factor under the symbol the published tables use, so a
  /// known-answer test can read the table off the page instead of translating
  /// names first.
  Map<String, double> get bySymbol => <String, double>{
    'd2': d2,
    'd3': d3,
    'c4': c4,
    'A': meanFactorKnownSigma,
    'A2': meanFactorFromRange,
    'A3': meanFactorFromSd,
    'D1': rangeLowerKnownSigma,
    'D2': rangeUpperKnownSigma,
    'D3': rangeLowerFactor,
    'D4': rangeUpperFactor,
    'B3': sdLowerFactor,
    'B4': sdUpperFactor,
    'B5': sdLowerKnownSigma,
    'B6': sdUpperKnownSigma,
  };
}

void _requireSubgroupSize(int n) {
  if (n < minimumSubgroupSize || n > maximumSubgroupSize) {
    throw StatsRefusal(
      'control-chart factors',
      'the published table covers subgroup sizes '
          '$minimumSubgroupSize–$maximumSubgroupSize, got $n; extrapolating '
          'a factor would invent reference data',
    );
  }
}
