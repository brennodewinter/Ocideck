part of 'stats.dart';

// Run rules: the patterns that say a chart is telling you something even
// though no point left the limits.
//
// Only rule 1 is on by default, and that is a considered position rather than
// caution. Each extra rule raises the chance of a false alarm on a process
// that is behaving perfectly; switch all eight on and a stable chart signals
// somewhere every few dozen points, after which people stop believing the
// chart. Which rules are in force is therefore always a choice the report
// makes in the open.
//
// Runs never cross a stage boundary. A stage exists because the process
// changed, so "nine points on the same side" that straddles the change is not
// nine points from one process.

/// Where a rule comes from.
enum RunRuleFamily {
  /// Nelson's eight rules (1984), the set most software calls "the" run rules.
  nelson,

  /// The four Western Electric rules (1956), the older and narrower set.
  westernElectric,
}

/// One run rule.
///
/// Nelson 1 and Western Electric 1 are the same test and both are listed:
/// a report says which *set* it applied, and dropping the duplicate would make
/// a Western Electric read-out silently miss its own first rule.
enum RunRule {
  nelson1(RunRuleFamily.nelson, 1, 'One point beyond 3σ from the centre line'),
  nelson2(RunRuleFamily.nelson, 2, 'Nine points in a row on the same side'),
  nelson3(
    RunRuleFamily.nelson,
    3,
    'Six points in a row steadily rising or falling',
  ),
  nelson4(
    RunRuleFamily.nelson,
    4,
    'Fourteen points in a row alternating up and down',
  ),
  nelson5(
    RunRuleFamily.nelson,
    5,
    'Two of three consecutive points beyond 2σ on the same side',
  ),
  nelson6(
    RunRuleFamily.nelson,
    6,
    'Four of five consecutive points beyond 1σ on the same side',
  ),
  nelson7(
    RunRuleFamily.nelson,
    7,
    'Fifteen points in a row within 1σ of the centre line',
  ),
  nelson8(
    RunRuleFamily.nelson,
    8,
    'Eight points in a row beyond 1σ on both sides',
  ),
  westernElectric1(
    RunRuleFamily.westernElectric,
    1,
    'One point beyond 3σ from the centre line',
  ),
  westernElectric2(
    RunRuleFamily.westernElectric,
    2,
    'Two of three consecutive points beyond 2σ on the same side',
  ),
  westernElectric3(
    RunRuleFamily.westernElectric,
    3,
    'Four of five consecutive points beyond 1σ on the same side',
  ),
  westernElectric4(
    RunRuleFamily.westernElectric,
    4,
    'Eight points in a row on the same side',
  );

  const RunRule(this.family, this.number, this.summary);

  final RunRuleFamily family;

  /// The rule's number within its family.
  final int number;

  /// What the rule tests, in one line. English, and data rather than a
  /// `d(...)` string: the UI layer decides how to present it.
  final String summary;
}

/// Rule 1 only — the default, and the only rule that is on unless a report
/// says otherwise.
const Set<RunRule> defaultRunRules = <RunRule>{RunRule.nelson1};

/// All eight Nelson rules.
const Set<RunRule> nelsonRunRules = <RunRule>{
  RunRule.nelson1,
  RunRule.nelson2,
  RunRule.nelson3,
  RunRule.nelson4,
  RunRule.nelson5,
  RunRule.nelson6,
  RunRule.nelson7,
  RunRule.nelson8,
};

/// All four Western Electric rules.
const Set<RunRule> westernElectricRunRules = <RunRule>{
  RunRule.westernElectric1,
  RunRule.westernElectric2,
  RunRule.westernElectric3,
  RunRule.westernElectric4,
};

/// One firing of one rule.
class RunRuleViolation {
  const RunRuleViolation({required this.rule, required this.points});

  final RunRule rule;

  /// The indices involved, in the series' own numbering, ascending.
  final List<int> points;

  /// The point at which the pattern completed — the one to mark on the chart.
  int get at => points.last;

  @override
  String toString() =>
      '${rule.family.name} ${rule.number} at ${at + 1}: ${rule.summary}';
}

/// Applies [rules] to [series] and returns every firing, ordered by the point
/// at which the pattern completed.
List<RunRuleViolation> applyRunRules(
  ControlChartSeries series, {
  Set<RunRule> rules = defaultRunRules,
}) {
  final List<RunRuleViolation> found = <RunRuleViolation>[];
  for (final ControlChartStage stage in series.stages) {
    final List<int> indices = <int>[];
    final List<double> z = <double>[];
    for (int i = stage.from; i < stage.to; i++) {
      final double sigma = stage.sigmaAt(i);
      if (sigma <= 0) continue;
      indices.add(i);
      z.add((series.points[i] - stage.centre) / sigma);
    }
    if (z.isEmpty) continue;
    for (final RunRule rule in rules) {
      for (final List<int> window in _fire(rule, z)) {
        found.add(
          RunRuleViolation(
            rule: rule,
            points: <int>[for (final int j in window) indices[j]],
          ),
        );
      }
    }
  }
  found.sort((RunRuleViolation a, RunRuleViolation b) {
    final int byPoint = a.at.compareTo(b.at);
    return byPoint != 0 ? byPoint : a.rule.index.compareTo(b.rule.index);
  });
  return found;
}

