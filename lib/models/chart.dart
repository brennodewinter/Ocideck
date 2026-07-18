import 'dart:convert';
import 'dart:math' as math;

import '../utils/log.dart';

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
///
/// New kinds are appended so a slide's stored `type` name stays stable. The
/// first six are the original set; the rest were added later:
/// - [area] — a filled line chart (trend + magnitude).
/// - [donut] — a pie with a hole and the total in the centre.
/// - [horizontalBar] — bars laid out left-to-right (long labels / rankings).
/// - [combo] — bars plus the last series drawn as a line on a second axis.
/// - [waterfall] — the first series as up/down steps building on a total.
/// - [heatmap] — a grid coloured by value (doubles as a risk matrix).
/// - [horizontalStackedBar] — a [stackedBar] laid on its side: one bar per
///   label with the series stacked left-to-right (long labels / part-to-whole).
enum ChartType {
  bar,
  stackedBar,
  line,
  pie,
  radar,
  scatter,
  area,
  donut,
  horizontalBar,
  combo,
  waterfall,
  heatmap,
  horizontalStackedBar,
}

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

// ── Heatmap colour scale ─────────────────────────────────────────────────────
// A [ChartType.heatmap] encodes MAGNITUDE, so — unlike the other charts — its
// cells are not tinted with the deck's series/accent colours (which made every
// heatmap read as "the theme" rather than as a heatmap). Instead it uses a
// fixed, theme-independent sequential "heat" ramp: a single perceptual
// direction, pale/cool = low → intense/hot = high, so a heatmap always looks
// like one. There are two ramps so magnitude maps to intensity on either
// surface: on a light slide the low end stays pale and the high end deepens to
// red (ColorBrewer YlOrRd, a colourblind-safe sequential scheme); on a dark
// slide the low end recedes into the dark and the high end brightens (a
// black-body warm ramp). Low cells intentionally have little contrast with the
// surface ("near zero recedes"); the numeric value printed in every cell keeps
// them readable.

const List<String> _heatRampLight = <String>[
  '#FFFFB2',
  '#FECC5C',
  '#FD8D3C',
  '#F03B20',
  '#BD0026',
];

const List<String> _heatRampDark = <String>[
  '#4B1D06',
  '#8C2D04',
  '#D7301F',
  '#FC8D3C',
  '#FEE08B',
];

/// The heat ramp for a slide whose background reads as [darkBackground].
List<String> heatmapRamp({required bool darkBackground}) =>
    darkBackground ? _heatRampDark : _heatRampLight;

/// The `#RRGGBB` colour at position [t] (0..1) along [ramp], linearly
/// interpolated between its stops.
String heatmapColorAt(List<String> ramp, double t) {
  final clamped = t.isNaN ? 0.0 : t.clamp(0.0, 1.0);
  final scaled = clamped * (ramp.length - 1);
  final i = scaled.floor().clamp(0, ramp.length - 2);
  final f = scaled - i;
  final a = _rgbOf(ramp[i]);
  final b = _rgbOf(ramp[i + 1]);
  int mix(int x, int y) => (x + (y - x) * f).round();
  return '#${_hex2(mix(a[0], b[0]))}${_hex2(mix(a[1], b[1]))}${_hex2(mix(a[2], b[2]))}';
}

/// Whether a `#RRGGBB` reads as dark — used to pick the ramp from the slide
/// background and to choose readable (white vs dark) in-cell text.
bool isDarkHex(String hex) => _relativeLuminance(hex) < 0.4;

/// The readable label colour (`#RRGGBB`) for a value printed on a heat cell of
/// [cellHex]: white on the hot/dark cells, a fixed dark ink on the pale ones.
/// Fixed (not the deck/app theme) because the cell colour is fixed too.
String heatmapInk(String cellHex) => isDarkHex(cellHex) ? '#FFFFFF' : '#334155';

/// Parse `#RRGGBB` (or `#RGB`) into `[r, g, b]` (0..255); tolerant of a missing
/// `#` and bad input (falls back to black).
List<int> _rgbOf(String hex) {
  var h = hex.replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length < 6) h = h.padRight(6, '0');
  int channel(int i) => int.tryParse(h.substring(i, i + 2), radix: 16) ?? 0;
  return [channel(0), channel(2), channel(4)];
}

String _hex2(int v) =>
    v.clamp(0, 255).toRadixString(16).padLeft(2, '0').toUpperCase();

/// WCAG relative luminance of a `#RRGGBB` colour (0 = black, 1 = white).
double _relativeLuminance(String hex) {
  final c = _rgbOf(hex);
  double lin(int v) {
    final s = v / 255.0;
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2]);
}

