part of 'stats.dart';

// The four distributions an improvement report needs, each with a CDF and a
// quantile. Everything rests on two special functions — the regularized
// incomplete gamma and the regularized incomplete beta — so there is one
// implementation to get right instead of four.
//
// Accuracy target: ~1e-12 relative over the range a report uses (tail
// probabilities down to ~1e-15). That is far tighter than any figure ever
// printed, which is the point: the rounding should happen once, at the end,
// where a human can see it.

/// Machine epsilon for doubles, and the floor the iterative routines stop at.
const double _epsilon = 2.220446049250313e-16;

/// Smallest positive normal double, used to keep a continued fraction away
/// from a zero denominator.
const double _tiny = 1e-300;

const int _maxIterations = 300;

/// Natural logarithm of the gamma function (Lanczos, g = 7, nine coefficients).
///
/// Good to about fifteen significant digits for x > 0, which is what the
/// incomplete-gamma and incomplete-beta routines below assume.
double lnGamma(double x) {
  if (x <= 0) {
    throw StatsRefusal('lnGamma', 'defined for x > 0, got $x');
  }
  const List<double> c = [
    0.99999999999980993,
    676.5203681218851,
    -1259.1392167224028,
    771.32342877765313,
    -176.61502916214059,
    12.507343278686905,
    -0.13857109526572012,
    9.9843695780195716e-6,
    1.5056327351493116e-7,
  ];
  final double z = x - 1;
  double series = c[0];
  for (int i = 1; i < c.length; i++) {
    series += c[i] / (z + i);
  }
  final double t = z + 7.5;
  return 0.5 * math.log(2 * math.pi) +
      (z + 0.5) * math.log(t) -
      t +
      math.log(series);
}

/// Natural logarithm of the beta function B(a, b).
double lnBeta(double a, double b) => lnGamma(a) + lnGamma(b) - lnGamma(a + b);

/// Series expansion of the lower regularized incomplete gamma P(a, x).
/// Converges quickly for x < a + 1.
double _gammaSeries(double a, double x) {
  double term = 1 / a;
  double sum = term;
  double n = a;
  for (int i = 0; i < _maxIterations; i++) {
    n += 1;
    term *= x / n;
    sum += term;
    if (term.abs() < sum.abs() * _epsilon) break;
  }
  return sum * math.exp(-x + a * math.log(x) - lnGamma(a));
}

/// Continued fraction (modified Lentz) for the upper regularized incomplete
/// gamma Q(a, x). Converges quickly for x >= a + 1.
double _gammaContinuedFraction(double a, double x) {
  double b = x + 1 - a;
  double c = 1 / _tiny;
  double d = 1 / b;
  double h = d;
  for (int i = 1; i <= _maxIterations; i++) {
    final double an = -i * (i - a);
    b += 2;
    d = an * d + b;
    if (d.abs() < _tiny) d = _tiny;
    c = b + an / c;
    if (c.abs() < _tiny) c = _tiny;
    d = 1 / d;
    final double delta = d * c;
    h *= delta;
    if ((delta - 1).abs() < _epsilon) break;
  }
  return math.exp(-x + a * math.log(x) - lnGamma(a)) * h;
}

/// Lower regularized incomplete gamma P(a, x) = γ(a, x) / Γ(a).
double regularizedGammaP(double a, double x) {
  if (x < 0 || a <= 0) {
    throw StatsRefusal('regularizedGammaP', 'needs a > 0 and x >= 0');
  }
  if (x == 0) return 0;
  return x < a + 1 ? _gammaSeries(a, x) : 1 - _gammaContinuedFraction(a, x);
}

/// Upper regularized incomplete gamma Q(a, x) = 1 − P(a, x), computed directly
/// in the tail so it keeps its relative accuracy where P would round to one.
double regularizedGammaQ(double a, double x) {
  if (x < 0 || a <= 0) {
    throw StatsRefusal('regularizedGammaQ', 'needs a > 0 and x >= 0');
  }
  if (x == 0) return 1;
  return x < a + 1 ? 1 - _gammaSeries(a, x) : _gammaContinuedFraction(a, x);
}

/// The error function.
double erf(double x) {
  if (x == 0) return 0;
  final double p = regularizedGammaP(0.5, x * x);
  return x > 0 ? p : -p;
}

/// The complementary error function, accurate deep into the tail.
double erfc(double x) {
  if (x == 0) return 1;
  final double q = regularizedGammaQ(0.5, x * x);
  return x > 0 ? q : 2 - q;
}

