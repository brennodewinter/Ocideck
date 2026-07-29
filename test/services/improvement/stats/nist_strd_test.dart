// NIST Statistical Reference Datasets (StRD) — the certified oracle.
//
// The fixtures in test/fixtures/nist/ are the NIST files as published
// (itl.nist.gov/div898/strd/), including their headers and their *certified*
// values. They are work of the United States government and freely usable.
//
// Both datasets here exist to break a specific shortcut:
//
//   * NumAcc1 has a sample mean of 10000002 and a standard deviation of
//     exactly 1. The textbook Σx² − (Σx)²/n subtracts two numbers near 1e14
//     to get 2, and reports a variance that is wrong or negative. Welford
//     returns the certified value.
//   * Longley is the classic ill-conditioned regression: a year column, a
//     population column in the hundreds of thousands, and an intercept.
//     Solving it through the normal equations squares the condition number
//     and loses most of the digits. Householder QR does not.
//
// This is the file that would fail first if either algorithm were ever
// "simplified".
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/improvement/stats/stats.dart';

/// Reads a NIST StRD `.dat` fixture. Everything after the last header line
/// that begins with `Data:` is the data block; anything in it that does not
/// parse as a row of numbers (the rule of dashes) is skipped.
List<List<double>> _readStrd(String name) {
  final List<String> lines = File('test/fixtures/nist/$name').readAsLinesSync();
  int start = 0;
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].trimLeft().startsWith('Data:')) start = i + 1;
  }
  final List<List<double>> rows = <List<double>>[];
  for (final String line in lines.skip(start)) {
    final List<String> tokens = line.trim().split(RegExp(r'\s+'));
    final List<double> row = <double>[];
    bool numeric = true;
    for (final String token in tokens) {
      final double? value = double.tryParse(token);
      if (value == null) {
        numeric = false;
        break;
      }
      row.add(value);
    }
    if (numeric && row.isNotEmpty) rows.add(row);
  }
  return rows;
}

/// Certified coefficient estimates and their standard deviations, copied from
/// the header of Longley.dat.
const List<(double estimate, double standardError)> _longleyCertified =
    <(double, double)>[
      (-3482258.63459582, 890420.383607373),
      (15.0618722713733, 84.9149257747669),
      (-0.358191792925910E-01, 0.334910077722432E-01),
      (-2.02022980381683, 0.488399681651699),
      (-1.03322686717359, 0.214274163161675),
      (-0.511041056535807E-01, 0.226073200069370),
      (1829.15146461355, 455.478499142212),
    ];

