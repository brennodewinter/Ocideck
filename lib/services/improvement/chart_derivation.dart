// Derives display-only statistics for Procesverbetering chart types
// (PROCESS_IMPROVEMENT.md Phase 2). Control limits, Cpk, Pareto ranks and
// box-plot hinges are computed here and never written back into ChartSpec.
import 'dart:math' as math;

import '../../models/chart.dart';
import '../../models/improvement_y01.dart';
import 'stats/stats.dart';

/// Flattened numeric sample from the first series (I-MR / histogram / box /
/// run). Empty when there is nothing to plot.
List<double> chartPrimarySample(ChartSpec spec) {
  if (spec.series.isEmpty) return const [];
  return List<double>.of(spec.series.first.data);
}

/// I-MR control-chart view model. Null when the sample is too small.
class ControlChartView {
  const ControlChartView({
    required this.values,
    required this.center,
    required this.ucl,
    required this.lcl,
    required this.outOfControl,
  });

  final List<double> values;
  final double center;
  final double ucl;
  final double lcl;
  final Set<int> outOfControl;
}

ControlChartView? deriveIndividualsChart(ChartSpec spec) {
  final values = chartPrimarySample(spec);
  if (values.length < 2) return null;
  try {
    final chart = ControlChart.individualsMovingRange(values);
    final primary = chart.primary;
    final stage = primary.stages.first;
    // Stage limits are per-point arrays; for a single stage they are constant.
    final ucl = stage.upper.first;
    final lcl = stage.lower.first;
    final flags = <int>{...primary.outOfControlPoints};
    for (final hit in applyRunRules(primary)) {
      flags.addAll(hit.points);
    }
    return ControlChartView(
      values: values,
      center: stage.centre,
      ucl: ucl,
      lcl: lcl,
      outOfControl: flags,
    );
  } on StatsRefusal {
    return null;
  }
}

/// Histogram bins + optional capability callout.
class HistogramView {
  const HistogramView({
    required this.edges,
    required this.counts,
    this.cpk,
    this.normalityPValue,
  });

  final List<double> edges;
  final List<int> counts;
  final double? cpk;
  final double? normalityPValue;
}

HistogramView? deriveHistogram(
  ChartSpec spec, {
  int binCount = 10,
  ImprovementY01Metric y01 = ImprovementY01Metric.empty,
}) {
  final values = chartPrimarySample(spec);
  if (values.length < 2) return null;
  try {
    final summary = Descriptives.of(values);
    final min = summary.minimum;
    final max = summary.maximum;
    final span = max - min;
    final width = span <= 0 ? 1.0 : span / binCount;
    final edges = [for (var i = 0; i <= binCount; i++) min + i * width];
    final counts = List<int>.filled(binCount, 0);
    for (final v in values) {
      var i = ((v - min) / width).floor();
      if (i >= binCount) i = binCount - 1;
      if (i < 0) i = 0;
      counts[i]++;
    }
    double? cpk;
    double? normalityPValue;
    final limits = resolveChartSpecLimits(
      yRef: spec.yRef,
      localUsl: spec.usl,
      localLsl: spec.lsl,
      localProcessTarget: spec.processTarget,
      y01: y01,
    );
    if (limits.usl != null || limits.lsl != null) {
      try {
        final cap = CapabilityAnalysis.of(
          values,
          lowerSpec: limits.lsl,
          upperSpec: limits.usl,
          target: limits.processTarget,
        );
        cpk = cap.cpk;
        normalityPValue = cap.normality.pValue;
      } on StatsRefusal {
        // Capability refused — still show the histogram.
      }
    }
    return HistogramView(
      edges: edges,
      counts: counts,
      cpk: cpk,
      normalityPValue: normalityPValue,
    );
  } on StatsRefusal {
    return null;
  }
}

/// Pareto: categories sorted by descending count, with cumulative %.
class ParetoView {
  const ParetoView({
    required this.labels,
    required this.values,
    required this.cumulativePct,
    required this.vitalFewCount,
  });

  final List<String> labels;
  final List<double> values;
  final List<double> cumulativePct;
  final int vitalFewCount;
}