/// Continued fraction (modified Lentz) for the regularized incomplete beta.
double _betaContinuedFraction(double a, double b, double x) {
  final double qab = a + b;
  final double qap = a + 1;
  final double qam = a - 1;
  double c = 1;
  double d = 1 - qab * x / qap;
  if (d.abs() < _tiny) d = _tiny;
  d = 1 / d;
  double h = d;
  for (int m = 1; m <= _maxIterations; m++) {
    final int m2 = 2 * m;
    double aa = m * (b - m) * x / ((qam + m2) * (a + m2));
    d = 1 + aa * d;
    if (d.abs() < _tiny) d = _tiny;
    c = 1 + aa / c;
    if (c.abs() < _tiny) c = _tiny;
    d = 1 / d;
    h *= d * c;
    aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
    d = 1 + aa * d;
    if (d.abs() < _tiny) d = _tiny;
    c = 1 + aa / c;
    if (c.abs() < _tiny) c = _tiny;
    d = 1 / d;
    final double delta = d * c;
    h *= delta;
    if ((delta - 1).abs() < _epsilon) break;
  }
  return h;
}

/// Regularized incomplete beta I_x(a, b).
double regularizedIncompleteBeta(double a, double b, double x) {
  if (a <= 0 || b <= 0) {
    throw StatsRefusal('regularizedIncompleteBeta', 'needs a > 0 and b > 0');
  }
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  final double front = math.exp(
    a * math.log(x) + b * math.log(1 - x) - lnBeta(a, b),
  );
  // The fraction converges only on the near half; the symmetry relation
  // I_x(a,b) = 1 − I_{1−x}(b,a) carries the other half.
  return x < (a + 1) / (a + b + 2)
      ? front * _betaContinuedFraction(a, b, x) / a
      : 1 - front * _betaContinuedFraction(b, a, 1 - x) / b;
}

/// Density of the standard normal distribution.
double standardNormalPdf(double z) =>
    math.exp(-0.5 * z * z) / math.sqrt(2 * math.pi);

/// Cumulative probability of the standard normal distribution.
double standardNormalCdf(double z) => 0.5 * erfc(-z / math.sqrt2);

