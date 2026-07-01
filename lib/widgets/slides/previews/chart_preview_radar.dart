// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability (radar chart builder & its labels/tooltip); all imports live in the main
// library file. These _ChartPreviewState chart builders relocate verbatim
// into an extension — same library, same members, no behaviour change.
part of '../slide_preview.dart';

extension _ChartPreviewRadar on _ChartPreviewState {
  Widget _radarChart(ChartSpec spec, Color textColor) {
    if (spec.x.length < 3 || spec.series.isEmpty) {
      return _placeholderText(
        context.l10n.d('Een spider-diagram heeft minstens drie labels nodig'),
      );
    }
    final grid = textColor.withValues(alpha: 0.18);
    final scale = radarScale(spec);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.02, vertical: w * 0.012),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Reserve a slim column on the right for the scale legend; the rest
          // of the area is shared between the spider and its axis labels.
          final legendWidth = w * 0.075;
          final boxW = math.max(
            0.0,
            constraints.maxWidth - legendWidth - w * 0.02,
          );
          final boxH = constraints.maxHeight;
          if (boxW <= 0 || !boxH.isFinite || boxH <= 0) {
            return const SizedBox.shrink();
          }
          // Measure every axis label and grow the spider until the labels just
          // fit between the polygon and the edges of the available area, so
          // the diagram uses the space the old fixed label bands wasted.
          final layout = _radarLabelLayout(spec, boxW, boxH, textColor);
          final chartSide = layout.chartSide;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: boxW,
                    height: boxH,
                    child: Stack(
                      children: [
                        for (var i = 0; i < spec.x.length; i++)
                          _radarAxisLabel(
                            label: spec.x[i],
                            index: i,
                            count: spec.x.length,
                            layout: layout,
                            textColor: textColor,
                          ),
                        Positioned(
                          left: (boxW - chartSide) / 2,
                          top: (boxH - chartSide) / 2,
                          width: chartSide,
                          height: chartSide,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: _radarChartCore(spec, grid, scale),
                              ),
                              if (_radarTouch != null)
                                _radarTooltip(spec, chartSide, _radarTouch!),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: legendWidth,
                child: _radarScaleLegend(scale, textColor),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _radarChartCore(
    ChartSpec spec,
    Color grid,
    ({double lo, double hi, int ticks}) scale,
  ) {
    return RadarChart(
      RadarChartData(
        dataSets: [
          for (var si = 0; si < spec.series.length; si++)
            RadarDataSet(
              dataEntries: [
                for (var xi = 0; xi < spec.x.length; xi++)
                  RadarEntry(
                    value:
                        (xi < spec.series[si].data.length
                            ? spec.series[si].data[xi]
                            : 0) *
                        _grow,
                  ),
              ],
              fillColor: _seriesDisplayColor(
                spec.series[si],
                si,
              ).withValues(alpha: _dimmed(si) ? 0.04 : 0.16),
              borderColor: _seriesDisplayColor(spec.series[si], si),
              borderWidth: w * (_hovered == si ? 0.0040 : 0.0022),
              entryRadius: w * (_hovered == si ? 0.006 : 0.004),
            ),
          // Invisible anchor pinning the scale to [lo, hi]
          // so the rings represent a fixed scale.
          RadarDataSet(
            dataEntries: [
              for (var xi = 0; xi < spec.x.length; xi++)
                RadarEntry(value: xi == 0 ? scale.hi : scale.lo),
            ],
            fillColor: Colors.transparent,
            borderColor: Colors.transparent,
            borderWidth: 0,
            entryRadius: 0,
          ),
        ],
        radarShape: RadarShape.polygon,
        radarBackgroundColor: Colors.transparent,
        radarBorderData: BorderSide(color: grid, width: 1),
        gridBorderData: BorderSide(color: grid, width: 1),
        tickBorderData: BorderSide(color: grid, width: 1),
        tickCount: scale.ticks,
        isMinValueAtCenter: true,
        // The scale now lives in a side legend, so hide
        // fl_chart's in-chart ring numbers.
        ticksTextStyle: const TextStyle(
          color: Colors.transparent,
          fontSize: 0.001,
        ),
        titlePositionPercentageOffset: 0,
        getTitle: (index, angle) =>
            RadarChartTitle(text: index < spec.x.length ? spec.x[index] : ''),
        // Labels are rendered as constrained widgets
        // around the chart so long text can wrap.
        titleTextStyle: const TextStyle(
          color: Colors.transparent,
          fontSize: 0.001,
        ),
        radarTouchData: RadarTouchData(
          enabled: true,
          touchSpotThreshold: (w * 0.02).clamp(8.0, 24.0).toDouble(),
          mouseCursorResolver: (event, response) =>
              _radarSpotFrom(response, spec) == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          touchCallback: (event, response) {
            final next = event.isInterestedForInteractions
                ? _radarSpotFrom(response, spec)
                : null;
            if (next != _radarTouch) {
              _rebuild(() => _radarTouch = next);
            }
          },
        ),
      ),
      duration: _chartAnimDuration,
    );
  }

  TextStyle _radarLabelStyle(int count, Color textColor) => _applyFont(
    font,
    TextStyle(
      fontSize: w * (count <= 6 ? 0.013 : 0.0115) * _labelScale,
      height: 1.05,
      color: textColor.withValues(alpha: 0.88),
      fontWeight: presentationMode ? FontWeight.w600 : FontWeight.w500,
    ),
  );

  /// True when the vertex in [direction] gets its label placed beside the
  /// polygon (left/right) rather than above/below it.
  bool _radarLabelBeside(Offset direction) => direction.dx.abs() > 0.35;

  /// Sizes the spider and places every axis label around it.
  ///
  /// Each label is measured at its real text size, then the polygon radius is
  /// grown until the tightest label exactly fits between the polygon and the
  /// edge of the [boxW]×[boxH] area. fl_chart draws the polygon at 0.4× the
  /// side of its (square) widget, which is what ties [chartSide] to the
  /// resulting radius.
  ({double chartSide, List<Rect> rects, List<TextAlign> aligns, int maxLines})
  _radarLabelLayout(ChartSpec spec, double boxW, double boxH, Color textColor) {
    const radiusFactor = 0.4; // fl_chart: radius = min(w, h) / 2 * 0.8
    final n = spec.x.length;
    final style = _radarLabelStyle(n, textColor);
    final gap = w * 0.008;
    final maxLines = n <= 6 ? 3 : 2;
    final sideCap = math.min(boxW * 0.28, w * 0.2);
    final topCap = math.min(boxW * 0.5, w * 0.3);

    Size measure(String text, double maxWidth) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
        ellipsis: '…',
      )..layout(maxWidth: math.max(0.0, maxWidth));
      final size = Size(painter.width, painter.height);
      painter.dispose();
      return size;
    }

    final directions = <Offset>[];
    final sizes = <Size>[];
    for (var i = 0; i < n; i++) {
      final angle = (2 * math.pi * i / n) - math.pi / 2;
      final dir = Offset(math.cos(angle), math.sin(angle));
      directions.add(dir);
      sizes.add(measure(spec.x[i], _radarLabelBeside(dir) ? sideCap : topCap));
    }

    // The largest polygon radius every label still fits next to.
    var radius = radiusFactor * math.min(boxW, boxH);
    for (var i = 0; i < n; i++) {
      final dx = directions[i].dx.abs();
      final dy = directions[i].dy.abs();
      if (_radarLabelBeside(directions[i])) {
        radius = math.min(radius, (boxW / 2 - gap - sizes[i].width) / dx);
        if (dy > 0.01) {
          radius = math.min(radius, (boxH / 2 - sizes[i].height / 2) / dy);
        }
      } else {
        radius = math.min(radius, (boxH / 2 - gap - sizes[i].height) / dy);
        if (dx > 0.01) {
          radius = math.min(radius, (boxW / 2 - sizes[i].width / 2) / dx);
        }
      }
    }
    // Never let extreme labels crush the spider entirely; below this floor the
    // labels get clamped (and ellipsized) instead.
    final floor = 0.18 * math.min(boxW, boxH);
    radius = radius.clamp(
      math.min(floor, radiusFactor * math.min(boxW, boxH)),
      radiusFactor * math.min(boxW, boxH),
    );
    final chartSide = radius / radiusFactor;

    final center = Offset(boxW / 2, boxH / 2);
    final rects = <Rect>[];
    final aligns = <TextAlign>[];
    for (var i = 0; i < n; i++) {
      final dir = directions[i];
      final anchor = center + dir * (radius + gap);
      var size = sizes[i];
      double left;
      double top;
      if (_radarLabelBeside(dir)) {
        // Re-measure against the room actually left beside the polygon, so a
        // clamped radius still produces a label that wraps inside the box.
        final room = dir.dx > 0 ? boxW - anchor.dx : anchor.dx;
        if (size.width > room) size = measure(spec.x[i], room);
        left = dir.dx > 0 ? anchor.dx : anchor.dx - size.width;
        top = anchor.dy - size.height / 2;
        aligns.add(dir.dx > 0 ? TextAlign.left : TextAlign.right);
      } else {
        left = anchor.dx - size.width / 2;
        top = dir.dy < 0 ? anchor.dy - size.height : anchor.dy;
        aligns.add(TextAlign.center);
      }
      rects.add(
        Rect.fromLTWH(
          left.clamp(0.0, math.max(0.0, boxW - size.width)),
          top.clamp(0.0, math.max(0.0, boxH - size.height)),
          size.width,
          size.height,
        ),
      );
    }
    return (
      chartSide: chartSide,
      rects: rects,
      aligns: aligns,
      maxLines: maxLines,
    );
  }

