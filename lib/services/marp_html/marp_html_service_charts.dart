// Part of the marp_html_service library — see ../marp_html_service.dart.
// Split out for navigability (chart SVG rendering); all imports live in the main
// library file. These were private `static` MarpHtmlService helpers; as
// top-level private functions they share the library and are called by
// bare name from the service's public render methods.
part of '../marp_html_service.dart';

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _color(ChartSpec spec, int i, ThemeProfile? theme) {
  final series = spec.series[i];
  if (series.color == null && i == 0 && theme != null) {
    return theme.accentColor;
  }
  return chartSeriesColor(series, i);
}

String _chartSvg(
  ChartSpec spec,
  ThemeProfile? theme, {
  ImprovementY01Metric y01 = ImprovementY01Metric.empty,
  String? background,
}) {
  if (!spec.hasInlineData) {
    return '<svg viewBox="0 0 800 450" xmlns="http://www.w3.org/2000/svg"></svg>';
  }
  // The chart sits on the slide background when exported, but on the app's card
  // in the document view — [background] lets that caller say where it actually
  // lands. The title and legend take the deck's text colour only when it stays
  // legible there; on a dark ground a dark theme colour flips to a readable ink.
  final ground = background ?? theme?.slideBackgroundColor ?? '#FFFFFF';
  final textColor = readableChartInk(theme?.textColor ?? '#111827', ground);
  final b = StringBuffer()
    ..write(
      '<svg viewBox="0 0 800 450" xmlns="http://www.w3.org/2000/svg" '
      'font-family="inherit" width="100%">',
    );
  if (spec.title.isNotEmpty) {
    final title = spec.title.length > 52
        ? '${spec.title.substring(0, 51)}…'
        : spec.title;
    // Plain bold title in the slide's text colour, matching every other
    // slide type instead of a boxed band.
    b.write(
      '<text x="40" y="40" font-size="26" font-weight="bold" '
      'fill="$textColor">${_esc(title)}</text>',
    );
  }
  final plotTop = spec.title.isNotEmpty ? 60.0 : 20.0;
  switch (spec.type) {
    case ChartType.bar:
      _barSvg(b, spec, plotTop, theme);
    case ChartType.stackedBar:
      _stackedBarSvg(b, spec, plotTop, theme);
    case ChartType.line:
      _lineSvg(b, spec, plotTop, theme);
    case ChartType.area:
      _lineSvg(b, spec, plotTop, theme, area: true);
    case ChartType.pie:
      final legendRows = (spec.x.length / 6).ceil().clamp(1, 3);
      _pieSvg(b, spec, plotTop, theme, bottom: 398 - (legendRows - 1) * 28);
    case ChartType.donut:
      final legendRows = (spec.x.length / 6).ceil().clamp(1, 3);
      _pieSvg(
        b,
        spec,
        plotTop,
        theme,
        bottom: 398 - (legendRows - 1) * 28,
        donut: true,
      );
    case ChartType.radar:
      _radarSvg(b, spec, plotTop, theme, textColor);
    case ChartType.scatter:
      _scatterSvg(b, spec, plotTop, theme);
    case ChartType.horizontalBar:
      _horizontalBarSvg(b, spec, plotTop, theme);
    case ChartType.horizontalStackedBar:
      _horizontalStackedBarSvg(b, spec, plotTop, theme);
    case ChartType.bullet:
      _bulletSvg(b, spec, plotTop, theme);
    case ChartType.combo:
      _comboSvg(b, spec, plotTop, theme);
    case ChartType.waterfall:
      _waterfallSvg(b, spec, plotTop, theme);
    case ChartType.heatmap:
      _heatmapSvg(b, spec, plotTop, theme, textColor);
    case ChartType.controlChart:
    case ChartType.histogram:
    case ChartType.pareto:
    case ChartType.runChart:
    case ChartType.boxPlot:
    case ChartType.probabilityPlot:
    case ChartType.mainEffects:
    case ChartType.interaction:
      _improvementChartSvg(b, spec, plotTop, theme, textColor, y01: y01);
  }
  // Pie/donut list their slices; heatmap and waterfall carry their own key
  // (colour scale / a single series), so they get no series legend.
  if (spec.isPieLike) {
    _pieLegendSvg(b, spec, textColor);
  } else if (spec.type != ChartType.heatmap &&
      spec.type != ChartType.waterfall &&
      !chartTypeRequiresProcesverbetering(spec.type)) {
    _legendSvg(b, spec, theme, textColor);
  }
  b.write('</svg>');
  return b.toString();
}

