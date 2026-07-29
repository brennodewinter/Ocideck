part of 'stats.dart';

// Least squares by Householder QR, never by the normal equations.
//
// Forming X'X and inverting it is shorter to write and squares the condition
// number of the problem, which on the sort of design matrix an improvement
// study produces — a column of years, a column of counts in the millions, an
// intercept — throws away half the available digits before the arithmetic
// starts. NIST publishes datasets built to expose exactly that (`Longley`,
// `Wampler`); they are in the test suite, and they are the reason this is QR.

/// One fitted coefficient with everything needed to judge it.
class RegressionCoefficient {
  const RegressionCoefficient({
    required this.name,
    required this.estimate,
    required this.standardError,
    required this.degreesOfFreedom,
  });

  /// `'Intercept'`, or the predictor's name.
  final String name;

  final double estimate;
  final double standardError;

  /// Residual degrees of freedom of the fit this coefficient came from.
  final double degreesOfFreedom;

  double get tStatistic => estimate / standardError;

  /// Two-sided p-value for the coefficient being zero.
  double get pValue =>
      StudentTDistribution(degreesOfFreedom).twoSidedP(tStatistic);

  /// Two-sided confidence interval at [level].
  ConfidenceInterval interval({double level = 0.95}) =>
      _tInterval(estimate, standardError, degreesOfFreedom, level);
}

/// A fitted linear model.
class LinearRegression {
  const LinearRegression._({
    required this.coefficients,
    required this.fitted,
    required this.residuals,
    required this.residualSumOfSquares,
    required this.totalSumOfSquares,
    required this.observationCount,
    required this.hasIntercept,
  });

  /// The coefficients, intercept first when there is one.
  final List<RegressionCoefficient> coefficients;

  final List<double> fitted;
  final List<double> residuals;

  final double residualSumOfSquares;

  /// Σ(y − ȳ)² for a model with an intercept, Σy² without one.
  final double totalSumOfSquares;

  final int observationCount;
  final bool hasIntercept;

  int get parameterCount => coefficients.length;

  /// Residual degrees of freedom, n − p.
  double get residualDegreesOfFreedom =>
      (observationCount - parameterCount).toDouble();

  /// The residual variance, RSS/(n − p).
  double get residualVariance =>
      residualSumOfSquares / residualDegreesOfFreedom;

  /// The residual standard error — the spread of the points around the line,
  /// in the units of y. The one figure worth quoting next to R².
  double get residualStandardError => math.sqrt(residualVariance);

  double get rSquared => 1 - residualSumOfSquares / totalSumOfSquares;

  /// R² with a penalty for each predictor, so adding noise columns stops
  /// looking like progress.
  double get adjustedRSquared =>
      1 -
      (residualSumOfSquares / residualDegreesOfFreedom) /
          (totalSumOfSquares / (observationCount - (hasIntercept ? 1 : 0)));

  /// Degrees of freedom of the overall F test.
  double get modelDegreesOfFreedom =>
      (parameterCount - (hasIntercept ? 1 : 0)).toDouble();

  /// F test of the model against the intercept alone.
  double get fStatistic =>
      ((totalSumOfSquares - residualSumOfSquares) / modelDegreesOfFreedom) /
      residualVariance;

  /// p-value of [fStatistic].
  double get pValue => FDistribution(
    modelDegreesOfFreedom,
    residualDegreesOfFreedom,
  ).survival(fStatistic);

  /// Predicts y for one row of predictor values.
  double predict(List<double> predictors) {
    final int expected = parameterCount - (hasIntercept ? 1 : 0);
    if (predictors.length != expected) {
      throw StatsRefusal(
        'prediction',
        'the model has $expected predictor(s), got ${predictors.length}',
      );
    }
    double y = hasIntercept ? coefficients.first.estimate : 0;
    final int offset = hasIntercept ? 1 : 0;
    for (int j = 0; j < predictors.length; j++) {
      y += coefficients[j + offset].estimate * predictors[j];
    }
    return y;
  }
}

/// Ordinary least squares of [y] on [x] with an intercept.
LinearRegression simpleLinearRegression(
  List<double> x,
  List<double> y, {
  String predictorName = 'x',
}) => multipleLinearRegression(
  <List<double>>[
    for (final double v in x) <double>[v],
  ],
  y,
  predictorNames: <String>[predictorName],
);