ParetoView? derivePareto(ChartSpec spec) {
  if (spec.series.isEmpty || spec.x.isEmpty) return null;
  final data = spec.series.first.data;
  final n = math.min(spec.x.length, data.length);
  if (n == 0) return null;
  final pairs = [for (var i = 0; i < n; i++) (label: spec.x[i], value: data[i])]
    ..sort((a, b) => b.value.compareTo(a.value));
  final total = pairs.fold<double>(0, (s, p) => s + p.value);
  if (total <= 0) return null;
  var running = 0.0;
  final cum = <double>[];
  var vital = 0;
  for (final p in pairs) {
    running += p.value;
    final pct = 100 * running / total;
    cum.add(pct);
    if (pct <= 80) vital++;
  }
  if (vital == 0) vital = 1;
  return ParetoView(
    labels: [for (final p in pairs) p.label],
    values: [for (final p in pairs) p.value],
    cumulativePct: cum,
    vitalFewCount: vital,
  );
}

/// Box-plot hinges for each series with enough points.
class BoxPlotView {
  const BoxPlotView({required this.boxes});

  final List<BoxPlotBox> boxes;
}

class BoxPlotBox {
  const BoxPlotBox({
    required this.label,
    required this.q1,
    required this.median,
    required this.q3,
    required this.whiskerLow,
    required this.whiskerHigh,
    required this.outliers,
  });

  final String label;
  final double q1;
  final double median;
  final double q3;
  final double whiskerLow;
  final double whiskerHigh;
  final List<double> outliers;
}

BoxPlotView? deriveBoxPlot(ChartSpec spec) {
  if (spec.series.isEmpty) return null;
  final boxes = <BoxPlotBox>[];
  for (var si = 0; si < spec.series.length; si++) {
    final series = spec.series[si];
    if (series.data.length < 4) continue;
    try {
      final d = Descriptives.of(series.data);
      final q1 = d.firstQuartile;
      final q3 = d.thirdQuartile;
      final iqr = q3 - q1;
      final lowFence = q1 - 1.5 * iqr;
      final highFence = q3 + 1.5 * iqr;
      final inside = series.data.where((v) => v >= lowFence && v <= highFence);
      final outliers = series.data
          .where((v) => v < lowFence || v > highFence)
          .toList();
      boxes.add(
        BoxPlotBox(
          label: series.name.isEmpty ? 'S${si + 1}' : series.name,
          q1: q1,
          median: d.median,
          q3: q3,
          whiskerLow: inside.isEmpty ? q1 : inside.reduce(math.min),
          whiskerHigh: inside.isEmpty ? q3 : inside.reduce(math.max),
          outliers: outliers,
        ),
      );
    } on StatsRefusal {
      continue;
    }
  }
  if (boxes.isEmpty) return null;
  return BoxPlotView(boxes: boxes);
}

// ── DOE charts (PROCESS_IMPROVEMENT.md Phase 9) ─────────────────────────────
//
// Grid convention for [ChartType.mainEffects] and [ChartType.interaction]:
//
//   * Each **row** is one run. Rows may appear in any order; they are matched to
//     the design by their coded factor levels, not by row label.
//   * The first *k* **series** are factors, in order A, B, C… (names are labels
//     only; position defines the factor). Cell values are coded levels: **−1**
//     (low) or **+1** (high). Values within 0.01 of ±1 are accepted.
//   * The **last series** is the response (Y). Its name is cosmetic.
//   * Run count must equal 2^k (full factorial) or a published 2^(k−p) fraction
//     for the same k. Replicates repeat the whole design block (run count is an
//     integer multiple of the distinct combinations).
//
// Nothing from [FactorialAnalysis] — effects, aliases, Lenth thresholds — is
// written back into [ChartSpec]; only the raw grid is stored.

/// Parsed DOE grid: design, responses in design order, and per-run coded rows.
class DoeChartData {
  const DoeChartData({
    required this.design,
    required this.responses,
    required this.codedRuns,
    required this.factorLabels,
  });

  final FactorialDesign design;
  final List<double> responses;
  final List<List<int>> codedRuns;
  final List<String> factorLabels;
}

int? _parseCodedLevel(double value) {
  if ((value + 1).abs() < 0.01) return -1;
  if ((value - 1).abs() < 0.01) return 1;
  return null;
}

FactorialDesign? _designForFactorCount(
  int factorCount,
  int pointCount,
  List<DesignFactor> factors,
) {
  if (pointCount == 1 << factorCount) {
    return FactorialDesign.full(factors);
  }
  for (var p = 1; p <= factorCount - 2; p++) {
    if (pointCount != 1 << (factorCount - p)) continue;
    try {
      return FactorialDesign.fractional(factors, fraction: p);
    } on StatsRefusal {
      continue;
    }
  }
  return null;
}

