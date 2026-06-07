import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../models/chart.dart';
import '../models/settings.dart';

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
  Future<String> build(String deckMarkdown, {ThemeProfile? theme}) async {
    final marked = await loadAsset('$_assetDir/marked.min.js');
    final hljs = await loadAsset('$_assetDir/highlight.min.js');
    final hljsCss = await loadAsset('$_assetDir/highlight.css');
    final mathjax = await loadAsset('$_assetDir/tex-svg.js');
    final mermaid = await loadAsset('$_assetDir/mermaid.min.js');
    final css = theme == null ? _baseCss : await _themedCss(theme);

    final sections = StringBuffer();
    for (final slide in marpSlides(deckMarkdown)) {
      sections
        ..write('<section class="slide"><script type="text/markdown">')
        ..write(_guard(renderChartBlocks(slide)))
        ..write('</script></section>');
    }

    String inline(String code) => '<script>${_guard(code)}</script>';

    return '<!doctype html>\n'
        '<html lang="nl"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<title>OciDeck export</title>'
        '<style>$css\n$hljsCss</style>'
        '<script>$_mathjaxConfig</script>'
        '${inline(marked)}'
        '${inline(hljs)}'
        '${inline(mathjax)}'
        '${inline(mermaid)}'
        '</head><body>'
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
  /// the surrounding <script> element. Safe for both JS (string contexts) and
  /// the embedded Markdown payloads.
  static String _guard(String s) => s
      .replaceAll('</script', r'<\/script')
      .replaceAll('</SCRIPT', r'<\/SCRIPT');

  // ── Charts → inline SVG ────────────────────────────────────────────────────

  static final RegExp _chartFence = RegExp(
    r'```chart[ \t]*\n([\s\S]*?)\n```',
    multiLine: true,
  );

  static const List<String> _chartPalette = [
    '#2563EB',
    '#F59E0B',
    '#10B981',
    '#EF4444',
    '#8B5CF6',
    '#06B6D4',
    '#EC4899',
    '#84CC16',
  ];

  /// Replace ```chart fenced blocks with a self-contained inline SVG, so the
  /// exported HTML renders charts without any JS chart library.
  static String renderChartBlocks(String slideMarkdown) {
    return slideMarkdown.replaceAllMapped(_chartFence, (m) {
      final spec = ChartSpec.parse(m.group(1)!);
      return '\n<div class="chart">${_chartSvg(spec)}</div>\n';
    });
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _color(int i) => _chartPalette[i % _chartPalette.length];

  static String _chartSvg(ChartSpec spec) {
    if (!spec.hasInlineData) {
      return '<svg viewBox="0 0 800 450" xmlns="http://www.w3.org/2000/svg"></svg>';
    }
    final b = StringBuffer()
      ..write(
        '<svg viewBox="0 0 800 450" xmlns="http://www.w3.org/2000/svg" '
        'font-family="inherit" width="100%">',
      );
    if (spec.title.isNotEmpty) {
      b.write(
        '<text x="400" y="34" text-anchor="middle" font-size="26" '
        'font-weight="bold" fill="#111">${_esc(spec.title)}</text>',
      );
    }
    // Legend (multi-series, non-pie).
    final top = spec.title.isNotEmpty ? 56.0 : 24.0;
    var plotTop = top;
    if (spec.type != ChartType.pie && spec.series.length > 1) {
      var lx = 60.0;
      for (var i = 0; i < spec.series.length; i++) {
        b
          ..write(
            '<rect x="$lx" y="${top + 2}" width="14" height="14" rx="3" fill="${_color(i)}"/>',
          )
          ..write(
            '<text x="${lx + 20}" y="${top + 14}" font-size="16" fill="#333">${_esc(spec.series[i].name)}</text>',
          );
        lx += 30 + spec.series[i].name.length * 9 + 24;
      }
      plotTop = top + 28;
    }
    switch (spec.type) {
      case ChartType.bar:
        _barSvg(b, spec, plotTop);
      case ChartType.line:
        _lineSvg(b, spec, plotTop);
      case ChartType.pie:
        _pieSvg(b, spec, plotTop);
    }
    b.write('</svg>');
    return b.toString();
  }

  static double _maxY(ChartSpec spec) {
    var m = 0.0;
    for (final s in spec.series) {
      for (final v in s.data) {
        if (v > m) m = v;
      }
    }
    return m <= 0 ? 1 : m * 1.15;
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
    for (var i = 0; i < n; i++) {
      final x = left + (right - left) * (i + 0.5) / n;
      b.write(
        '<text x="$x" y="${bottom + 22}" text-anchor="middle" font-size="14" fill="#334155">${_esc(spec.x[i])}</text>',
      );
    }
  }

  static void _barSvg(StringBuffer b, ChartSpec spec, double top) {
    const left = 60.0, right = 770.0, bottom = 400.0;
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
          '<rect x="$x" y="${bottom - h}" width="${barW * 0.92}" height="$h" rx="2" fill="${_color(si)}"/>',
        );
      }
    }
  }

  static void _lineSvg(StringBuffer b, ChartSpec spec, double top) {
    const left = 60.0, right = 770.0, bottom = 400.0;
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
        '<polyline points="$pts" fill="none" stroke="${_color(si)}" stroke-width="3"/>',
      );
      for (var i = 0; i < data.length; i++) {
        b.write(
          '<circle cx="${px(i)}" cy="${py(data[i])}" r="4" fill="${_color(si)}"/>',
        );
      }
    }
  }

  static void _pieSvg(StringBuffer b, ChartSpec spec, double top) {
    final series = spec.series.first;
    final total = series.data.fold<double>(0, (a, v) => a + v);
    const cx = 250.0, cy = 240.0, r = 150.0;
    var angle = -90.0; // start at top
    for (var i = 0; i < series.data.length; i++) {
      final frac = total > 0 ? series.data[i] / total : 0;
      final sweep = frac * 360;
      final a0 = angle * math.pi / 180;
      final a1 = (angle + sweep) * math.pi / 180;
      final x0 = cx + r * math.cos(a0), y0 = cy + r * math.sin(a0);
      final x1 = cx + r * math.cos(a1), y1 = cy + r * math.sin(a1);
      final large = sweep > 180 ? 1 : 0;
      b.write(
        '<path d="M$cx,$cy L$x0,$y0 A$r,$r 0 $large,1 $x1,$y1 Z" fill="${_color(i)}"/>',
      );
      angle += sweep;
    }
    // Legend on the right.
    var ly = 120.0;
    for (var i = 0; i < spec.x.length && i < series.data.length; i++) {
      b
        ..write(
          '<rect x="520" y="$ly" width="16" height="16" rx="3" fill="${_color(i)}"/>',
        )
        ..write(
          '<text x="544" y="${ly + 13}" font-size="16" fill="#333">${_esc(spec.x[i])}</text>',
        );
      ly += 28;
    }
  }

  /// CSS that mirrors the deck's [ThemeProfile]: slide background, text and
  /// accent colours, table colours and font. The EB Garamond font is embedded
  /// (base64) so it renders offline; other fonts resolve to system families.
  Future<String> _themedCss(ThemeProfile t) async {
    final fontFace = await _ebGaramondFontFace(t.fontFamily);
    final family = _cssFontStack(t.fontFamily);
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
        '.slide pre{background:#f6f8fa;border:1px solid #e1e4e8;border-radius:6px;'
        'padding:16px;overflow:auto;font-size:18px}'
        '.slide code{font-family:SFMono-Regular,Consolas,"Liberation Mono",monospace}'
        '.slide pre.mermaid{background:transparent;border:0;text-align:center}'
        '.slide img{max-width:100%}'
        '.slide blockquote{border-left:4px solid ${t.accentColor};margin:.5em 0;'
        'padding-left:16px;opacity:.85}'
        '.slide table{border-collapse:collapse}'
        '.slide th{background:${t.sectionBackgroundColor};color:${t.tableHeaderTextColor};'
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
    } catch (_) {
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
@media print{body{background:#fff}.slide{margin:0;box-shadow:none;border-radius:0;page-break-after:always;width:100%;min-height:100vh}}
''';

  static const _renderScript = r'''
(function(){
  if(window.marked&&marked.setOptions){marked.setOptions({gfm:true,breaks:false});}
  document.querySelectorAll('section.slide').forEach(function(sec){
    var holder=sec.querySelector('script[type="text/markdown"]');
    var src=holder?holder.textContent:'';
    var div=document.createElement('div');div.className='content';
    div.innerHTML=window.marked?marked.parse(src):src;
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
