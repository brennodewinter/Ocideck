import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../models/chart.dart';
import '../models/deck.dart';
import '../models/settings.dart';
import '../utils/log.dart';
import 'export_metadata.dart';

/// Builds a single, self-contained HTML file from a deck's Marp Markdown.
///
/// The output embeds (inlines) `marked` for Markdown, `highlight.js` for code,
/// `MathJax` (tex-svg, so no external font files are needed) for math, and
/// `mermaid` for diagrams — so the resulting `.html` renders fully offline.
///
/// Note: this is a Marp-*flavoured* deck rendered with `marked`, not Marp Core,
/// so theme fidelity differs from the in-app preview / PDF / PPTX. The strength
/// here is a portable, dependency-free presentation that opens in any browser.
class MarpHtmlService {
  /// Reads a bundled text asset (defaults to the Flutter asset bundle).
  /// Injectable so the builder can be unit-tested against the on-disk files.
  final Future<String> Function(String asset) loadAsset;

  /// Reads a bundled binary asset (used to embed the EB Garamond font).
  final Future<Uint8List> Function(String asset) loadBytes;

  MarpHtmlService({
    Future<String> Function(String asset)? loadAsset,
    Future<Uint8List> Function(String asset)? loadBytes,
  }) : loadAsset = loadAsset ?? rootBundle.loadString,
       loadBytes =
           loadBytes ??
           ((a) async => (await rootBundle.load(a)).buffer.asUint8List());

  static const _assetDir = 'assets/web_export';

  /// Builds the HTML. When [theme] is given, the slides take that profile's
  /// colours and font so the export matches the in-app / PDF look.
  Future<String> build(
    String deckMarkdown, {
    ThemeProfile? theme,
    ExportDocumentMetadata? metadata,
    String fallbackTitle = 'Presentatie',
  }) async {
    final marked = await loadAsset('$_assetDir/marked.min.js');
    final purify = await loadAsset('$_assetDir/purify.min.js');
    final hljs = await loadAsset('$_assetDir/highlight.min.js');
    final hljsCss = await loadAsset('$_assetDir/highlight.css');
    final mathjax = await loadAsset('$_assetDir/tex-svg.js');
    final mermaid = await loadAsset('$_assetDir/mermaid.min.js');
    final css = theme == null ? _baseCss : await _themedCss(theme);

    final sections = StringBuffer();
    for (final slide in marpSlides(deckMarkdown)) {
      sections
        ..write('<section class="slide"><script type="text/markdown">')
        ..write(_guard(renderChartBlocks(slide, theme: theme)))
        ..write('</script></section>');
    }

    String inline(String code) => '<script>${_guard(code)}</script>';

    final meta = metadata ?? const ExportDocumentMetadata();
    final title = _htmlAttr(meta.displayTitle(fallbackTitle));
    final headMeta = _htmlHeadMeta(meta, fallbackTitle: fallbackTitle);
    final banner = meta.htmlClassification == null
        ? ''
        : '<div class="tlp-export-banner">${_htmlAttr(meta.htmlClassification!)}</div>';

    return '<!doctype html>\n'
        '<html lang="nl"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<title>$title</title>'
        '$headMeta'
        '<style>$css\n$hljsCss</style>'
        '<script>$_mathjaxConfig</script>'
        '${inline(marked)}'
        '${inline(purify)}'
        '${inline(hljs)}'
        '${inline(mathjax)}'
        '${inline(mermaid)}'
        '</head><body>'
        '$banner'
        '$sections'
        '${inline(_renderScript)}'
        '</body></html>';
  }

