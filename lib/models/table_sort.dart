import 'dart:collection';

enum TableSortKind { automatic, text, number, date, time }

enum TableParseKind { text, number, date, time, mixed }

enum TableSortDirection { ascending, descending }

enum TableAnalysisSuitability {
  suitable,
  suitableWithAttentionPoints,
  notYetSuitable,
}

enum TableSortDecision { apply, cancel }

enum TableSortOutcome { applied, cancelled, failed }

class TableColumnProfile {
  const TableColumnProfile({
    required this.nonEmptyCount,
    required this.emptyCount,
    required this.dominantKind,
    required this.parsedRowIndices,
    required this.unparsedRowIndices,
    required this.alreadyMonotonic,
    required this.confidence,
    required this.reasons,
  });

  final int nonEmptyCount;
  final int emptyCount;
  final TableParseKind dominantKind;
  final List<int> parsedRowIndices;
  final List<int> unparsedRowIndices;
  final bool alreadyMonotonic;
  final double confidence;
  final List<String> reasons;
}

class TableSortAnalysis {
  const TableSortAnalysis({
    required this.profile,
    required this.suitability,
    required this.requestedKind,
    required this.resolvedKind,
  });

  final TableColumnProfile profile;
  final TableAnalysisSuitability suitability;
  final TableSortKind requestedKind;
  final TableParseKind resolvedKind;

  bool get canSort => suitability != TableAnalysisSuitability.notYetSuitable;
}

class TableSortResult {
  TableSortResult({
    required List<String> lines,
    required this.outcome,
    required this.analysis,
    this.reason,
  }) : lines = UnmodifiableListView(lines);

  final List<String> lines;
  final TableSortOutcome outcome;
  final TableSortAnalysis? analysis;
  final String? reason;

  bool get changed => outcome == TableSortOutcome.applied;
}

class TableSourceSortResult {
  const TableSourceSortResult({
    required this.source,
    required this.outcome,
    required this.analysis,
    this.reason,
  });

  final String source;
  final TableSortOutcome outcome;
  final TableSortAnalysis? analysis;
  final String? reason;

  bool get changed => outcome == TableSortOutcome.applied;
}