void _legendSvg(
  StringBuffer b,
  ChartSpec spec,
  ThemeProfile? theme,
  String textColor,
) {
  final count = math.min(spec.series.length, 6);
  final cellWidth = 720.0 / count;
  for (var i = 0; i < count; i++) {
    final rawName = spec.series[i].name.isEmpty
        ? 'Reeks ${i + 1}'
        : spec.series[i].name;
    final name = rawName.length > 12 ? '${rawName.substring(0, 11)}…' : rawName;
    final x = 40 + i * cellWidth;
    b
      ..write(
        '<rect x="$x" y="414" width="${cellWidth - 8}" height="24" rx="12" '
        'fill="$textColor" fill-opacity=".05"/>',
      )
      ..write(
        '<circle cx="${x + 13}" cy="426" r="5" '
        'fill="${_color(spec, i, theme)}"/>',
      )
      ..write(
        '<text x="${x + 24}" y="431" font-size="13" font-weight="600" '
        'fill="$textColor">${_esc(name)}</text>',
      );
  }
}

void _pieLegendSvg(StringBuffer b, ChartSpec spec, String textColor) {
  const maxColumns = 6;
  final columns = math.min(spec.x.length, maxColumns);
  final rows = (spec.x.length / maxColumns).ceil().clamp(1, 3);
  final cellWidth = 720.0 / columns;
  final startY = 414.0 - (rows - 1) * 28;
  for (var i = 0; i < spec.x.length; i++) {
    final row = i ~/ maxColumns;
    if (row >= rows) break;
    final column = i % maxColumns;
    final x = 40 + column * cellWidth;
    final y = startY + row * 28;
    final label = spec.x[i].length > 12
        ? '${spec.x[i].substring(0, 11)}…'
        : spec.x[i];
    b
      ..write(
        '<rect x="$x" y="$y" width="${cellWidth - 8}" height="24" rx="12" '
        'fill="$textColor" fill-opacity=".05"/>',
      )
      ..write(
        '<circle cx="${x + 13}" cy="${y + 12}" r="5" '
        'fill="${chartRowColor(spec, i)}"/>',
      )
      ..write(
        '<text x="${x + 24}" y="${y + 17}" font-size="13" font-weight="600" '
        'fill="$textColor">${_esc(label)}</text>',
      );
  }
}

/// De onderkant van de y-as.
///
/// De app-preview heeft dit al ([_ChartPreview._minY] in
/// `chart_preview.dart`) en geeft het als `minY` aan fl_chart mee; de
/// SVG-export had alleen een `_maxY` die bij 0 begint en nooit daalt. Negatieve
/// reeksen — een verlies, een begrotingsafwijking, een verandering t.o.v. een
/// nulmeting — kwamen daardoor uit op `height="-1610"`, en een negatieve hoogte
/// is ongeldige SVG: de browser laat het element wég. De ontvanger kreeg een
/// leeg grafiekvlak met een y-as van 0 tot 1, terwijl de gegevens −5 tot −8
/// liepen. Dat is erger dan een lege grafiek, want het ziet er aannemelijk uit.
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

/// De y-coördinaat voor [value] binnen [top]..[bottom].
///
/// Eén plek, zodat de assen, de staven, de lijnen en de puntenwolk niet elk hun
/// eigen afbeelding houden — dat is precies hoe de nul-ondergrens hier ooit is
/// blijven staan toen de preview er wél een kreeg.
double _yOf(double value, double top, double bottom, double minY, double maxY) {
  final span = maxY - minY;
  if (span <= 0) return bottom;
  return bottom - (bottom - top) * ((value - minY) / span);
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
  if (spec.supportsBounds) {
    for (final b in [spec.minBound, spec.maxBound]) {
      if (b != null && b > m) m = b;
    }
  }
  return m <= 0 ? 1 : m * 1.15;
}

/// Draw the optional min/max threshold lines (bar/line only) as dashed rules.
void _boundLinesSvg(
  StringBuffer b,
  ChartSpec spec,
  double left,
  double top,
  double right,
  double bottom,
  double maxY,
  double minY,
) {
  if (!spec.supportsBoundLines) return;
  void draw(double? value, String color, String prefix) {
    if (value == null || value < minY || value > maxY) return;
    final y = _yOf(value, top, bottom, minY, maxY);
    b
      ..write(
        '<line x1="$left" y1="$y" x2="$right" y2="$y" stroke="$color" '
        'stroke-width="2.5" stroke-dasharray="8 5"/>',
      )
      ..write(
        '<text x="${right - 4}" y="${y - 5}" text-anchor="end" '
        'font-size="14" font-weight="700" fill="$color">'
        '$prefix ${_num(value)}</text>',
      );
  }

  draw(spec.minBound, '#F59E0B', 'min');
  draw(spec.maxBound, '#EF4444', 'max');
}