/// Inverse of [standardNormalCdf].
///
/// Acklam's rational approximation (relative error < 1.15e-9) followed by one
/// Halley step against [erfc], which takes it to roughly machine precision.
/// Written out rather than solved by bisection because the sigma level of a
/// six-sigma process asks for the quantile at p = 0.9999966, where a bisection
/// on a CDF that has already saturated returns nothing useful.
double standardNormalQuantile(double p) {
  if (p <= 0 || p >= 1) {
    throw StatsRefusal(
      'standardNormalQuantile',
      'defined for 0 < p < 1, got $p',
    );
  }
  const List<double> a = [
    -3.969683028665376e+01,
    2.209460984245205e+02,
    -2.759285104469687e+02,
    1.383577518672690e+02,
    -3.066479806614716e+01,
    2.506628277459239e+00,
  ];
  const List<double> b = [
    -5.447609879822406e+01,
    1.615858368580409e+02,
    -1.556989798598866e+02,
    6.680131188771972e+01,
    -1.328068155288572e+01,
  ];
  const List<double> c = [
    -7.784894002430293e-03,
    -3.223964580411365e-01,
    -2.400758277161838e+00,
    -2.549732539343734e+00,
    4.374664141464968e+00,
    2.938163982698783e+00,
  ];
  const List<double> d = [
    7.784695709041462e-03,
    3.224671290700398e-01,
    2.445134137142996e+00,
    3.754408661907416e+00,
  ];
  const double pLow = 0.02425;
  double z;
  if (p < pLow) {
    final double q = math.sqrt(-2 * math.log(p));
    z =
        (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
        ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
  } else if (p <= 1 - pLow) {
    final double q = p - 0.5;
    final double r = q * q;
    z =
        (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) *
        q /
        (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1);
  } else {
    final double q = math.sqrt(-2 * math.log(1 - p));
    z =
        -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
        ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
  }
  final double e = 0.5 * erfc(-z / math.sqrt2) - p;
  final double u = e * math.sqrt(2 * math.pi) * math.exp(z * z / 2);
  return z - u / (1 + z * u / 2);
}

/// A continuous distribution with a cumulative probability and its inverse.
abstract class ContinuousDistribution {
  const ContinuousDistribution();

  /// P(X <= x).
  double cdf(double x);

  /// The x for which [cdf] equals [p], for 0 < p < 1.
  double quantile(double p);

  /// P(X > x).
  double survival(double x) => 1 - cdf(x);
}

/// Bisection on a monotone [cdf], bracketed outward from [guess].
///
/// Used for the t, χ² and F quantiles. Bisection rather than Newton because
/// these are called with a user's α, never in a loop, and a method that cannot
/// diverge is worth more here than one that converges faster.
double _solveQuantile(
  double Function(double) cdf,
  double p,
  double guess,
  double lowerBound,
) {
  double lo = lowerBound;
  double hi = guess <= lowerBound ? lowerBound + 1 : guess;
  int expansions = 0;
  while (cdf(hi) < p) {
    lo = hi;
    hi = lowerBound + (hi - lowerBound) * 2 + 1;
    if (++expansions > 200) {
      throw StatsRefusal('quantile', 'the distribution never reaches p = $p');
    }
  }
  for (int i = 0; i < 200; i++) {
    final double mid = 0.5 * (lo + hi);
    if (mid == lo || mid == hi) break;
    if (cdf(mid) < p) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return 0.5 * (lo + hi);
}

/// The normal distribution.
class NormalDistribution extends ContinuousDistribution {
  const NormalDistribution({this.mean = 0, this.standardDeviation = 1});

  final double mean;
  final double standardDeviation;

  /// Density at [x].
  double pdf(double x) =>
      standardNormalPdf((x - mean) / standardDeviation) / standardDeviation;

  @override
  double cdf(double x) => standardNormalCdf((x - mean) / standardDeviation);

  @override
  double quantile(double p) =>
      mean + standardDeviation * standardNormalQuantile(p);
}

/// Student's t distribution with [degreesOfFreedom].
class StudentTDistribution extends ContinuousDistribution {
  const StudentTDistribution(this.degreesOfFreedom);

  final double degreesOfFreedom;

  @override
  double cdf(double t) {
    final double v = degreesOfFreedom;
    final double half =
        0.5 * regularizedIncompleteBeta(0.5 * v, 0.5, v / (v + t * t));
    return t >= 0 ? 1 - half : half;
  }

  @override
  double quantile(double p) {
    if (p == 0.5) return 0;
    // Symmetric, so solve the upper half and mirror: the lower tail of the
    // bracket search would otherwise have to start at negative infinity.
    if (p < 0.5) return -quantile(1 - p);
    return _solveQuantile(cdf, p, 2, 0);
  }

  /// Two-sided p-value for an observed [t].
  double twoSidedP(double t) => 2 * (1 - cdf(t.abs()));
}

/// The chi-squared distribution with [degreesOfFreedom].
class ChiSquaredDistribution extends ContinuousDistribution {
  const ChiSquaredDistribution(this.degreesOfFreedom);

  final double degreesOfFreedom;

  @override
  double cdf(double x) =>
      x <= 0 ? 0 : regularizedGammaP(0.5 * degreesOfFreedom, 0.5 * x);

  @override
  double survival(double x) =>
      x <= 0 ? 1 : regularizedGammaQ(0.5 * degreesOfFreedom, 0.5 * x);

  @override
  double quantile(double p) => _solveQuantile(cdf, p, degreesOfFreedom + 1, 0);
}

/// The F distribution with [numeratorDf] and [denominatorDf].
class FDistribution extends ContinuousDistribution {
  const FDistribution(this.numeratorDf, this.denominatorDf);

  final double numeratorDf;
  final double denominatorDf;

  @override
  double cdf(double x) {
    if (x <= 0) return 0;
    return regularizedIncompleteBeta(
      0.5 * numeratorDf,
      0.5 * denominatorDf,
      numeratorDf * x / (numeratorDf * x + denominatorDf),
    );
  }

  @override
  double survival(double x) {
    if (x <= 0) return 1;
    // Computed from the other end so a small upper-tail probability keeps its
    // significant digits instead of being 1 minus something that rounds to 1.
    return regularizedIncompleteBeta(
      0.5 * denominatorDf,
      0.5 * numeratorDf,
      denominatorDf / (numeratorDf * x + denominatorDf),
    );
  }

  @override
  double quantile(double p) => _solveQuantile(cdf, p, 2, 0);
}
