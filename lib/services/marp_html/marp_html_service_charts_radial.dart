part of '../marp_html_service.dart';

/// De niet-cartesische grafiektypen van de HTML-export: taart, radar, de
/// horizontale staafvarianten, combo, waterval en heatmap.
///
/// Apart bestand omdat `marp_html_service_charts.dart` tegen de regelratchet
/// aan zit. De scheiding is die van het assenstelsel: hiernaast staat alles wat
/// een gedeelde y-as deelt (en dus [_yOf], [_minY] en [_maxY] gebruikt), hier
/// staat wat zijn eigen schaal meebrengt.

void _pieSvg(
  StringBuffer b,
  ChartSpec spec,
  double top,
  ThemeProfile? theme, {
  required double bottom,
  bool donut = false,
}) {
  final count = math.min(spec.series.length, 2);
  final columns = count;
  final rows = (count / columns).ceil();
  final cellWidth = 720.0 / columns;
  final cellHeight = (bottom - top) / rows;
  final radius = math.min(cellWidth * 0.25, cellHeight * 0.42);
  for (var xi = 0; xi < count; xi++) {
    final col = xi % columns;
    final row = xi ~/ columns;
    final cellLeft = 40 + cellWidth * col;
    final cx = cellLeft + cellWidth * 0.36;
    final cy = top + cellHeight * (row + 0.5);
    final series = spec.series[xi];
    final values = [
      for (var labelIndex = 0; labelIndex < spec.x.length; labelIndex++)
        labelIndex < series.data.length && series.data[labelIndex] > 0
            ? series.data[labelIndex]
            : 0.0,
    ];
    final total = values.fold<double>(0, (a, v) => a + v);
    var angle = -90.0;
    for (var labelIndex = 0; labelIndex < values.length; labelIndex++) {
      final frac = total > 0 ? values[labelIndex] / total : 0;
      final sweep = frac * 360;
      if (sweep <= 0) continue;
      final a0 = angle * math.pi / 180;
      final a1 = (angle + sweep) * math.pi / 180;
      final x0 = cx + radius * math.cos(a0);
      final y0 = cy + radius * math.sin(a0);
      final x1 = cx + radius * math.cos(a1);
      final y1 = cy + radius * math.sin(a1);
      final large = sweep > 180 ? 1 : 0;
      b.write(
        '<path d="M$cx,$cy L$x0,$y0 A$radius,$radius 0 $large,1 '
        '$x1,$y1 Z" '
        'fill="${chartRowColor(spec, labelIndex)}" '
        'stroke="white" '
        'stroke-width="2"/>',
      );
      angle += sweep;
    }
    if (donut) {
      // Only a donut carries a hole; a pie stays solid to the centre so the
      // slices meet at a single point. (A pie used to get a 0.43 hole too.)
      b.write(
        '<circle cx="$cx" cy="$cy" r="${radius * 0.6}" '
        'fill="${theme?.slideBackgroundColor ?? 'white'}"/>',
      );
      // The total, printed in the centre hole.
      b.write(
        '<text x="$cx" y="${cy + 6}" text-anchor="middle" font-size="18" '
        'font-weight="700" fill="${theme?.textColor ?? '#111827'}">'
        '${_num(total)}</text>',
      );
    }
    b.write(
      '<text x="${cellLeft + cellWidth * 0.66}" y="${cy + 5}" '
      'font-size="14" font-weight="700">'
      '${_esc(_shortChartLabel(series.name.isEmpty ? 'Reeks ${xi + 1}' : series.name))}</text>',
    );
  }
}

