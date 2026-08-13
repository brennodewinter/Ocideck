// Part of the slide_preview library — see ../slide_preview.dart.
// Hover/touch tooltip helpers for the hand-drawn and combo charts, plus the
// _HoverPieChart widget. These are top-level (not members of _ChartPreviewState)
// so they don't inflate that class's size ratchet — mirroring the top-level
// _formatChartValue that stays in chart_preview.dart. Split out of
// chart_preview_extra.dart for cohesion; _HoverPieChart moved here from
// chart_preview.dart to keep that file under the 1000-line ceiling.
part of '../slide_preview.dart';

/// Compose the floating tooltip text for a hover mirrored from the other screen
/// (presenter ↔ beamer). Reuses the same label/value helpers the local tooltips
/// use, so a mirrored hover reads identically and introduces no new localised
/// words. A bar/point hover carries both indices (label + one series' value); a
/// category-only hover lists every series (like a stacked column); a legend
/// hover carries only the series name.
String? composedChartHoverText(
  BuildContext context,
  ChartSpec spec,
  ChartHover hover,
) {
  final cat = hover.category;
  final si = hover.series;
  if (cat != null && si != null) {
    return _seriesCellTooltip(context, spec, cat, si);
  }
  if (cat != null) return _stackedTooltipText(spec, cat);
  if (si != null) return _seriesTooltipLabel(context, spec, si);
  return null;
}

/// Series name for an overlay tooltip, with the localised `Reeks` fallback used
/// across the legend and the pie/radar tooltips. Used where the text lands in a
/// real [Text] widget (a hard-coded-text gate sink), so the fallback must be
/// localised — unlike the fl_chart callback text below.
String _seriesTooltipLabel(BuildContext context, ChartSpec spec, int si) {
  if (si >= 0 && si < spec.series.length && spec.series[si].name.isNotEmpty) {
    return spec.series[si].name;
  }
  return '${context.l10n.d('Reeks')} ${si + 1}';
}

/// `label\nseries: value` for one hand-drawn bar or segment.
String _seriesCellTooltip(
  BuildContext context,
  ChartSpec spec,
  int cat,
  int si,
) {
  final label = cat >= 0 && cat < spec.x.length ? spec.x[cat] : '';
  final has =
      si >= 0 && si < spec.series.length && cat < spec.series[si].data.length;
  final value = has ? spec.series[si].data[cat] : 0.0;
  final head = label.isEmpty ? '' : '$label\n';
  return '$head${_seriesTooltipLabel(context, spec, si)}: '
      '${_formatChartValue(value)}';
}

/// Multi-line tooltip for one stacked group: the label then each series' value
/// (the rod only knows the stack total). This lands in an fl_chart
/// [BarTooltipItem], not a [Text], so the `Reeks N` fallback stays a literal —
/// matching the existing bar/line tooltips and the hard-coded-text gate.
String _stackedTooltipText(ChartSpec spec, int xi) {
  final label = xi >= 0 && xi < spec.x.length ? spec.x[xi] : '';
  final buffer = StringBuffer(label);
  for (var si = 0; si < spec.series.length; si++) {
    if (xi >= spec.series[si].data.length) continue;
    final name = spec.series[si].name.isEmpty
        ? 'Reeks ${si + 1}'
        : spec.series[si].name;
    buffer.write('\n$name: ${_formatChartValue(spec.series[si].data[xi])}');
  }
  return buffer.toString();
}

/// Recover a scatter point's `label\nseries: value` from the parallel meta table
/// (by identity, falling back to an x/y match). fl_chart callback text.
String? _scatterTooltipText(
  ChartSpec spec,
  List<ScatterSpot> spots,
  List<({int series, int xi})> meta,
  ScatterSpot spot,
) {
  var idx = spots.indexWhere((s) => identical(s, spot));
  if (idx < 0) idx = spots.indexWhere((s) => s.x == spot.x && s.y == spot.y);
  if (idx < 0 || idx >= meta.length) return null;
  final m = meta[idx];
  final label = m.xi < spec.x.length ? spec.x[m.xi] : '';
  final name = m.series < spec.series.length ? spec.series[m.series].name : '';
  final series = name.isEmpty ? 'Reeks ${m.series + 1}' : name;
  return '${label.isEmpty ? '' : '$label\n'}$series: '
      '${_formatChartValue(spot.y)}';
}

