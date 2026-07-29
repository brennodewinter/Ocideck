// Pure helpers for Procesverbetering analysis dialogs (Phase 8).
// Parsing and stats calls live here so widgets stay thin and tests stay fast.
import '../../models/chart.dart';
import 'stats/stats.dart';

/// One number per line, or separated by comma, semicolon or tab.
List<double> parseNumberColumn(String raw) {
  final out = <double>[];
  for (final part in raw.split(RegExp(r'[\n,;\t]+'))) {
    final text = part.trim().replaceAll(',', '.');
    if (text.isEmpty) continue;
    final value = double.tryParse(text);
    if (value != null) out.add(value);
  }
  return out;
}

/// Groups of numbers separated by a blank line (or a line that is only whitespace).
List<List<double>> parseGroupedNumberBlocks(String raw) {
  final groups = <List<double>>[];
  final buf = StringBuffer();
  for (final line in raw.split('\n')) {
    if (line.trim().isEmpty) {
      if (buf.isNotEmpty) {
        groups.add(parseNumberColumn(buf.toString()));
        buf.clear();
      }
      continue;
    }
    if (buf.isNotEmpty) buf.write('\n');
    buf.write(line);
  }
  if (buf.isNotEmpty) groups.add(parseNumberColumn(buf.toString()));
  return groups.where((g) => g.isNotEmpty).toList();
}

/// Two aligned columns: one X and one Y value per row.
({List<double> x, List<double> y})? parseXYColumns(String xRaw, String yRaw) {
  final xs = parseNumberColumn(xRaw);
  final ys = parseNumberColumn(yRaw);
  if (xs.isEmpty || ys.isEmpty || xs.length != ys.length) return null;
  return (x: xs, y: ys);
}

/// Gage R&R table: Part, Operator, Value — header row optional.
List<List<List<double>>>? parseGageRrTable(String raw) {
  final rows = raw
      .replaceAll('\r\n', '\n')
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (rows.isEmpty) return null;

  var start = 0;
  final first = rows.first.toLowerCase();
  if (first.contains('part') && first.contains('operator')) start = 1;

  final cells = <({String part, String operator, double value})>[];
  for (final line in rows.skip(start)) {
    final parts = line.split(RegExp(r'[\t,;]+'));
    if (parts.length < 3) continue;
    final value = double.tryParse(parts[2].trim().replaceAll(',', '.'));
    if (value == null) continue;
    final part = parts[0].trim();
    final operator = parts[1].trim();
    if (part.isEmpty || operator.isEmpty) continue;
    cells.add((part: part, operator: operator, value: value));
  }
  if (cells.isEmpty) return null;
  return _nestGageRrCells(cells);
}

/// Chart grid: duplicate part labels are replicates; each series column is an
/// operator.
List<List<List<double>>>? gageRrFromChartGrid({
  required List<String> partLabels,
  required List<String> operatorNames,
  required List<List<String>> cellValues,
}) {
  if (operatorNames.length < 2) return null;

  final partOrder = <String>[];
  final partRows = <String, List<int>>{};
  for (var r = 0; r < partLabels.length; r++) {
    final part = partLabels[r].trim();
    if (part.isEmpty) continue;
    partRows.putIfAbsent(part, () => []).add(r);
    if (!partOrder.contains(part)) partOrder.add(part);
  }
  if (partOrder.length < 2) return null;

  final replicateCount = partRows.values.first.length;
  if (replicateCount < 2) return null;
  for (final rows in partRows.values) {
    if (rows.length != replicateCount) return null;
  }

  final measurements = <List<List<double>>>[];
  for (final part in partOrder) {
    final operatorCells = <List<double>>[
      for (var o = 0; o < operatorNames.length; o++) <double>[],
    ];
    for (final row in partRows[part]!) {
      if (row >= cellValues.length) return null;
      for (var o = 0; o < operatorNames.length; o++) {
        final raw = o < cellValues[row].length ? cellValues[row][o].trim() : '';
        if (raw.isEmpty) return null;
        final value = double.tryParse(raw.replaceAll(',', '.'));
        if (value == null) return null;
        operatorCells[o].add(value);
      }
    }
    for (final cell in operatorCells) {
      if (cell.length != replicateCount) return null;
    }
    measurements.add(operatorCells);
  }
  return measurements;
}

List<List<List<double>>>? _nestGageRrCells(
  List<({String part, String operator, double value})> cells,
) {
  final partOrder = <String>[];
  final operatorOrder = <String>[];
  final nested = <String, Map<String, List<double>>>{};

  for (final cell in cells) {
    nested.putIfAbsent(cell.part, () => {});
    nested[cell.part]!.putIfAbsent(cell.operator, () => []).add(cell.value);
    if (!partOrder.contains(cell.part)) partOrder.add(cell.part);
    if (!operatorOrder.contains(cell.operator)) {
      operatorOrder.add(cell.operator);
    }
  }
  if (partOrder.length < 2 || operatorOrder.length < 2) return null;

  final replicateCount = nested[partOrder.first]!.values.first.length;
  if (replicateCount < 2) return null;

  final measurements = <List<List<double>>>[];
  for (final part in partOrder) {
    final byOp = nested[part]!;
    if (byOp.length != operatorOrder.length) return null;
    final row = <List<double>>[];
    for (final operator in operatorOrder) {
      final values = byOp[operator];
      if (values == null || values.length != replicateCount) return null;
      row.add(List<double>.of(values));
    }
    measurements.add(row);
  }
  return measurements;
}