void _radarSvg(
  StringBuffer b,
  ChartSpec spec,
  double top,
  ThemeProfile? theme,
  String textColor,
) {
  final n = spec.x.length;
  if (n < 3 || spec.series.isEmpty) return;
  const bottom = 382.0;
  const cx = 400.0;
  final cy = (top + bottom) / 2;
  final radius = math.min(170.0, (bottom - top) / 2 - 34);
  final (lo, hi, ticks) = _radarScale(spec);
  final span = (hi - lo) == 0 ? 1.0 : (hi - lo);
  double angle(int i) => -math.pi / 2 + 2 * math.pi * i / n;

  // Concentric grid rings, evenly spaced across the [lo, hi] scale.
  for (var ring = 1; ring <= ticks; ring++) {
    final rr = radius * ring / ticks;
    final pts = [
      for (var i = 0; i < n; i++)
        '${cx + rr * math.cos(angle(i))},${cy + rr * math.sin(angle(i))}',
    ].join(' ');
    b.write(
      '<polygon points="$pts" fill="none" stroke="#e2e8f0" '
      'stroke-width="1"/>',
    );
  }

  // Scale legend on the right: hi at the top down to lo at the bottom, so the
  // figure itself stays clean.
  final legendX = cx + radius + 30;
  for (var k = ticks; k >= 0; k--) {
    final value = lo + span * k / ticks;
    final y = (cy - radius) + (2 * radius) * (ticks - k) / ticks;
    b
      ..write(
        '<line x1="$legendX" y1="$y" x2="${legendX + 8}" y2="$y" '
        'stroke="#cbd5e1" stroke-width="1"/>',
      )
      ..write(
        '<text x="${legendX + 12}" y="${y + 4}" font-size="12" '
        'fill="#94a3b8">${_num(value)}</text>',
      );
  }

  // Spokes and axis labels.
  for (var i = 0; i < n; i++) {
    final c = math.cos(angle(i));
    final s = math.sin(angle(i));
    b.write(
      '<line x1="$cx" y1="$cy" x2="${cx + radius * c}" '
      'y2="${cy + radius * s}" stroke="#e2e8f0" stroke-width="1"/>',
    );
    final anchor = c > 0.3 ? 'start' : (c < -0.3 ? 'end' : 'middle');
    final label = spec.x[i].length > 12
        ? '${spec.x[i].substring(0, 11)}…'
        : spec.x[i];
    b.write(
      '<text x="${cx + (radius + 18) * c}" y="${cy + (radius + 18) * s + 4}" '
      'text-anchor="$anchor" font-size="13" fill="$textColor">'
      '${_esc(label)}</text>',
    );
  }

  // One filled polygon per series.
  for (var si = 0; si < spec.series.length; si++) {
    final data = spec.series[si].data;
    final pts = [
      for (var i = 0; i < n; i++)
        () {
          final v = i < data.length ? data[i] : 0.0;
          final rr = radius * ((v - lo) / span).clamp(0.0, 1.0);
          return '${cx + rr * math.cos(angle(i))},'
              '${cy + rr * math.sin(angle(i))}';
        }(),
    ].join(' ');
    final color = _color(spec, si, theme);
    b.write(
      '<polygon points="$pts" fill="$color" fill-opacity="0.16" '
      'stroke="$color" stroke-width="2" stroke-linejoin="round"/>',
    );
  }
}

/// Radar scale shared with the live preview: honour optional min/max bounds,
/// otherwise round the data range to a tidy scale with an even tick count.
(double, double, int) _radarScale(ChartSpec spec) {
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
  final range = (rawHi - rawLo).abs();
  final r = range <= 0 ? 1.0 : range;
  final rawStep = r / 4;
  final mag = math.pow(10, (math.log(rawStep) / math.ln10).floor()).toDouble();
  final norm = rawStep / mag;
  final niceNorm = norm < 1.5
      ? 1.0
      : norm < 3
      ? 2.0
      : norm < 7
      ? 5.0
      : 10.0;
  final step = niceNorm * mag;
  final lo = spec.minBound ?? (rawLo / step).floorToDouble() * step;
  var hi = spec.maxBound ?? (rawHi / step).ceilToDouble() * step;
  if (hi <= lo) hi = lo + step;
  final ticks = math.max(2, ((hi - lo) / step).round());
  return (lo, hi, ticks);
}

