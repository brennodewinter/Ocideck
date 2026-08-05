// Part of the slide_preview library — see ../slide_preview.dart.
// Hover/touch tooltip helpers for the hand-drawn and combo charts. These are
// top-level functions (not members of _ChartPreviewState) so they don't inflate
// that class's size ratchet — mirroring the top-level _formatChartValue and the
// _HoverPieChart widget in chart_preview.dart. Split out of
// chart_preview_extra.dart for cohesion.
part of '../slide_preview.dart';

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
