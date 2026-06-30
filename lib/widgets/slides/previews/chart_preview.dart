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

  /// Trigger a rebuild from the chart-builder extensions in the `parts/` files.
  /// They can't call the `@protected` [setState] directly (it is only callable
  /// from instance members of a State subclass), so they route through this.
  void _rebuild(VoidCallback fn) => setState(fn);

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
