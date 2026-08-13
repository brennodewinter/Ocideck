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
  final ImprovementY01Metric y01;

  const _ChartPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
    required this.presentationMode,
    this.y01 = ImprovementY01Metric.empty,
  });

  @override
  State<_ChartPreview> createState() => _ChartPreviewState();
}

class _ChartPreviewState extends State<_ChartPreview>
    with SingleTickerProviderStateMixin {
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

  /// Hover-tooltip text for the hand-drawn charts (horizontal bar, horizontal
  /// stacked bar, bullet) and the combo overlay — they carry no fl_chart touch
  /// layer of their own, so a [MouseRegion] sets this and [_withCellTooltip]
  /// floats it. Null when nothing is hovered. Composed from data (label + value)
  /// so it introduces no new localised words.
  String? _cellTooltip;

  /// This chart's own pointer hover, normalised to a [ChartHover] so the shared
  /// [_hoverController] can forward it to the other screen (presenter ↔ beamer,
  /// #930-style). Null when the pointer is off the chart.
  ChartHover? _localHover;

  /// The shared hover bus for this surface, or null in the editor preview /
  /// thumbnails / export (no [ChartHoverScope] above → no mirroring). Resolved
  /// in [didChangeDependencies]; we listen so an external hover from the other
  /// screen repaints this chart.
  ChartHoverController? _hoverController;

  /// Parsed chart spec, cached so the per-pointer-move hover rebuilds don't
  /// re-parse the chart JSON every frame. Re-parsed only when the slide's chart
  /// markdown actually changes.
  late ChartSpec _spec;

  /// Entrance growth: plotted values multiply by [_grow] (0 then 1) while the
  /// axis (minY/maxY, radar anchor) stays fixed. The 0 -> 1 swap is tweened by
  /// fl_chart itself over [_chartAnimDuration] — far cheaper than rebuilding the
  /// whole chart every frame, which (with several previews on screen at once in
  /// presentation) made navigation feel sluggish.
  double _grow = 1;

  /// fl_chart's tween duration: the activation duration during the entrance,
  /// [Duration.zero] once grown so hover/tooltip rebuilds never re-animate.
  Duration _chartAnimDuration = Duration.zero;

  /// Pure timer for the entrance: it just times when to freeze the duration and
  /// drives the pie's scale/fade (the only per-frame work, and only one cheap
  /// Transform). Disposed on unmount, so it never leaks a pending timer.
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _spec = ChartSpec.parse(widget.slide.customMarkdown);
    _entrance = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _chartAnimDuration = Duration.zero);
        }
      });
    _maybeAnimateIn();
  }

  @override
  void didUpdateWidget(_ChartPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final markdownChanged =
        widget.slide.customMarkdown != oldWidget.slide.customMarkdown;
    if (markdownChanged) {
      _spec = ChartSpec.parse(widget.slide.customMarkdown);
    }
    // The preview widget is reused across slides (no key in the presenter), so
    // re-run the entrance whenever this position now shows a different slide or
    // the inherited theme duration changed — not only on a markdown edit. Two
    // adjacent chart slides with identical chart markdown otherwise wouldn't
    // animate, and a live theme-duration change wouldn't take effect (parity
    // with cockpit_preview / timeline_preview).
    if (markdownChanged ||
        widget.slide.id != oldWidget.slide.id ||
        widget.profile.animationDurationMs !=
            oldWidget.profile.animationDurationMs) {
      _maybeAnimateIn();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Join (or leave) the presenter↔beamer hover mirror. The controller lives in
    // an inherited [ChartHoverScope]; only the current-slide canvas and the
    // beamer provide one, so elsewhere this stays null and the chart is private.
    final controller = ChartHoverScope.of(context);
    if (controller != _hoverController) {
      _hoverController?.removeListener(_onExternalHover);
      _hoverController = controller;
      _hoverController?.addListener(_onExternalHover);
    }
  }

  /// The other screen moved its pointer: repaint so this chart shows the mirrored
  /// highlight/tooltip. Only meaningful while this chart isn't hovered locally —
  /// a local hover wins in [_effectiveHoverSeries]/[_effectivePieHover] and in
  /// [_withMirroredTooltip].
  void _onExternalHover() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _hoverController?.removeListener(_onExternalHover);
    _entrance.dispose();
    super.dispose();
  }

  /// Charts draw themselves in (values grow from the baseline) when a chart
  /// slide is shown in presentation mode, over the theme's shared activation
  /// duration. In the editor/thumbnails values are final and nothing animates.
  void _maybeAnimateIn() {
    _entrance.stop();
    if (!presentationMode || !_spec.hasInlineData || !_spec.animateOnEnter) {
      _grow = 1;
      _chartAnimDuration = Duration.zero;
      _entrance.value = 1;
      return;
    }
    // null override = inherit the theme's shared activation duration.
    final ms = clampThemeAnimationDuration(
      _spec.animationDurationMs ?? profile.animationDurationMs,
    );
    _grow = 0;
    _chartAnimDuration = Duration(milliseconds: ms);
    _entrance.duration = Duration(milliseconds: ms);
    // Reset synchronously (the controller is reused across slides) so the pie's
    // scale/fade starts collapsed on this very frame; otherwise a reused
    // controller still reads value 1 from the previous slide and the pie flashes
    // full-size for one frame before snapping small.
    _entrance.value = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Swap to the real values once: fl_chart tweens 0 -> value internally.
      setState(() => _grow = 1);
      _entrance.forward(from: 0);
    });
  }

  /// Pie entrance: a scale-up + fade (a pie can't grow from a zero total the
  /// way a bar grows from a zero height). Only this small Transform rebuilds per
  /// frame — the pie itself (`child`) is built once.
  Widget _pieEntrance(Widget pie) {
    return AnimatedBuilder(
      animation: _entrance,
      child: pie,
      builder: (context, child) {
        if (_chartAnimDuration == Duration.zero) return child!;
        final t = Curves.easeOutCubic.transform(_entrance.value);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
        );
      },
    );
  }

  /// Hovering a series legend chip: dim the other series locally, and report the
  /// series so the other screen mirrors the same emphasis.
  void _hoverSeriesLegend(int? index) {
    final next = index == null ? null : ChartHover(series: index);
    if (_hovered == index && _localHover == next) return;
    setState(() {
      _hovered = index;
      _localHover = next;
    });
    _hoverController?.setLocal(next);
  }

  /// Hovering a pie/donut legend chip: [index] is a slice (category), not a
  /// series — mirror it as such so the other screen enlarges the same slice.
  void _hoverSliceLegend(int? index) {
    final next = index == null ? null : ChartHover(category: index);
    if (_hovered == index && _localHover == next) return;
    setState(() {
      _hovered = index;
      _localHover = next;
    });
    _hoverController?.setLocal(next);
  }

  /// Report a plot-level hover (a bar/point/slice under the cursor) to the shared
  /// bus without touching [_hovered] — fl_chart and [_HoverPieChart] already draw
  /// the local tooltip; this only feeds the mirror to the other screen.
  void _setLocalHover(ChartHover? hover) {
    final next = (hover?.isEmpty ?? true) ? null : hover;
    if (_localHover == next) return;
    setState(() => _localHover = next);
    _hoverController?.setLocal(next);
  }

  /// Series index to emphasise (dim the rest / thicken the line): a local legend
  /// hover, or the series mirrored from the other screen. A local *plot* hover
  /// deliberately does not dim — matching what a lone pointer shows here.
  int? get _effectiveHoverSeries =>
      _hovered ?? _hoverController?.external?.series;

  /// Slice index to enlarge in a pie/donut: a local legend/slice hover, or the
  /// slice mirrored from the other screen.
  int? get _effectivePieHover =>
      _hovered ?? _hoverController?.external?.category;

  /// When the other screen is hovering this chart (and the local pointer isn't),
  /// float the same label/value tooltip here. Pie/donut mirror through
  /// [_HoverPieChart.externalHover], which draws its own tooltip, so they opt
  /// out. The text is composed from the data — no new localised words.
  Widget _withMirroredTooltip(
    BuildContext context,
    ChartSpec spec,
    Widget chart,
  ) {
    if (_localHover != null || spec.isPieLike) return chart;
    final external = _hoverController?.external;
    if (external == null) return chart;
    final text = composedChartHoverText(context, spec, external);
    if (text == null) return chart;
    return _withCellTooltip(
      chart: chart,
      tooltip: text,
      w: w,
      style: _tooltipStyle(),
    );
  }

  /// Set the hand-drawn charts' floating hover tooltip (see [_cellTooltip]).
  /// The overlay widgets themselves are top-level helpers in
  /// chart_preview_touch.dart, to keep this class off the size ratchet.
  void _setCellTooltip(String? text) {
    if (_cellTooltip != text) setState(() => _cellTooltip = text);
  }

  /// Trigger a rebuild from the chart-builder extensions in the `parts/` files.
  /// They can't call the `@protected` [setState] directly (it is only callable
  /// from instance members of a State subclass), so they route through this.
  void _rebuild(VoidCallback fn) => setState(fn);

  /// True when another legend entry is hovered, so [index] should fade back.
  /// Honours the hover mirrored from the other screen too, so the audience sees
  /// the same series stand out that the presenter is pointing at.
  bool _dimmed(int index) {
    final active = _effectiveHoverSeries;
    return active != null && active != index;
  }

  /// Series colour with legend-hover feedback: non-hovered series fade out so
  /// the hovered one stands out in the plot.
  Color _seriesDisplayColor(ChartSeries series, int i) {
    final base = _seriesColor(series, i);
    return _dimmed(i) ? base.withValues(alpha: 0.2) : base;
  }

  double get _labelScale => presentationMode ? 1.12 : 1;

  Color _seriesColor(ChartSeries series, int i) {
    if (series.color == null && i == 0) {
      return AppTheme.parseHexColor(profile.accentColor);
    }
    return AppTheme.parseHexColor(chartSeriesColor(series, i));
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
      ChartType.area => l10n.d('Vlak'),
      ChartType.pie => l10n.d('Cirkel'),
      ChartType.donut => l10n.d('Donut'),
      ChartType.radar => l10n.d('Spider'),
      ChartType.scatter => l10n.d('Spreiding'),
      ChartType.horizontalBar => l10n.d('Horizontale staaf'),
      ChartType.combo => l10n.d('Combo'),
      ChartType.waterfall => l10n.d('Waterval'),
      ChartType.heatmap => l10n.d('Heatmap'),
      ChartType.horizontalStackedBar => l10n.d('Horizontale gestapelde staaf'),
      ChartType.bullet => l10n.d('Norm en prestatie'),
      ChartType.controlChart => l10n.d('Regelkaart'),
      ChartType.histogram => l10n.d('Histogram'),
      ChartType.pareto => l10n.d('Pareto'),
      ChartType.runChart => l10n.d('Run chart'),
      ChartType.boxPlot => l10n.d('Boxplot'),
      ChartType.probabilityPlot => l10n.d('Probability plot'),
      ChartType.mainEffects => l10n.d('Hoofdeffecten'),
      ChartType.interaction => l10n.d('Interactie'),
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
          : decodeNamedHtmlEntities(series.name);
      final values = [
        for (var xi = 0; xi < spec.x.length && xi < series.data.length; xi++)
          '${decodeNamedHtmlEntities(spec.x[xi])} ${_fmtNum(series.data[xi])}',
      ];
      buffer.write('. $name: ${values.join(', ')}');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    final horizontalPad = w * 0.05;
    final verticalPad = w * 0.018;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final textColor = AppTheme.parseHexColor(profile.textColor);

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
      color: AppTheme.parseHexColor(profile.slideBackgroundColor),
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
                    color: AppTheme.parseHexColor(profile.textColor),
                  ),
                ),
                linkColor: AppTheme.parseHexColor(profile.accentColor),
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
                          ? _withMirroredTooltip(
                              context,
                              spec,
                              _chart(spec, textColor),
                            )
                          : _placeholder(context),
                    ),
                    if (_legendWidget(spec, textColor) case final legend?) ...[
                      SizedBox(height: w * 0.006),
                      legend,
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

  /// The legend under the plot, or null for chart types that carry their key
  /// elsewhere: pie/donut list their slices, heatmap shows a colour scale
  /// inside the plot, and a waterfall reads a single series so a legend adds
  /// nothing.
  Widget? _legendWidget(ChartSpec spec, Color textColor) {
    if (!spec.hasInlineData || spec.series.isEmpty) return null;
    if (spec.type == ChartType.heatmap || spec.type == ChartType.waterfall) {
      return null;
    }
    if (spec.isPieLike) return _pieLegend(spec, textColor);
    return _legend(spec, textColor);
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
                onEnter: (_) => _hoverSeriesLegend(i),
                onExit: (_) => _hoverSeriesLegend(null),
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
                                ? '${context.l10n.d('Reeks')} ${i + 1}'
                                : decodeNamedHtmlEntities(spec.series[i].name),
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
                  onEnter: (_) => _hoverSliceLegend(i),
                  onExit: (_) => _hoverSliceLegend(null),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: _dimmed(i) ? 0.4 : 1,
                    child: Container(
                      width: itemWidth,
                      height: w * 0.03 * _labelScale,
                      padding: EdgeInsets.symmetric(horizontal: w * 0.008),
                      decoration: BoxDecoration(
                        color: _hovered == i
                            ? AppTheme.parseHexColor(
                                chartRowColor(spec, i),
                              ).withValues(alpha: 0.18)
                            : textColor.withValues(alpha: 0.045),
                        borderRadius: BorderRadius.circular(w),
                        border: Border.all(
                          color: _hovered == i
                              ? AppTheme.parseHexColor(chartRowColor(spec, i))
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
                              color: AppTheme.parseHexColor(
                                chartRowColor(spec, i),
                              ),
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: w * 0.006),
                          Expanded(
                            child: Text(
                              decodeNamedHtmlEntities(spec.x[i]),
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
      case ChartType.area:
        return _lineChart(spec, textColor, area: true);
      case ChartType.pie:
        return _pieEntrance(_pieChart(spec, textColor));
      case ChartType.donut:
        return _pieEntrance(_pieChart(spec, textColor, donut: true));
      case ChartType.radar:
        return _radarChart(spec, textColor);
      case ChartType.scatter:
        return _scatterChart(spec, textColor);
      case ChartType.horizontalBar:
        return _horizontalBarChart(spec, textColor);
      case ChartType.combo:
        return _comboChart(spec, textColor);
      case ChartType.waterfall:
        return _waterfallChart(spec, textColor);
      case ChartType.heatmap:
        return _heatmapChart(spec, textColor);
      case ChartType.horizontalStackedBar:
        return _horizontalStackedBarChart(spec, textColor);
      case ChartType.bullet:
        return _bulletChart(spec, textColor);
      case ChartType.controlChart:
        return _controlChart(spec, textColor);
      case ChartType.histogram:
        return _histogramChart(spec, textColor);
      case ChartType.pareto:
        return _paretoChart(spec, textColor);
      case ChartType.runChart:
        return _runChart(spec, textColor);
      case ChartType.boxPlot:
        return _boxPlotChart(spec, textColor);
      case ChartType.probabilityPlot:
        return _probabilityPlotChart(spec, textColor);
      case ChartType.mainEffects:
        return _mainEffectsChart(spec, textColor);
      case ChartType.interaction:
        return _interactionChart(spec, textColor);
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
          line(spec.minBound!, AppTheme.amber500, 'min'),
        if (spec.maxBound != null)
          line(spec.maxBound!, AppTheme.danger500, 'max'),
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
                  decodeNamedHtmlEntities(spec.x[i]),
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
          color: AppTheme.slideInkFaint,
        ),
        SizedBox(height: w * 0.01),
        Text(
          text,
          style: TextStyle(color: AppTheme.slideInkFaint, fontSize: w * 0.02),
        ),
      ],
    ),
  );
}

String _formatChartValue(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);
