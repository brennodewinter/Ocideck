// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability (horizontal bar / combo / waterfall / heatmap
// chart builders); all imports live in the main library file. These
// _ChartPreviewState chart builders are an extension in the same library.
part of '../slide_preview.dart';

extension _ChartPreviewExtra on _ChartPreviewState {
  /// Growth wrapper for the hand-drawn charts (horizontal bar, heatmap) that
  /// don't ride fl_chart's own tween: rebuilds against [_entrance] so a value
  /// [t] runs 0→1 on enter and sits at 1 otherwise (editor, animation off).
  Widget _customGrow(Widget Function(double t) build) {
    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, _) {
        final t = _chartAnimDuration == Duration.zero
            ? 1.0
            : Curves.easeOut.transform(_entrance.value.clamp(0.0, 1.0));
        return build(t);
      },
    );
  }

  // ── Horizontal bar ───────────────────────────────────────────────────────

  double _maxHorizontal(ChartSpec spec) {
    var m = 0.0;
    for (final s in spec.series) {
      for (final v in s.data) {
        if (v > m) m = v;
      }
    }
    return m <= 0 ? 1 : m * 1.15;
  }

  /// Bars laid left-to-right, one group per label with a thin bar per series.
  /// Good for rankings and long category names that a vertical axis would
  /// crowd. Static (no tooltip); each bar prints its value at the tip.
  Widget _horizontalBarChart(ChartSpec spec, Color textColor) {
    final n = spec.x.length;
    if (n == 0 || spec.series.isEmpty) {
      return _placeholderText(context.l10n.d('Geen grafiekgegevens'));
    }
    final maxX = _maxHorizontal(spec);
    final labelStyle = _applyFont(
      font,
      TextStyle(
        fontSize: w * 0.0115 * _labelScale,
        color: textColor.withValues(alpha: 0.88),
        fontWeight: presentationMode ? FontWeight.w600 : FontWeight.normal,
      ),
    );
    final axisStyle = labelStyle.copyWith(fontSize: w * 0.0105 * _labelScale);
    return _withCellTooltip(
      tooltip: _cellTooltip,
      w: w,
      style: _tooltipStyle(),
      chart: _customGrow((t) {
        return LayoutBuilder(
          builder: (context, c) {
            final labelW = math.max(w * 0.12, c.maxWidth * 0.24);
            final axisH = w * 0.03 * _labelScale;
            final plotW = math.max(0.0, c.maxWidth - labelW);
            return Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: labelW,
                        child: Column(
                          children: [
                            for (var i = 0; i < n; i++)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(right: w * 0.008),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      spec.x[i],
                                      textAlign: TextAlign.right,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: labelStyle,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            for (var g = 0; g <= 4; g++)
                              Positioned(
                                left: plotW * g / 4,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  width: 1,
                                  color: textColor.withValues(alpha: 0.12),
                                ),
                              ),
                            Column(
                              children: [
                                for (var i = 0; i < n; i++)
                                  Expanded(
                                    child: _hBarBand(
                                      spec,
                                      i,
                                      maxX,
                                      plotW,
                                      t,
                                      textColor,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: axisH,
                  child: Row(
                    children: [
                      SizedBox(width: labelW),
                      Expanded(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (var g = 0; g <= 4; g++)
                              Positioned(
                                left: (plotW * g / 4 - w * 0.03).clamp(
                                  0.0,
                                  math.max(0.0, plotW - w * 0.02),
                                ),
                                top: 0,
                                width: w * 0.06,
                                child: Text(
                                  _fmtNum(maxX * g / 4),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: axisStyle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      }),
    );
  }

  Widget _hBarBand(
    ChartSpec spec,
    int cat,
    double maxX,
    double plotW,
    double t,
    Color textColor,
  ) {
    final s = spec.series;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: w * 0.005),
      child: Column(
        children: [
          for (var si = 0; si < s.length; si++)
            if (cat < s[si].data.length)
              Expanded(
                child: MouseRegion(
                  key: ValueKey('hbar-cell-$cat-$si'),
                  onEnter: (_) => _setCellTooltip(
                    _seriesCellTooltip(context, spec, cat, si),
                  ),
                  onExit: (_) => _setCellTooltip(null),
                  child: _hBarCell(
                    s[si].data[cat],
                    _seriesDisplayColor(s[si], si),
                    maxX,
                    plotW,
                    t,
                    textColor,
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _hBarCell(
    double value,
    Color color,
    double maxX,
    double plotW,
    double t,
    Color textColor,
  ) {
    final frac = maxX <= 0 ? 0.0 : (value / maxX).clamp(0.0, 1.0);
    final len = math.max(0.0, plotW * frac * t);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: w * 0.0015),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: len,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(w * 0.004),
                ),
              ),
            ),
          ),
          if (t > 0.98 && value != 0)
            Positioned(
              left: math.min(len + w * 0.006, math.max(0.0, plotW - w * 0.05)),
              top: 0,
              bottom: 0,
              child: Center(
                child: Text(
                  _fmtNum(value),
                  maxLines: 1,
                  style: _applyFont(
                    font,
                    TextStyle(
                      fontSize: w * 0.011 * _labelScale,
                      color: textColor.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Horizontal stacked bar ───────────────────────────────────────────────

  /// The largest per-label *total*: unlike a plain horizontal bar (which scales
  /// to the biggest single value), a stacked bar's value axis must fit the sum
  /// of its segments, so the widest whole bar just reaches the axis end.
  double _maxHorizontalStacked(ChartSpec spec) {
    var m = 0.0;
    for (var xi = 0; xi < spec.x.length; xi++) {
      var sum = 0.0;
      for (final s in spec.series) {
        if (xi < s.data.length) sum += s.data[xi];
      }
      if (sum > m) m = sum;
    }
    return m <= 0 ? 1 : m * 1.15;
  }

  /// A [_stackedBarChart] laid on its side: one bar per label with the series
  /// stacked left-to-right. Reuses the horizontal-bar scaffolding (right-aligned
  /// label column, vertical gridlines, a value axis) but each band is a single
  /// segmented bar instead of one thin bar per series. Static (no tooltip); a
  /// segment prints its value when it is wide enough to fit.
  Widget _horizontalStackedBarChart(ChartSpec spec, Color textColor) {
    final n = spec.x.length;
    if (n == 0 || spec.series.isEmpty) {
      return _placeholderText(context.l10n.d('Geen grafiekgegevens'));
    }
    final maxX = _maxHorizontalStacked(spec);
    final labelStyle = _applyFont(
      font,
      TextStyle(
        fontSize: w * 0.0115 * _labelScale,
        color: textColor.withValues(alpha: 0.88),
        fontWeight: presentationMode ? FontWeight.w600 : FontWeight.normal,
      ),
    );
    final axisStyle = labelStyle.copyWith(fontSize: w * 0.0105 * _labelScale);
    return _withCellTooltip(
      tooltip: _cellTooltip,
      w: w,
      style: _tooltipStyle(),
      chart: _customGrow((t) {
        return LayoutBuilder(
          builder: (context, c) {
            final labelW = math.max(w * 0.12, c.maxWidth * 0.24);
            final axisH = w * 0.03 * _labelScale;
            final plotW = math.max(0.0, c.maxWidth - labelW);
            return Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: labelW,
                        child: Column(
                          children: [
                            for (var i = 0; i < n; i++)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(right: w * 0.008),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      spec.x[i],
                                      textAlign: TextAlign.right,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: labelStyle,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            for (var g = 0; g <= 4; g++)
                              Positioned(
                                left: plotW * g / 4,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  width: 1,
                                  color: textColor.withValues(alpha: 0.12),
                                ),
                              ),
                            Column(
                              children: [
                                for (var i = 0; i < n; i++)
                                  Expanded(
                                    child: _hStackBand(
                                      spec,
                                      i,
                                      maxX,
                                      plotW,
                                      t,
                                      textColor,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: axisH,
                  child: Row(
                    children: [
                      SizedBox(width: labelW),
                      Expanded(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (var g = 0; g <= 4; g++)
                              Positioned(
                                left: (plotW * g / 4 - w * 0.03).clamp(
                                  0.0,
                                  math.max(0.0, plotW - w * 0.02),
                                ),
                                top: 0,
                                width: w * 0.06,
                                child: Text(
                                  _fmtNum(maxX * g / 4),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: axisStyle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      }),
    );
  }

  /// One stacked bar (a whole category), its series abutting left-to-right. The
  /// outer-right end is rounded (the growing tip); segments print their value
  /// when wide enough. White hairline separators keep touching segments legible.
  Widget _hStackBand(
    ChartSpec spec,
    int cat,
    double maxX,
    double plotW,
    double t,
    Color textColor,
  ) {
    final s = spec.series;
    final segs = <({double len, Color color, double value, int si})>[];
    for (var si = 0; si < s.length; si++) {
      if (cat >= s[si].data.length) continue;
      final value = s[si].data[cat];
      final frac = maxX <= 0 ? 0.0 : (value / maxX).clamp(0.0, 1.0);
      final len = math.max(0.0, plotW * frac * t);
      if (len <= 0) continue;
      segs.add((
        len: len,
        color: _seriesDisplayColor(s[si], si),
        value: value,
        si: si,
      ));
    }
    final labelStyle = _applyFont(
      font,
      TextStyle(
        fontSize: w * 0.011 * _labelScale,
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: w * 0.006),
      child: ClipRRect(
        borderRadius: BorderRadius.horizontal(
          right: Radius.circular(w * 0.004),
        ),
        child: Row(
          children: [
            for (var i = 0; i < segs.length; i++)
              MouseRegion(
                key: ValueKey('hstack-seg-$cat-${segs[i].si}'),
                onEnter: (_) => _setCellTooltip(
                  _seriesCellTooltip(context, spec, cat, segs[i].si),
                ),
                onExit: (_) => _setCellTooltip(null),
                child: SizedBox(
                  width: segs[i].len,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: segs[i].color,
                      border: i == 0
                          ? null
                          : Border(
                              left: BorderSide(
                                color: Colors.white.withValues(alpha: 0.9),
                                width: w * 0.001,
                              ),
                            ),
                    ),
                    child: segs[i].len > w * 0.045 && segs[i].value != 0
                        ? Center(
                            child: Text(
                              _fmtNum(segs[i].value),
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                              style: labelStyle,
                            ),
                          )
                        : const SizedBox.expand(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Combo (bars + line on a second axis) ─────────────────────────────────

  double _comboBarMaxY(List<ChartSeries> barSeries, ChartSpec spec) {
    var m = 0.0;
    for (final s in barSeries) {
      for (final v in s.data) {
        if (v > m) m = v;
      }
    }
    for (final b in [spec.minBound, spec.maxBound]) {
      if (b != null && b > m) m = b;
    }
    return m <= 0 ? 1 : m * 1.15;
  }

  (double, double) _comboLineRange(ChartSeries line) {
    double? lo, hi;
    for (final v in line.data) {
      lo = lo == null ? v : math.min(lo, v);
      hi = hi == null ? v : math.max(hi, v);
    }
    if (lo == null || hi == null) return (0, 1);
    if (hi == lo) hi = lo + 1;
    final pad = (hi - lo) * 0.15;
    return (lo > 0 ? 0.0 : lo - pad, hi + pad);
  }

  /// Bars for every series except the last, which is drawn as a line on its
  /// own right-hand axis. Two fl_charts stacked with identical plot insets so
  /// the line's points sit over the bar groups. Degrades to a plain bar chart
  /// when there is only one series.
  Widget _comboChart(ChartSpec spec, Color textColor) {
    if (spec.series.length < 2) return _barChart(spec, textColor);
    final n = spec.x.length;
    final barSeries = spec.series.sublist(0, spec.series.length - 1);
    final lineIdx = spec.series.length - 1;
    final lineSeries = spec.series[lineIdx];
    final barMaxY = _comboBarMaxY(barSeries, spec);
    final (lineMin, lineMax) = _comboLineRange(lineSeries);
    final lineColor = _seriesDisplayColor(lineSeries, lineIdx);
    final leftRes = w * 0.05 * _labelScale;
    final bottomRes = w * 0.044 * _labelScale;
    final rightRes = w * 0.058 * _labelScale;
    final barRodW = (w * 0.032 / barSeries.length).clamp(w * 0.008, w * 0.022);

    // Both fl_chart layers keep touch off; the top line layer's Positioned.fill
    // would otherwise swallow hover before it reaches the bars. A single
    // transparent MouseRegion over the whole Stack maps the pointer to a column.
    final layers = Stack(
      children: [
        Positioned.fill(
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: barMaxY,
              alignment: BarChartAlignment.spaceEvenly,
              barGroups: [
                for (var xi = 0; xi < n; xi++)
                  BarChartGroupData(
                    x: xi,
                    barRods: [
                      for (var si = 0; si < barSeries.length; si++)
                        if (xi < barSeries[si].data.length)
                          BarChartRodData(
                            toY: barSeries[si].data[xi] * _grow,
                            color: _seriesDisplayColor(barSeries[si], si),
                            width: barRodW,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(w * 0.006),
                            ),
                          ),
                    ],
                  ),
              ],
              titlesData: _comboTitles(
                spec,
                textColor,
                leftRes: leftRes,
                bottomRes: bottomRes,
                rightRes: rightRes,
                forLine: false,
                lineColor: lineColor,
              ),
              gridData: _grid(textColor),
              borderData: FlBorderData(show: false),
              extraLinesData: _boundLines(spec),
              barTouchData: BarTouchData(enabled: false),
            ),
            duration: _chartAnimDuration,
          ),
        ),
        Positioned.fill(
          child: LineChart(
            LineChartData(
              minX: -0.5,
              maxX: n - 0.5,
              minY: lineMin,
              maxY: lineMax,
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var xi = 0; xi < lineSeries.data.length; xi++)
                      FlSpot(xi.toDouble(), lineSeries.data[xi] * _grow),
                  ],
                  color: lineColor,
                  barWidth: w * 0.006,
                  isCurved: true,
                  curveSmoothness: 0.2,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, bar, index) =>
                        FlDotCirclePainter(
                          radius: w * 0.006,
                          color: lineColor,
                          strokeWidth: w * 0.0025,
                          strokeColor: AppTheme.parseHexColor(
                            profile.slideBackgroundColor,
                          ),
                        ),
                  ),
                ),
              ],
              titlesData: _comboTitles(
                spec,
                textColor,
                leftRes: leftRes,
                bottomRes: bottomRes,
                rightRes: rightRes,
                forLine: true,
                lineColor: lineColor,
              ),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
            ),
            duration: _chartAnimDuration,
          ),
        ),
      ],
    );
    return _comboHoverOverlay(
      layers: layers,
      n: n,
      leftRes: leftRes,
      rightRes: rightRes,
      w: w,
      style: _tooltipStyle(),
      tooltip: _cellTooltip,
      setTooltip: _setCellTooltip,
      textForColumn: (col) =>
          _comboTooltipText(context, spec, col, barSeries, lineSeries),
    );
  }

  /// Titles for one combo layer. Both layers reserve the SAME left/right/bottom
  /// bands (blank where the other layer owns them) so their plot rectangles —
  /// and therefore the x positions — line up exactly.
  FlTitlesData _comboTitles(
    ChartSpec spec,
    Color textColor, {
    required double leftRes,
    required double bottomRes,
    required double rightRes,
    required bool forLine,
    required Color lineColor,
  }) {
    final baseStyle = _applyFont(
      font,
      TextStyle(
        fontSize: w * 0.0105 * _labelScale,
        color: textColor.withValues(alpha: 0.88),
        fontWeight: presentationMode ? FontWeight.w600 : FontWeight.normal,
      ),
    );
    const blank = SizedBox.shrink();
    final n = spec.x.length;
    final step = math.max(1, (n / 8).ceil());
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: leftRes,
          getTitlesWidget: (value, meta) =>
              forLine ? blank : Text(_fmtNum(value), style: baseStyle),
        ),
      ),
      rightTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: rightRes,
          getTitlesWidget: (value, meta) => forLine
              ? Text(
                  _fmtNum(value),
                  style: baseStyle.copyWith(color: lineColor),
                )
              : blank,
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: 1,
          reservedSize: bottomRes,
          getTitlesWidget: (value, meta) {
            if (forLine) return blank;
            final i = value.round();
            if (i < 0 || i >= n) return blank;
            if (i % step != 0 && i != n - 1) return blank;
            return Padding(
              padding: EdgeInsets.only(top: w * 0.006),
              child: Text(
                spec.x[i],
                style: baseStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Waterfall ────────────────────────────────────────────────────────────

  /// The first series read as up/down steps: each bar floats from the previous
  /// running total to the new one, green for a rise and red for a fall.
  Widget _waterfallChart(ChartSpec spec, Color textColor) {
    final n = spec.x.length;
    if (spec.series.isEmpty || n == 0) {
      return _placeholderText(context.l10n.d('Geen grafiekgegevens'));
    }
    final s = spec.series.first;
    final tops = <double>[];
    final bottoms = <double>[];
    final deltas = <double>[];
    var cum = 0.0;
    for (var i = 0; i < n; i++) {
      final d = i < s.data.length ? s.data[i] : 0.0;
      final to = cum + d;
      bottoms.add(math.min(cum, to));
      tops.add(math.max(cum, to));
      deltas.add(d);
      cum = to;
    }
    var maxY = 0.0;
    var minY = 0.0;
    for (var i = 0; i < n; i++) {
      if (tops[i] > maxY) maxY = tops[i];
      if (bottoms[i] < minY) minY = bottoms[i];
    }
    if (spec.maxBound != null && spec.maxBound! > maxY) maxY = spec.maxBound!;
    if (spec.minBound != null && spec.minBound! < minY) minY = spec.minBound!;
    maxY = maxY <= 0 ? 1 : maxY * 1.15;
    if (minY < 0) minY = minY * 1.15;
    const up = AppTheme.success700;
    const down = AppTheme.danger500;
    final barW = (w * 0.03).clamp(w * 0.01, w * 0.03);

    return BarChart(
      BarChartData(
        minY: minY,
        maxY: maxY,
        alignment: BarChartAlignment.spaceEvenly,
        barGroups: [
          for (var i = 0; i < n; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  fromY: bottoms[i] * _grow,
                  toY: tops[i] * _grow,
                  width: barW,
                  color: deltas[i] >= 0 ? up : down,
                  borderRadius: BorderRadius.all(Radius.circular(w * 0.003)),
                ),
              ],
            ),
        ],
        titlesData: _titles(spec, textColor, bars: true),
        gridData: _grid(textColor),
        borderData: FlBorderData(show: false),
        extraLinesData: _boundLines(spec),
        // Show the step's signed delta, read from [deltas] rather than the rod's
        // from/to (which are min/max — the sign of a fall is lost there).
        barTouchData: BarTouchData(
          enabled: true,
          mouseCursorResolver: (event, response) => response?.spot == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          touchTooltipData: BarTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => AppTheme.chartTooltipBg,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final xi = group.x;
              final label = xi >= 0 && xi < spec.x.length ? spec.x[xi] : '';
              final delta = xi >= 0 && xi < deltas.length
                  ? deltas[xi]
                  : rod.toY - rod.fromY;
              return BarTooltipItem(
                '${label.isEmpty ? '' : '$label\n'}${_fmtNum(delta)}',
                _tooltipStyle(),
              );
            },
          ),
        ),
      ),
      duration: _chartAnimDuration,
    );
  }
}
