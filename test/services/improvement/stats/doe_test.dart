// Two-level factorial designs: the design that comes out, the aliasing it
// admits to, and the effects read back from a response with a known model.
//
// The strongest check here is the resolution one. The engine stores the
// published *generators* and derives the resolution from the defining
// relation, so the test can compare the derived resolution against the Roman
// numeral the standard tables print next to each design (NIST/SEMATECH
// e-Handbook §5.3.3.4.7). A transcription slip in the generator table would
// almost certainly change the resolution, and this is what would catch it.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/improvement/stats/stats.dart';

List<DesignFactor> _factors(int count) => <DesignFactor>[
  for (int i = 0; i < count; i++) DesignFactor('Factor ${i + 1}'),
];

void main() {
  group('the full factorial', () {
    final FactorialDesign design = FactorialDesign.full(_factors(3));

    test('every combination appears once, in standard order', () {
      expect(design.pointCount, 8);
      expect(design.runCount, 8);
      expect(design.fraction, 0);
      expect(design.resolution, isNull);
      expect(design.definingRelation, isEmpty);
      // The first factor alternates fastest — the Yates convention.
      expect(design.points.first, <int>[-1, -1, -1]);
      expect(design.points[1], <int>[1, -1, -1]);
      expect(design.points[2], <int>[-1, 1, -1]);
      expect(design.points.last, <int>[1, 1, 1]);
    });

    test('the columns are balanced and orthogonal', () {
      for (final List<int> a in design.estimableTerms) {
        final List<int> columnA = design.contrastColumn(a);
        expect(columnA.reduce((int x, int y) => x + y), 0, reason: '$a sums');
        for (final List<int> b in design.estimableTerms) {
          if (factorialTermLabel(a) == factorialTermLabel(b)) continue;
          int dot = 0;
          final List<int> columnB = design.contrastColumn(b);
          for (int i = 0; i < columnA.length; i++) {
            dot += columnA[i] * columnB[i];
          }
          expect(dot, 0, reason: '$a against $b');
        }
      }
    });

    test('it estimates every term and confounds nothing', () {
      expect(design.estimableTerms.map(factorialTermLabel).toList(), <String>[
        'A',
        'B',
        'C',
        'AB',
        'AC',
        'BC',
        'ABC',
      ]);
      expect(design.aliasesOf(<int>[0]), isEmpty);
    });

    test('coded levels map back onto the settings that were asked for', () {
      final FactorialDesign real = FactorialDesign.full(const <DesignFactor>[
        DesignFactor('Temperature', low: 180, high: 220),
        DesignFactor('Time', low: 30, high: 60),
      ]);
      expect(real.settingsFor(0), <double>[180, 30]);
      expect(real.settingsFor(1), <double>[220, 30]);
      expect(real.settingsFor(3), <double>[220, 60]);
      expect(() => real.settingsFor(4), throwsA(isA<StatsRefusal>()));
    });

    test('a replicate repeats the whole block', () {
      final FactorialDesign twice = FactorialDesign.full(
        _factors(2),
        replicates: 3,
      );
      expect(twice.pointCount, 4);
      expect(twice.runCount, 12);
      expect(twice.codedRun(0), twice.codedRun(4));
      expect(twice.codedRun(0), twice.codedRun(8));
    });

    test('a randomised order is a permutation of the runs', () {
      final List<int> order = design.randomisedRunOrder(math.Random(42));
      expect(order, hasLength(design.runCount));
      expect(order.toSet(), <int>{0, 1, 2, 3, 4, 5, 6, 7});
    });

    test('a full factorial that is really a wish is refused', () {
      expect(
        () => FactorialDesign.full(_factors(13)),
        throwsA(
          isA<StatsRefusal>().having(
            (StatsRefusal e) => e.reason,
            'reason',
            contains('8192 runs'),
          ),
        ),
      );
      expect(
        () => FactorialDesign.full(_factors(1)),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => FactorialDesign.full(const <DesignFactor>[
          DesignFactor('Stuck', low: 5, high: 5),
          DesignFactor('Fine'),
        ]),
        throwsA(isA<StatsRefusal>()),
      );
    });
  });

  group('the fraction, and what it costs', () {
    final FactorialDesign half = FactorialDesign.fractional(
      _factors(4),
      fraction: 1,
    );

    test('2^(4−1) is eight runs at resolution IV', () {
      expect(half.pointCount, 8);
      expect(half.baseFactorCount, 3);
      expect(half.generators, <String>['D = ABC']);
      expect(half.resolution, 4);
      expect(half.definingRelation.single.label, 'ABCD');
      expect(half.definingRelation.single.order, 4);
      expect(half.definingRelation.single.sign, 1);
    });

    test('the generated column really is the product it claims to be', () {
      for (final List<int> point in half.points) {
        expect(point[3], point[0] * point[1] * point[2]);
      }
    });

    test('each main effect names the interaction it hides behind', () {
      expect(half.aliasesOf(<int>[0]).single.label, 'BCD');
      expect(half.aliasesOf(<int>[3]).single.label, 'ABC');
      // Two-factor interactions are confounded in pairs at resolution IV.
      expect(half.aliasesOf(factorialTerm('AB')).single.label, 'CD');
    });

    test('the column is named by the shortest term that sits on it', () {
      expect(half.estimableTerms.map(factorialTermLabel).toList(), <String>[
        'A',
        'B',
        'C',
        'D',
        'AB',
        'AC',
        'AD',
      ]);
      expect(
        factorialTermLabel(half.clearestAliasOf(factorialTerm('ABC'))),
        'D',
      );
    });

    test('the published tables and the derived resolution agree', () {
      // (factors, fraction, resolution) exactly as the tables print it.
      const List<(int, int, int)> published = <(int, int, int)>[
        (3, 1, 3),
        (4, 1, 4),
        (5, 1, 5),
        (5, 2, 3),
        (6, 1, 6),
        (6, 2, 4),
        (6, 3, 3),
        (7, 1, 7),
        (7, 2, 4),
        (7, 3, 4),
        (7, 4, 3),
        (8, 1, 8),
        (8, 2, 5),
        (8, 3, 4),
        (8, 4, 4),
        (9, 1, 9),
        (9, 2, 6),
        (9, 3, 4),
        (9, 4, 4),
        (9, 5, 3),
      ];
      for (final (int k, int p, int resolution) in published) {
        final FactorialDesign design = FactorialDesign.fractional(
          _factors(k),
          fraction: p,
        );
        expect(
          design.resolution,
          resolution,
          reason: '2^($k−$p) should be resolution $resolution',
        );
        expect(design.pointCount, 1 << (k - p));
        expect(design.definingRelation, hasLength((1 << p) - 1));
      }
    });

    test('resolution III really does confound a main effect with a pair', () {
      final FactorialDesign quarter = FactorialDesign.fractional(
        _factors(5),
        fraction: 2,
      );
      expect(quarter.resolution, 3);
      expect(
        quarter.aliasesOf(<int>[0]).map((SignedTerm t) => t.order),
        contains(2),
      );
    });

    test(
      'a negative generator flips the defining word, not the design size',
      () {
        final FactorialDesign mirrored = FactorialDesign.fractional(
          _factors(4),
          fraction: 1,
          generators: <String>['D = -ABC'],
        );
        expect(mirrored.pointCount, 8);
        expect(mirrored.resolution, 4);
        expect(mirrored.definingRelation.single.sign, -1);
        expect(mirrored.definingRelation.single.label, '−ABCD');
        for (final List<int> point in mirrored.points) {
          expect(point[3], -point[0] * point[1] * point[2]);
        }
      },
    );

    test('a size the table has no published choice for is refused', () {
      expect(
        () => FactorialDesign.fractional(_factors(10), fraction: 3),
        throwsA(
          isA<StatsRefusal>().having(
            (StatsRefusal e) => e.reason,
            'reason',
            contains('no published generator set'),
          ),
        ),
      );
    });

    test('a malformed or impossible generator is refused', () {
      expect(
        () => FactorialDesign.fractional(
          _factors(4),
          fraction: 1,
          generators: <String>['ABC'],
        ),
        throwsA(isA<StatsRefusal>()),
      );
      // Placing D on a single factor would make it a copy of that factor.
      expect(
        () => FactorialDesign.fractional(
          _factors(4),
          fraction: 1,
          generators: <String>['D = A'],
        ),
        throwsA(isA<StatsRefusal>()),
      );
      // The generator has to place the next factor, not an earlier one.
      expect(
        () => FactorialDesign.fractional(
          _factors(4),
          fraction: 1,
          generators: <String>['C = AB'],
        ),
        throwsA(isA<StatsRefusal>()),
      );
      // A generator may not ride on a factor outside the base design.
      expect(
        () => FactorialDesign.fractional(
          _factors(5),
          fraction: 2,
          generators: <String>['D = AB', 'E = AD'],
        ),
        throwsA(isA<StatsRefusal>()),
      );
      // The wrong number of generators for the fraction asked for.
      expect(
        () => FactorialDesign.fractional(
          _factors(5),
          fraction: 2,
          generators: <String>['D = AB'],
        ),
        throwsA(isA<StatsRefusal>()),
      );
      // A fraction that leaves fewer than two base factors.
      expect(
        () => FactorialDesign.fractional(_factors(3), fraction: 2),
        throwsA(isA<StatsRefusal>()),
      );
    });

    test('the letter I is skipped, so the ninth factor is J', () {
      expect(designFactorLetters.contains('I'), isFalse);
      expect(factorialTermLabel(<int>[8]), 'J');
      expect(factorialTerm('J'), <int>[8]);
      expect(factorialTermLabel(const <int>[]), 'I');
      expect(() => factorialTerm('AA'), throwsA(isA<StatsRefusal>()));
      expect(() => factorialTerm('AI'), throwsA(isA<StatsRefusal>()));
    });
  });

  group('reading the effects back', () {
    /// y = 10 + 2·A + 3·B + 1.5·AB in coded units, so the *effects* — twice
    /// the coefficients — must come back as 4, 6 and 3, and C as nothing.
    final FactorialDesign design = FactorialDesign.full(_factors(3));
    final List<double> response = <double>[
      for (final List<int> p in design.points)
        10 + 2 * p[0] + 3 * p[1] + 1.5 * p[0] * p[1],
    ];
    final FactorialAnalysis analysis = FactorialAnalysis.of(design, response);

    test('the grand mean is the intercept of the coded model', () {
      expect(analysis.grandMean, closeTo(10, 1e-13));
    });

    test(
      'an effect is the high mean minus the low mean, twice the coefficient',
      () {
        expect(analysis.effectNamed('A').effect, closeTo(4, 1e-13));
        expect(analysis.effectNamed('A').coefficient, closeTo(2, 1e-13));
        expect(analysis.effectNamed('B').effect, closeTo(6, 1e-13));
        expect(analysis.effectNamed('AB').effect, closeTo(3, 1e-13));
        expect(analysis.effectNamed('C').effect, closeTo(0, 1e-13));
        expect(analysis.effectNamed('ABC').effect, closeTo(0, 1e-13));
      },
    );

    test('the sums of squares add up to the total variation', () {
      double total = 0;
      for (final FactorialEffect effect in analysis.effects) {
        total += effect.sumOfSquares;
      }
      expect(total, closeTo(analysis.totalSumOfSquares, 1e-9));
      // N·coefficient², so 8·4 = 32 for A.
      expect(analysis.effectNamed('A').sumOfSquares, closeTo(32, 1e-11));
    });

    test('main effects and interactions are separable', () {
      expect(analysis.mainEffects.map((FactorialEffect e) => e.name), <String>[
        'A',
        'B',
        'C',
      ]);
      expect(analysis.interactions, hasLength(4));
      expect(analysis.effectsUpTo(2), hasLength(6));
      expect(analysis.bySize.first.name, 'B');
      expect(analysis.effects.first.order, 1);
    });

    test('an unreplicated design offers no p-value, and says so with null', () {
      expect(analysis.isReplicated, isFalse);
      expect(analysis.pureErrorMeanSquare, isNull);
      for (final FactorialEffect effect in analysis.effects) {
        expect(effect.standardError, isNull);
        expect(effect.tStatistic, isNull);
        expect(effect.pValue, isNull);
      }
    });

    test('a replicated design does, and pure error closes the books', () {
      final FactorialDesign replicated = FactorialDesign.full(
        _factors(3),
        replicates: 2,
      );
      final math.Random random = math.Random(1234);
      final List<double> noisy = <double>[
        for (int i = 0; i < replicated.runCount; i++)
          10 +
              2 * replicated.codedRun(i)[0] +
              3 * replicated.codedRun(i)[1] +
              (random.nextDouble() - 0.5) * 0.2,
      ];
      final FactorialAnalysis fitted = FactorialAnalysis.of(replicated, noisy);
      expect(fitted.isReplicated, isTrue);
      expect(fitted.pureErrorDegreesOfFreedom, 8);
      expect(fitted.pureErrorMeanSquare, greaterThan(0));

      double explained = 0;
      for (final FactorialEffect effect in fitted.effects) {
        explained += effect.sumOfSquares;
      }
      expect(
        explained + fitted.pureErrorSumOfSquares!,
        closeTo(fitted.totalSumOfSquares, 1e-9),
      );

      final FactorialEffect a = fitted.effectNamed('A');
      expect(a.effect, closeTo(4, 0.15));
      expect(a.standardError, isNotNull);
      expect(a.pValue, lessThan(0.001));
      expect(fitted.effectNamed('C').pValue, greaterThan(0.05));
    });

    test("Lenth's method finds the one real effect without replication", () {
      final FactorialDesign sixteen = FactorialDesign.full(_factors(4));
      final math.Random random = math.Random(7);
      final List<double> noisy = <double>[
        for (final List<int> p in sixteen.points)
          50 + 5 * p[0] + (random.nextDouble() - 0.5) * 0.4,
      ];
      final FactorialAnalysis unreplicated = FactorialAnalysis.of(
        sixteen,
        noisy,
      );
      final double margin = unreplicated.lenthMarginOfError();
      final double simultaneous = unreplicated.lenthSimultaneousMarginOfError();
      expect(unreplicated.lenthPseudoStandardError, greaterThan(0));
      expect(simultaneous, greaterThan(margin));
      expect(
        unreplicated.effectNamed('A').effect.abs(),
        greaterThan(simultaneous),
      );
      for (final FactorialEffect effect in unreplicated.effects) {
        if (effect.name == 'A') continue;
        expect(
          effect.effect.abs(),
          lessThan(margin),
          reason: '${effect.name} should read as noise',
        );
      }
    });

    test('a fraction reports the effect it estimates with its aliases', () {
      final FactorialDesign half = FactorialDesign.fractional(
        _factors(4),
        fraction: 1,
      );
      // A model in which the AB interaction is real. At resolution IV it is
      // indistinguishable from CD, and the report has to say that.
      final List<double> y = <double>[
        for (final List<int> p in half.points)
          20 + 4 * p[0] + 2.5 * p[0] * p[1],
      ];
      final FactorialAnalysis fitted = FactorialAnalysis.of(half, y);
      expect(fitted.effectNamed('A').effect, closeTo(8, 1e-12));
      expect(fitted.effectNamed('AB').effect, closeTo(5, 1e-12));
      expect(fitted.effectNamed('AB').aliases.single.label, 'CD');
      // Asking by the alias name reaches the same column.
      expect(fitted.effectNamed('CD').name, 'AB');
    });

    test('what the analysis refuses', () {
      expect(
        () => FactorialAnalysis.of(design, <double>[1, 2, 3]),
        throwsA(
          isA<StatsRefusal>().having(
            (StatsRefusal e) => e.reason,
            'reason',
            contains('response'),
          ),
        ),
      );
      expect(() => analysis.effectNamed('ABCD'), throwsA(isA<StatsRefusal>()));
      expect(
        () => design.contrastColumn(<int>[9]),
        throwsA(isA<StatsRefusal>()),
      );
    });
  });
}