String _num(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

void _axes(
  StringBuffer b,
  ChartSpec spec,
  double left,
  double top,
  double right,
  double bottom,
  double maxY,
  double minY,
) {
  // Horizontal gridlines + y labels.
  for (var i = 0; i <= 4; i++) {
    final y = bottom - (bottom - top) * i / 4;
    final val = minY + (maxY - minY) * i / 4;
    b
      ..write(
        '<line x1="$left" y1="$y" x2="$right" y2="$y" stroke="#e2e8f0" stroke-width="1"/>',
      )
      ..write(
        '<text x="${left - 8}" y="${y + 5}" text-anchor="end" font-size="14" fill="#64748b">${_num(val)}</text>',
      );
  }
  // X labels.
  final n = spec.x.length;
  final step = math.max(1, (n / 8).ceil());
  for (var i = 0; i < n; i++) {
    if (i != n - 1 && i % step != 0) continue;
    final x = left + (right - left) * (i + 0.5) / n;
    final label = spec.x[i].length > 10
        ? '${spec.x[i].substring(0, 9)}…'
        : spec.x[i];
    b.write(
      '<text x="$x" y="${bottom + 20}" text-anchor="middle" '
      'font-size="13" fill="#334155">${_esc(label)}</text>',
    );
  }
}

void _barSvg(StringBuffer b, ChartSpec spec, double top, ThemeProfile? theme) {
  const left = 60.0, right = 770.0, bottom = 382.0;
  final maxY = _maxY(spec);
  final minY = _minY(spec);
  _axes(b, spec, left, top, right, bottom, maxY, minY);
  final n = spec.x.length;
  final groupW = (right - left) / n;
  final sCount = spec.series.length;
  final barW = (groupW * 0.7) / sCount;
  for (var xi = 0; xi < n; xi++) {
    final gx = left + groupW * xi + groupW * 0.15;
    for (var si = 0; si < sCount; si++) {
      if (xi >= spec.series[si].data.length) continue;
      final v = spec.series[si].data[xi];
      // Vanaf de nullijn, niet vanaf de onderrand: bij een negatieve waarde
      // hangt de staaf omláág. En de hoogte is per definitie positief — een
      // negatieve `height` is ongeldige SVG en werd door de browser genegeerd,
      // waardoor de staaf simpelweg niet bestond.
      final yZero = _yOf(0, top, bottom, minY, maxY);
      final yVal = _yOf(v, top, bottom, minY, maxY);
      final x = gx + barW * si;
      final barTop = yVal < yZero ? yVal : yZero;
      final h = (yVal - yZero).abs();
      b.write(
        '<rect x="$x" y="$barTop" width="${barW * 0.86}" height="$h" '
        'rx="5" fill="${_color(spec, si, theme)}"/>',
      );
    }
  }
  _boundLinesSvg(b, spec, left, top, right, bottom, maxY, minY);
}

void _stackedBarSvg(
  StringBuffer b,
  ChartSpec spec,
  double top,
  ThemeProfile? theme,
) {
  const left = 60.0, right = 770.0, bottom = 382.0;
  final maxY = _maxY(spec);
  final minY = _minY(spec);
  _axes(b, spec, left, top, right, bottom, maxY, minY);
  final n = spec.x.length;
  final groupW = (right - left) / n;
  final barW = groupW * 0.55;
  for (var xi = 0; xi < n; xi++) {
    final gx = left + groupW * xi + (groupW - barW) / 2;
    // Stapelen begint op de nullijn, niet op de onderrand — die twee vallen
    // alleen samen zolang er niets negatiefs in de reeks zit.
    var bottomY = _yOf(0, top, bottom, minY, maxY);
    for (var si = 0; si < spec.series.length; si++) {
      if (xi >= spec.series[si].data.length) continue;
      final v = spec.series[si].data[xi];
      final h =
          (_yOf(v, top, bottom, minY, maxY) - _yOf(0, top, bottom, minY, maxY))
              .abs();
      bottomY -= h;
      b.write(
        '<rect x="$gx" y="$bottomY" width="$barW" height="$h" '
        'rx="4" fill="${_color(spec, si, theme)}"/>',
      );
    }
  }
  _boundLinesSvg(b, spec, left, top, right, bottom, maxY, minY);
}

void _scatterSvg(
  StringBuffer b,
  ChartSpec spec,
  double top,
  ThemeProfile? theme,
) {
  const left = 60.0, right = 770.0, bottom = 382.0;
  final maxY = _maxY(spec);
  final minY = _minY(spec);
  _axes(b, spec, left, top, right, bottom, maxY, minY);
  final n = spec.x.length;
  double px(int i) => left + (right - left) * (i + 0.5) / n;
  double py(double v) => _yOf(v, top, bottom, minY, maxY);
  for (var si = 0; si < spec.series.length; si++) {
    for (var xi = 0; xi < spec.series[si].data.length; xi++) {
      final x = px(xi);
      final y = py(spec.series[si].data[xi]);
      b.write(
        '<circle cx="$x" cy="$y" r="6" fill="${_color(spec, si, theme)}"/>',
      );
    }
  }
  _boundLinesSvg(b, spec, left, top, right, bottom, maxY, minY);
}

void _lineSvg(
  StringBuffer b,
  ChartSpec spec,
  double top,
  ThemeProfile? theme, {
  bool area = false,
}) {
  const left = 60.0, right = 770.0, bottom = 382.0;
  final maxY = _maxY(spec);
  final minY = _minY(spec);
  _axes(b, spec, left, top, right, bottom, maxY, minY);
  final n = spec.x.length;
  double px(int i) => left + (right - left) * (i + 0.5) / n;
  double py(double v) => _yOf(v, top, bottom, minY, maxY);
  for (var si = 0; si < spec.series.length; si++) {
    final data = spec.series[si].data;
    final pts = [
      for (var i = 0; i < data.length; i++) '${px(i)},${py(data[i])}',
    ].join(' ');
    if (area && data.isNotEmpty) {
      // Close the line down to the baseline and back for a filled area.
      final fill = '$pts ${px(data.length - 1)},$bottom ${px(0)},$bottom';
      b.write(
        '<polygon points="$fill" fill="${_color(spec, si, theme)}" '
        'fill-opacity="${spec.series.length == 1 ? 0.28 : 0.16}" '
        'stroke="none"/>',
      );
    }
    b.write(
      '<polyline points="$pts" fill="none" '
      'stroke="${_color(spec, si, theme)}" stroke-width="4" '
      'stroke-linecap="round" stroke-linejoin="round"/>',
    );
    for (var i = 0; i < data.length; i++) {
      b.write(
        '<circle cx="${px(i)}" cy="${py(data[i])}" r="5" '
        'fill="${_color(spec, si, theme)}" stroke="white" stroke-width="2"/>',
      );
    }
  }
  _boundLinesSvg(b, spec, left, top, right, bottom, maxY, minY);
}

/// Compact SVG for Procesverbetering chart types. Limits/Cpk are derived here
/// and never read from the stored block.
void _improvementChartSvg(
  StringBuffer b,
  ChartSpec spec,
  double top,
  ThemeProfile? theme,
  String textColor, {
  ImprovementY01Metric y01 = ImprovementY01Metric.empty,
}) {
  final accent = theme?.accentColor ?? '#2563EB';
  const left = 60.0;
  const right = 760.0;
  final bottom = 400.0;
  final plotH = bottom - top;

  void polyline(List<double> ys, String stroke, {List<int> mark = const []}) {
    if (ys.isEmpty) return;
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);
    final span = (maxY - minY).abs() < 1e-9 ? 1.0 : maxY - minY;
    double xOf(int i) =>
        left +
        (ys.length <= 1
            ? (right - left) / 2
            : i * (right - left) / (ys.length - 1));
    double yOf(double v) => bottom - ((v - minY) / span) * plotH;
    final pts = [
      for (var i = 0; i < ys.length; i++) '${xOf(i)},${yOf(ys[i])}',
    ].join(' ');
    b.write(
      '<polyline points="$pts" fill="none" stroke="$stroke" '
      'stroke-width="3" stroke-linejoin="round"/>',
    );
    for (var i = 0; i < ys.length; i++) {
      final r = mark.contains(i) ? 6 : 4;
      final fill = mark.contains(i) ? '#DC2626' : stroke;
      b.write(
        '<circle cx="${xOf(i)}" cy="${yOf(ys[i])}" r="$r" fill="$fill"/>',
      );
    }
  }

  switch (spec.type) {
    case ChartType.controlChart:
      final view = deriveIndividualsChart(spec);
      if (view == null) return;
      polyline(view.values, accent, mark: view.outOfControl.toList());
      b.write(
        '<text x="$left" y="${top - 8}" font-size="12" fill="$textColor">'
        'UCL ${view.ucl.toStringAsFixed(2)} · CL ${view.center.toStringAsFixed(2)} · '
        'LCL ${view.lcl.toStringAsFixed(2)}</text>',
      );
    case ChartType.runChart:
      final values = chartPrimarySample(spec);
      if (values.length < 2) return;
      polyline(values, accent);
    case ChartType.histogram:
      _histogramImprovementSvg(
        b,
        spec,
        y01: y01,
        accent: accent,
        textColor: textColor,
        left: left,
        right: right,
        top: top,
        bottom: bottom,
        plotH: plotH,
      );
    case ChartType.pareto:
      final view = derivePareto(spec);
      if (view == null) return;
      final maxV = view.values
          .fold<double>(0, math.max)
          .clamp(1e-9, double.infinity);
      final n = view.values.length;
      final barW = (right - left) / n;
      for (var i = 0; i < n; i++) {
        final h = (view.values[i] / maxV) * plotH;
        final fill = i < view.vitalFewCount ? accent : '#93C5FD';
        b.write(
          '<rect x="${left + i * barW + 2}" y="${bottom - h}" '
          'width="${barW - 4}" height="$h" fill="$fill" rx="2"/>',
        );
      }
    case ChartType.boxPlot:
      final view = deriveBoxPlot(spec);
      if (view == null) return;
      b.write(
        '<text x="$left" y="${top + 20}" font-size="14" fill="$textColor">'
        '${view.boxes.length} box(es)</text>',
      );
    case ChartType.probabilityPlot:
      final view = deriveProbabilityPlot(spec);
      if (view == null) return;
      final xs = view.theoreticalQuantiles;
      final ys = view.sortedValues;
      final minX = xs.reduce(math.min);
      final maxX = xs.reduce(math.max);
      final minY = ys.reduce(math.min);
      final maxY = ys.reduce(math.max);
      final spanX = (maxX - minX).abs() < 1e-9 ? 1.0 : maxX - minX;
      final spanY = (maxY - minY).abs() < 1e-9 ? 1.0 : maxY - minY;
      double xOf(double v) => left + ((v - minX) / spanX) * (right - left);
      double yOf(double v) => bottom - ((v - minY) / spanY) * plotH;
      for (var i = 0; i < xs.length; i++) {
        b.write(
          '<circle cx="${xOf(xs[i])}" cy="${yOf(ys[i])}" r="4" fill="$accent"/>',
        );
      }
      if (view.normalityPValue != null) {
        b.write(
          '<text x="$left" y="${top - 8}" font-size="12" fill="$textColor">'
          'AD p=${view.normalityPValue!.toStringAsFixed(2)}</text>',
        );
      }
    case ChartType.mainEffects:
      final mainFx = deriveMainEffects(spec);
      if (mainFx == null) return;
      var meMinY = mainFx.grandMean;
      var meMaxY = mainFx.grandMean;
      for (final line in mainFx.lines) {
        meMinY = math.min(meMinY, math.min(line.low, line.high));
        meMaxY = math.max(meMaxY, math.max(line.low, line.high));
      }
      final meSpan = (meMaxY - meMinY).abs() < 1e-9 ? 1.0 : meMaxY - meMinY;
      meMinY -= meSpan * 0.1;
      meMaxY += meSpan * 0.1;
      final meYSpan = meMaxY - meMinY;
      double meYOf(double v) => bottom - ((v - meMinY) / meYSpan) * plotH;
      b.write(
        '<line x1="$left" y1="${meYOf(mainFx.grandMean)}" x2="$right" '
        'y2="${meYOf(mainFx.grandMean)}" stroke="$textColor" stroke-opacity="0.25"/>',
      );
      final meSlot = (right - left) / mainFx.lines.length;
      for (var i = 0; i < mainFx.lines.length; i++) {
        final line = mainFx.lines[i];
        final cx = left + (i + 0.5) * meSlot;
        final xLow = cx - meSlot * 0.18;
        final xHigh = cx + meSlot * 0.18;
        final stroke = chartColorPalette[i % chartColorPalette.length];
        b.write(
          '<line x1="$xLow" y1="${meYOf(line.low)}" x2="$xHigh" '
          'y2="${meYOf(line.high)}" stroke="$stroke" stroke-width="3"/>',
        );
        b.write(
          '<circle cx="$xLow" cy="${meYOf(line.low)}" r="4" fill="$stroke"/>',
        );
        b.write(
          '<circle cx="$xHigh" cy="${meYOf(line.high)}" r="4" fill="$stroke"/>',
        );
        b.write(
          '<text x="${cx - 12}" y="${bottom + 16}" font-size="11" '
          'fill="$textColor">${_esc(line.label)}</text>',
        );
      }
    case ChartType.interaction:
      final inter = deriveInteraction(spec);
      if (inter == null) return;
      var ixMinY = double.infinity;
      var ixMaxY = double.negativeInfinity;
      for (final panel in inter.panels) {
        for (final line in panel.lines) {
          ixMinY = math.min(
            ixMinY,
            math.min(line.atFactorLow, line.atFactorHigh),
          );
          ixMaxY = math.max(
            ixMaxY,
            math.max(line.atFactorLow, line.atFactorHigh),
          );
        }
      }
      if (!ixMinY.isFinite) return;
      final ixSpan = (ixMaxY - ixMinY).abs() < 1e-9 ? 1.0 : ixMaxY - ixMinY;
      ixMinY -= ixSpan * 0.1;
      ixMaxY += ixSpan * 0.1;
      final ixYSpan = ixMaxY - ixMinY;
      double ixYOf(double v) => bottom - ((v - ixMinY) / ixYSpan) * plotH;
      final ixSlot = (right - left) / inter.panels.length;
      for (var pi = 0; pi < inter.panels.length; pi++) {
        final panel = inter.panels[pi];
        final cx = left + (pi + 0.5) * ixSlot;
        final xLow = cx - ixSlot * 0.18;
        final xHigh = cx + ixSlot * 0.18;
        for (var li = 0; li < panel.lines.length; li++) {
          final line = panel.lines[li];
          final stroke = li == 0
              ? accent
              : chartColorPalette[(li + 1) % chartColorPalette.length];
          b.write(
            '<line x1="$xLow" y1="${ixYOf(line.atFactorLow)}" x2="$xHigh" '
            'y2="${ixYOf(line.atFactorHigh)}" stroke="$stroke" stroke-width="3"/>',
          );
        }
        b.write(
          '<text x="${cx - 16}" y="${bottom + 14}" font-size="10" '
          'fill="$textColor">${_esc(panel.label)}</text>',
        );
      }
    default:
      break;
  }
}

