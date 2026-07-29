// Gage R&R by the ANOVA method.
//
// The study below is the smallest crossed design there is — two parts, two
// operators, two measurements each — with the values chosen so the whole
// ANOVA table can be worked out on paper:
//
//   cell means 1.5, 3.5, 5.5, 7.5; grand mean 4.5
//   Part SS      = 2·2·((2.5−4.5)² + (6.5−4.5)²)               = 32, df 1
//   Operator SS  = 2·2·((3.5−4.5)² + (5.5−4.5)²)               =  8, df 1
//   Part×Op SS   = 0 (the interaction cancels exactly)         =  0, df 1
//   Repeatability SS = 4 cells × 0.5                           =  2, df 4
//
// The interaction is not significant, so it is pooled: the residual mean
// square becomes (0 + 2)/5 = 0.4, and every variance component below follows
// from that one number.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/improvement/stats/stats.dart';

const List<List<List<double>>> _study = <List<List<double>>>[
  <List<double>>[
    <double>[1, 2],
    <double>[3, 4],
  ],
  <List<double>>[
    <double>[5, 6],
    <double>[7, 8],
  ],
];

void main() {
  group('the ANOVA table, worked by hand', () {
    final GageRr gage = GageRr.crossed(_study, tolerance: 20);

    test('the study is described by what was actually measured', () {
      expect(gage.partCount, 2);
      expect(gage.operatorCount, 2);
      expect(gage.replicateCount, 2);
    });

    test('the four sums of squares and their degrees of freedom', () {
      expect(gage.table.map((VarianceComponent c) => c.name).toList(), <String>[
        'Part',
        'Operator',
        'Part × Operator',
        'Repeatability',
      ]);
      expect(gage.table[0].sumOfSquares, closeTo(32, 1e-12));
      expect(gage.table[0].degreesOfFreedom, 1);
      expect(gage.table[1].sumOfSquares, closeTo(8, 1e-12));
      expect(gage.table[1].degreesOfFreedom, 1);
      expect(gage.table[2].sumOfSquares, closeTo(0, 1e-12));
      expect(gage.table[2].degreesOfFreedom, 1);
      expect(gage.table[3].sumOfSquares, closeTo(2, 1e-12));
      expect(gage.table[3].degreesOfFreedom, 4);
      expect(gage.table[3].meanSquare, closeTo(0.5, 1e-12));
    });

    test(
      'an interaction that is not there is pooled, and that is recorded',
      () {
        expect(gage.interactionPValue, closeTo(1, 1e-12));
        expect(gage.interactionPooled, isTrue);
        expect(gage.interactionVariance, 0);
        expect(gage.repeatabilityVariance, closeTo(0.4, 1e-12));
      },
    );

    test('the variance components follow from the pooled residual', () {
      expect(gage.operatorVariance, closeTo(1.9, 1e-12));
      expect(gage.partVariance, closeTo(7.9, 1e-12));
      expect(gage.reproducibilityVariance, closeTo(1.9, 1e-12));
      expect(gage.gageVariance, closeTo(2.3, 1e-12));
      expect(gage.totalVariance, closeTo(10.2, 1e-12));
    });

    test(
      'the two percentages differ, and the larger one is the honest one',
      () {
        expect(gage.percentContribution, closeTo(22.549, 0.001));
        expect(gage.percentStudyVariation, closeTo(47.486, 0.001));
        expect(
          gage.percentStudyVariation,
          greaterThan(gage.percentContribution),
        );
      },
    );

    test('the specification width gives a third figure again', () {
      expect(gage.percentTolerance, closeTo(45.497, 0.001));
      expect(GageRr.crossed(_study).percentTolerance, isNull);
      expect(GageRr.crossed(_study, tolerance: 0).percentTolerance, isNull);
    });

    test('the number of distinct categories is floored, not rounded', () {
      // 1.41 · √7.9 / √2.3 = 2.61 → two categories: high and low, no more.
      expect(gage.distinctCategories, 2);
    });
  });

  group('a gauge that can see the parts, and one that cannot', () {
    /// Five parts far apart, measured almost identically every time.
    List<List<List<double>>> study(double noise) => <List<List<double>>>[
      for (int part = 0; part < 5; part++)
        <List<double>>[
          for (int operator = 0; operator < 3; operator++)
            <double>[
              part * 10 + operator * noise,
              part * 10 + noise,
              part * 10 - operator * noise,
            ],
        ],
    ];

    test('a precise gauge passes every rule of thumb', () {
      final GageRr good = GageRr.crossed(study(0.05));
      expect(good.percentStudyVariation, lessThan(10));
      expect(good.distinctCategories, greaterThanOrEqualTo(5));
      expect(good.partVariance, greaterThan(good.gageVariance));
    });

    test('a noisy gauge fails them', () {
      final GageRr bad = GageRr.crossed(study(8));
      expect(bad.percentStudyVariation, greaterThan(30));
      expect(bad.distinctCategories, lessThan(5));
    });

    test('the standard deviations are the square roots of the variances', () {
      final GageRr gage = GageRr.crossed(study(0.5));
      expect(gage.gageSd * gage.gageSd, closeTo(gage.gageVariance, 1e-12));
      expect(gage.partSd * gage.partSd, closeTo(gage.partVariance, 1e-12));
      expect(gage.totalSd * gage.totalSd, closeTo(gage.totalVariance, 1e-12));
      expect(
        gage.repeatabilitySd * gage.repeatabilitySd,
        closeTo(gage.repeatabilityVariance, 1e-12),
      );
      expect(
        gage.reproducibilitySd * gage.reproducibilitySd,
        closeTo(gage.reproducibilityVariance, 1e-12),
      );
    });

    test('a real interaction is kept rather than pooled away', () {
      // Operator 1 reads high on part 0 and low on part 1, and nowhere else:
      // exactly the pattern the average-and-range method cannot see.
      final List<List<List<double>>> interacting = <List<List<double>>>[
        <List<double>>[
          <double>[10.0, 10.1],
          <double>[14.0, 14.1],
        ],
        <List<double>>[
          <double>[20.0, 20.1],
          <double>[16.0, 16.1],
        ],
        <List<double>>[
          <double>[30.0, 30.1],
          <double>[30.0, 30.1],
        ],
      ];
      final GageRr gage = GageRr.crossed(interacting);
      expect(gage.interactionPValue, lessThan(0.25));
      expect(gage.interactionPooled, isFalse);
      expect(gage.interactionVariance, greaterThan(0));
      expect(gage.reproducibilityVariance, greaterThan(gage.operatorVariance));
    });
  });

  group('what a Gage R&R refuses', () {
    test('fewer than two parts, operators or measurements', () {
      expect(
        () => GageRr.crossed(<List<List<double>>>[_study.first]),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => GageRr.crossed(<List<List<double>>>[
          <List<double>>[
            <double>[1, 2],
          ],
          <List<double>>[
            <double>[3, 4],
          ],
        ]),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => GageRr.crossed(<List<List<double>>>[
          <List<double>>[
            <double>[1],
            <double>[2],
          ],
          <List<double>>[
            <double>[3],
            <double>[4],
          ],
        ]),
        throwsA(isA<StatsRefusal>()),
      );
    });

    test('a study that is not balanced', () {
      expect(
        () => GageRr.crossed(<List<List<double>>>[
          <List<double>>[
            <double>[1, 2],
            <double>[3, 4],
          ],
          <List<double>>[
            <double>[5, 6],
          ],
        ]),
        throwsA(
          isA<StatsRefusal>().having(
            (StatsRefusal e) => e.reason,
            'reason',
            contains('balanced'),
          ),
        ),
      );
      expect(
        () => GageRr.crossed(<List<List<double>>>[
          <List<double>>[
            <double>[1, 2],
            <double>[3, 4],
          ],
          <List<double>>[
            <double>[5, 6],
            <double>[7, 8, 9],
          ],
        ]),
        throwsA(isA<StatsRefusal>()),
      );
    });
  });
}
