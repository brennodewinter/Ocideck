import 'dart:convert';

/// Directory (relative to the deck) where linked chart CSVs are kept, so the
/// data files stay tidily in one place — separate from images/media.
const String chartDataDirName = 'data';

const List<String> chartColorPalette = [
  '#003399',
  '#FFCC00',
  '#2563EB',
  '#F59E0B',
  '#10B981',
  '#EF4444',
  '#8B5CF6',
  '#06B6D4',
  '#EC4899',
  '#84CC16',
];

/// Supported chart kinds for a chart slide.
enum ChartType { bar, line, pie, radar }

ChartType _chartTypeFromName(String? name) => ChartType.values.firstWhere(
  (t) => t.name == name,
  orElse: () => ChartType.bar,
);

/// One named data series (a row of values aligned to the x labels).
class ChartSeries {
  final String name;
  final List<double> data;
  final String? color;
  const ChartSeries({required this.name, required this.data, this.color});

  Map<String, dynamic> toJson({bool includeData = true}) => {
    'name': name,
    if (includeData) 'data': data,
    if (color != null) 'color': color,
  };

  factory ChartSeries.fromJson(Map<String, dynamic> json) {
    final color = normalizeChartColor(json['color']?.toString());
    return ChartSeries(
      name: (json['name'] ?? '').toString(),
      color: color,
      data: [
        for (final v in (json['data'] as List? ?? const []))
          (v as num?)?.toDouble() ?? 0,
      ],
    );
  }
}

String? normalizeChartColor(String? value) {
  if (value == null) return null;
  final raw = value.trim().toUpperCase();
  final normalized = raw.startsWith('#') ? raw : '#$raw';
  return RegExp(r'^#[0-9A-F]{6}$').hasMatch(normalized) ? normalized : null;
}

String chartSeriesColor(ChartSeries series, int index) =>
    normalizeChartColor(series.color) ??
    chartColorPalette[index % chartColorPalette.length];

String chartRowColor(ChartSpec spec, int index) => index < spec.rowColors.length
    ? normalizeChartColor(spec.rowColors[index]) ??
          chartColorPalette[index % chartColorPalette.length]
    : chartColorPalette[index % chartColorPalette.length];

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
  final List<String?> rowColors;
  final List<ChartSeries> series;

  /// Optional horizontal reference lines drawn across the plot so it is clear
  /// where a data point sits relative to a threshold. Only meaningful for bar
  /// and line charts (ignored for pie); either may be left null.
  final double? minBound;
  final double? maxBound;

  const ChartSpec({
    this.type = ChartType.bar,
    this.title = '',
    this.source,
    this.x = const [],
    this.rowColors = const [],
    this.series = const [],
    this.minBound,
    this.maxBound,
  });

  bool get hasInlineData => x.isNotEmpty && series.isNotEmpty;

  /// Whether the optional [minBound]/[maxBound] apply. On bar/line they are
  /// horizontal threshold lines; on radar they fix the scale (centre/outer
  /// ring). Pie charts have no axis, so they never use bounds.
  bool get supportsBounds => type != ChartType.pie;

  /// True only where bounds render as horizontal threshold *lines*.
  bool get supportsBoundLines =>
      type == ChartType.bar || type == ChartType.line;

  ChartSpec copyWith({
    ChartType? type,
    String? title,
    String? source,
    bool clearSource = false,
    List<String>? x,
    List<String?>? rowColors,
    List<ChartSeries>? series,
    double? minBound,
    bool clearMinBound = false,
    double? maxBound,
    bool clearMaxBound = false,
  }) => ChartSpec(
    type: type ?? this.type,
    title: title ?? this.title,
    source: clearSource ? null : (source ?? this.source),
    x: x ?? this.x,
    rowColors: rowColors ?? this.rowColors,
    series: series ?? this.series,
    minBound: clearMinBound ? null : (minBound ?? this.minBound),
    maxBound: clearMaxBound ? null : (maxBound ?? this.maxBound),
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
        minBound: (data['minBound'] as num?)?.toDouble(),
        maxBound: (data['maxBound'] as num?)?.toDouble(),
        x: [for (final v in (data['x'] as List? ?? const [])) v.toString()],
        rowColors: [
          for (final value in (data['rowColors'] as List? ?? const []))
            normalizeChartColor(value?.toString()),
        ],
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
    if (supportsBounds) {
      if (minBound != null) map['minBound'] = minBound;
      if (maxBound != null) map['maxBound'] = maxBound;
    }
    final dropData = forStorage && source != null;
    if (rowColors.any((color) => color != null)) {
      map['rowColors'] = rowColors;
    }
    if (!dropData) {
      if (x.isNotEmpty) map['x'] = x;
      if (series.isNotEmpty) {
        map['series'] = [for (final s in series) s.toJson()];
      }
    } else if (series.any((series) => series.color != null)) {
      map['series'] = [
        for (final series in series) series.toJson(includeData: false),
      ];
    }
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Return a copy with x/series taken from [csv]; keeps [source].
  ChartSpec withCsv(String csv) {
    final parsed = parseCsv(csv);
    final colorsByLabel = x.isEmpty
        ? const <String, String?>{}
        : <String, String?>{
            for (var i = 0; i < x.length; i++)
              x[i]: i < rowColors.length ? rowColors[i] : null,
          };
    return copyWith(
      x: parsed.$1,
      rowColors: [
        for (var i = 0; i < parsed.$1.length; i++)
          colorsByLabel[parsed.$1[i]] ??
              (i < rowColors.length ? rowColors[i] : null),
      ],
      series: [
        for (var i = 0; i < parsed.$2.length; i++)
          ChartSeries(
            name: parsed.$2[i].name,
            data: parsed.$2[i].data,
            color: i < series.length ? series[i].color : null,
          ),
      ],
    );
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
