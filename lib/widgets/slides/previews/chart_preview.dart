// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// Renders a chart slide (bar/line/pie) from its ```chart JSON spec.
class _ChartPreview extends StatefulWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;
  final bool presentationMode;

  const _ChartPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
    required this.presentationMode,
  });

  @override
  State<_ChartPreview> createState() => _ChartPreviewState();
}

class _ChartPreviewState extends State<_ChartPreview> {
  Slide get slide => widget.slide;
  double get w => widget.w;
  String get font => widget.font;
  ThemeProfile get profile => widget.profile;
  bool get presentationMode => widget.presentationMode;

  /// Legend entry the pointer is over: a series index for bar/line charts, or a
  /// slice (category) index for pie charts. Null when nothing is hovered.
  int? _hovered;

  /// The radar vertex under the pointer, used to draw its tooltip. Null when not
  /// hovering a point.
  ({int series, int entry, double value, Offset offset})? _radarTouch;

  void _setHover(int? index) {
    if (_hovered != index) setState(() => _hovered = index);
  }

  /// True when another legend entry is hovered, so [index] should fade back.
  bool _dimmed(int index) => _hovered != null && _hovered != index;

  /// Series colour with legend-hover feedback: non-hovered series fade out so
  /// the hovered one stands out in the plot.
  Color _seriesDisplayColor(ChartSeries series, int i) {
    final base = _seriesColor(series, i);
    return _dimmed(i) ? base.withValues(alpha: 0.2) : base;
  }

  double get _labelScale => presentationMode ? 1.12 : 1;

  Color _seriesColor(ChartSeries series, int i) {
    if (series.color == null && i == 0) {
      return _hexColor(profile.accentColor);
    }
    return _hexColor(chartSeriesColor(series, i));
  }