  Widget _radarAxisLabel({
    required String label,
    required int index,
    required int count,
    required ({
      double chartSide,
      List<Rect> rects,
      List<TextAlign> aligns,
      int maxLines,
    })
    layout,
    required Color textColor,
  }) {
    final rect = layout.rects[index];
    return Positioned(
      key: ValueKey('radar-axis-label-$index'),
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Text(
        label,
        maxLines: layout.maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: layout.aligns[index],
        style: _radarLabelStyle(count, textColor),
      ),
    );
  }

  /// Extract the touched real-series vertex from a radar touch response,
  /// ignoring the invisible scale anchor dataset.
  ({int series, int entry, double value, Offset offset})? _radarSpotFrom(
    RadarTouchResponse? response,
    ChartSpec spec,
  ) {
    final spot = response?.touchedSpot;
    if (spot == null) return null;
    if (spot.touchedDataSetIndex < 0 ||
        spot.touchedDataSetIndex >= spec.series.length) {
      return null; // the anchor dataset, or out of range
    }
    return (
      series: spot.touchedDataSetIndex,
      entry: spot.touchedRadarEntryIndex,
      value: spot.touchedRadarEntry.value,
      offset: spot.offset,
    );
  }

  /// A small floating tooltip for the hovered radar vertex, like the other
  /// charts: the axis label, the series name and the value.
  Widget _radarTooltip(
    ChartSpec spec,
    double side,
    ({int series, int entry, double value, Offset offset}) touch,
  ) {
    final axis = touch.entry >= 0 && touch.entry < spec.x.length
        ? spec.x[touch.entry]
        : '';
    final series = touch.series < spec.series.length
        ? spec.series[touch.series].name
        : '';
    final label = series.isEmpty ? 'Reeks ${touch.series + 1}' : series;
    final onLeftHalf = touch.offset.dx <= side / 2;
    return Positioned(
      left: onLeftHalf ? (touch.offset.dx + w * 0.012) : null,
      right: onLeftHalf ? null : (side - touch.offset.dx + w * 0.012),
      top: (touch.offset.dy - w * 0.03).clamp(0.0, math.max(0.0, side - 1)),
      child: IgnorePointer(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: side * 0.6),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.012,
              vertical: w * 0.006,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(w * 0.008),
              boxShadow: const [
                BoxShadow(color: Color(0x33000000), blurRadius: 6),
              ],
            ),
            child: Text(
              '${axis.isEmpty ? '' : '$axis\n'}$label: ${_fmtNum(touch.value)}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: _tooltipStyle(),
            ),
          ),
        ),
      ),
    );
  }

  /// Vertical scale legend shown to the right of a radar chart: the tick values
  /// from the outer ring (top) down to the centre (bottom), in a small font.
  Widget _radarScaleLegend(
    ({double lo, double hi, int ticks}) scale,
    Color textColor,
  ) {
    final style = _applyFont(
      font,
      TextStyle(
        fontSize: w * 0.012 * _labelScale,
        color: textColor.withValues(alpha: 0.62),
        fontWeight: FontWeight.w600,
      ),
    );
    final tickColor = textColor.withValues(alpha: 0.3);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var k = scale.ticks; k >= 0; k--) ...[
          if (k != scale.ticks) SizedBox(height: w * 0.018 * _labelScale),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: w * 0.012, height: 1, color: tickColor),
              SizedBox(width: w * 0.006),
              Flexible(
                child: Text(
                  _fmtNum(scale.lo + (scale.hi - scale.lo) * k / scale.ticks),
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Resolves the radar scale: a low/high pair plus an even tick count. Honours
  /// the optional [ChartSpec.minBound]/[maxBound] and otherwise rounds the data
  /// range to a tidy scale so the rings read as round numbers.
  ({double lo, double hi, int ticks}) radarScale(ChartSpec spec) {
    var dataMin = 0.0;
    var dataMax = 0.0;
    var seen = false;
    for (final s in spec.series) {
      for (final v in s.data) {
        if (!seen) {
          dataMin = v;
          dataMax = v;
          seen = true;
        } else {
          if (v < dataMin) dataMin = v;
          if (v > dataMax) dataMax = v;
        }
      }
    }
    if (!seen) {
      dataMin = 0;
      dataMax = 1;
    }
    final rawLo = spec.minBound ?? (dataMin < 0 ? dataMin : 0);
    final rawHi = spec.maxBound ?? dataMax;
    final nice = _niceScale(rawLo, rawHi);
    final lo = spec.minBound ?? nice.lo;
    var hi = spec.maxBound ?? nice.hi;
    if (hi <= lo) hi = lo + nice.step;
    final ticks = math.max(2, ((hi - lo) / nice.step).round());
    return (lo: lo, hi: hi, ticks: ticks);
  }

  ({double lo, double hi, double step}) _niceScale(double lo, double hi) {
    final range = (hi - lo).abs();
    final r = range <= 0 ? 1.0 : range;
    final rawStep = r / 4;
    final mag = math
        .pow(10, (math.log(rawStep) / math.ln10).floor())
        .toDouble();
    final norm = rawStep / mag;
    final niceNorm = norm < 1.5
        ? 1.0
        : norm < 3
        ? 2.0
        : norm < 7
        ? 5.0
        : 10.0;
    final step = niceNorm * mag;
    return (
      lo: (lo / step).floor() * step,
      hi: (hi / step).ceil() * step,
      step: step,
    );
  }
}
