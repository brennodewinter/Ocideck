// The run rules, driven over a synthetic chart rather than a real one.
//
// Every stage below has centre 0 and limits ±3, so sigma is exactly 1 and a
// plotted point *is* its own z-score. That is the whole reason for building the
// series by hand instead of computing one: a rule that fires on "four of five
// beyond 1σ" can then be written down as the four numbers it fires on, and a
// reader can check the expectation without recomputing a control limit first.
//
// `control_charts_test.dart` covers rules 1, 2 and 3 on charts that were really
// computed. This file takes the rules the arithmetic of a small worked series
// cannot reach without also tripping something else — 14 alternating points,
// two of three beyond 2σ, fifteen hugging the centre line — plus the two edges
// that decide whether a rule is honest at all: a run may not cross a stage
// boundary, and a point with no spread to judge it against is not judged.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/improvement/stats/stats.dart';

/// A one-stage series with centre 0 and ±3 limits, so point value == z.
ControlChartSeries _unitSeries(List<double> z) => ControlChartSeries(
  label: 'X',
  points: z,
  stages: <ControlChartStage>[
    ControlChartStage(
      label: '',
      from: 0,
      to: z.length,
      centre: 0,
      upper: List<double>.filled(z.length, 3),
      lower: List<double>.filled(z.length, -3),
    ),
  ],
);

List<RunRuleViolation> _fire(List<double> z, RunRule rule) =>
    applyRunRules(_unitSeries(z), rules: <RunRule>{rule});