  /// Split Marp Markdown into per-slide Markdown chunks: drop the leading YAML
  /// front-matter, then break on lines that contain only `---`.
  static List<String> marpSlides(String markdown) {
    var text = markdown.replaceAll('\r\n', '\n');
    // Strip a leading YAML front-matter block: ---\n ... \n---\n
    if (text.startsWith('---\n')) {
      final close = text.indexOf('\n---', 4);
      if (close != -1) {
        final nl = text.indexOf('\n', close + 1);
        text = nl == -1 ? '' : text.substring(nl + 1);
      }
    }
    final slides = <String>[];
    final buf = StringBuffer();
    for (final line in text.split('\n')) {
      if (line.trim() == '---') {
        slides.add(buf.toString().trim());
        buf.clear();
      } else {
        buf.writeln(line);
      }
    }
    slides.add(buf.toString().trim());
    return slides.where((s) => s.isNotEmpty).toList();
  }

  /// Neutralise any `</script` inside inlined content so it can't break out of
  /// the surrounding <script> element. Case-insensitive — `</ScRiPt>` must not
  /// slip through. Safe for both JS (string contexts) and the embedded Markdown
  /// payloads.
  static final RegExp _scriptClose = RegExp(
    r'</(script)',
    caseSensitive: false,
  );

  static String _guard(String s) =>
      s.replaceAllMapped(_scriptClose, (m) => '<\\/${m.group(1)}');

  // ── Charts → inline SVG ────────────────────────────────────────────────────

  static final RegExp _chartFence = RegExp(
    r'```chart[ \t]*\n([\s\S]*?)\n```',
    multiLine: true,
  );