bool _sameCoded(List<int> a, List<int> b) =>
    a.length == b.length &&
    List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);

DoeChartData? parseDoeChartGrid(ChartSpec spec) {
  if (spec.series.length < 3 || spec.x.isEmpty) return null;
  final factorCount = spec.series.length - 1;
  if (factorCount < 2) return null;

  final nRows = spec.x.length;
  final codedRows = <List<int>>[];
  for (var r = 0; r < nRows; r++) {
    final coded = <int>[];
    for (var f = 0; f < factorCount; f++) {
      if (r >= spec.series[f].data.length) return null;
      final level = _parseCodedLevel(spec.series[f].data[r]);
      if (level == null) return null;
      coded.add(level);
    }
    codedRows.add(coded);
  }

  final responseSeries = spec.series.last;
  if (responseSeries.data.length < nRows) return null;

  final factors = <DesignFactor>[
    for (var i = 0; i < factorCount; i++)
      DesignFactor(
        spec.series[i].name.isEmpty
            ? designFactorLetters[i]
            : spec.series[i].name,
      ),
  ];
  final labels = [for (final f in factors) f.name];

  FactorialDesign? design;
  var replicates = 1;
  for (var r = 1; r <= nRows; r++) {
    if (nRows % r != 0) continue;
    final points = nRows ~/ r;
    final candidate = _designForFactorCount(factorCount, points, factors);
    if (candidate != null) {
      design = candidate;
      replicates = r;
      break;
    }
  }
  if (design == null) return null;

  final designWithRep = replicates == 1
      ? design
      : (design.fraction == 0
            ? FactorialDesign.full(factors, replicates: replicates)
            : FactorialDesign.fractional(
                factors,
                fraction: design.fraction,
                replicates: replicates,
              ));

  final byPoint = List<List<double>>.generate(
    designWithRep.pointCount,
    (_) => <double>[],
  );
  for (var r = 0; r < nRows; r++) {
    final coded = codedRows[r];
    var pointIndex = -1;
    for (var p = 0; p < designWithRep.pointCount; p++) {
      if (_sameCoded(coded, designWithRep.points[p])) {
        pointIndex = p;
        break;
      }
    }
    if (pointIndex < 0) return null;
    if (byPoint[pointIndex].length >= replicates) return null;
    byPoint[pointIndex].add(responseSeries.data[r]);
  }
  for (final cell in byPoint) {
    if (cell.length != replicates) return null;
  }

  final responses = <double>[
    for (var p = 0; p < designWithRep.pointCount; p++) ...byPoint[p],
  ];

  return DoeChartData(
    design: designWithRep,
    responses: responses,
    codedRuns: codedRows,
    factorLabels: labels,
  );
}

/// One main-effect line: mean response at coded −1 and +1.
class MainEffectLine {
  const MainEffectLine({
    required this.label,
    required this.low,
    required this.high,
  });

  final String label;
  final double low;
  final double high;
}

class MainEffectsView {
  const MainEffectsView({required this.lines, required this.grandMean});

  final List<MainEffectLine> lines;
  final double grandMean;
}

MainEffectsView? deriveMainEffects(ChartSpec spec) {
  final grid = parseDoeChartGrid(spec);
  if (grid == null) return null;
  try {
    final analysis = FactorialAnalysis.of(grid.design, grid.responses);
    final lines = <MainEffectLine>[
      for (final effect in analysis.mainEffects)
        MainEffectLine(
          label: effect.name,
          low: analysis.grandMean - effect.effect / 2,
          high: analysis.grandMean + effect.effect / 2,
        ),
    ];
    if (lines.isEmpty) return null;
    return MainEffectsView(lines: lines, grandMean: analysis.grandMean);
  } on StatsRefusal {
    return null;
  }
}

/// One line in an interaction panel (second factor held at one level).
class InteractionLine {
  const InteractionLine({
    required this.label,
    required this.atFactorLow,
    required this.atFactorHigh,
  });

  final String label;
  final double atFactorLow;
  final double atFactorHigh;
}

/// One two-factor interaction: paired lines over the first factor's levels.
class InteractionPanel {
  const InteractionPanel({required this.label, required this.lines});

  final String label;
  final List<InteractionLine> lines;
}

class InteractionView {
  const InteractionView({required this.panels});

  final List<InteractionPanel> panels;
}

