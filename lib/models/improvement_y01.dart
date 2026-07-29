/// Primary Y metric (**Y-01**) for a Procesverbetering deck.
///
/// Stored as flat front-matter keys (`ocideck_improvement_y01`,
/// `ocideck_improvement_y01_usl`, …) because FILE_FORMAT forbids nested YAML.
/// Charts with `yRef: "Y-01"` resolve USL/LSL/target from this at draw time —
/// never write-through into the chart JSON (PROCESS_IMPROVEMENT.md §3.6).
class ImprovementY01Metric {
  const ImprovementY01Metric({
    this.name = '',
    this.unit = '',
    this.usl,
    this.lsl,
    this.target,
    this.baseline,
    this.goal,
  });

  static const empty = ImprovementY01Metric();

  /// Free-text description / name (`ocideck_improvement_y01`).
  final String name;
  final String unit;
  final double? usl;
  final double? lsl;
  final double? target;
  final double? baseline;
  final double? goal;

  bool get hasSpecLimits => usl != null || lsl != null;

  bool get isEmpty =>
      name.isEmpty &&
      unit.isEmpty &&
      usl == null &&
      lsl == null &&
      target == null &&
      baseline == null &&
      goal == null;

  ImprovementY01Metric copyWith({
    String? name,
    String? unit,
    double? usl,
    double? lsl,
    double? target,
    double? baseline,
    double? goal,
    bool clearUsl = false,
    bool clearLsl = false,
    bool clearTarget = false,
    bool clearBaseline = false,
    bool clearGoal = false,
  }) => ImprovementY01Metric(
    name: name ?? this.name,
    unit: unit ?? this.unit,
    usl: clearUsl ? null : (usl ?? this.usl),
    lsl: clearLsl ? null : (lsl ?? this.lsl),
    target: clearTarget ? null : (target ?? this.target),
    baseline: clearBaseline ? null : (baseline ?? this.baseline),
    goal: clearGoal ? null : (goal ?? this.goal),
  );
}

/// Effective chart spec limits after optional Y-ref resolution.
class ChartSpecLimits {
  const ChartSpecLimits({this.usl, this.lsl, this.processTarget});

  final double? usl;
  final double? lsl;
  final double? processTarget;
}

/// Resolve USL/LSL/target for a chart: when [yRef] is `Y-01`, deck wins;
/// otherwise local chart fields. Never writes back into the chart.
ChartSpecLimits resolveChartSpecLimits({
  required String? yRef,
  required double? localUsl,
  required double? localLsl,
  required double? localProcessTarget,
  required ImprovementY01Metric y01,
}) {
  final ref = yRef?.trim().toUpperCase();
  if (ref == 'Y-01') {
    return ChartSpecLimits(
      usl: y01.usl,
      lsl: y01.lsl,
      processTarget: y01.target,
    );
  }
  return ChartSpecLimits(
    usl: localUsl,
    lsl: localLsl,
    processTarget: localProcessTarget,
  );
}