/// The full chart specification, stored as JSON inside a ```chart fenced block.
///
/// The numbers may live inline, or in a data file next to the deck that
/// [source] points at (packaged alongside the deck like images). With a
/// [source] set, the inline data is stripped from the markdown on save and
/// read back on load, so the `.md` stays about the *shape* of the chart while
/// the data file holds the values.
///
/// Two file forms are supported. New data files are written as JSON
/// ([dataToJson]); `.csv` is still read, because decks written before the
/// switch link one and a CSV remains the thing you can hand to a spreadsheet.
/// [withData] picks on the extension.
///
/// What never moves to the data file is styling — per-row and per-series
/// colours stay in the block. That is what lets the data file be replaced
/// wholesale without the chart losing its look.
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

  /// Whether the chart draws itself in (values grow from the baseline) when the
  /// slide is shown in presentation mode.
  final bool animateOnEnter;

  /// Per-slide activation-duration override (ms). `null` = inherit the theme's
  /// ThemeProfile.animationDurationMs. Only serialised when set.
  final int? animationDurationMs;

  const ChartSpec({
    this.type = ChartType.bar,
    this.title = '',
    this.source,
    this.x = const [],
    this.rowColors = const [],
    this.series = const [],
    this.minBound,
    this.maxBound,
    this.animateOnEnter = true,
    this.animationDurationMs,
  });

  bool get hasInlineData => x.isNotEmpty && series.isNotEmpty;

  /// Whether the optional [minBound]/[maxBound] apply. On the cartesian charts
  /// they are horizontal threshold lines; on radar they fix the scale
  /// (centre/outer ring). The proportional/grid charts (pie, donut, horizontal
  /// bar, heatmap) have no single value axis, so they never use bounds.
  bool get supportsBounds =>
      type != ChartType.pie &&
      type != ChartType.donut &&
      type != ChartType.horizontalBar &&
      type != ChartType.horizontalStackedBar &&
      type != ChartType.heatmap;

  /// Whether this is a pie-like proportional chart (one circle per series,
  /// segments per label) — pie and donut share their data mapping, legend and
  /// screen-reader readout.
  bool get isPieLike => type == ChartType.pie || type == ChartType.donut;

  /// True only where bounds render as horizontal threshold *lines*.
  bool get supportsBoundLines =>
      type == ChartType.bar ||
      type == ChartType.stackedBar ||
      type == ChartType.line ||
      type == ChartType.area ||
      type == ChartType.combo ||
      type == ChartType.waterfall ||
      type == ChartType.scatter;

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
    bool? animateOnEnter,
    int? animationDurationMs,
    bool inheritAnimationDuration = false,
  }) => ChartSpec(
    type: type ?? this.type,
    title: title ?? this.title,
    source: clearSource ? null : (source ?? this.source),
    x: x ?? this.x,
    rowColors: rowColors ?? this.rowColors,
    series: series ?? this.series,
    minBound: clearMinBound ? null : (minBound ?? this.minBound),
    maxBound: clearMaxBound ? null : (maxBound ?? this.maxBound),
    animateOnEnter: animateOnEnter ?? this.animateOnEnter,
    animationDurationMs: inheritAnimationDuration
        ? null
        : (animationDurationMs ?? this.animationDurationMs),
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
        animateOnEnter: data['animateOnEnter'] != false,
        animationDurationMs: (data['animationDurationMs'] as num?)?.round(),
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
    } catch (e, s) {
      logError('ChartSpec.parse: decode chart JSON block', e, s);
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
    // Animation: defaults (on, inherit theme duration) stay out of the block so
    // a clean chart stays clean and follows the theme.
    if (!animateOnEnter) map['animateOnEnter'] = false;
    if (animationDurationMs != null) {
      map['animationDurationMs'] = animationDurationMs;
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
  ChartSpec withCsv(String csv) => _withParsedData(parseCsv(csv));

  /// Return a copy with x/series taken from [json] — the contents of a
  /// `data/<naam>.json`; keeps [source]. Tolerant like [ChartSpec.parse]: a
  /// malformed file leaves the spec untouched rather than blanking the chart.
  ChartSpec withJson(String json) {
    final parsed = parseChartDataJson(json);
    return parsed == null ? this : _withParsedData(parsed);
  }

  /// Return a copy filled from the data file at [path] — JSON or CSV, chosen on
  /// the extension so callers do not have to know which form a deck uses.
  ChartSpec withData(String content, {required String path}) =>
      path.toLowerCase().endsWith('.json')
      ? withJson(content)
      : withCsv(content);

  /// The data half of this spec as the contents of a `data/<naam>.json`.
  ///
  /// Only x and series values: the colours stay behind in the chart block,
  /// because they are styling rather than data — that split is what lets the
  /// data file be regenerated from a spreadsheet without losing the deck's
  /// look. Mirrored by [parseChartDataJson].
  /// Deliberately not [ChartSeries.toJson], which carries `color` along: this
  /// file must hold values only, so that comparing two of them answers "did the
  /// numbers change" without a recolour counting as a data edit.
  String dataToJson() => const JsonEncoder.withIndent('  ').convert({
    'x': x,
    'series': [
      for (final s in series) {'name': s.name, 'data': s.data},
    ],
  });

  /// Shared tail of [withCsv]/[withJson]: adopt fresh labels and values while
  /// keeping the colours. Row colours follow their *label* (so re-ordering or
  /// inserting rows in a spreadsheet does not shuffle them) and fall back to
  /// position; series colours follow position.
  ChartSpec _withParsedData((List<String>, List<ChartSeries>) parsed) {
    final (labels, parsedSeries) = parsed;
    final colorsByLabel = x.isEmpty
        ? const <String, String?>{}
        : <String, String?>{
            for (var i = 0; i < x.length; i++)
              x[i]: i < rowColors.length ? rowColors[i] : null,
          };
    return copyWith(
      x: labels,
      rowColors: [
        for (var i = 0; i < labels.length; i++)
          colorsByLabel[labels[i]] ??
              (i < rowColors.length ? rowColors[i] : null),
      ],
      series: [
        for (var i = 0; i < parsedSeries.length; i++)
          ChartSeries(
            name: parsedSeries[i].name,
            data: parsedSeries[i].data,
            color: i < series.length ? series[i].color : null,
          ),
      ],
    );
  }
}

/// [parseCsv] in reverse: a header row of series names, then one row per label.
///
/// Only used to keep a deck that already links a `.csv` on CSV. Values that
/// would need quoting are not produced here — a label with a comma in it is
/// exactly why new data files are written as JSON.
String chartDataAsCsv(ChartSpec spec) {
  final buf = StringBuffer()
    ..writeln(',${spec.series.map((s) => _csvValue(s.name)).join(',')}');
  for (var r = 0; r < spec.x.length; r++) {
    buf.writeln(
      [
        _csvValue(spec.x[r]),
        for (final s in spec.series) r < s.data.length ? s.data[r] : 0,
      ].join(','),
    );
  }
  return buf.toString();
}

/// A cell as CSV: quoted when it contains a comma, a quote or edge whitespace,
/// with `"` doubled — the form [parseCsv] reads back verbatim.
String _csvValue(String raw) =>
    raw.contains(',') || raw.contains('"') || raw.trim() != raw
    ? '"${raw.replaceAll('"', '""')}"'
    : raw;

/// Parse the contents of a `data/<naam>.json` into (x labels, series), or null
/// when the file is not usable — bad JSON, or not an object with an `x` list.
///
/// Null rather than empty on purpose: a chart whose data file is corrupt should
/// keep whatever it already has instead of silently becoming an empty plot.
(List<String>, List<ChartSeries>)? parseChartDataJson(String json) {
  try {
    final data = jsonDecode(json.trim());
    if (data is! Map || data['x'] is! List) return null;
    return (
      [for (final v in (data['x'] as List)) v.toString()],
      [
        for (final s in (data['series'] as List? ?? const []))
          if (s is Map) ChartSeries.fromJson(Map<String, dynamic>.from(s)),
      ],
    );
  } catch (e, s) {
    logError('parseChartDataJson: decode chart data file', e, s);
    return null;
  }
}

/// Split one CSV line into cells, honouring RFC 4180 quoting: a field wrapped
/// in double quotes may contain commas, and a doubled `""` inside it is one
/// literal quote. Unquoted fields keep the historical behaviour and are
/// trimmed; a quoted field's content is taken verbatim, so `" a "` keeps its
/// inner spaces.
///
/// Deliberately lenient about malformed input, because the CSV comes from
/// whatever a user exported: an unterminated quote runs to the end of the line,
/// and characters between a closing quote and the next separator are discarded.
List<String> _csvCells(String line, String delimiter) {
  final cells = <String>[];
  var i = 0;
  while (true) {
    final start = i;
    // Tolerate space before an opening quote, so ` "Amsterdam, NL"` still reads
    // as one quoted field — but never eat the separator itself, or a
    // tab-delimited line would collapse into a single cell.
    while (i < line.length &&
        line[i] != delimiter &&
        (line[i] == ' ' || line[i] == '\t')) {
      i++;
    }

    if (i < line.length && line[i] == '"') {
      i++; // opening quote
      final field = StringBuffer();
      while (i < line.length) {
        if (line[i] != '"') {
          field.write(line[i]);
          i++;
        } else if (i + 1 < line.length && line[i + 1] == '"') {
          field.write('"');
          i += 2;
        } else {
          i++; // closing quote
          break;
        }
      }
      cells.add(field.toString());
      while (i < line.length && line[i] != delimiter) {
        i++;
      }
    } else {
      final next = line.indexOf(delimiter, i);
      final end = next == -1 ? line.length : next;
      cells.add(line.substring(start, end).trim());
      i = end;
    }

    if (i >= line.length) return cells;
    i++; // the separator
  }
}

/// Pick the separator a file actually uses: whichever of `,` `;` or tab carves
/// the header into the most cells. A Dutch Excel writes `;` whenever the system
/// decimal mark is a comma, so assuming `,` silently produced a chart with no
/// series at all. Ties fall back to `,`, which is what the format nominally is.
String _detectDelimiter(String headerLine) {
  var best = ',';
  var bestCount = _csvCells(headerLine, ',').length;
  for (final candidate in const [';', '\t']) {
    final count = _csvCells(headerLine, candidate).length;
    if (count > bestCount) {
      best = candidate;
      bestCount = count;
    }
  }
  return best;
}

/// Read one cell as a number, or return null if it cannot be read.
///
/// When the separator is *not* a comma, a comma cannot be separating fields, so
/// it can only be a decimal mark: `10,5` is 10.5. That inference is only sound
/// because the delimiter is known, which is why it lives here and not in a
/// general number parser.
///
/// Anything still ambiguous is deliberately refused rather than guessed. A bare
/// `1,234` may be 1234 or 1.234 depending on where the file was written, and a
/// value carrying both marks (`1.234,56`) needs a thousands-separator rule this
/// does not have. Refusing puts them in front of the user instead of inventing
/// a plausible number.
double? _parseCsvNumber(String raw, String delimiter) {
  final direct = double.tryParse(raw);
  if (direct != null) return direct;
  if (delimiter != ',' && raw.contains(',') && !raw.contains('.')) {
    return double.tryParse(raw.replaceAll(',', '.'));
  }
  return null;
}

/// Parse CSV text into (x labels, series). The first row is a header whose
/// first cell is ignored (the label column) and whose remaining cells are the
/// series names; each later row is `label, v1, v2, …`.
///
/// The separator is detected per file (see [_detectDelimiter]), so a Dutch
/// Excel export using `;` reads as well as a comma-separated one.
///
/// Quoted fields are understood per RFC 4180 (see [_csvCells]), with one
/// documented exception: a newline inside a quoted field is **not** supported.
/// Rows are split on line breaks before fields are parsed, so such a value is
/// torn across two rows. Chart data is one label plus numbers per row, where an
/// embedded newline has no legitimate use; supporting it would mean scanning
/// the whole document instead of per line. Blank lines are skipped.
///
/// A cell that holds something other than a number still counts as 0 — a chart
/// has to draw *something* — but every such cell is also returned in
/// [unreadable], so a caller can say so out loud. A value silently rendered as
/// 0 looks exactly like a real measurement of zero, which is the more damaging
/// of the two failures. An empty cell is not reported: a short row means "no
/// value here", which is a statement, not a mistake.
(List<String>, List<ChartSeries>, {List<String> unreadable}) parseCsv(
  String csv,
) {
  final lines = csv
      .replaceAll('\r\n', '\n')
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (lines.isEmpty) return (const [], const [], unreadable: const []);

  final delimiter = _detectDelimiter(lines.first);
  final header = _csvCells(lines.first, delimiter);
  final seriesNames = header.length > 1 ? header.sublist(1) : <String>[];
  final x = <String>[];
  final seriesData = [for (final _ in seriesNames) <double>[]];
  final unreadable = <String>[];

  for (final line in lines.skip(1)) {
    final row = _csvCells(line, delimiter);
    if (row.isEmpty) continue;
    x.add(row.first);
    for (var i = 0; i < seriesNames.length; i++) {
      final raw = (i + 1) < row.length ? row[i + 1] : '';
      final value = raw.isEmpty ? 0.0 : _parseCsvNumber(raw, delimiter);
      if (value == null) unreadable.add(raw);
      seriesData[i].add(value ?? 0);
    }
  }

  return (
    x,
    [
      for (var i = 0; i < seriesNames.length; i++)
        ChartSeries(name: seriesNames[i], data: seriesData[i]),
    ],
    unreadable: unreadable,
  );
}
