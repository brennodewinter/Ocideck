part of 'openkat_report_composer.dart';

String _slideId(String seed) {
  final bytes = utf8.encode('ocideck-openkat-$seed');
  final hash = md5.convert(bytes);
  return 'ocikat-${hash.toString().substring(0, 16)}';
}

String _safeCode(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

String _safeTableText(String value) => sanitizeImportedInline(
  value.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
);

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _termSuffix(String value) {
  final suffix = RegExp(r'\s*(\([^)]+\))\s*$').firstMatch(value)?.group(1);
  return suffix == null ? '' : ' ${sanitizeImportedText(suffix)}';
}

const int _maxRecommendations = 5;

const Map<String, String> _severityColors = {
  'critical': '#B00020',
  'high': '#EF4444',
  'medium': '#F59E0B',
  'low': '#2563EB',
  openKatOtherSeverity: '#64748B',
};

List<String> _visibleBands(Iterable<Map<String, int>> counts) => [
  ...openKatSeverityBands,
  if (counts.any((c) => (c[openKatOtherSeverity] ?? 0) > 0))
    openKatOtherSeverity,
];

ChartSpec _historyChart(
  List<OpenKatHistoryPoint> history, {
  required String title,
  required bool english,
}) {
  final bands = _visibleBands([for (final p in history) p.severityCounts]);
  final labels = english ? _severityLabelsEnglish : _severityLabels;
  return ChartSpec(
    type: ChartType.line,
    title: title,
    x: [for (final point in history) _isoDate(point.date)],
    series: [
      for (final band in bands)
        ChartSeries(
          name: labels[band] ?? band,
          color: _severityColors[band],
          data: [
            for (final point in history)
              (point.severityCounts[band] ?? 0).toDouble(),
          ],
        ),
    ],
  );
}

ChartSpec _distributionChart(
  Map<String, int> counts, {
  required String title,
  required bool english,
}) {
  final bands = _visibleBands([counts]);
  final labels = english ? _severityLabelsEnglish : _severityLabels;
  return ChartSpec(
    type: ChartType.bar,
    title: title,
    x: [for (final band in bands) labels[band] ?? band],
    rowColors: [for (final band in bands) _severityColors[band]],
    series: [
      ChartSeries(
        name: english ? 'Findings' : 'Bevindingen',
        data: [for (final band in bands) (counts[band] ?? 0).toDouble()],
      ),
    ],
  );
}

const Map<String, String> _severityLabels = {
  'critical': 'Kritiek',
  'high': 'Hoog',
  'medium': 'Middel',
  'low': 'Laag',
  openKatOtherSeverity: 'Overig',
};

const Map<String, String> _severityLabelsEnglish = {
  'critical': 'Critical',
  'high': 'High',
  'medium': 'Medium',
  'low': 'Low',
  openKatOtherSeverity: 'Other',
};

String _severityLine(Map<String, int> counts, {required bool english}) {
  final labels = english ? _severityLabelsEnglish : _severityLabels;
  final parts = [
    '${labels['critical']}: ${counts['critical'] ?? 0}',
    '${labels['high']}: ${counts['high'] ?? 0}',
    '${labels['medium']}: ${counts['medium'] ?? 0}',
    '${labels['low']}: ${counts['low'] ?? 0}',
    if ((counts[openKatOtherSeverity] ?? 0) > 0)
      '${english ? 'Other' : 'Overig'}: ${counts[openKatOtherSeverity]}',
  ];
  return parts.join(', ');
}

List<List<String>> _systemsTable(
  List<OpenKatSystemStats> stats, {
  required bool showOther,
  required bool english,
}) => [
  [
    '#',
    english ? 'System' : 'Systeem',
    english ? 'Total' : 'Totaal',
    english ? 'Critical' : 'Kritiek',
    english ? 'High' : 'Hoog',
    english ? 'Medium' : 'Middel',
    english ? 'Low' : 'Laag',
    if (showOther) english ? 'Other' : 'Overig',
  ],
  for (var i = 0; i < stats.length; i++)
    [
      '${i + 1}',
      _safeTableText(stats[i].systemId),
      '${stats[i].total}',
      '${stats[i].critical}',
      '${stats[i].high}',
      '${stats[i].medium}',
      '${stats[i].low}',
      if (showOther) '${stats[i].other}',
    ],
];