String _shortChartLabel(String value) =>
    value.length > 13 ? '${value.substring(0, 12)}…' : value;

double _maxHorizontalSvg(ChartSpec spec) {
  var m = 0.0;
  for (final s in spec.series) {
    for (final v in s.data) {
      if (v > m) m = v;
    }
  }
  return m <= 0 ? 1 : m * 1.15;
}

void _horizontalBarSvg(
  StringBuffer b,
  ChartSpec spec,
  double top,
  ThemeProfile? theme,
) {
  const plotLeft = 170.0, right = 770.0, bottom = 382.0;
  final n = spec.x.length;
  if (n == 0 || spec.series.isEmpty) return;
  final maxX = _maxHorizontalSvg(spec);
  final plotW = right - plotLeft;
  // Vertical gridlines + value labels along the bottom.
  for (var g = 0; g <= 4; g++) {
    final x = plotLeft + plotW * g / 4;
    b
      ..write(
        '<line x1="$x" y1="$top" x2="$x" y2="$bottom" stroke="#e2e8f0" '
        'stroke-width="1"/>',
      )
      ..write(
        '<text x="$x" y="${bottom + 18}" text-anchor="middle" font-size="13" '
        'fill="#64748b">${_num(maxX * g / 4)}</text>',
      );
  }
  final bandH = (bottom - top) / n;
  final sCount = spec.series.length;
  for (var xi = 0; xi < n; xi++) {
    final bandTop = top + bandH * xi;
    final label = spec.x[xi].length > 16
        ? '${spec.x[xi].substring(0, 15)}…'
        : spec.x[xi];
    b.write(
      '<text x="${plotLeft - 12}" y="${bandTop + bandH / 2 + 5}" '
      'text-anchor="end" font-size="13" fill="#334155">${_esc(label)}</text>',
    );
    final subH = (bandH * 0.72) / sCount;
    for (var si = 0; si < sCount; si++) {
      if (xi >= spec.series[si].data.length) continue;
      final v = spec.series[si].data[xi];
      final len = plotW * (v / maxX);
      final y = bandTop + bandH * 0.14 + subH * si;
      b.write(
        '<rect x="$plotLeft" y="$y" width="$len" height="${subH * 0.84}" '
        'rx="4" fill="${_color(spec, si, theme)}"/>',
      );
      if (v != 0) {
        b.write(
          '<text x="${plotLeft + len + 6}" y="${y + subH * 0.62}" '
          'font-size="12" fill="#334155">${_num(v)}</text>',
        );
      }
    }
  }
}