void main() {
  group('the rules as a catalogue', () {
    test('rule 1 is the same test in both families, and both are listed', () {
      expect(RunRule.nelson1.summary, RunRule.westernElectric1.summary);
      expect(RunRule.nelson1.family, RunRuleFamily.nelson);
      expect(RunRule.westernElectric1.family, RunRuleFamily.westernElectric);
      expect(RunRule.nelson1.number, 1);
      expect(RunRule.westernElectric1.number, 1);
    });

    test('the two published sets are complete and numbered from one', () {
      expect(nelsonRunRules.length, 8);
      expect(westernElectricRunRules.length, 4);
      expect(
        nelsonRunRules.map((RunRule r) => r.number).toList()..sort(),
        <int>[1, 2, 3, 4, 5, 6, 7, 8],
      );
      expect(
        westernElectricRunRules.map((RunRule r) => r.number).toList()..sort(),
        <int>[1, 2, 3, 4],
      );
      expect(
        nelsonRunRules.every((RunRule r) => r.family == RunRuleFamily.nelson),
        isTrue,
      );
      expect(
        westernElectricRunRules.every(
          (RunRule r) => r.family == RunRuleFamily.westernElectric,
        ),
        isTrue,
      );
      expect(
        nelsonRunRules.followedBy(westernElectricRunRules).toSet(),
        RunRule.values.toSet(),
      );
    });

    test('only rule 1 is on unless the report says otherwise', () {
      expect(defaultRunRules, <RunRule>{RunRule.nelson1});
    });

    test('every rule says in one line what it tests', () {
      for (final RunRule rule in RunRule.values) {
        expect(rule.summary, isNotEmpty);
        expect(rule.summary.trim(), rule.summary);
      }
    });
  });

  group('each rule on the pattern it is meant to catch', () {
    test('rule 1: a point past 3σ, and 3σ exactly is not past it', () {
      expect(_fire(<double>[0, 3.01, 0], RunRule.nelson1).single.at, 1);
      expect(_fire(<double>[0, -3.01, 0], RunRule.nelson1).single.at, 1);
      expect(_fire(<double>[0, 3, -3, 0], RunRule.nelson1), isEmpty);
    });

    test('rule 2: nine on one side, and the tenth reports again', () {
      final List<double> nine = List<double>.filled(9, 0.5);
      expect(_fire(nine, RunRule.nelson2).single.points, <int>[
        for (int i = 0; i < 9; i++) i,
      ]);
      expect(_fire(<double>[...nine, 0.5], RunRule.nelson2), hasLength(2));
      expect(_fire(List<double>.filled(8, 0.5), RunRule.nelson2), isEmpty);
      expect(
        _fire(List<double>.filled(9, -0.5), RunRule.nelson2),
        hasLength(1),
      );
    });

    test('rule 2: a point on the centre line ends the run rather than joining '
        'either side', () {
      final List<double> straddling = <double>[
        ...List<double>.filled(5, 0.5),
        0,
        ...List<double>.filled(5, 0.5),
      ];
      expect(_fire(straddling, RunRule.nelson2), isEmpty);
    });

    test('rule 3: six steadily rising, or six steadily falling', () {
      const List<double> rising = <double>[-1, -0.6, -0.2, 0.2, 0.6, 1];
      expect(_fire(rising, RunRule.nelson3).single.at, 5);
      expect(_fire(rising.reversed.toList(), RunRule.nelson3).single.at, 5);
      expect(_fire(<double>[...rising, 1.4], RunRule.nelson3), hasLength(2));
      expect(_fire(rising.take(5).toList(), RunRule.nelson3), isEmpty);
    });

    test('rule 3: a repeat in the middle breaks the climb', () {
      const List<double> plateau = <double>[-1, -0.6, -0.2, -0.2, 0.2, 0.6, 1];
      expect(_fire(plateau, RunRule.nelson3), isEmpty);
    });

    test('rule 4: fourteen alternating up and down', () {
      final List<double> zigzag = <double>[
        for (int i = 0; i < 14; i++) i.isEven ? 0.5 : -0.5,
      ];
      expect(_fire(zigzag, RunRule.nelson4).single.points, <int>[
        for (int i = 0; i < 14; i++) i,
      ]);
      expect(_fire(zigzag.take(13).toList(), RunRule.nelson4), isEmpty);
    });

    test('rule 4: one flat step in the middle resets it', () {
      final List<double> zigzag = <double>[
        for (int i = 0; i < 15; i++) i.isEven ? 0.5 : -0.5,
      ]..[7] = 0.5;
      expect(_fire(zigzag, RunRule.nelson4), isEmpty);
    });

    test('rule 5: two of three beyond 2σ on the same side', () {
      expect(
        _fire(<double>[0, 2.5, 0.1, 2.6], RunRule.nelson5).single.points,
        <int>[1, 3],
      );
      expect(
        _fire(<double>[-2.5, 0.1, -2.6], RunRule.nelson5).single.points,
        <int>[0, 2],
      );
      expect(RunRule.westernElectric2.summary, RunRule.nelson5.summary);
      expect(
        _fire(<double>[0, 2.5, 0.1, 2.6], RunRule.westernElectric2),
        hasLength(1),
      );
    });

    test('rule 5: opposite sides do not add up', () {
      expect(_fire(<double>[2.5, 0.1, -2.6], RunRule.nelson5), isEmpty);
    });

    test('rule 5: the window is reported only when it just completed', () {
      // Points 0 and 1 offend; without the "last point offends" condition the
      // windows ending at 2 and at 3 would report the same pair twice more.
      expect(
        _fire(<double>[2.5, 2.6, 0.1, 0.2], RunRule.nelson5).single.points,
        <int>[0, 1],
      );
    });

    test('rule 6: four of five beyond 1σ on the same side', () {
      expect(
        _fire(<double>[1.2, 1.3, 0.2, 1.4, 1.5], RunRule.nelson6).single.points,
        <int>[0, 1, 3, 4],
      );
      expect(
        _fire(<double>[
          -1.2,
          -1.3,
          0.2,
          -1.4,
          -1.5,
        ], RunRule.nelson6).single.points,
        <int>[0, 1, 3, 4],
      );
      expect(RunRule.westernElectric3.summary, RunRule.nelson6.summary);
      expect(
        _fire(<double>[1.2, 1.3, 0.2, 1.4, 1.5], RunRule.westernElectric3),
        hasLength(1),
      );
      expect(
        _fire(<double>[1.2, 0.3, 0.2, 1.4, 1.5], RunRule.nelson6),
        isEmpty,
      );
    });

    test('rule 7: fifteen in a row hugging the centre line', () {
      expect(
        _fire(List<double>.filled(15, 0.5), RunRule.nelson7).single.at,
        14,
      );
      expect(_fire(List<double>.filled(14, 0.5), RunRule.nelson7), isEmpty);
    });

    test('rule 7: hugging means within 1σ, on either side, and 1σ exactly is '
        'not within', () {
      final List<double> mixed = <double>[
        for (int i = 0; i < 15; i++) i.isEven ? 0.9 : -0.9,
      ];
      expect(_fire(mixed, RunRule.nelson7), hasLength(1));
      final List<double> touching = List<double>.filled(15, 0.5)..[7] = 1;
      expect(_fire(touching, RunRule.nelson7), isEmpty);
    });

    test('rule 8: eight beyond 1σ with both sides represented', () {
      final List<double> mixed = <double>[
        for (int i = 0; i < 8; i++) i.isEven ? 1.5 : -1.5,
      ];
      expect(_fire(mixed, RunRule.nelson8).single.points, <int>[
        for (int i = 0; i < 8; i++) i,
      ]);
      expect(_fire(mixed.take(7).toList(), RunRule.nelson8), isEmpty);
    });

    test('rule 8: eight on one side is rule 2 territory, not rule 8', () {
      expect(_fire(List<double>.filled(8, 1.5), RunRule.nelson8), isEmpty);
    });

    test('Western Electric 4 is eight on one side, one point earlier than '
        "Nelson's nine", () {
      final List<double> eight = List<double>.filled(8, 0.5);
      expect(_fire(eight, RunRule.westernElectric4), hasLength(1));
      expect(_fire(eight, RunRule.nelson2), isEmpty);
    });
  });

  group('what a run may not cross', () {
    test('a stage boundary breaks a run instead of continuing it', () {
      final List<double> ten = List<double>.filled(10, 0.5);
      expect(_fire(ten, RunRule.nelson2), hasLength(2));

      final ControlChartSeries split = ControlChartSeries(
        label: 'X',
        points: ten,
        stages: <ControlChartStage>[
          ControlChartStage(
            label: 'before',
            from: 0,
            to: 5,
            centre: 0,
            upper: List<double>.filled(5, 3),
            lower: List<double>.filled(5, -3),
          ),
          ControlChartStage(
            label: 'after',
            from: 5,
            to: 10,
            centre: 0,
            upper: List<double>.filled(5, 3),
            lower: List<double>.filled(5, -3),
          ),
        ],
      );
      expect(applyRunRules(split, rules: <RunRule>{RunRule.nelson2}), isEmpty);
    });

    test(
      'a point with no spread to judge it against is skipped, not judged',
      () {
        // A stage whose limits sit on the centre line has sigma 0: an attribute
        // chart on a subgroup that saw nothing. Judging a point against a zero
        // spread would put every one of them infinitely far out.
        final ControlChartSeries flat = ControlChartSeries(
          label: 'p',
          points: List<double>.filled(9, 0.5),
          stages: <ControlChartStage>[
            ControlChartStage(
              label: '',
              from: 0,
              to: 9,
              centre: 0,
              upper: List<double>.filled(9, 0),
              lower: List<double>.filled(9, 0),
            ),
          ],
        );
        expect(applyRunRules(flat, rules: nelsonRunRules), isEmpty);
      },
    );

    test(
      'the skipped points close the gap rather than shifting the numbering',
      () {
        // Points 0..3 have no spread; the nine that do are 4..12, and the
        // violation must name those absolute indices even though the rule saw
        // them as a run of nine starting at zero.
        final ControlChartSeries partial = ControlChartSeries(
          label: 'p',
          points: List<double>.filled(13, 0.5),
          stages: <ControlChartStage>[
            ControlChartStage(
              label: '',
              from: 0,
              to: 13,
              centre: 0,
              upper: <double>[for (int i = 0; i < 13; i++) i < 4 ? 0 : 3],
              lower: <double>[for (int i = 0; i < 13; i++) i < 4 ? 0 : -3],
            ),
          ],
        );
        expect(
          applyRunRules(
            partial,
            rules: <RunRule>{RunRule.nelson2},
          ).single.points,
          <int>[4, 5, 6, 7, 8, 9, 10, 11, 12],
        );
      },
    );

    test('a stage with nothing left to judge contributes nothing', () {
      final ControlChartSeries empty = ControlChartSeries(
        label: 'X',
        points: const <double>[0.5, 0.5],
        stages: <ControlChartStage>[
          const ControlChartStage(
            label: '',
            from: 0,
            to: 2,
            centre: 0,
            upper: <double>[0, 0],
            lower: <double>[0, 0],
          ),
        ],
      );
      expect(applyRunRules(empty, rules: nelsonRunRules), isEmpty);
    });
  });

  group('how the findings come back', () {
    test('ordered by the point that completed them, then by rule', () {
      // Rule 6 completes at point 4, rule 2 at point 8, rule 1 at point 9.
      final List<double> series = <double>[
        1.2, 1.3, 0.2, 1.4, 1.5, 1.5, 1.5, 1.5, 1.5, 3.5, //
      ];
      final List<RunRuleViolation> found = applyRunRules(
        _unitSeries(series),
        rules: nelsonRunRules,
      );
      expect(found, isNotEmpty);
      for (int i = 1; i < found.length; i++) {
        expect(found[i].at, greaterThanOrEqualTo(found[i - 1].at));
        if (found[i].at == found[i - 1].at) {
          expect(found[i].rule.index, greaterThan(found[i - 1].rule.index));
        }
      }
      // Two rules complete on the last point; the tie is broken by rule order,
      // so the one that fires first in the book is reported first.
      final List<RunRule> atNine = <RunRule>[
        for (final RunRuleViolation v in found)
          if (v.at == 9) v.rule,
      ];
      expect(atNine.first, RunRule.nelson1);
      expect(atNine, contains(RunRule.nelson6));
    });

    test('a violation names its family, its number and a one-based point', () {
      final RunRuleViolation v = _fire(<double>[
        0,
        3.5,
      ], RunRule.nelson1).single;
      expect(v.at, 1);
      expect(v.points, <int>[1]);
      expect(v.toString(), 'nelson 1 at 2: ${RunRule.nelson1.summary}');
    });

    test('the completing point is the last one of the window', () {
      final RunRuleViolation v = _fire(
        List<double>.filled(9, 0.5),
        RunRule.nelson2,
      ).single;
      expect(v.at, v.points.last);
      expect(v.at, 8);
    });

    test('an empty rule set finds nothing, however bad the chart', () {
      expect(
        applyRunRules(
          _unitSeries(<double>[9, -9, 9, -9]),
          rules: const <RunRule>{},
        ),
        isEmpty,
      );
    });
  });
}
