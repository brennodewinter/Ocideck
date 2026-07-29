// Control charts: the limits of a small series worked out by hand, the stage
// machinery, and the run rules.
//
// The I-MR case below is arithmetic anyone can repeat: eight observations with
// a mean of 12.5 and seven moving ranges summing to 11, so MR̄ = 11/7 and
// σ̂ = MR̄/d2(2) = (11/7)/1.1284. Every limit in that group follows from those
// three numbers.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/improvement/stats/stats.dart';

const List<double> _series = <double>[10, 12, 11, 13, 12, 14, 13, 15];

void main() {
  group('individuals and moving range, worked by hand', () {
    final ControlChart chart = ControlChart.individualsMovingRange(_series);

    test('the short-term sigma is MR̄ / d2(2)', () {
      expect(chart.kind, ControlChartKind.individualsMovingRange);
      expect(chart.withinSubgroupSigma, closeTo(1.3926166, 1e-6));
    });

    test('the X chart is centred on the mean, three sigma either side', () {
      final ControlChartSeries x = chart.primary;
      expect(x.label, 'X');
      expect(x.points, _series);
      expect(x.centreAt(0), closeTo(12.5, 1e-12));
      expect(x.upperAt(0), closeTo(16.6778498, 1e-6));
      expect(x.lowerAt(0), closeTo(8.3221502, 1e-6));
      expect(x.sigmaAt(0), closeTo(1.3926166, 1e-6));
    });

    test('the MR chart is centred on MR̄ with the D3/D4 factors', () {
      final ControlChartSeries mr = chart.dispersion!;
      expect(mr.label, 'MR');
      expect(mr.points, <double>[2, 1, 2, 1, 2, 1, 2]);
      expect(mr.centreAt(0), closeTo(11 / 7, 1e-12));
      expect(mr.upperAt(0), closeTo(5.1330455, 1e-6));
      // Below n = 7 the range chart has no lower limit at all.
      expect(mr.lowerAt(0), 0);
    });

    test('a stable series signals nothing', () {
      expect(chart.primary.outOfControlPoints, isEmpty);
      expect(chart.dispersion!.outOfControlPoints, isEmpty);
      expect(applyRunRules(chart.primary), isEmpty);
    });

    test('a point outside its own limit is found', () {
      final ControlChart spiked = ControlChart.individualsMovingRange(<double>[
        ..._series,
        60,
      ]);
      expect(spiked.primary.outOfControlPoints, contains(8));
      final List<RunRuleViolation> fired = applyRunRules(spiked.primary);
      expect(fired, isNotEmpty);
      expect(fired.first.rule, RunRule.nelson1);
      expect(fired.first.at, 8);
    });

    test(
      'the limits are recomputed per stage, not smeared across the change',
      () {
        final ControlChart staged = ControlChart.individualsMovingRange(
          <double>[..._series, 40, 42, 41, 43, 42, 44, 43, 45],
          stageBreaks: const <ControlChartStageBreak>[
            ControlChartStageBreak(from: 8, label: 'After pilot'),
          ],
        );
        final ControlChartSeries x = staged.primary;
        expect(x.stages, hasLength(2));
        expect(x.stages.last.label, 'After pilot');
        expect(x.centreAt(0), closeTo(12.5, 1e-12));
        expect(x.centreAt(8), closeTo(42.5, 1e-12));
        // Both periods are stable *within themselves*, which is the point.
        expect(x.outOfControlPoints, isEmpty);
      },
    );

    test('a chart needs at least two observations', () {
      expect(
        () => ControlChart.individualsMovingRange(<double>[1]),
        throwsA(isA<StatsRefusal>()),
      );
    });

    test('a stage break outside the series is refused', () {
      expect(
        () => ControlChart.individualsMovingRange(
          _series,
          stageBreaks: const <ControlChartStageBreak>[
            ControlChartStageBreak(from: 99),
          ],
        ),
        throwsA(isA<StatsRefusal>()),
      );
    });
  });

  group('X-bar and R over equal subgroups', () {
    final List<List<double>> subgroups = <List<double>>[
      <double>[1, 2, 3, 4],
      <double>[2, 3, 4, 5],
      <double>[3, 4, 5, 6],
    ];
    final ControlChart chart = ControlChart.xBarR(subgroups);

    test('the grand mean and the mean range set the limits', () {
      // Means 2.5, 3.5, 4.5 → grand mean 3.5; every range is 3 → R̄ = 3.
      expect(chart.primary.points, <double>[2.5, 3.5, 4.5]);
      expect(chart.primary.centreAt(0), closeTo(3.5, 1e-12));
      // A2(4) = 3/(d2·√4) = 3/(2.0588·2).
      expect(chart.primary.upperAt(0), closeTo(5.6857395, 1e-6));
      expect(chart.primary.lowerAt(0), closeTo(1.3142605, 1e-6));
      // σ̂ = R̄/d2(4).
      expect(chart.withinSubgroupSigma, closeTo(3 / 2.0588, 1e-9));
    });

    test('the R chart uses D3 and D4', () {
      final ControlChartSeries r = chart.dispersion!;
      expect(r.label, 'R');
      expect(r.points, <double>[3, 3, 3]);
      expect(r.centreAt(0), closeTo(3, 1e-12));
      expect(r.upperAt(0), closeTo(6.8460267, 1e-5));
      expect(r.lowerAt(0), 0);
    });

    test('unequal subgroups are refused rather than guessed at', () {
      expect(
        () => ControlChart.xBarR(<List<double>>[
          <double>[1, 2, 3],
          <double>[1, 2],
        ]),
        throwsA(
          isA<StatsRefusal>().having(
            (StatsRefusal e) => e.reason,
            'reason',
            contains('same size'),
          ),
        ),
      );
    });

    test('X-bar and s use c4 instead of d2', () {
      final ControlChart s = ControlChart.xBarS(subgroups);
      expect(s.kind, ControlChartKind.xBarS);
      expect(s.dispersion!.label, 's');
      // Every subgroup has the same spread, so s̄ is that spread.
      final double spread = Descriptives.of(subgroups.first).standardDeviation;
      expect(s.dispersion!.centreAt(0), closeTo(spread, 1e-12));
      expect(s.withinSubgroupSigma, closeTo(spread / c4For(4), 1e-12));
    });
  });

  group('the attribute charts', () {
    test('a p chart with unequal subgroups has limits that step per point', () {
      final ControlChart chart = ControlChart.p(
        <int>[5, 3, 8, 2],
        <int>[100, 100, 400, 50],
      );
      final ControlChartStage stage = chart.primary.stages.single;
      expect(chart.primary.points, <double>[0.05, 0.03, 0.02, 0.04]);
      // p̄ is pooled from the totals: 18/650.
      expect(stage.upper.first, isNot(stage.upper[2]));
      expect(stage.hasConstantLimits, isFalse);
      expect(() => stage.upperLimit, throwsA(isA<StatsRefusal>()));
      // The largest subgroup gets the tightest limit.
      expect(stage.upper[2], lessThan(stage.upper[3]));
      expect(chart.withinSubgroupSigma, isNull);
    });

    test('a proportion limit is never allowed past one, nor below zero', () {
      final ControlChart chart = ControlChart.p(
        <int>[9, 8, 10, 7],
        <int>[10, 10, 10, 10],
      );
      final ControlChartStage stage = chart.primary.stages.single;
      expect(stage.upper.every((double u) => u <= 1), isTrue);
      expect(stage.lower.every((double l) => l >= 0), isTrue);
    });

    test('an np chart plots counts with a constant subgroup size', () {
      final ControlChart chart = ControlChart.np(<int>[5, 3, 8, 4], 100);
      expect(chart.primary.points, <double>[5, 3, 8, 4]);
      // p̄ = 20/400 = 0.05, so the centre is 5 and σ = √(100·0.05·0.95).
      expect(chart.primary.centreAt(0), closeTo(5, 1e-12));
      expect(chart.primary.sigmaAt(0), closeTo(2.179449, 1e-6));
    });

    test('a c chart is centred on the mean count with σ = √c̄', () {
      final ControlChart chart = ControlChart.c(<int>[4, 6, 5, 5]);
      expect(chart.primary.centreAt(0), closeTo(5, 1e-12));
      expect(chart.primary.upperAt(0), closeTo(5 + 3 * 2.2360680, 1e-6));
      expect(chart.primary.lowerAt(0), 0);
    });

    test('a u chart divides by the area of opportunity', () {
      final ControlChart chart = ControlChart.u(
        <int>[10, 20, 15],
        <int>[5, 10, 5],
      );
      expect(chart.primary.points, <double>[2, 2, 3]);
      expect(chart.primary.upperAt(0), greaterThan(chart.primary.upperAt(1)));
    });

    test('a negative count or an empty subgroup is refused', () {
      expect(() => ControlChart.c(<int>[1, -1]), throwsA(isA<StatsRefusal>()));
      expect(
        () => ControlChart.p(<int>[1, 1], <int>[10, 0]),
        throwsA(isA<StatsRefusal>()),
      );
      expect(
        () => ControlChart.p(<int>[1, 1], <int>[10]),
        throwsA(isA<StatsRefusal>()),
      );
    });
  });

  group('the run rules', () {
    /// A series whose limits are wide enough that only the patterns fire.
    ControlChartSeries seriesOf(List<double> points) =>
        ControlChart.individualsMovingRange(points).primary;

    test('rule 1 is the only one on by default', () {
      expect(defaultRunRules, <RunRule>{RunRule.nelson1});
      expect(nelsonRunRules, hasLength(8));
      expect(westernElectricRunRules, hasLength(4));
    });

    test('nine points on the same side fire Nelson 2', () {
      // Nine points above the mean and nine below, zig-zagging hard enough
      // that the moving ranges keep the limits wide: no point leaves 3σ, so
      // rule 1 stays silent and only the pattern is left to find.
      final List<double> points = <double>[
        for (int i = 0; i < 9; i++) i.isEven ? 11 : 12,
        for (int i = 0; i < 9; i++) i.isEven ? 9 : 8,
      ];
      final ControlChartSeries series = seriesOf(points);
      expect(applyRunRules(series), isEmpty);
      final List<RunRuleViolation> fired = applyRunRules(
        series,
        rules: <RunRule>{RunRule.nelson2},
      );
      expect(fired, isNotEmpty);
      expect(fired.first.rule, RunRule.nelson2);
      expect(fired.first.points, hasLength(9));
    });

    test('six rising points fire Nelson 3', () {
      final ControlChartSeries series = seriesOf(<double>[
        10,
        9,
        11,
        10,
        10.1,
        10.2,
        10.3,
        10.4,
        10.5,
        10.6,
      ]);
      final List<RunRuleViolation> fired = applyRunRules(
        series,
        rules: <RunRule>{RunRule.nelson3},
      );
      expect(fired, isNotEmpty);
      expect(fired.first.points, hasLength(6));
    });

    test(
      'a violation names its family, number and the point it completed on',
      () {
        final ControlChartSeries series = seriesOf(<double>[..._series, 60]);
        final RunRuleViolation fired = applyRunRules(series).first;
        expect(fired.rule.family, RunRuleFamily.nelson);
        expect(fired.rule.number, 1);
        expect(fired.toString(), contains('nelson 1'));
        expect(fired.toString(), contains('beyond 3'));
      },
    );

    test('a run never crosses a stage boundary', () {
      // Nine low points, then nine high ones, with the change declared. Each
      // period is only nine points long, so a run of nine exists inside each —
      // but the eighteen-point run across the change must not be reported.
      final List<double> points = <double>[
        for (int i = 0; i < 9; i++) 10 + (i.isEven ? 0.1 : -0.1),
        for (int i = 0; i < 9; i++) 20 + (i.isEven ? 0.1 : -0.1),
      ];
      final ControlChartSeries series = ControlChart.individualsMovingRange(
        points,
        stageBreaks: const <ControlChartStageBreak>[
          ControlChartStageBreak(from: 9, label: 'After'),
        ],
      ).primary;
      final List<RunRuleViolation> fired = applyRunRules(
        series,
        rules: <RunRule>{RunRule.nelson2},
      );
      // Within a stage the points alternate about their own centre, so no
      // same-side run of nine survives the split.
      expect(fired, isEmpty);
    });

    test(
      'the Western Electric set is its own set, duplicate rule 1 and all',
      () {
        final ControlChartSeries series = seriesOf(<double>[..._series, 60]);
        final List<RunRuleViolation> fired = applyRunRules(
          series,
          rules: westernElectricRunRules,
        );
        expect(
          fired.map((RunRuleViolation v) => v.rule),
          contains(RunRule.westernElectric1),
        );
      },
    );
  });
}