/// Ordinary least squares of [y] on [rows], one row of predictors per
/// observation.
LinearRegression multipleLinearRegression(
  List<List<double>> rows,
  List<double> y, {
  List<String>? predictorNames,
  bool intercept = true,
}) {
  const String what = 'linear regression';
  _requireAtLeast(what, 'observations', rows.length, 2);
  if (rows.length != y.length) {
    throw StatsRefusal(
      what,
      'got ${rows.length} row(s) of predictors and ${y.length} response(s)',
    );
  }
  final int predictors = rows.first.length;
  _requireAtLeast(what, 'predictors', predictors, 1);
  for (final List<double> row in rows) {
    if (row.length != predictors) {
      throw StatsRefusal(what, 'the rows do not all have the same width');
    }
  }
  final List<String> names = <String>[
    if (intercept) 'Intercept',
    ...?predictorNames,
    for (int j = (predictorNames?.length ?? 0); j < predictors; j++)
      'x${j + 1}',
  ];
  final int parameters = predictors + (intercept ? 1 : 0);
  if (names.length != parameters) {
    throw StatsRefusal(
      what,
      'got ${names.length - (intercept ? 1 : 0)} predictor name(s) for '
      '$predictors predictor(s)',
    );
  }
  if (rows.length <= parameters) {
    throw StatsRefusal(
      what,
      'fitting $parameters parameter(s) to ${rows.length} observation(s) '
      'leaves nothing to estimate the error from',
    );
  }

  final List<List<double>> design = <List<double>>[
    for (final List<double> row in rows) <double>[if (intercept) 1, ...row],
  ];
  final _QrSolution solution = _solveByHouseholderQr(design, y, what);

  final List<double> fitted = <double>[
    for (final List<double> row in design) _dot(row, solution.coefficients),
  ];
  final List<double> residuals = <double>[
    for (int i = 0; i < y.length; i++) y[i] - fitted[i],
  ];
  double residualSumOfSquares = 0;
  for (final double r in residuals) {
    residualSumOfSquares += r * r;
  }
  final double totalSumOfSquares = intercept
      ? Descriptives.of(y).sumOfSquaredDeviations
      : _dot(y, y);
  final double df = (rows.length - parameters).toDouble();
  final double residualVariance = residualSumOfSquares / df;

  return LinearRegression._(
    coefficients: <RegressionCoefficient>[
      for (int j = 0; j < parameters; j++)
        RegressionCoefficient(
          name: names[j],
          estimate: solution.coefficients[j],
          standardError: math.sqrt(
            residualVariance * solution.unscaledVariance[j],
          ),
          degreesOfFreedom: df,
        ),
    ],
    fitted: fitted,
    residuals: residuals,
    residualSumOfSquares: residualSumOfSquares,
    totalSumOfSquares: totalSumOfSquares,
    observationCount: rows.length,
    hasIntercept: intercept,
  );
}

/// Coefficients plus the diagonal of (X'X)⁻¹, which is all the standard errors
/// need and is read straight off R without ever forming X'X.
class _QrSolution {
  const _QrSolution(this.coefficients, this.unscaledVariance);

  final List<double> coefficients;
  final List<double> unscaledVariance;
}

_QrSolution _solveByHouseholderQr(
  List<List<double>> design,
  List<double> response,
  String what,
) {
  final int n = design.length;
  final int p = design.first.length;
  final List<List<double>> a = <List<double>>[
    for (final List<double> row in design) List<double>.of(row),
  ];
  final List<double> b = List<double>.of(response);

  for (int k = 0; k < p; k++) {
    double norm = 0;
    for (int i = k; i < n; i++) {
      norm += a[i][k] * a[i][k];
    }
    norm = math.sqrt(norm);
    if (norm == 0) {
      throw StatsRefusal(
        what,
        'predictor ${k + 1} adds nothing the earlier ones do not already '
        'carry (the design matrix is rank deficient)',
      );
    }
    // Subtracting toward the far side keeps the leading entry away from
    // cancellation; the sign is the whole reason Householder is stable.
    final double alpha = a[k][k] >= 0 ? -norm : norm;
    final List<double> v = List<double>.filled(n, 0);
    v[k] = a[k][k] - alpha;
    for (int i = k + 1; i < n; i++) {
      v[i] = a[i][k];
    }
    double vtv = 0;
    for (int i = k; i < n; i++) {
      vtv += v[i] * v[i];
    }
    if (vtv > 0) {
      for (int j = k; j < p; j++) {
        double s = 0;
        for (int i = k; i < n; i++) {
          s += v[i] * a[i][j];
        }
        s = 2 * s / vtv;
        for (int i = k; i < n; i++) {
          a[i][j] -= s * v[i];
        }
      }
      double s = 0;
      for (int i = k; i < n; i++) {
        s += v[i] * b[i];
      }
      s = 2 * s / vtv;
      for (int i = k; i < n; i++) {
        b[i] -= s * v[i];
      }
    }
  }

  for (int k = 0; k < p; k++) {
    if (a[k][k].abs() < 1e-12 * (a[0][0].abs() + 1)) {
      throw StatsRefusal(
        what,
        'the predictors are collinear, so the coefficients are not '
        'identifiable',
      );
    }
  }

  final List<double> beta = List<double>.filled(p, 0);
  for (int i = p - 1; i >= 0; i--) {
    double sum = b[i];
    for (int j = i + 1; j < p; j++) {
      sum -= a[i][j] * beta[j];
    }
    beta[i] = sum / a[i][i];
  }

  // (X'X)⁻¹ = R⁻¹R⁻ᵀ, so its diagonal is the row-wise sum of squares of R⁻¹.
  final List<List<double>> rInverse = <List<double>>[
    for (int i = 0; i < p; i++) List<double>.filled(p, 0),
  ];
  for (int col = p - 1; col >= 0; col--) {
    rInverse[col][col] = 1 / a[col][col];
    for (int i = col - 1; i >= 0; i--) {
      double sum = 0;
      for (int j = i + 1; j <= col; j++) {
        sum += a[i][j] * rInverse[j][col];
      }
      rInverse[i][col] = -sum / a[i][i];
    }
  }
  final List<double> unscaled = <double>[
    for (int i = 0; i < p; i++)
      () {
        double sum = 0;
        for (int k = i; k < p; k++) {
          sum += rInverse[i][k] * rInverse[i][k];
        }
        return sum;
      }(),
  ];

  return _QrSolution(beta, unscaled);
}

double _dot(List<double> a, List<double> b) {
  double sum = 0;
  for (int i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}