  /// Text alternative for the chart (WCAG 1.1.1): chart type, title and the
  /// underlying values per series, so a screen reader conveys the same
  /// information the visual encodes.
  String _semanticsLabel(BuildContext context, ChartSpec spec) {
    final l10n = context.l10n;
    final typeName = switch (spec.type) {
      ChartType.bar => l10n.d('Staaf'),
      ChartType.stackedBar => l10n.d('Gestapelde staaf'),
      ChartType.line => l10n.d('Lijn'),
      ChartType.pie => l10n.d('Cirkel'),
      ChartType.radar => l10n.d('Spider'),
      ChartType.scatter => l10n.d('Spreiding'),
    };
    final buffer = StringBuffer('${l10n.d('Grafiek')} ($typeName)');
    if (spec.title.isNotEmpty) {
      buffer.write(': ${stripInlineMarkdown(spec.title)}');
    }
    if (!spec.hasInlineData) return buffer.toString();
    for (var si = 0; si < spec.series.length; si++) {
      final series = spec.series[si];
      final name = series.name.isEmpty
          ? '${l10n.d('Reeks')} ${si + 1}'
          : series.name;
      final values = [
        for (var xi = 0; xi < spec.x.length && xi < series.data.length; xi++)
          '${spec.x[xi]} ${_fmtNum(series.data[xi])}',
      ];
      buffer.write('. $name: ${values.join(', ')}');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final spec = ChartSpec.parse(slide.customMarkdown);
    final horizontalPad = w * 0.05;
    final verticalPad = w * 0.018;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final textColor = _hexColor(profile.textColor);

    return Semantics(
      image: true,
      label: _semanticsLabel(context, spec),
      // The visual chart (axis labels, legend chips, tooltips) would read as
      // disconnected fragments; the label above carries the full story.
      child: ExcludeSemantics(
        child: _chartBody(
          context,
          spec,
          horizontalPad,
          verticalPad,
          safe,
          textColor,
        ),
      ),
    );
  }

  Widget _chartBody(
    BuildContext context,
    ChartSpec spec,
    double horizontalPad,
    double verticalPad,
    EdgeInsets safe,
    Color textColor,
  ) {
    return Container(
      color: _hexColor(profile.slideBackgroundColor),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPad,
          verticalPad + safe.top,
          horizontalPad,
          _logoAwareBottomPadding(verticalPad, safe.bottom),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (spec.title.isNotEmpty) ...[
              // Render the title like every other content slide (plain bold
              // text in the slide's text colour) instead of a boxed band, so
              // the header reads consistently across slide types.
              _md(
                context,
                spec.title,
                _applyFont(
                  font,
                  TextStyle(
                    fontSize: w * 0.038,
                    height: 1.2,
                    fontWeight: FontWeight.bold,
                    color: _hexColor(profile.textColor),
                  ),
                ),
                linkColor: _hexColor(profile.accentColor),
              ),
              SizedBox(height: w * 0.012),
            ],
            Expanded(
              child: Container(
                key: const ValueKey('chart-surface'),
                padding: EdgeInsets.fromLTRB(
                  w * 0.02,
                  w * 0.01,
                  w * 0.025,
                  w * 0.01,
                ),
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.035),
                  borderRadius: BorderRadius.circular(w * 0.014),
                  border: Border.all(color: textColor.withValues(alpha: 0.09)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: spec.hasInlineData
                          ? _chart(spec, textColor)
                          : _placeholder(context),
                    ),
                    if (spec.hasInlineData && spec.series.isNotEmpty) ...[
                      SizedBox(height: w * 0.006),
                      spec.type == ChartType.pie
                          ? _pieLegend(spec, textColor)
                          : _legend(spec, textColor),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(ChartSpec spec, Color textColor) {
    return SizedBox(
      height: w * 0.03,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < spec.series.length; i++) ...[
              if (i > 0) SizedBox(width: w * 0.01),
              MouseRegion(
                onEnter: (_) => _setHover(i),
                onExit: (_) => _setHover(null),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: _dimmed(i) ? 0.4 : 1,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: w * 0.01,
                      vertical: w * 0.004,
                    ),
                    decoration: BoxDecoration(
                      color: _hovered == i
                          ? _seriesColor(
                              spec.series[i],
                              i,
                            ).withValues(alpha: 0.18)
                          : textColor.withValues(alpha: 0.045),
                      borderRadius: BorderRadius.circular(w),
                      border: Border.all(
                        color: _hovered == i
                            ? _seriesColor(spec.series[i], i)
                            : Colors.transparent,
                        width: w * 0.0015,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: w * 0.012,
                          height: w * 0.012,
                          decoration: BoxDecoration(
                            color: _seriesColor(spec.series[i], i),
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: w * 0.006),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: w * 0.16),
                          child: Text(
                            spec.series[i].name.isEmpty
                                ? 'Reeks ${i + 1}'
                                : spec.series[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _applyFont(
                              font,
                              TextStyle(
                                fontSize: w * 0.013,
                                fontWeight: FontWeight.w600,
                                color: textColor.withValues(alpha: 0.82),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pieLegend(ChartSpec spec, Color textColor) {
    final itemCount = math.min(spec.x.length, 18);
    final columns = math.min(itemCount, presentationMode ? 4 : 6);
    final rows = (itemCount / columns).ceil();
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = w * 0.006;
        final itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return SizedBox(
          height: rows * w * 0.03 * _labelScale + (rows - 1) * gap,
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < itemCount; i++)
                MouseRegion(
                  onEnter: (_) => _setHover(i),
                  onExit: (_) => _setHover(null),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: _dimmed(i) ? 0.4 : 1,
                    child: Container(
                      width: itemWidth,
                      height: w * 0.03 * _labelScale,
                      padding: EdgeInsets.symmetric(horizontal: w * 0.008),
                      decoration: BoxDecoration(
                        color: _hovered == i
                            ? _hexColor(
                                chartRowColor(spec, i),
                              ).withValues(alpha: 0.18)
                            : textColor.withValues(alpha: 0.045),
                        borderRadius: BorderRadius.circular(w),
                        border: Border.all(
                          color: _hovered == i
                              ? _hexColor(chartRowColor(spec, i))
                              : Colors.transparent,
                          width: w * 0.0015,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: w * 0.012,
                            height: w * 0.012,
                            decoration: BoxDecoration(
                              color: _hexColor(chartRowColor(spec, i)),
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: w * 0.006),
                          Expanded(
                            child: Text(
                              spec.x[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _applyFont(
                                font,
                                TextStyle(
                                  fontSize: w * 0.013 * _labelScale,
                                  fontWeight: FontWeight.w600,
                                  color: textColor.withValues(alpha: 0.82),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _chart(ChartSpec spec, Color textColor) {
    switch (spec.type) {
      case ChartType.bar:
        return _barChart(spec, textColor);
      case ChartType.stackedBar:
        return _stackedBarChart(spec, textColor);
      case ChartType.line:
        return _lineChart(spec, textColor);
      case ChartType.pie:
        return _pieChart(spec, textColor);
      case ChartType.radar:
        return _radarChart(spec, textColor);
      case ChartType.scatter:
        return _scatterChart(spec, textColor);
    }
  }

  double _maxY(ChartSpec spec) {
    var m = 0.0;
    if (spec.type == ChartType.stackedBar) {
      for (var xi = 0; xi < spec.x.length; xi++) {
        var sum = 0.0;
        for (final s in spec.series) {
          if (xi < s.data.length) sum += s.data[xi];
        }
        if (sum > m) m = sum;
      }
    } else {
      for (final s in spec.series) {
        for (final v in s.data) {
          if (v > m) m = v;
        }
      }
    }
    // Keep any bound line comfortably inside the plot so its label is visible.
    if (spec.supportsBounds) {
      for (final b in [spec.minBound, spec.maxBound]) {
        if (b != null && b > m) m = b;
      }
    }
    return m <= 0 ? 1 : m * 1.15;
  }

  double _minY(ChartSpec spec) {
    var m = 0.0;
    for (final s in spec.series) {
      for (final v in s.data) {
        if (v < m) m = v;
      }
    }
    if (spec.supportsBounds) {
      for (final b in [spec.minBound, spec.maxBound]) {
        if (b != null && b < m) m = b;
      }
    }
    return m >= 0 ? 0 : m * 1.15;
  }

  /// Optional min/max threshold lines drawn across the plot (bar/line only).
  ExtraLinesData _boundLines(ChartSpec spec) {
    if (!spec.supportsBoundLines) return const ExtraLinesData();
    final dash = [
      (w * 0.018).round().clamp(4, 14),
      (w * 0.01).round().clamp(3, 9),
    ];
    HorizontalLine line(double value, Color color, String prefix) =>
        HorizontalLine(
          y: value,
          color: color,
          strokeWidth: w * 0.0035,
          dashArray: dash,
          label: HorizontalLineLabel(
            show: true,
            alignment: Alignment.topRight,
            padding: EdgeInsets.only(right: w * 0.006, bottom: w * 0.002),
            style: _applyFont(
              font,
              TextStyle(
                fontSize: w * 0.0115 * _labelScale,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            labelResolver: (_) => '$prefix ${_fmtNum(value)}',
          ),
        );
    return ExtraLinesData(
      horizontalLines: [
        if (spec.minBound != null)
          line(spec.minBound!, const Color(0xFFF59E0B), 'min'),
        if (spec.maxBound != null)
          line(spec.maxBound!, const Color(0xFFEF4444), 'max'),
      ],
    );
  }

  FlTitlesData _titles(ChartSpec spec, Color textColor, {bool bars = false}) {
    final style = _applyFont(
      font,
      TextStyle(
        fontSize: w * 0.0115 * _labelScale,
        color: textColor.withValues(alpha: 0.88),
        fontWeight: presentationMode ? FontWeight.w600 : FontWeight.normal,
      ),
    );
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: w * 0.05 * _labelScale,
          getTitlesWidget: (value, meta) => Text(
            _fmtNum(value),
            style: style.copyWith(fontSize: w * 0.0105 * _labelScale),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: 1,
          reservedSize: w * 0.044 * _labelScale,
          getTitlesWidget: (value, meta) {
            final i = value.round();
            final n = spec.x.length;
            if (i < 0 || i >= n) return const SizedBox.shrink();
            // Show as many labels as fit without colliding: keep at least
            // [minSlot] of horizontal room per label, then thin them out
            // evenly based on the actual pixel spacing between points. Line
            // charts spread n points over n-1 intervals; bar groups are laid
            // out spaceEvenly, which puts their centres (axis + groupWidth) /
            // (n + 1) apart.
            final spacing = bars
                ? (meta.parentAxisSize + _barGroupWidth(spec)) / (n + 1)
                : (n > 1 ? meta.parentAxisSize / (n - 1) : meta.parentAxisSize);
            final minSlot = w * 0.085 * _labelScale;
            final step = math.max(1, (minSlot / spacing).ceil());
            final lastMultiple = ((n - 1) ~/ step) * step;
            final lastGap = n - 1 - lastMultiple;
            final showLast = i == n - 1 && lastGap > step / 2;
            if (i % step != 0 && !showLast) return const SizedBox.shrink();
            // The extra end label can sit closer than a full step to its
            // neighbour; shrink both of their slots to the real gap so they
            // never run through each other.
            var slotSteps = step.toDouble();
            if (showLast || (i == lastMultiple && lastGap > step / 2)) {
              slotSteps = math.min(slotSteps, lastGap.toDouble());
            }
            final slot = (slotSteps * spacing - w * 0.012).clamp(
              w * 0.04,
              w * 0.16,
            );
            return Padding(
              padding: EdgeInsets.only(top: w * 0.008),
              child: SizedBox(
                width: slot,
                child: Text(
                  spec.x[i],
                  style: style,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _fmtNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  FlGridData _grid(Color textColor) => FlGridData(
    show: true,
    drawVerticalLine: false,
    getDrawingHorizontalLine: (v) =>
        FlLine(color: textColor.withValues(alpha: 0.12), strokeWidth: 1),
  );

  /// Width of one bar rod, shared by the chart and the axis-label spacing.
  double _barRodWidth(ChartSpec spec) =>
      (w * 0.032 / spec.series.length).clamp(w * 0.008, w * 0.022);

  /// Total width of one bar group: its rods plus fl_chart's default 2px
  /// spacing between rods within a group.
  double _barGroupWidth(ChartSpec spec) {
    final rods = math.max(1, spec.series.length);
    return rods * _barRodWidth(spec) + (rods - 1) * 2;
  }

  Widget _barChart(ChartSpec spec, Color textColor) {
    final groups = <BarChartGroupData>[];
    for (var xi = 0; xi < spec.x.length; xi++) {
      groups.add(
        BarChartGroupData(
          x: xi,
          barRods: [
            for (var si = 0; si < spec.series.length; si++)
              if (xi < spec.series[si].data.length)
                BarChartRodData(
                  toY: spec.series[si].data[xi],
                  color: _seriesDisplayColor(spec.series[si], si),
                  width: _barRodWidth(spec),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(w * 0.006),
                  ),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: _maxY(spec),
                    color: textColor.withValues(alpha: 0.025),
                  ),
                ),
          ],
        ),
      );
    }
    return BarChart(
      BarChartData(
        minY: _minY(spec),
        maxY: _maxY(spec),
        // The axis-label spacing in _titles assumes this layout; keep it
        // explicit rather than relying on fl_chart's default.
        alignment: BarChartAlignment.spaceEvenly,
        barGroups: groups,
        titlesData: _titles(spec, textColor, bars: true),
        gridData: _grid(textColor),
        borderData: FlBorderData(show: false),
        extraLinesData: _boundLines(spec),
        barTouchData: BarTouchData(
          enabled: true,
          mouseCursorResolver: (event, response) => response?.spot == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          touchTooltipData: BarTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => const Color(0xFF0F172A),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final label = group.x >= 0 && group.x < spec.x.length
                  ? spec.x[group.x]
                  : '';
              final series = rodIndex < spec.series.length
                  ? spec.series[rodIndex].name
                  : '';
              return BarTooltipItem(
                '$label\n${series.isEmpty ? 'Reeks ${rodIndex + 1}' : series}: ${_fmtNum(rod.toY)}',
                _tooltipStyle(),
              );
            },
          ),
        ),
      ),
      duration: Duration.zero,
    );
  }

  Widget _stackedBarChart(ChartSpec spec, Color textColor) {
    final groups = <BarChartGroupData>[];
    for (var xi = 0; xi < spec.x.length; xi++) {
      var bottom = 0.0;
      final rods = <BarChartRodData>[];
      for (var si = 0; si < spec.series.length; si++) {
        if (xi >= spec.series[si].data.length) continue;
        final value = spec.series[si].data[xi];
        rods.add(
          BarChartRodData(
            fromY: bottom,
            toY: bottom + value,
            color: _seriesDisplayColor(spec.series[si], si),
            width: _barRodWidth(spec),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(w * 0.006),
            ),
          ),
        );
        bottom += value;
      }
      groups.add(BarChartGroupData(x: xi, barRods: rods));
    }
    return BarChart(
      BarChartData(
        minY: _minY(spec),
        maxY: _maxY(spec),
        alignment: BarChartAlignment.spaceEvenly,
        barGroups: groups,
        titlesData: _titles(spec, textColor, bars: true),
        gridData: _grid(textColor),
        borderData: FlBorderData(show: false),
        extraLinesData: _boundLines(spec),
        barTouchData: BarTouchData(enabled: false),
      ),
      duration: Duration.zero,
    );
  }

  Widget _scatterChart(ChartSpec spec, Color textColor) {
    final spots = <ScatterSpot>[];
    for (var si = 0; si < spec.series.length; si++) {
      for (var xi = 0; xi < spec.series[si].data.length; xi++) {
        spots.add(
          ScatterSpot(
            xi.toDouble(),
            spec.series[si].data[xi],
            dotPainter: FlDotCirclePainter(
              radius: w * 0.007,
              color: _seriesDisplayColor(spec.series[si], si),
              strokeWidth: w * 0.002,
              strokeColor: _hexColor(profile.slideBackgroundColor),
            ),
          ),
        );
      }
    }
    return ScatterChart(
      ScatterChartData(
        minY: _minY(spec),
        maxY: _maxY(spec),
        scatterSpots: spots,
        titlesData: _titles(spec, textColor),
        gridData: _grid(textColor),
        borderData: FlBorderData(show: false),
        scatterTouchData: ScatterTouchData(enabled: false),
      ),
      duration: Duration.zero,
    );
  }

  Widget _lineChart(ChartSpec spec, Color textColor) {
    final bars = <LineChartBarData>[];
    for (var si = 0; si < spec.series.length; si++) {
      bars.add(
        LineChartBarData(
          spots: [
            for (var xi = 0; xi < spec.series[si].data.length; xi++)
              FlSpot(xi.toDouble(), spec.series[si].data[xi]),
          ],
          color: _seriesDisplayColor(spec.series[si], si),
          barWidth: w * (_hovered == si ? 0.0065 : 0.0045),
          isCurved: true,
          curveSmoothness: 0.22,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: w * 0.005,
              color: _seriesDisplayColor(spec.series[si], si),
              strokeWidth: w * 0.0025,
              strokeColor: _hexColor(profile.slideBackgroundColor),
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            color: _seriesDisplayColor(
              spec.series[si],
              si,
            ).withValues(alpha: spec.series.length == 1 ? 0.14 : 0.05),
          ),
        ),
      );
    }
    return LineChart(
      LineChartData(
        minY: _minY(spec),
        maxY: _maxY(spec),
        lineBarsData: bars,
        titlesData: _titles(spec, textColor),
        gridData: _grid(textColor),
        borderData: FlBorderData(show: false),
        extraLinesData: _boundLines(spec),
        lineTouchData: LineTouchData(
          enabled: true,
          // Measure proximity to the actual dot (x *and* y), not just the
          // column, so the tooltip belongs to the point under the cursor.
          distanceCalculator: (touch, spot) => (touch - spot).distance,
          touchSpotThreshold: (w * 0.02).clamp(8.0, 24.0).toDouble(),
          mouseCursorResolver: (event, response) =>
              response?.lineBarSpots?.isEmpty ?? true
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => const Color(0xFF0F172A),
            // Show every dot near the cursor. When several dots sit on (almost)
            // the same spot they all appear; the font shrinks to keep them
            // readable when stacked.
            getTooltipItems: (spots) {
              final style = _lineTooltipStyle(spots.length);
              return [
                for (final spot in spots)
                  LineTooltipItem(
                    '${spot.spotIndex < spec.x.length ? spec.x[spot.spotIndex] : ''}\n'
                    '${spot.barIndex < spec.series.length && spec.series[spot.barIndex].name.isNotEmpty ? spec.series[spot.barIndex].name : 'Reeks ${spot.barIndex + 1}'}: ${_fmtNum(spot.y)}',
                    style,
                  ),
              ];
            },
          ),
        ),
      ),
      duration: Duration.zero,
    );
  }

  Widget _pieChart(ChartSpec spec, Color textColor) {
    if (spec.series.isEmpty || spec.x.isEmpty) {
      return _placeholderText('—');
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final visibleSeries = math.min(spec.series.length, 2);
        final columns = visibleSeries;
        const rows = 1;
        final tileHeight = constraints.maxHeight / rows;
        final tileWidth = constraints.maxWidth / columns;
        return GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: tileWidth / tileHeight,
            crossAxisSpacing: w * 0.012,
            mainAxisSpacing: w * 0.008,
          ),
          itemCount: visibleSeries,
          itemBuilder: (context, si) {
            final series = spec.series[si];
            final values = [
              for (var xi = 0; xi < spec.x.length; xi++)
                xi < series.data.length && series.data[xi] > 0
                    ? series.data[xi]
                    : 0.0,
            ];
            final total = values.fold<double>(0, (a, b) => a + b);
            return Row(
              children: [
                Expanded(
                  flex: 4,
                  child: total <= 0
                      ? Center(
                          child: Text(
                            '0',
                            style: _applyFont(
                              font,
                              TextStyle(
                                fontSize: w * 0.025,
                                color: textColor.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, pieConstraints) {
                            final available =
                                pieConstraints.biggest.shortestSide;
                            final radius = (available * 0.42).clamp(
                              w * 0.018,
                              w * 0.075,
                            );
                            return ClipRect(
                              child: _HoverPieChart(
                                externalHover: _hovered,
                                values: values,
                                labels: spec.x,
                                colors: [
                                  for (var xi = 0; xi < values.length; xi++)
                                    _hexColor(chartRowColor(spec, xi)),
                                ],
                                radius: radius,
                                centerSpaceRadius: radius * 0.42,
                                sectionSpace: w * 0.002,
                                titleStyle: _applyFont(
                                  font,
                                  TextStyle(
                                    fontSize: (radius * 0.18).clamp(
                                      w * 0.009,
                                      w * 0.013,
                                    ),
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                tooltipStyle: _tooltipStyle(),
                              ),
                            );
                          },
                        ),
                ),
                SizedBox(width: w * 0.008),
                Expanded(
                  flex: 2,
                  child: Text(
                    series.name.isEmpty ? 'Reeks ${si + 1}' : series.name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: _applyFont(
                      font,
                      TextStyle(
                        fontSize: w * 0.015,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

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
                                child: RadarChart(
                                  RadarChartData(
                                    dataSets: [
                                      for (
                                        var si = 0;
                                        si < spec.series.length;
                                        si++
                                      )
                                        RadarDataSet(
                                          dataEntries: [
                                            for (
                                              var xi = 0;
                                              xi < spec.x.length;
                                              xi++
                                            )
                                              RadarEntry(
                                                value:
                                                    xi <
                                                        spec
                                                            .series[si]
                                                            .data
                                                            .length
                                                    ? spec.series[si].data[xi]
                                                    : 0,
                                              ),
                                          ],
                                          fillColor:
                                              _seriesDisplayColor(
                                                spec.series[si],
                                                si,
                                              ).withValues(
                                                alpha: _dimmed(si)
                                                    ? 0.04
                                                    : 0.16,
                                              ),
                                          borderColor: _seriesDisplayColor(
                                            spec.series[si],
                                            si,
                                          ),
                                          borderWidth:
                                              w *
                                              (_hovered == si
                                                  ? 0.0055
                                                  : 0.0035),
                                          entryRadius:
                                              w *
                                              (_hovered == si ? 0.006 : 0.004),
                                        ),
                                      // Invisible anchor pinning the scale to [lo, hi]
                                      // so the rings represent a fixed scale.
                                      RadarDataSet(
                                        dataEntries: [
                                          for (
                                            var xi = 0;
                                            xi < spec.x.length;
                                            xi++
                                          )
                                            RadarEntry(
                                              value: xi == 0
                                                  ? scale.hi
                                                  : scale.lo,
                                            ),
                                        ],
                                        fillColor: Colors.transparent,
                                        borderColor: Colors.transparent,
                                        borderWidth: 0,
                                        entryRadius: 0,
                                      ),
                                    ],
                                    radarShape: RadarShape.polygon,
                                    radarBackgroundColor: Colors.transparent,
                                    radarBorderData: BorderSide(
                                      color: grid,
                                      width: 1,
                                    ),
                                    gridBorderData: BorderSide(
                                      color: grid,
                                      width: 1,
                                    ),
                                    tickBorderData: BorderSide(
                                      color: grid,
                                      width: 1,
                                    ),
                                    tickCount: scale.ticks,
                                    isMinValueAtCenter: true,
                                    // The scale now lives in a side legend, so hide
                                    // fl_chart's in-chart ring numbers.
                                    ticksTextStyle: const TextStyle(
                                      color: Colors.transparent,
                                      fontSize: 0.001,
                                    ),
                                    titlePositionPercentageOffset: 0,
                                    getTitle: (index, angle) => RadarChartTitle(
                                      text: index < spec.x.length
                                          ? spec.x[index]
                                          : '',
                                    ),
                                    // Labels are rendered as constrained widgets
                                    // around the chart so long text can wrap.
                                    titleTextStyle: const TextStyle(
                                      color: Colors.transparent,
                                      fontSize: 0.001,
                                    ),
                                    radarTouchData: RadarTouchData(
                                      enabled: true,
                                      touchSpotThreshold: (w * 0.02)
                                          .clamp(8.0, 24.0)
                                          .toDouble(),
                                      mouseCursorResolver: (event, response) =>
                                          _radarSpotFrom(response, spec) == null
                                          ? SystemMouseCursors.basic
                                          : SystemMouseCursors.click,
                                      touchCallback: (event, response) {
                                        final next =
                                            event.isInterestedForInteractions
                                            ? _radarSpotFrom(response, spec)
                                            : null;
                                        if (next != _radarTouch) {
                                          setState(() => _radarTouch = next);
                                        }
                                      },
                                    ),
                                  ),
                                  duration: Duration.zero,
                                ),
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
  static bool _radarLabelBeside(Offset direction) => direction.dx.abs() > 0.35;

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

  TextStyle _tooltipStyle() => _applyFont(
    font,
    TextStyle(
      color: Colors.white,
      fontSize: (w * 0.013 * _labelScale).clamp(11, 18),
      height: 1.25,
      fontWeight: FontWeight.w700,
    ),
  );

  /// Tooltip style for line charts. Each touched dot adds two lines, so when
  /// several dots overlap the font shrinks a step to keep the stack readable.
  TextStyle _lineTooltipStyle(int count) {
    final base = (w * 0.013 * _labelScale).clamp(11.0, 18.0);
    final shrink = (1 - (count - 2) * 0.13).clamp(0.6, 1.0);
    return _applyFont(
      font,
      TextStyle(
        color: Colors.white,
        fontSize: (base * shrink).clamp(8.0, 18.0),
        height: 1.2,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _placeholder(BuildContext context) =>
      _placeholderText(context.l10n.d('Geen grafiekgegevens'));

  Widget _placeholderText(String text) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.bar_chart_outlined,
          size: w * 0.08,
          color: const Color(0xFF94A3B8),
        ),
        SizedBox(height: w * 0.01),
        Text(
          text,
          style: TextStyle(color: const Color(0xFF94A3B8), fontSize: w * 0.02),
        ),
      ],
    ),
  );
}

class _HoverPieChart extends StatefulWidget {
  final List<double> values;
  final List<String> labels;
  final List<Color> colors;
  final double radius;
  final double centerSpaceRadius;
  final double sectionSpace;
  final TextStyle titleStyle;
  final TextStyle tooltipStyle;

  /// Slice index highlighted from outside (e.g. hovering the legend), combined
  /// with this chart's own touch hover.
  final int? externalHover;

  const _HoverPieChart({
    required this.values,
    required this.labels,
    required this.colors,
    required this.radius,
    required this.centerSpaceRadius,
    required this.sectionSpace,
    required this.titleStyle,
    required this.tooltipStyle,
    this.externalHover,
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
                    title: widget.values[i] / total >= 0.08
                        ? '${(widget.values[i] / total * 100).round()}%'
                        : '',
                    radius: widget.radius * (hovered == i ? 1.08 : 1),
                    titleStyle: widget.titleStyle,
                  ),
              ],
              sectionsSpace: widget.sectionSpace,
              centerSpaceRadius: widget.centerSpaceRadius,
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
                  if (next != _hovered) setState(() => _hovered = next);
                },
              ),
            ),
            duration: Duration.zero,
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
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(color: Color(0x33000000), blurRadius: 6),
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

String _formatChartValue(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);