/// Combo tooltip for one column: every bar series' value plus the line value.
String _comboTooltipText(
  BuildContext context,
  ChartSpec spec,
  int col,
  List<ChartSeries> barSeries,
  ChartSeries lineSeries,
) {
  final label = col >= 0 && col < spec.x.length ? spec.x[col] : '';
  final buffer = StringBuffer(label);
  for (var si = 0; si < barSeries.length; si++) {
    if (col >= barSeries[si].data.length) continue;
    buffer.write(
      '\n${_seriesTooltipLabel(context, spec, si)}: '
      '${_formatChartValue(barSeries[si].data[col])}',
    );
  }
  if (col >= 0 && col < lineSeries.data.length) {
    buffer.write(
      '\n${_seriesTooltipLabel(context, spec, spec.series.length - 1)}: '
      '${_formatChartValue(lineSeries.data[col])}',
    );
  }
  return buffer.toString();
}

/// The floating tooltip pinned to the top of a hand-drawn chart, mirroring the
/// pie/radar hover overlays. [style] is the chart's `_tooltipStyle()`.
Widget _cellTooltipOverlay(double w, TextStyle style, String text) {
  return Positioned(
    top: 4,
    left: 4,
    right: 4,
    child: IgnorePointer(
      child: Center(
        child: Container(
          key: const ValueKey('cell-hover-tooltip'),
          padding: EdgeInsets.symmetric(
            horizontal: w * 0.012,
            vertical: w * 0.006,
          ),
          decoration: BoxDecoration(
            color: AppTheme.chartTooltipBg,
            borderRadius: BorderRadius.circular(w * 0.008),
            boxShadow: const [
              BoxShadow(color: AppTheme.shadow20, blurRadius: 6),
            ],
          ),
          child: Text(
            text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: style,
          ),
        ),
      ),
    ),
  );
}

/// Wrap a hand-drawn [chart] in a [Stack] that floats [tooltip] (or nothing).
Widget _withCellTooltip({
  required Widget chart,
  required String? tooltip,
  required double w,
  required TextStyle style,
}) {
  return Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned.fill(child: chart),
      if (tooltip case final text?) _cellTooltipOverlay(w, style, text),
    ],
  );
}

/// Overlay a transparent [MouseRegion] over the two combo layers, mapping the
/// pointer's x to the nearest column and floating one tooltip. The fl_chart
/// layers keep touch off, because the top line layer's `Positioned.fill` would
/// otherwise intercept the hover before it reached the bars underneath.
Widget _comboHoverOverlay({
  required Widget layers,
  required int n,
  required double leftRes,
  required double rightRes,
  required double w,
  required TextStyle style,
  required String? tooltip,
  required void Function(String?) setTooltip,
  required String Function(int col) textForColumn,
}) {
  return LayoutBuilder(
    builder: (context, c) {
      final plotW = math.max(1.0, c.maxWidth - leftRes - rightRes);
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: layers),
          Positioned.fill(
            child: MouseRegion(
              opaque: false,
              onHover: (event) {
                if (n <= 0) return;
                final frac = (event.localPosition.dx - leftRes) / plotW;
                final col = (frac * n).floor().clamp(0, n - 1);
                setTooltip(textForColumn(col));
              },
              onExit: (_) => setTooltip(null),
              child: const SizedBox.expand(),
            ),
          ),
          if (tooltip case final text?) _cellTooltipOverlay(w, style, text),
        ],
      );
    },
  );
}

class _HoverPieChart extends StatefulWidget {
  final List<double> values;
  final List<String> labels;
  final List<Color> colors;