void main() {
  group('NumAcc1 — univariate summaries on 8-digit integers', () {
    final List<double> values = <double>[
      for (final List<double> row in _readStrd('NumAcc1.dat')) row.single,
    ];

    test('the fixture is the dataset NIST publishes', () {
      expect(values, <double>[10000001, 10000003, 10000002]);
    });

    test('the certified mean and standard deviation come back exactly', () {
      final Descriptives summary = Descriptives.of(values);
      expect(summary.count, 3);
      expect(summary.mean, 10000002);
      expect(summary.standardDeviation, 1);
      expect(summary.variance, 1);
    });

    test('one more digit of offset and the shortcut does give way', () {
      // NumAcc1 sits just inside what a double can hold exactly, so the
      // textbook Σx² − (Σx)²/n survives it. Move the same three values two
      // orders of magnitude further out and it does not — while Welford
      // still returns the 1 the construction puts there.
      final List<double> further = <double>[
        for (final double x in values) x * 100 + 1000000000,
      ];
      double sum = 0;
      double sumOfSquares = 0;
      for (final double x in further) {
        sum += x;
        sumOfSquares += x * x;
      }
      final double naive = math.sqrt((sumOfSquares - sum * sum / 3) / 2);
      final double welford = Descriptives.of(further).standardDeviation;
      expect(welford, closeTo(100, 1e-9));
      expect((naive - 100).abs(), greaterThan(1e-6));
    });
  });

  group('NumAcc3-style construction — a tiny spread on a large offset', () {
    // NumAcc3.dat is 1001 values built by the rule quoted in its own header:
    // 1000000.2 once, then 1000000.1 and 1000000.3 alternating five hundred
    // times each. Certified: mean 1000000.2 (exact), sd 0.1 (exact). It is
    // generated here rather than committed because a thousand-line fixture of
    // two repeating values carries no information a reader could check.
    final List<double> values = <double>[
      1000000.2,
      for (int i = 0; i < 500; i++) ...<double>[1000000.1, 1000000.3],
    ];

    test('the certified values are reproduced to ten digits', () {
      final Descriptives summary = Descriptives.of(values);
      expect(summary.count, 1001);
      expect(summary.mean, closeTo(1000000.2, 1e-9));
      expect(summary.standardDeviation, closeTo(0.1, 1e-9));
    });
  });

  group('Longley — least squares that punishes the normal equations', () {
    final List<List<double>> rows = _readStrd('Longley.dat');
    final List<double> y = <double>[
      for (final List<double> row in rows) row.first,
    ];
    final List<List<double>> x = <List<double>>[
      for (final List<double> row in rows) row.sublist(1),
    ];
    final LinearRegression fit = multipleLinearRegression(
      x,
      y,
      predictorNames: const <String>['x1', 'x2', 'x3', 'x4', 'x5', 'x6'],
    );

    test('the fixture is the dataset NIST publishes', () {
      expect(rows, hasLength(16));
      expect(rows.first, <double>[
        60323,
        83.0,
        234289,
        2356,
        1590,
        107608,
        1947,
      ]);
      expect(rows.last, <double>[
        70551,
        116.9,
        554894,
        4007,
        2827,
        130081,
        1962,
      ]);
    });

    test('every certified coefficient is reproduced', () {
      expect(fit.coefficients, hasLength(7));
      expect(fit.coefficients.first.name, 'Intercept');
      for (int j = 0; j < _longleyCertified.length; j++) {
        final (double estimate, double standardError) = _longleyCertified[j];
        expect(
          fit.coefficients[j].estimate,
          closeTo(estimate, estimate.abs() * 1e-7),
          reason: 'B$j estimate',
        );
        expect(
          fit.coefficients[j].standardError,
          closeTo(standardError, standardError.abs() * 1e-7),
          reason: 'B$j standard error',
        );
      }
    });

    test('the certified fit statistics are reproduced', () {
      expect(
        fit.residualStandardError,
        closeTo(304.854073561965, 304.854073561965 * 1e-8),
      );
      expect(fit.rSquared, closeTo(0.995479004577296, 1e-11));
      expect(fit.residualDegreesOfFreedom, 9);
      expect(fit.modelDegreesOfFreedom, 6);
      expect(
        fit.residualSumOfSquares,
        closeTo(836424.055505915, 836424.055505915 * 1e-7),
      );
      expect(
        fit.totalSumOfSquares - fit.residualSumOfSquares,
        closeTo(184172401.944494, 184172401.944494 * 1e-8),
      );
      expect(
        fit.fStatistic,
        closeTo(330.285339234588, 330.285339234588 * 1e-7),
      );
      expect(fit.pValue, lessThan(1e-9));
    });

    test('the residuals are what a fit means: y minus the prediction', () {
      for (int i = 0; i < y.length; i++) {
        expect(fit.fitted[i] + fit.residuals[i], closeTo(y[i], 1e-6));
        expect(fit.predict(x[i]), closeTo(fit.fitted[i], 1e-6));
      }
      double sum = 0;
      for (final double r in fit.residuals) {
        sum += r;
      }
      // A model with an intercept has residuals that sum to zero.
      expect(sum, closeTo(0, 1e-6));
    });

    test('adjusted R² sits below R², and the coefficient p-values exist', () {
      expect(fit.adjustedRSquared, lessThan(fit.rSquared));
      for (final RegressionCoefficient c in fit.coefficients) {
        expect(c.pValue, inInclusiveRange(0, 1));
        expect(c.tStatistic, closeTo(c.estimate / c.standardError, 1e-12));
        final ConfidenceInterval interval = c.interval();
        expect(interval.contains(c.estimate), isTrue);
        expect(interval.level, 0.95);
      }
    });
  });

  group('simple regression against a line with no error', () {
    test('a perfect fit is recovered exactly', () {
      final List<double> x = <double>[1, 2, 3, 4, 5, 6];
      final List<double> y = <double>[for (final double v in x) 3 + 2 * v];
      final LinearRegression fit = simpleLinearRegression(x, y);
      expect(fit.coefficients.first.estimate, closeTo(3, 1e-10));
      expect(fit.coefficients.last.estimate, closeTo(2, 1e-10));
      expect(fit.coefficients.last.name, 'x');
      expect(fit.rSquared, closeTo(1, 1e-12));
      expect(fit.residualStandardError, closeTo(0, 1e-8));
    });

    test('shifting and scaling move the line the way they should', () {
      final List<double> x = <double>[1, 2, 3, 4, 5, 6, 7];
      final List<double> y = <double>[2.1, 3.9, 6.2, 7.8, 10.1, 12.2, 13.8];
      final LinearRegression base = simpleLinearRegression(x, y);
      final LinearRegression scaled = simpleLinearRegression(x, <double>[
        for (final double v in y) v * 10,
      ]);
      expect(
        scaled.coefficients.last.estimate,
        closeTo(base.coefficients.last.estimate * 10, 1e-9),
      );
      expect(scaled.rSquared, closeTo(base.rSquared, 1e-12));
    });

    test('a collinear design is refused, not silently inverted', () {
      final List<List<double>> rows = <List<double>>[
        for (int i = 1; i <= 8; i++) <double>[i.toDouble(), 2.0 * i],
      ];
      expect(
        () => multipleLinearRegression(rows, <double>[
          for (int i = 1; i <= 8; i++) i * 1.5,
        ]),
        throwsA(isA<StatsRefusal>()),
      );
    });

    test('more parameters than observations is refused', () {
      expect(
        () => multipleLinearRegression(
          <List<double>>[
            <double>[1, 2],
            <double>[2, 1],
            <double>[3, 5],
          ],
          <double>[1, 2, 3],
        ),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => simpleLinearRegression(<double>[1, 2, 3], <double>[1, 2]),
        throwsA(isA<StatsRefusal>()),
      );
    });

    test('a prediction needs as many predictors as the model has', () {
      final LinearRegression fit = simpleLinearRegression(
        <double>[1, 2, 3, 4],
        <double>[2, 4, 6, 8.1],
      );
      expect(fit.predict(<double>[5]), closeTo(10.05, 0.2));
      expect(() => fit.predict(<double>[5, 6]), throwsA(isA<StatsRefusal>()));
    });
  });

  group('the special functions the whole engine rests on', () {
    test('lnGamma matches the factorials it generalises', () {
      double factorial = 1;
      for (int n = 1; n <= 10; n++) {
        expect(
          math.exp(lnGamma(n.toDouble())),
          closeTo(factorial, factorial * 1e-12),
          reason: 'Γ($n)',
        );
        factorial *= n;
      }
      // Γ(1/2) = √π.
      expect(math.exp(lnGamma(0.5)), closeTo(math.sqrt(math.pi), 1e-12));
      expect(() => lnGamma(0), throwsA(isA<StatsRefusal>()));
    });

    test('the normal CDF and its inverse are inverse over the whole range', () {
      for (final double z in <double>[-6, -3, -1, 0, 1, 3, 4.5, 6]) {
        expect(
          standardNormalQuantile(standardNormalCdf(z)),
          closeTo(z, 1e-7),
          reason: 'z = $z',
        );
      }
      expect(standardNormalCdf(0), closeTo(0.5, 1e-15));
      expect(standardNormalCdf(1.959963985), closeTo(0.975, 1e-9));
      expect(standardNormalQuantile(0.975), closeTo(1.959963985, 1e-9));
    });

    test('the error function keeps its digits deep in the tail', () {
      expect(erf(0), 0);
      expect(erf(1), closeTo(0.8427007929497149, 1e-12));
      expect(erfc(1), closeTo(0.1572992070502851, 1e-12));
      expect(erfc(-1), closeTo(1.8427007929497149, 1e-12));
      // Where 1 − erf(6) would round to zero, erfc still has ten digits.
      expect(erfc(6), closeTo(2.1519736712498913e-17, 1e-25));
    });

    test('the incomplete beta obeys its own symmetry', () {
      for (final double x in <double>[0.1, 0.3, 0.5, 0.7, 0.9]) {
        expect(
          regularizedIncompleteBeta(2, 5, x),
          closeTo(1 - regularizedIncompleteBeta(5, 2, 1 - x), 1e-13),
        );
      }
      expect(regularizedIncompleteBeta(2, 5, 0), 0);
      expect(regularizedIncompleteBeta(2, 5, 1), 1);
    });

    test('P and Q of the incomplete gamma add to one', () {
      for (final double x in <double>[0.5, 1, 3, 10, 30]) {
        expect(
          regularizedGammaP(3, x) + regularizedGammaQ(3, x),
          closeTo(1, 1e-13),
        );
      }
    });
  });
}
