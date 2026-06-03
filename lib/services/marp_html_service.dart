import 'package:flutter/services.dart' show rootBundle;

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
  /// Reads a bundled asset (defaults to the Flutter asset bundle). Injectable so
  /// the builder can be unit-tested against the on-disk asset files.
  final Future<String> Function(String asset) loadAsset;

  MarpHtmlService({Future<String> Function(String asset)? loadAsset})
    : loadAsset = loadAsset ?? rootBundle.loadString;

  static const _assetDir = 'assets/web_export';

  Future<String> build(String deckMarkdown) async {
    final marked = await loadAsset('$_assetDir/marked.min.js');
    final hljs = await loadAsset('$_assetDir/highlight.min.js');
    final hljsCss = await loadAsset('$_assetDir/highlight.css');
    final mathjax = await loadAsset('$_assetDir/tex-svg.js');
    final mermaid = await loadAsset('$_assetDir/mermaid.min.js');

    final sections = StringBuffer();
    for (final slide in marpSlides(deckMarkdown)) {
      sections
        ..write('<section class="slide"><script type="text/markdown">')
        ..write(_guard(slide))
        ..write('</script></section>');
    }

    String inline(String code) => '<script>${_guard(code)}</script>';

    return '<!doctype html>\n'
        '<html lang="nl"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<title>OciDeck export</title>'
        '<style>$_baseCss\n$hljsCss</style>'
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