  /// Per-slice ink for the on-slice percentage, chosen to stay readable on that
  /// slice's fill (white on a dark slice, a dark ink on a pale one).
  final List<Color> labelColors;
  final double radius;
  final double centerSpaceRadius;
  final double sectionSpace;
  final TextStyle titleStyle;
  final TextStyle tooltipStyle;

  /// Whether each slice prints its share as a percentage. Off = a clean circle.
  final bool showLabels;

  /// Rotation in degrees clockwise from the top (12 o'clock). 0 = first slice
  /// starts at the top, matching the HTML export.
  final double startAngle;

  /// Slice index highlighted from outside (e.g. hovering the legend, or the
  /// slice the other screen is pointing at), combined with this chart's own
  /// touch hover.
  final int? externalHover;

  /// Reports the slice under the pointer (or null on exit) so the parent can
  /// mirror it to the other screen. Null off the mirror (editor/thumbnails).
  final ValueChanged<int?>? onHovered;

  /// Optional text drawn in the centre hole (the total, for a donut).
  final String? centerLabel;
  final TextStyle? centerLabelStyle;

  const _HoverPieChart({
    required this.values,
    required this.labels,
    required this.colors,
    required this.labelColors,
    required this.radius,
    required this.centerSpaceRadius,
    required this.sectionSpace,
    required this.titleStyle,
    required this.tooltipStyle,
    this.showLabels = true,
    this.startAngle = 0,
    this.externalHover,
    this.onHovered,
    this.centerLabel,
    this.centerLabelStyle,
  });

  @override
  State<_HoverPieChart> createState() => _HoverPieChartState();
}

class _HoverPieChartState extends State<_HoverPieChart> {
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final total = widget.values.fold<double>(0, (a, b) => a + b);
    final external = widget.externalHover;
    final hovered =
        _hovered ??
        (external != null && external >= 0 && external < widget.values.length
            ? external
            : null);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: PieChart(
            PieChartData(
              sections: [
                for (var i = 0; i < widget.values.length; i++)
                  PieChartSectionData(
                    value: widget.values[i],
                    color: widget.colors[i],
                    title: widget.showLabels && widget.values[i] / total >= 0.08
                        ? '${(widget.values[i] / total * 100).round()}%'
                        : '',
                    radius: widget.radius * (hovered == i ? 1.08 : 1),
                    titleStyle: widget.titleStyle.copyWith(
                      color: widget.labelColors[i],
                    ),
                  ),
              ],
              sectionsSpace: widget.sectionSpace,
              centerSpaceRadius: widget.centerSpaceRadius,
              // fl_chart's 0° is the right (3 o'clock); the -90 turns that to the
              // top so a 0 startAngle matches the HTML export, then startAngle
              // rotates clockwise from there.
              startDegreeOffset: widget.startAngle - 90,
              pieTouchData: PieTouchData(
                enabled: true,
                mouseCursorResolver: (event, response) =>
                    response?.touchedSection == null
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.click,
                touchCallback: (event, response) {
                  final next = event.isInterestedForInteractions
                      ? response?.touchedSection?.touchedSectionIndex
                      : null;
                  if (next != _hovered) {
                    setState(() => _hovered = next);
                    widget.onHovered?.call(next);
                  }
                },
              ),
            ),
            duration: Duration.zero,
          ),
        ),
        if (widget.centerLabel != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Text(
                  widget.centerLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: widget.centerLabelStyle,
                ),
              ),
            ),
          ),
        if (hovered != null && hovered >= 0 && hovered < widget.values.length)
          Positioned(
            top: 4,
            left: 4,
            right: 4,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  key: const ValueKey('pie-hover-tooltip'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.chartTooltipBg,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(color: AppTheme.shadow20, blurRadius: 6),
                    ],
                  ),
                  child: Text(
                    '${widget.labels[hovered]}: ${_formatChartValue(widget.values[hovered])}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: widget.tooltipStyle,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