/// Histogram bars plus Y-01/spec limit lines and Cpk label for HTML export.
void _histogramImprovementSvg(
  StringBuffer b,
  ChartSpec spec, {
  required ImprovementY01Metric y01,
  required String accent,
  required String textColor,
  required double left,
  required double right,
  required double top,
  required double bottom,
  required double plotH,
}) {
  final view = deriveHistogram(spec, y01: y01);
  if (view == null) return;
  final maxC = view.counts.fold<int>(0, math.max).clamp(1, 1 << 30);
  final n = view.counts.length;
  final barW = (right - left) / n;
  for (var i = 0; i < n; i++) {
    final h = (view.counts[i] / maxC) * plotH;
    b.write(
      '<rect x="${left + i * barW + 1}" y="${bottom - h}" '
      'width="${barW - 2}" height="$h" fill="$accent" rx="2"/>',
    );
  }
  final limits = resolveChartSpecLimits(
    yRef: spec.yRef,
    localUsl: spec.usl,
    localLsl: spec.lsl,
    localProcessTarget: spec.processTarget,
    y01: y01,
  );
  void specLine(double? v) {
    if (v == null || view.edges.length < 2) return;
    final minX = view.edges.first;
    final maxX = view.edges.last;
    final span = (maxX - minX).abs() < 1e-9 ? 1.0 : maxX - minX;
    final x = left + ((v - minX) / span) * (right - left);
    if (x < left || x > right) return;
    b.write(
      '<line x1="$x" y1="$top" x2="$x" y2="$bottom" '
      'stroke="#DC2626" stroke-width="1.5"/>',
    );
  }

  specLine(limits.lsl);
  specLine(limits.usl);
  if (view.cpk != null) {
    b.write(
      '<text x="$left" y="${top - 8}" font-size="12" fill="$textColor">'
      'Cpk ${view.cpk!.toStringAsFixed(2)}</text>',
    );
  }
}
