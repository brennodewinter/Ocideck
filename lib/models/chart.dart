import 'dart:convert';

/// Directory (relative to the deck) where linked chart CSVs are kept, so the
/// data files stay tidily in one place — separate from images/media.
const String chartDataDirName = 'data';

/// Supported chart kinds for a chart slide.
enum ChartType { bar, line, pie }

ChartType _chartTypeFromName(String? name) => ChartType.values.firstWhere(
  (t) => t.name == name,
  orElse: () => ChartType.bar,
);

/// One named data series (a row of values aligned to the x labels).
class ChartSeries {
  final String name;
  final List<double> data;
  const ChartSeries({required this.name, required this.data});

  Map<String, dynamic> toJson() => {'name': name, 'data': data};

  factory ChartSeries.fromJson(Map<String, dynamic> json) => ChartSeries(
    name: (json['name'] ?? '').toString(),
    data: [
      for (final v in (json['data'] as List? ?? const []))
        (v as num?)?.toDouble() ?? 0,
    ],
  );
}

/// The full chart specification, stored as JSON inside a ```chart fenced block.
///
/// Small charts keep their data inline; data-driven charts instead point at an
/// external CSV via [source] (kept as the living source of truth and packaged
/// alongside the deck like images). When a [source] is set the inline data is
/// stripped from the markdown on save and re-hydrated from the CSV on load.
class ChartSpec {
  final ChartType type;
  final String title;
  final String? source;
  final List<String> x;
  final List<ChartSeries> series;

  const ChartSpec({
    this.type = ChartType.bar,
    this.title = '',
    this.source,
    this.x = const [],
    this.series = const [],
  });

  bool get hasInlineData => x.isNotEmpty && series.isNotEmpty;

  ChartSpec copyWith({
    ChartType? type,
    String? title,
    String? source,
    bool clearSource = false,
    List<String>? x,
    List<ChartSeries>? series,
  }) => ChartSpec(
    type: type ?? this.type,
    title: title ?? this.title,
    source: clearSource ? null : (source ?? this.source),
    x: x ?? this.x,
    series: series ?? this.series,
  );

  /// Parse the JSON content of a ```chart block. Tolerant: returns a default
  /// spec on any error so a malformed block never crashes rendering.
  factory ChartSpec.parse(String raw) {
    try {
      final data = jsonDecode(raw.trim());
      if (data is! Map) return const ChartSpec();
      final src = (data['source'] as String?)?.trim();
      return ChartSpec(
        type: _chartTypeFromName(data['type'] as String?),
        title: (data['title'] ?? '').toString(),
        source: (src == null || src.isEmpty) ? null : src,
        x: [for (final v in (data['x'] as List? ?? const [])) v.toString()],
        series: [
          for (final s in (data['series'] as List? ?? const []))
            ChartSeries.fromJson(Map<String, dynamic>.from(s as Map)),
        ],
      );
    } catch (_) {
      return const ChartSpec();
    }
  }

  /// Serialize back to the pretty JSON that lives in the markdown block.
  /// When [forStorage] is true and a [source] is set, the (re-hydratable)
  /// inline data is omitted so the .md stays lean and the CSV stays the source.
  String toBlock({bool forStorage = false}) {
    final map = <String, dynamic>{'type': type.name};
    if (title.isNotEmpty) map['title'] = title;
    if (source != null) map['source'] = source;
    final dropData = forStorage && source != null;
    if (!dropData) {
      if (x.isNotEmpty) map['x'] = x;
      if (series.isNotEmpty) {
        map['series'] = [for (final s in series) s.toJson()];
      }
    }
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Return a copy with x/series taken from [csv]; keeps [source].
  ChartSpec withCsv(String csv) {
    final parsed = parseCsv(csv);
    return copyWith(x: parsed.$1, series: parsed.$2);
  }
}

/// Parse CSV text into (x labels, series). The first row is a header whose
/// first cell is ignored (the label column) and whose remaining cells are the
/// series names; each later row is `label, v1, v2, …`.
(List<String>, List<ChartSeries>) parseCsv(String csv) {
  final lines = csv
      .replaceAll('\r\n', '\n')
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (lines.isEmpty) return (const [], const []);

  List<String> cells(String line) =>
      line.split(',').map((c) => c.trim()).toList();

  final header = cells(lines.first);
  final seriesNames = header.length > 1 ? header.sublist(1) : <String>[];
  final x = <String>[];
  final seriesData = [for (final _ in seriesNames) <double>[]];

  for (final line in lines.skip(1)) {
    final row = cells(line);
    if (row.isEmpty) continue;
    x.add(row.first);
    for (var i = 0; i < seriesNames.length; i++) {
      final raw = (i + 1) < row.length ? row[i + 1] : '';
      seriesData[i].add(double.tryParse(raw) ?? 0);
    }
  }

  return (
    x,
    [
      for (var i = 0; i < seriesNames.length; i++)
        ChartSeries(name: seriesNames[i], data: seriesData[i]),
    ],
  );
}