/// The windows in which [rule] fires over the standardised values [z].
List<List<int>> _fire(RunRule rule, List<double> z) {
  switch (rule) {
    case RunRule.nelson1:
    case RunRule.westernElectric1:
      return <List<int>>[
        for (int i = 0; i < z.length; i++)
          if (z[i].abs() > 3) <int>[i],
      ];
    case RunRule.nelson2:
      return _sameSideRun(z, 9);
    case RunRule.westernElectric4:
      return _sameSideRun(z, 8);
    case RunRule.nelson3:
      return _monotoneRun(z, 6);
    case RunRule.nelson4:
      return _alternatingRun(z, 14);
    case RunRule.nelson5:
    case RunRule.westernElectric2:
      return _kOfNBeyond(z, 2, 3, 2);
    case RunRule.nelson6:
    case RunRule.westernElectric3:
      return _kOfNBeyond(z, 4, 5, 1);
    case RunRule.nelson7:
      return _hugRun(z, 15);
    case RunRule.nelson8:
      return _bothSidesOutsideRun(z, 8);
  }
}

/// [length] consecutive points strictly on one side of the centre line.
List<List<int>> _sameSideRun(List<double> z, int length) {
  final List<List<int>> hits = <List<int>>[];
  int start = 0;
  for (int i = 0; i < z.length; i++) {
    if (i > 0 && (z[i] == 0 || z[i].sign != z[i - 1].sign)) start = i;
    if (z[i] == 0) {
      start = i + 1;
      continue;
    }
    if (i - start + 1 >= length) {
      hits.add(<int>[for (int j = i - length + 1; j <= i; j++) j]);
    }
  }
  return hits;
}

/// [length] consecutive points all rising or all falling.
List<List<int>> _monotoneRun(List<double> z, int length) {
  final List<List<int>> hits = <List<int>>[];
  int rising = 1;
  int falling = 1;
  for (int i = 1; i < z.length; i++) {
    rising = z[i] > z[i - 1] ? rising + 1 : 1;
    falling = z[i] < z[i - 1] ? falling + 1 : 1;
    if (rising >= length || falling >= length) {
      hits.add(<int>[for (int j = i - length + 1; j <= i; j++) j]);
    }
  }
  return hits;
}

/// [length] consecutive points alternating up, down, up, down.
List<List<int>> _alternatingRun(List<double> z, int length) {
  final List<List<int>> hits = <List<int>>[];
  int run = 1;
  for (int i = 1; i < z.length; i++) {
    final double previousStep = i >= 2 ? z[i - 1] - z[i - 2] : 0;
    final double step = z[i] - z[i - 1];
    final bool alternates =
        i >= 2 &&
        step != 0 &&
        previousStep != 0 &&
        step.sign != previousStep.sign;
    run = alternates ? run + 1 : (step == 0 ? 1 : 2);
    if (run >= length) {
      hits.add(<int>[for (int j = i - length + 1; j <= i; j++) j]);
    }
  }
  return hits;
}

/// [k] of [n] consecutive points beyond [sigma]σ on the same side.
///
/// The window is reported only when its *last* point is one of the offenders;
/// otherwise the same pattern is reported again by every later window that
/// still contains it.
///
/// The window is allowed to be short at the start of the series. "Two of three"
/// needs two offenders, not three points: with the first two points both past
/// 2σ the rule has already fired, and waiting for a third would let the worst
/// possible opening go unreported — the run rules exist to signal early.
List<List<int>> _kOfNBeyond(List<double> z, int k, int n, int sigma) {
  final List<List<int>> hits = <List<int>>[];
  for (int end = 0; end < z.length; end++) {
    if (z[end].abs() <= sigma) continue;
    final int start = end - n + 1 < 0 ? 0 : end - n + 1;
    for (final int side in const <int>[1, -1]) {
      final List<int> offenders = <int>[
        for (int j = start; j <= end; j++)
          if (z[j] * side > sigma) j,
      ];
      if (offenders.length >= k && offenders.last == end) {
        hits.add(offenders);
      }
    }
  }
  return hits;
}

/// [length] consecutive points all within 1σ — a chart that hugs its centre
/// line, which usually means the limits were computed from the wrong spread.
List<List<int>> _hugRun(List<double> z, int length) {
  final List<List<int>> hits = <List<int>>[];
  int run = 0;
  for (int i = 0; i < z.length; i++) {
    run = z[i].abs() < 1 ? run + 1 : 0;
    if (run >= length) {
      hits.add(<int>[for (int j = i - length + 1; j <= i; j++) j]);
    }
  }
  return hits;
}

/// [length] consecutive points all beyond 1σ, with both sides represented —
/// the signature of two streams mixed into one chart.
List<List<int>> _bothSidesOutsideRun(List<double> z, int length) {
  final List<List<int>> hits = <List<int>>[];
  int run = 0;
  for (int i = 0; i < z.length; i++) {
    run = z[i].abs() > 1 ? run + 1 : 0;
    if (run < length) continue;
    final List<int> window = <int>[for (int j = i - length + 1; j <= i; j++) j];
    final bool above = window.any((int j) => z[j] > 1);
    final bool below = window.any((int j) => z[j] < -1);
    if (above && below) hits.add(window);
  }
  return hits;
}