/// The widest per-label total — the value axis of a horizontal stacked bar must
/// fit the sum of a bar's segments, not just its biggest single value.
double _maxHorizontalStackedSvg(ChartSpec spec) {
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

void _horizontalStackedBarSvg(
  StringBuffer b,
  ChartSpec spec,
  double top,
  ThemeProfile? theme,
) {
  const plotLeft = 170.0, right = 770.0, bottom = 382.0;
  final n = spec.x.length;
  if (n == 0 || spec.series.isEmpty) return;
  final maxX = _maxHorizontalStackedSvg(spec);
  final plotW = right - plotLeft;
  // Vertical gridlines + value labels along the bottom.
  for (var g = 0; g <= 4; g++) {
    final x = plotLeft + plotW * g / 4;
    b
      ..write(
        '<line x1="$x" y1="$top" x2="$x" y2="$bottom" stroke="#e2e8f0" '
        'stroke-width="1"/>',
      )
      ..write(
        '<text x="$x" y="${bottom + 18}" text-anchor="middle" font-size="13" '
        'fill="#64748b">${_num(maxX * g / 4)}</text>',
      );
  }
  final bandH = (bottom - top) / n;
  final barH = bandH * 0.6;
  for (var xi = 0; xi < n; xi++) {
    final bandTop = top + bandH * xi;
    final label = spec.x[xi].length > 16
        ? '${spec.x[xi].substring(0, 15)}…'
        : spec.x[xi];
    b.write(
      '<text x="${plotLeft - 12}" y="${bandTop + bandH / 2 + 5}" '
      'text-anchor="end" font-size="13" fill="#334155">${_esc(label)}</text>',
    );
    final barTop = bandTop + (bandH - barH) / 2;
    var segLeft = plotLeft;
    for (var si = 0; si < spec.series.length; si++) {
      if (xi >= spec.series[si].data.length) continue;
      final v = spec.series[si].data[xi];
      if (v <= 0) continue;
      final len = plotW * (v / maxX);
      // A thin white edge keeps abutting segments legible without the notches
      // that per-segment rounding would leave.
      b.write(
        '<rect x="$segLeft" y="$barTop" width="$len" height="$barH" rx="3" '
        'fill="${_color(spec, si, theme)}" stroke="white" stroke-width="1"/>',
      );
      if (len > 34) {
        b.write(
          '<text x="${segLeft + len / 2}" y="${barTop + barH / 2 + 5}" '
          'text-anchor="middle" font-size="12" font-weight="700" fill="white">'
          '${_num(v)}</text>',
        );
      }
      segLeft += len;
    }
  }
}

(double, double) _comboLineRangeSvg(ChartSeries line) {
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

void _comboSvg(
  StringBuffer b,
  ChartSpec spec,
  double top,
  ThemeProfile? theme,
) {
  if (spec.series.length < 2) {
    _barSvg(b, spec, top, theme);
    return;
  }
  const left = 60.0, right = 735.0, bottom = 382.0;
  final n = spec.x.length;
  final barCount = spec.series.length - 1;
  final lineIdx = spec.series.length - 1;
  final line = spec.series[lineIdx];
  var barMax = 0.0;
  // Ook naar beneden kijken: de staafschaal van de combografiek had, net als de
  // andere typen, een vaste ondergrens van nul.
  var barMin = 0.0;
  for (var si = 0; si < barCount; si++) {
    for (final v in spec.series[si].data) {
      if (v > barMax) barMax = v;
      if (v < barMin) barMin = v;
    }
  }
  for (final bnd in [spec.minBound, spec.maxBound]) {
    if (bnd != null && bnd > barMax) barMax = bnd;
    if (bnd != null && bnd < barMin) barMin = bnd;
  }
  barMax = barMax <= 0 ? 1 : barMax * 1.15;
  barMin = barMin >= 0 ? 0 : barMin * 1.15;
  _axes(b, spec, left, top, right, bottom, barMax, barMin);
  final groupW = (right - left) / n;
  final barW = (groupW * 0.6) / barCount;
  for (var xi = 0; xi < n; xi++) {
    final gx = left + groupW * xi + groupW * 0.2;
    for (var si = 0; si < barCount; si++) {
      if (xi >= spec.series[si].data.length) continue;
      final v = spec.series[si].data[xi];
      final yZero = _yOf(0, top, bottom, barMin, barMax);
      final yVal = _yOf(v, top, bottom, barMin, barMax);
      final x = gx + barW * si;
      b.write(
        '<rect x="$x" y="${yVal < yZero ? yVal : yZero}" '
        'width="${barW * 0.86}" height="${(yVal - yZero).abs()}" '
        'rx="4" fill="${_color(spec, si, theme)}"/>',
      );
    }
  }
  _boundLinesSvg(b, spec, left, top, right, bottom, barMax, barMin);
  // Line on its own right-hand scale.
  final (lineMin, lineMax) = _comboLineRangeSvg(line);
  final span = (lineMax - lineMin) == 0 ? 1.0 : (lineMax - lineMin);
  double lx(int i) => left + (right - left) * (i + 0.5) / n;
  double ly(double v) => bottom - (bottom - top) * ((v - lineMin) / span);
  final color = _color(spec, lineIdx, theme);
  final pts = [
    for (var i = 0; i < line.data.length; i++) '${lx(i)},${ly(line.data[i])}',
  ].join(' ');
  b.write(
    '<polyline points="$pts" fill="none" stroke="$color" stroke-width="4" '
    'stroke-linecap="round" stroke-linejoin="round"/>',
  );
  for (var i = 0; i < line.data.length; i++) {
    b.write(
      '<circle cx="${lx(i)}" cy="${ly(line.data[i])}" r="5" fill="$color" '
      'stroke="white" stroke-width="2"/>',
    );
  }
  for (var k = 0; k <= 4; k++) {
    final v = lineMin + span * k / 4;
    final y = bottom - (bottom - top) * k / 4;
    b.write(
      '<text x="${right + 8}" y="${y + 4}" font-size="13" fill="$color">'
      '${_num(v)}</text>',
    );
  }
}

void _waterfallSvg(
  StringBuffer b,
  ChartSpec spec,
  double top,
  ThemeProfile? theme,
) {
  const left = 60.0, right = 770.0, bottom = 382.0;
  final n = spec.x.length;
  if (spec.series.isEmpty || n == 0) return;
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
  var maxY = 0.0, minY = 0.0;
  for (var i = 0; i < n; i++) {
    if (tops[i] > maxY) maxY = tops[i];
    if (bottoms[i] < minY) minY = bottoms[i];
  }
  if (spec.maxBound != null && spec.maxBound! > maxY) maxY = spec.maxBound!;
  if (spec.minBound != null && spec.minBound! < minY) minY = spec.minBound!;
  maxY = maxY <= 0 ? 1 : maxY * 1.15;
  if (minY < 0) minY = minY * 1.15;
  final span = (maxY - minY) == 0 ? 1.0 : (maxY - minY);
  double py(double v) => bottom - (bottom - top) * ((v - minY) / span);
  // Gridlines + y labels over the signed scale.
  for (var i = 0; i <= 4; i++) {
    final val = minY + span * i / 4;
    final y = py(val);
    b
      ..write(
        '<line x1="$left" y1="$y" x2="$right" y2="$y" stroke="#e2e8f0" '
        'stroke-width="1"/>',
      )
      ..write(
        '<text x="${left - 8}" y="${y + 5}" text-anchor="end" font-size="14" '
        'fill="#64748b">${_num(val)}</text>',
      );
  }
  // X labels.
  final step = math.max(1, (n / 8).ceil());
  for (var i = 0; i < n; i++) {
    if (i != n - 1 && i % step != 0) continue;
    final x = left + (right - left) * (i + 0.5) / n;
    final label = spec.x[i].length > 10
        ? '${spec.x[i].substring(0, 9)}…'
        : spec.x[i];
    b.write(
      '<text x="$x" y="${bottom + 20}" text-anchor="middle" font-size="13" '
      'fill="#334155">${_esc(label)}</text>',
    );
  }
  final groupW = (right - left) / n;
  final barW = groupW * 0.5;
  for (var i = 0; i < n; i++) {
    final gx = left + groupW * i + (groupW - barW) / 2;
    final y0 = py(tops[i]);
    final h = py(bottoms[i]) - y0;
    // Matches AppTheme.success700 / danger500 used by the live preview.
    final fill = deltas[i] >= 0 ? '#15803D' : '#EF4444';
    b.write(
      '<rect x="$gx" y="$y0" width="$barW" height="$h" rx="3" fill="$fill"/>',
    );
  }
  // Optional min/max reference lines on the same signed scale.
  void bound(double? value, String color, String prefix) {
    if (value == null || value < minY || value > maxY) return;
    final y = py(value);
    b
      ..write(
        '<line x1="$left" y1="$y" x2="$right" y2="$y" stroke="$color" '
        'stroke-width="2.5" stroke-dasharray="8 5"/>',
      )
      ..write(
        '<text x="${right - 4}" y="${y - 5}" text-anchor="end" font-size="14" '
        'font-weight="700" fill="$color">$prefix ${_num(value)}</text>',
      );
  }

  bound(spec.minBound, '#F59E0B', 'min');
  bound(spec.maxBound, '#EF4444', 'max');
}

void _heatmapSvg(
  StringBuffer b,
  ChartSpec spec,
  double top,
  ThemeProfile? theme,
  String textColor,
) {
  const gridLeft = 170.0, right = 770.0, bottom = 382.0;
  final rows = spec.series;
  final cols = spec.x;
  if (rows.isEmpty || cols.isEmpty) return;
  double? lo, hi;
  for (final s in rows) {
    for (final v in s.data) {
      lo = lo == null ? v : math.min(lo, v);
      hi = hi == null ? v : math.max(hi, v);
    }
  }
  final low = lo ?? 0;
  var high = hi ?? 1;
  if (high <= low) high = low + 1;
  // Magnitude → a fixed heat ramp (see chart.dart), not the deck theme, matching
  // the live preview. The ramp follows the slide background so low always
  // recedes and high always intensifies.
  final bg = theme?.slideBackgroundColor ?? '#FFFFFF';
  final ramp = heatmapRamp(darkBackground: isDarkHex(bg));
  final cellW = (right - gridLeft) / cols.length;
  final cellH = (bottom - top) / rows.length;
  for (var r = 0; r < rows.length; r++) {
    final rowY = top + cellH * r;
    final name = rows[r].name.isEmpty ? 'Reeks ${r + 1}' : rows[r].name;
    b.write(
      '<text x="${gridLeft - 12}" y="${rowY + cellH / 2 + 5}" '
      'text-anchor="end" font-size="13" fill="$textColor">'
      '${_esc(_shortChartLabel(name))}</text>',
    );
    for (var c = 0; c < cols.length; c++) {
      final present = c < rows[r].data.length;
      final v = present ? rows[r].data[c] : 0.0;
      final norm = ((v - low) / (high - low)).clamp(0.0, 1.0);
      final fill = present ? heatmapColorAt(ramp, norm) : '#f1f5f9';
      final x = gridLeft + cellW * c;
      b.write(
        '<rect x="${x + 2}" y="${rowY + 2}" width="${cellW - 4}" '
        'height="${cellH - 4}" rx="4" fill="$fill"/>',
      );
      if (present) {
        final on = heatmapInk(fill);
        b.write(
          '<text x="${x + cellW / 2}" y="${rowY + cellH / 2 + 5}" '
          'text-anchor="middle" font-size="14" font-weight="700" fill="$on">'
          '${_num(v)}</text>',
        );
      }
    }
  }
  // Column labels.
  for (var c = 0; c < cols.length; c++) {
    final label = cols[c].length > 10 ? '${cols[c].substring(0, 9)}…' : cols[c];
    b.write(
      '<text x="${gridLeft + cellW * (c + 0.5)}" y="${bottom + 18}" '
      'text-anchor="middle" font-size="13" fill="$textColor">'
      '${_esc(label)}</text>',
    );
  }
  // Discrete colour-scale strip with min/max labels.
  const scaleY = 404.0;
  final scaleLeft = gridLeft;
  final scaleW = right - gridLeft - 80;
  const segments = 24;
  b.write(
    '<text x="${scaleLeft - 8}" y="${scaleY + 12}" text-anchor="end" '
    'font-size="12" fill="#64748b">${_num(low)}</text>',
  );
  for (var i = 0; i < segments; i++) {
    final fill = heatmapColorAt(ramp, i / (segments - 1));
    final x = scaleLeft + scaleW * i / segments;
    b.write(
      '<rect x="$x" y="$scaleY" width="${scaleW / segments + 0.5}" '
      'height="14" fill="$fill"/>',
    );
  }
  b.write(
    '<text x="${scaleLeft + scaleW + 8}" y="${scaleY + 12}" '
    'font-size="12" fill="#64748b">${_num(high)}</text>',
  );
}
