/// Chart kinds the presentation import can salvage into an OciDeck `chart` slide.
///
/// Mirrors OciDeck's `ChartType` (lib/models/chart.dart) so a salvaged chart
/// maps 1:1 without lossy conversion in the emitter.
enum SourceChartType { bar, stackedBar, line, pie, radar, scatter }

/// One named data series aligned to the chart's x labels.
class SourceChartSeries {
  const SourceChartSeries({required this.name, required this.data, this.color});

  final String name;
  final List<double> data;

  /// Hex colour (`#RRGGBB`) if the source specified one, otherwise null so
  /// OciDeck falls back to its palette.
  final String? color;
}

/// A chart extracted from a PPTX chart part or an ODP chart.
///
/// Small charts keep their data inline; the emitter decides whether to point
/// at a `data/<hash>.csv` instead (FILE_FORMAT §6.4). The import only captures the
/// data here — the storage decision belongs to the deck builder.
class SourceChart {
  const SourceChart({
    required this.type,
    required this.x,
    required this.series,
    this.title = '',
    this.rowColors = const [],
    this.minBound,
    this.maxBound,
  });

  final SourceChartType type;

  /// Category labels (x axis) or pie/radar segments.
  final List<String> x;

  final List<SourceChartSeries> series;

  final String title;

  /// Optional per-label colours for pie/radar.
  final List<String?> rowColors;

  /// Optional reference lines / scale bounds (ignored for pie).
  final double? minBound;
  final double? maxBound;
}