/// Read-only summary of a crossed Gage R&R study.
class GageRrSummary {
  const GageRrSummary({
    required this.percentStudyVariation,
    required this.percentContribution,
    required this.distinctCategories,
    required this.interactionPooled,
    this.percentTolerance,
  });

  final double percentStudyVariation;
  final double percentContribution;
  final int distinctCategories;
  final bool interactionPooled;
  final double? percentTolerance;
}

/// Runs Gage R&R or returns a refusal message.
({GageRrSummary? result, String? refusal}) runGageRrAnalysis(
  List<List<List<double>>> measurements, {
  double? tolerance,
}) {
  try {
    final gage = GageRr.crossed(measurements, tolerance: tolerance);
    return (
      result: GageRrSummary(
        percentStudyVariation: gage.percentStudyVariation,
        percentContribution: gage.percentContribution,
        distinctCategories: gage.distinctCategories,
        interactionPooled: gage.interactionPooled,
        percentTolerance: gage.percentTolerance,
      ),
      refusal: null,
    );
  } on StatsRefusal catch (e) {
    return (result: null, refusal: e.toString());
  }
}

enum InferenceTestKind { oneSampleT, twoSampleT, oneWayAnova }

/// Outcome of a hypothesis test dialog run.
class InferenceSummary {
  const InferenceSummary({
    required this.title,
    required this.statisticLabel,
    required this.statistic,
    required this.degreesOfFreedom,
    required this.pValue,
    this.estimate,
  });

  final String title;
  final String statisticLabel;
  final double statistic;
  final double degreesOfFreedom;
  final double pValue;
  final double? estimate;
}

({InferenceSummary? result, String? refusal}) runInferenceAnalysis({
  required InferenceTestKind kind,
  required String dataRaw,
  double hypothesizedMean = 0,
}) {
  try {
    switch (kind) {
      case InferenceTestKind.oneSampleT:
        final values = parseNumberColumn(dataRaw);
        final t = oneSampleT(values, hypothesizedMean: hypothesizedMean);
        return (
          result: InferenceSummary(
            title: 'One-sample t',
            statisticLabel: 't',
            statistic: t.statistic,
            degreesOfFreedom: t.degreesOfFreedom,
            pValue: t.pValue,
            estimate: t.estimate,
          ),
          refusal: null,
        );
      case InferenceTestKind.twoSampleT:
        final groups = parseGroupedNumberBlocks(dataRaw);
        if (groups.length != 2) {
          return (
            result: null,
            refusal:
                'StatsRefusal: two-sample t test — needs exactly two '
                'samples separated by a blank line, got ${groups.length}',
          );
        }
        final t = twoSampleT(groups[0], groups[1]);
        return (
          result: InferenceSummary(
            title: 'Two-sample t (Welch)',
            statisticLabel: 't',
            statistic: t.statistic,
            degreesOfFreedom: t.degreesOfFreedom,
            pValue: t.pValue,
            estimate: t.estimate,
          ),
          refusal: null,
        );
      case InferenceTestKind.oneWayAnova:
        final groups = parseGroupedNumberBlocks(dataRaw);
        final anova = oneWayAnova(groups);
        return (
          result: InferenceSummary(
            title: 'One-way ANOVA',
            statisticLabel: 'F',
            statistic: anova.fStatistic,
            degreesOfFreedom: anova.denominatorDf,
            pValue: anova.pValue,
            estimate: anova.etaSquared,
          ),
          refusal: null,
        );
    }
  } on StatsRefusal catch (e) {
    return (result: null, refusal: e.toString());
  }
}

/// Simple linear regression summary.
class RegressionSummary {
  const RegressionSummary({
    required this.intercept,
    required this.slope,
    required this.rSquared,
    required this.observationCount,
  });

  final double intercept;
  final double slope;
  final double rSquared;
  final int observationCount;
}

({RegressionSummary? result, String? refusal}) runRegressionAnalysis({
  required String xRaw,
  required String yRaw,
}) {
  final parsed = parseXYColumns(xRaw, yRaw);
  if (parsed == null) {
    return (
      result: null,
      refusal:
          'StatsRefusal: linear regression — X and Y need the same '
          'number of numeric values',
    );
  }
  try {
    final fit = simpleLinearRegression(parsed.x, parsed.y);
    final intercept = fit.coefficients.first.estimate;
    final slope = fit.coefficients[1].estimate;
    return (
      result: RegressionSummary(
        intercept: intercept,
        slope: slope,
        rSquared: fit.rSquared,
        observationCount: fit.observationCount,
      ),
      refusal: null,
    );
  } on StatsRefusal catch (e) {
    return (result: null, refusal: e.toString());
  }
}

/// Convenience for the chart editor: build nested Gage R&R data from a spec.
List<List<List<double>>>? gageRrFromChartSpec(ChartSpec spec) {
  if (spec.series.length < 2 || spec.x.isEmpty) return null;
  final values = [
    for (var r = 0; r < spec.x.length; r++)
      [
        for (final s in spec.series)
          r < s.data.length ? s.data[r].toString() : '',
      ],
  ];
  return gageRrFromChartGrid(
    partLabels: spec.x,
    operatorNames: [for (final s in spec.series) s.name],
    cellValues: values,
  );
}