double _meanResponseWhere(
  List<List<int>> runs,
  List<double> responses,
  Map<int, int> levels,
) {
  var sum = 0.0;
  var count = 0;
  for (var r = 0; r < runs.length; r++) {
    var match = true;
    for (final entry in levels.entries) {
      if (runs[r][entry.key] != entry.value) {
        match = false;
        break;
      }
    }
    if (!match) continue;
    sum += responses[r];
    count++;
  }
  return count == 0 ? double.nan : sum / count;
}

InteractionView? deriveInteraction(ChartSpec spec) {
  final grid = parseDoeChartGrid(spec);
  if (grid == null || grid.design.factorCount < 2) return null;
  final runs = grid.codedRuns;
  final responses = spec.series.last.data;
  if (responses.length < runs.length) return null;
  final k = grid.design.factorCount;
  final panels = <InteractionPanel>[];
  for (var a = 0; a < k - 1; a++) {
    for (var b = a + 1; b < k; b++) {
      final nameA = grid.factorLabels[a];
      final nameB = grid.factorLabels[b];
      final lineLow = InteractionLine(
        label: '$nameB −',
        atFactorLow: _meanResponseWhere(runs, responses, {a: -1, b: -1}),
        atFactorHigh: _meanResponseWhere(runs, responses, {a: 1, b: -1}),
      );
      final lineHigh = InteractionLine(
        label: '$nameB +',
        atFactorLow: _meanResponseWhere(runs, responses, {a: -1, b: 1}),
        atFactorHigh: _meanResponseWhere(runs, responses, {a: 1, b: 1}),
      );
      if ([
        lineLow.atFactorLow,
        lineLow.atFactorHigh,
        lineHigh.atFactorLow,
        lineHigh.atFactorHigh,
      ].any((v) => v.isNaN)) {
        continue;
      }
      panels.add(
        InteractionPanel(label: '$nameA × $nameB', lines: [lineLow, lineHigh]),
      );
    }
  }
  if (panels.isEmpty) return null;
  return InteractionView(panels: panels);
}

/// Grid rows for a factorial design table (coded factors + empty Y column).
class DoeDesignGrid {
  const DoeDesignGrid({
    required this.xLabels,
    required this.seriesNames,
    required this.cellValues,
  });

  final List<String> xLabels;
  final List<String> seriesNames;
  final List<List<String>> cellValues;
}

/// Builds a paste-friendly design table for the chart grid.
DoeDesignGrid? generateDoeDesignGrid({
  required int factorCount,
  required bool fractional,
  int fraction = 1,
}) {
  if (factorCount < 2 || factorCount > designFactorLetters.length) return null;
  final factors = <DesignFactor>[
    for (var i = 0; i < factorCount; i++)
      DesignFactor(String.fromCharCode(65 + i)),
  ];
  try {
    final FactorialDesign design = fractional
        ? FactorialDesign.fractional(factors, fraction: fraction)
        : FactorialDesign.full(factors);
    final factorNames = [for (final f in factors) f.name];
    return DoeDesignGrid(
      xLabels: [for (var i = 0; i < design.pointCount; i++) '${i + 1}'],
      seriesNames: [...factorNames, 'Y'],
      cellValues: [
        for (var i = 0; i < design.pointCount; i++)
          [for (var j = 0; j < factorCount; j++) '${design.points[i][j]}', ''],
      ],
    );
  } on StatsRefusal {
    return null;
  }
}

/// Normal probability plot (Q-Q) for the first series.
class ProbabilityPlotView {
  const ProbabilityPlotView({
    required this.sortedValues,
    required this.theoreticalQuantiles,
    this.normalityPValue,
  });

  final List<double> sortedValues;
  final List<double> theoreticalQuantiles;
  final double? normalityPValue;
}

/// Blom plotting positions against the standard normal inverse CDF.
ProbabilityPlotView? deriveProbabilityPlot(ChartSpec spec) {
  final values = chartPrimarySample(spec);
  if (values.length < 4) return null;
  try {
    final sorted = List<double>.of(values)..sort();
    final n = sorted.length;
    final theoretical = <double>[
      for (var i = 0; i < n; i++)
        standardNormalQuantile((i + 1 - 0.375) / (n + 0.25)),
    ];
    double? normalityPValue;
    if (n >= 8) {
      try {
        normalityPValue = andersonDarlingNormality(values).pValue;
      } on StatsRefusal {
        // Plot still draws; normality callout omitted.
      }
    }
    return ProbabilityPlotView(
      sortedValues: sorted,
      theoreticalQuantiles: theoretical,
      normalityPValue: normalityPValue,
    );
  } on StatsRefusal {
    return null;
  }
}