  /// Replace ```chart fenced blocks with a self-contained inline SVG, so the
  /// exported HTML renders charts without any JS chart library.
  static String renderChartBlocks(String slideMarkdown, {ThemeProfile? theme}) {
    return slideMarkdown.replaceAllMapped(_chartFence, (m) {
      final spec = ChartSpec.parse(m.group(1)!);
      return '\n<div class="chart">${_chartSvg(spec, theme)}</div>\n';
    });
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _color(ChartSpec spec, int i, ThemeProfile? theme) {
    final series = spec.series[i];
    if (series.color == null && i == 0 && theme != null) {
      return theme.accentColor;
    }
    return chartSeriesColor(series, i);
  }

  static String _chartSvg(ChartSpec spec, ThemeProfile? theme) {
    if (!spec.hasInlineData) {
      return '<svg viewBox="0 0 800 450" xmlns="http://www.w3.org/2000/svg"></svg>';
    }
    final textColor = theme?.textColor ?? '#111827';
    final titleBackground = theme?.titleBackgroundColor ?? '#F8FAFC';
    final titleColor = theme?.titleTextColor ?? textColor;
    final accent = theme?.accentColor ?? '#2563EB';
    final b = StringBuffer()
      ..write(
        '<svg viewBox="0 0 800 450" xmlns="http://www.w3.org/2000/svg" '
        'font-family="inherit" width="100%">',
      );
    if (spec.title.isNotEmpty) {
      final title = spec.title.length > 52
          ? '${spec.title.substring(0, 51)}…'
          : spec.title;
      b
        ..write(
          '<rect x="38" y="12" width="724" height="44" rx="9" '
          'fill="$titleBackground"/>',
        )
        ..write(
          '<rect x="38" y="12" width="7" height="44" rx="3" fill="$accent"/>',
        )
        ..write(
          '<text x="62" y="41" font-size="23" font-weight="bold" '
          'fill="$titleColor">${_esc(title)}</text>',
        );
    }
    final plotTop = spec.title.isNotEmpty ? 68.0 : 20.0;
    switch (spec.type) {
      case ChartType.bar:
        _barSvg(b, spec, plotTop, theme);
      case ChartType.line:
        _lineSvg(b, spec, plotTop, theme);
      case ChartType.pie:
        final legendRows = (spec.x.length / 6).ceil().clamp(1, 3);
        _pieSvg(b, spec, plotTop, theme, bottom: 398 - (legendRows - 1) * 28);
      case ChartType.radar:
        _radarSvg(b, spec, plotTop, theme, textColor);
    }
    if (spec.type == ChartType.pie) {
      _pieLegendSvg(b, spec, textColor);
    } else {
      _legendSvg(b, spec, theme, textColor);
    }
    b.write('</svg>');
    return b.toString();
  }

  static void _legendSvg(
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
      final name = rawName.length > 12
          ? '${rawName.substring(0, 11)}…'
          : rawName;
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

  static void _pieLegendSvg(StringBuffer b, ChartSpec spec, String textColor) {
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

  static double _maxY(ChartSpec spec) {
    var m = 0.0;
    for (final s in spec.series) {
      for (final v in s.data) {
        if (v > m) m = v;
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
  static void _boundLinesSvg(
    StringBuffer b,
    ChartSpec spec,
    double left,
    double top,
    double right,
    double bottom,
    double maxY,
  ) {
    if (!spec.supportsBoundLines) return;
    void draw(double? value, String color, String prefix) {
      if (value == null || value < 0 || value > maxY) return;
      final y = bottom - (bottom - top) * (value / maxY);
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

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  static void _axes(
    StringBuffer b,
    ChartSpec spec,
    double left,
    double top,
    double right,
    double bottom,
    double maxY,
  ) {
    // Horizontal gridlines + y labels.
    for (var i = 0; i <= 4; i++) {
      final y = bottom - (bottom - top) * i / 4;
      final val = maxY * i / 4;
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

  static void _barSvg(
    StringBuffer b,
    ChartSpec spec,
    double top,
    ThemeProfile? theme,
  ) {
    const left = 60.0, right = 770.0, bottom = 382.0;
    final maxY = _maxY(spec);
    _axes(b, spec, left, top, right, bottom, maxY);
    final n = spec.x.length;
    final groupW = (right - left) / n;
    final sCount = spec.series.length;
    final barW = (groupW * 0.7) / sCount;
    for (var xi = 0; xi < n; xi++) {
      final gx = left + groupW * xi + groupW * 0.15;
      for (var si = 0; si < sCount; si++) {
        if (xi >= spec.series[si].data.length) continue;
        final v = spec.series[si].data[xi];
        final h = (bottom - top) * (v / maxY);
        final x = gx + barW * si;
        b.write(
          '<rect x="$x" y="${bottom - h}" width="${barW * 0.86}" height="$h" '
          'rx="5" fill="${_color(spec, si, theme)}"/>',
        );
      }
    }
    _boundLinesSvg(b, spec, left, top, right, bottom, maxY);
  }

  static void _lineSvg(
    StringBuffer b,
    ChartSpec spec,
    double top,
    ThemeProfile? theme,
  ) {
    const left = 60.0, right = 770.0, bottom = 382.0;
    final maxY = _maxY(spec);
    _axes(b, spec, left, top, right, bottom, maxY);
    final n = spec.x.length;
    double px(int i) => left + (right - left) * (i + 0.5) / n;
    double py(double v) => bottom - (bottom - top) * (v / maxY);
    for (var si = 0; si < spec.series.length; si++) {
      final data = spec.series[si].data;
      final pts = [
        for (var i = 0; i < data.length; i++) '${px(i)},${py(data[i])}',
      ].join(' ');
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
    _boundLinesSvg(b, spec, left, top, right, bottom, maxY);
  }

  static void _pieSvg(
    StringBuffer b,
    ChartSpec spec,
    double top,
    ThemeProfile? theme, {
    required double bottom,
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
      b
        ..write('<circle cx="$cx" cy="$cy" r="${radius * 0.43}" fill="white"/>')
        ..write(
          '<text x="${cellLeft + cellWidth * 0.66}" y="${cy + 5}" '
          'font-size="14" font-weight="700">'
          '${_esc(_shortChartLabel(series.name.isEmpty ? 'Reeks ${xi + 1}' : series.name))}</text>',
        );
    }
  }

  static void _radarSvg(
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
        'stroke="$color" stroke-width="3" stroke-linejoin="round"/>',
      );
    }
  }

  /// Radar scale shared with the live preview: honour optional min/max bounds,
  /// otherwise round the data range to a tidy scale with an even tick count.
  static (double, double, int) _radarScale(ChartSpec spec) {
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
    final lo = spec.minBound ?? (rawLo / step).floorToDouble() * step;
    var hi = spec.maxBound ?? (rawHi / step).ceilToDouble() * step;
    if (hi <= lo) hi = lo + step;
    final ticks = math.max(2, ((hi - lo) / step).round());
    return (lo, hi, ticks);
  }

  static String _shortChartLabel(String value) =>
      value.length > 13 ? '${value.substring(0, 12)}…' : value;

  /// CSS that mirrors the deck's [ThemeProfile]: slide background, text and
  /// accent colours, table colours and font. The EB Garamond font is embedded
  /// (base64) so it renders offline; other fonts resolve to system families.
  Future<String> _themedCss(ThemeProfile t) async {
    final fontFace = await _ebGaramondFontFace(t.fontFamily);
    final family = _cssFontStack(t.fontFamily);
    final codePrefix = t.codeFontFamily == 'monospace'
        ? ''
        : "'${t.codeFontFamily}',";
    final codeFamily =
        '${codePrefix}SFMono-Regular,Consolas,"Liberation Mono",monospace';
    return '$fontFace\n'
        '*{box-sizing:border-box}'
        'html,body{margin:0;padding:0}'
        'body{background:#1e1e1e;font-family:$family;color:${t.textColor}}'
        '.slide{position:relative;width:1280px;min-height:720px;margin:24px auto;'
        'background:${t.slideBackgroundColor};color:${t.textColor};padding:60px;'
        'overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,.4);border-radius:4px;'
        'font-family:$family}'
        '.slide h1{font-size:48px;margin:.15em 0;color:${t.textColor}}'
        '.slide h2{font-size:34px;margin:.15em 0;color:${t.accentColor}}'
        '.slide a{color:${t.accentColor}}'
        '.slide p,.slide li{font-size:24px;line-height:1.45}'
        '.slide pre{background:${t.codeBackgroundColor};color:${t.codeTextColor};'
        'border:1px solid ${t.codeTextColor}38;border-radius:6px;'
        'padding:16px;overflow:auto;font-size:18px;font-family:$codeFamily}'
        '.slide pre code{color:${t.codeTextColor};background:transparent}'
        '.slide code{font-family:$codeFamily}'
        '.slide pre.mermaid{background:transparent;border:0;text-align:center}'
        '.slide img{max-width:100%}'
        '.slide blockquote{border-left:4px solid ${t.accentColor};margin:.5em 0;'
        'padding-left:16px;opacity:.85}'
        '.slide table{border-collapse:collapse}'
        '.slide th{background:${t.tableHeaderBackgroundColor};color:${t.tableHeaderTextColor};'
        'border:1px solid #ccc;padding:6px 12px;font-size:20px}'
        '.slide td{color:${t.tableTextColor};border:1px solid #ccc;padding:6px 12px;font-size:20px}'
        '@media print{body{background:#fff}.slide{margin:0;box-shadow:none;'
        'border-radius:0;page-break-after:always;width:100%;min-height:100vh}}';
  }

  String _cssFontStack(String font) {
    if (font == 'EB Garamond') return "'EB Garamond', Georgia, serif";
    const serif = {'Georgia', 'Times New Roman'};
    final generic = serif.contains(font) ? 'serif' : 'sans-serif';
    return "'$font', $generic";
  }

  /// Embed the bundled EB Garamond variable font as base64 so it works offline.
  /// Returns an empty string for any other (system) font.
  Future<String> _ebGaramondFontFace(String font) async {
    if (font != 'EB Garamond') return '';
    try {
      final bytes = await loadBytes('assets/fonts/EBGaramond-Variable.ttf');
      final b64 = base64Encode(bytes);
      return "@font-face{font-family:'EB Garamond';font-weight:400 800;"
          "font-style:normal;src:url(data:font/ttf;base64,$b64) "
          "format('truetype');}";
    } catch (e) {
      logWarning('MarpHtmlService._ebGaramondFontFace: load font asset', e);
      return ''; // Fall back to the CSS font stack if the asset is missing.
    }
  }

  static const _mathjaxConfig =
      r'''window.MathJax={tex:{inlineMath:[['$','$']],displayMath:[['$$','$$']]},svg:{fontCache:'global'},startup:{typeset:false}};''';

  static const _baseCss = r'''
*{box-sizing:border-box}
html,body{margin:0;padding:0}
body{background:#1e1e1e;font-family:-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;color:#1a1a1a}
.slide{position:relative;width:1280px;min-height:720px;margin:24px auto;background:#fff;padding:60px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,.4);border-radius:4px}
.slide h1{font-size:48px;margin:.15em 0}
.slide h2{font-size:34px;margin:.15em 0}
.slide p,.slide li{font-size:24px;line-height:1.45}
.slide pre{background:#f6f8fa;border:1px solid #e1e4e8;border-radius:6px;padding:16px;overflow:auto;font-size:18px}
.slide code{font-family:SFMono-Regular,Consolas,"Liberation Mono",monospace}
.slide pre.mermaid{background:transparent;border:0;text-align:center}
.slide img{max-width:100%}
.slide blockquote{border-left:4px solid #ccc;margin:.5em 0;padding-left:16px;color:#555}
.slide table{border-collapse:collapse}.slide th,.slide td{border:1px solid #ccc;padding:6px 12px;font-size:20px}
.tlp-export-banner{position:fixed;top:0;left:0;right:0;background:#000;color:#ffc000;text-align:center;font:700 14px/2.4 monospace;z-index:9999;letter-spacing:.06em}
@media print{body{background:#fff}.slide{margin:0;box-shadow:none;border-radius:0;page-break-after:always;width:100%;min-height:100vh}}
''';

  static String _htmlAttr(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;');
  }

  static String _htmlHeadMeta(
    ExportDocumentMetadata meta, {
    required String fallbackTitle,
  }) {
    final buf = StringBuffer();
    void tag(String name, String content) {
      if (content.trim().isEmpty) return;
      buf.write('<meta name="$name" content="${_htmlAttr(content)}">');
    }

    tag('author', meta.documentAuthor);
    tag('keywords', meta.exportKeywords());
    final desc = meta.htmlDescription;
    if (desc != null) tag('description', desc);
    final classification = meta.htmlClassification;
    if (classification != null) {
      tag('classification', classification);
      tag('tlp', meta.tlp.key);
    }
    tag('generator', meta.producer);
    return buf.toString();
  }

  static const _renderScript = r'''
(function(){
  if(window.marked&&marked.setOptions){marked.setOptions({gfm:true,breaks:false});}
  document.querySelectorAll('section.slide').forEach(function(sec){
    var holder=sec.querySelector('script[type="text/markdown"]');
    var src=holder?holder.textContent:'';
    var div=document.createElement('div');div.className='content';
    var html=window.marked?marked.parse(src):src;
    // Sanitise rendered Markdown before it touches the DOM: a deck must not be
    // able to run script/onerror/javascript: payloads when the export is opened.
    // If the sanitiser somehow isn't present, fail closed to plain text.
    if(window.DOMPurify){div.innerHTML=DOMPurify.sanitize(html);}else{div.textContent=src;}
    sec.innerHTML='';sec.appendChild(div);
  });
  document.querySelectorAll('code.language-mermaid').forEach(function(code){
    var pre=code.closest('pre');if(!pre)return;
    var holder=document.createElement('pre');holder.className='mermaid';
    holder.textContent=code.textContent;pre.replaceWith(holder);
  });
  if(window.hljs){document.querySelectorAll('pre code').forEach(function(el){try{hljs.highlightElement(el);}catch(e){}});}
  if(window.mermaid){try{mermaid.initialize({startOnLoad:false});mermaid.run();}catch(e){}}
  if(window.MathJax&&MathJax.typesetPromise){MathJax.typesetPromise();}
})();
''';
}
