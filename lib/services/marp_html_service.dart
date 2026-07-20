import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../models/chart.dart';
import '../models/cockpit.dart';
import '../models/question.dart';
import '../models/deck.dart';
import '../models/settings.dart';
import '../utils/log.dart';
import 'export_metadata.dart';

part 'parts/marp_html_service_cockpit.dart';
part 'parts/marp_html_service_charts.dart';
part 'parts/marp_html_service_charts_radial.dart';
part 'parts/marp_html_service_charts_bullet.dart';

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
  }) : loadAsset = loadAsset ?? _cachedLoadString,
       loadBytes = loadBytes ?? _cachedLoadBytes,
       _usesDefaultBytesLoader = loadBytes == null;

  /// Of [loadBytes] de default (rootBundle) is; alleen dan mag de statische
  /// font-face-cache worden gebruikt, zodat tests met een geïnjecteerde loader
  /// geen resultaat van een eerdere run terugkrijgen.
  final bool _usesDefaultBytesLoader;

  // Bundel-assets zijn immutable; cache ze over exports heen (de service wordt
  // per export opnieuw geconstrueerd, dus dit moet static). Alleen de default
  // loaders cachen — geïnjecteerde testloaders blijven elke keer draaien.
  static final _assetTextCache = <String, String>{};
  static final _assetBytesCache = <String, Uint8List>{};

  static Future<String> _cachedLoadString(String asset) async =>
      _assetTextCache[asset] ??= await rootBundle.loadString(asset);

  static Future<Uint8List> _cachedLoadBytes(String asset) async =>
      _assetBytesCache[asset] ??= (await rootBundle.load(
        asset,
      )).buffer.asUint8List();

  static const _assetDir = 'assets/web_export';

  /// Builds the HTML. When [theme] is given, the slides take that profile's
  /// colours and font so the export matches the in-app / PDF look.
  Future<String> build(
    String deckMarkdown, {
    ThemeProfile? theme,
    CockpitColorScheme cockpitColorScheme = CockpitColorScheme.standard,
    ExportDocumentMetadata? metadata,
    String fallbackTitle = 'Presentatie',
  }) async {
    // De zes bundel-assets en de themed CSS zijn onafhankelijk; sequentieel
    // wachten stapelde hun laadtijden op.
    final [
      marked,
      purify,
      hljs,
      hljsCss,
      mathjax,
      mermaid,
      css,
    ] = await Future.wait([
      loadAsset('$_assetDir/marked.min.js'),
      loadAsset('$_assetDir/purify.min.js'),
      loadAsset('$_assetDir/highlight.min.js'),
      loadAsset('$_assetDir/highlight.css'),
      loadAsset('$_assetDir/tex-svg.js'),
      loadAsset('$_assetDir/mermaid.min.js'),
      theme == null ? Future.value(_baseCss) : _themedCss(theme),
    ]);

    // Per-export CSP nonce. Every executable <script> we emit carries it; the
    // CSP then allows only nonce'd scripts, so an injected inline <script> that
    // somehow survives DOMPurify can't execute when the file is opened. The
    // per-slide `<script type="text/markdown">` data holders are inert (never
    // executed) and intentionally carry no nonce.
    final rng = math.Random.secure();
    final nonce = base64.encode(
      List<int>.generate(16, (_) => rng.nextInt(256)),
    );

    final sections = StringBuffer();
    for (final slide in marpSlides(deckMarkdown)) {
      final renderedBlocks = renderCockpitBlocks(
        renderQuestionBlocks(renderChartBlocks(slide, theme: theme)),
        theme: theme,
        scheme: cockpitColorScheme,
      );
      final markerClass = _bulletMarkerSectionClass(slide);
      final titleColorStyle = _titleColorSectionStyle(slide);
      sections
        ..write('<section class="slide$markerClass"$titleColorStyle>')
        ..write('<script type="text/markdown">')
        ..write(_guardMarkdown(renderedBlocks))
        ..write('</script></section>');
    }

    String inline(String code) =>
        '<script nonce="$nonce">${_guardScript(code)}</script>';

    final meta = metadata ?? const ExportDocumentMetadata();
    final title = _htmlAttr(meta.displayTitle(fallbackTitle));
    final headMeta = _htmlHeadMeta(meta, fallbackTitle: fallbackTitle);
    final banner = meta.htmlClassification == null
        ? ''
        : '<div class="tlp-export-banner">${_htmlAttr(meta.htmlClassification!)}</div>';

    return '<!doctype html>\n'
        '<html lang="nl"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        // Neutralise injected inline scripts (defence-in-depth behind DOMPurify)
        // without over-restricting style, which would break locally opened
        // exports. No default-src: the inline <style> block must keep working
        // (adding one would force 'unsafe-inline' for style). Instead every
        // network-capable resource type is pinned to local sources so nothing a
        // crafted deck smuggles past DOMPurify can beacon home when the file is
        // opened: connect-src 'none' (fetch/XHR/beacon), img-src/media-src
        // self/data/blob/file (a surviving <img>/<video src="https://…">),
        // font-src self/data (a hostile @font-face url()), and form-action
        // 'none' (a planted <form action="https://…"> on submit). MathJax is
        // tex-svg (no web fonts) and the bundled theme/highlight CSS carry no
        // url()/@font-face, so these limits never bite a legitimate export.
        '<meta http-equiv="Content-Security-Policy" '
        'content="script-src \'nonce-$nonce\'; object-src \'none\'; '
        'base-uri \'none\'; frame-src \'none\'; form-action \'none\'; '
        'img-src \'self\' data: blob: file:; '
        'media-src \'self\' data: blob: file:; font-src \'self\' data:; '
        'connect-src \'none\'">'
        '<title>$title</title>'
        '$headMeta'
        '<style>$css\n$hljsCss</style>'
        '<script nonce="$nonce">$_mathjaxConfig</script>'
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

  static final RegExp _listStyleComment = RegExp(
    r'<!--\s*ocideck_list_style:\s*(\w+)',
  );
  static final RegExp _bulletMarkerComment = RegExp(
    r'<!--\s*ocideck_bullet_marker:\s*(\w+)',
  );

  /// Strict hex so the matched value can never break out of the `style`
  /// attribute it is written into (see [_titleColorSectionStyle]).
  static final RegExp _titleColorComment = RegExp(
    r'<!--\s*ocideck_title_text_color:\s*(#[0-9A-Fa-f]{3,8})',
  );

  /// Inline style carrying a title slide's per-slide title-text-colour override
  /// (`ocideck_title_text_color`) as a CSS custom property, or `''` when the
  /// slide sets none. The title `h1` reads this variable (with the theme's title
  /// colour as fallback), so a slide that dims or lightens its title for a busy
  /// background image keeps that choice in the HTML export — matching the app
  /// preview, presenter and PDF/PPTX, which already honour the override.
  static String _titleColorSectionStyle(String slideMarkdown) {
    final hex = _titleColorComment.firstMatch(slideMarkdown)?.group(1);
    return hex == null ? '' : ' style="--ocideck-title-color:$hex"';
  }

  /// Extra `<section>` class that turns this slide's plain bullets into cat-paw
  /// markers (` paw-bullets`), or `''`. The decision is taken entirely from the
  /// `ocideck_bullet_marker` comment that the *export* markdown carries for
  /// every paw-rendering bullet slide (see `MarkdownService`, `forExport`). A
  /// free-markdown slide that merely contains a `-` list never carries that
  /// comment, so it never gets a paw — keeping HTML, app and PDF/PPTX identical.
  /// Numbered, checklist and rich-text slides keep their own markers.
  static String _bulletMarkerSectionClass(String slideMarkdown) {
    final style = _listStyleComment.firstMatch(slideMarkdown)?.group(1);
    if (style == 'numbered' || style == 'checklist' || style == 'richText') {
      return '';
    }
    final marker = _bulletMarkerComment.firstMatch(slideMarkdown)?.group(1);
    return marker == BulletMarker.paw.name ? ' paw-bullets' : '';
  }

  /// A self-contained cat-paw as an inline SVG `data:` URI, with [accent] baked
  /// in as the fill. Used as the `li::before` marker for paw bullet lists. The
  /// whole SVG is percent-encoded, so the (theme-controlled) colour value can
  /// never break out of the attribute.
  static String _pawDataUri(String accent) {
    const path =
        "M8 9.28Q12.64 9.28 10.32 12.4Q8 15.52 5.68 12.4Q3.36 9.28 8 9.28Z";
    final svg =
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'>"
        "<path d='$path' fill='$accent'/>"
        "<ellipse cx='2.56' cy='6.88' rx='1.76' ry='2.4' fill='$accent' transform='rotate(-31.5 2.56 6.88)'/>"
        "<ellipse cx='6.24' cy='3.36' rx='1.92' ry='2.8' fill='$accent' transform='rotate(-10.3 6.24 3.36)'/>"
        "<ellipse cx='9.76' cy='3.36' rx='1.92' ry='2.8' fill='$accent' transform='rotate(10.3 9.76 3.36)'/>"
        "<ellipse cx='13.44' cy='6.88' rx='1.76' ry='2.4' fill='$accent' transform='rotate(31.5 13.44 6.88)'/>"
        "</svg>";
    return 'data:image/svg+xml,${Uri.encodeComponent(svg)}';
  }

  /// Neutralise any `</script` inside inlined content so it can't break out of
  /// the surrounding <script> element. Case-insensitive — `</ScRiPt>` must not
  /// slip through. Safe for both JS (string contexts) and the embedded Markdown
  /// payloads.
  static final RegExp _scriptClose = RegExp(
    r'</(script)',
    caseSensitive: false,
  );

  /// Maakt [s] veilig als inhoud van een `<script type="text/markdown">`.
  ///
  /// `</script` is niet de enige uitgang. De HTML-tokenizer kent binnen een
  /// script-element ook *script data escaped*: een `<!--` zet hem in die stand,
  /// en een daaropvolgende `<script` in *double escaped* — en dáár sluit een
  /// echte `</script>` het element níét meer, hij zet alleen één stand terug.
  /// Alles erna wordt scripttekst: de rest van de dia's, én het renderscript dat
  /// de markdown-houders pas zichtbaar maakt. De export opende dan als een lege
  /// witte pagina, zonder enige foutmelding.
  ///
  /// Dat is geen exotische invoer. Een codedia die kwetsbare paginabron citeert
  /// — precies wat een pentestrapport doet — bevat routineus een uitgezette
  /// `<script>` in commentaar. In de app, de presenter en de PDF klopte die dia.
  ///
  /// Het renderscript draait de ontsnapping terug vóórdat marked de tekst ziet
  /// (zie [_renderScript]). Zonder die terugdraai zou een `<!-- _class: … -->`
  /// als zichtbare tekst mét backslash in het document belanden — en dat was al
  /// het geval voor `</script`, dat werd ontsnapt maar nooit hersteld.
  static String _guardMarkdown(String s) =>
      _guardScript(s).replaceAll('<!--', r'<\!--');

  /// Neutraliseert `</script` in échte JavaScript.
  ///
  /// Hier bewust géén `<!--`-behandeling: in JavaScript is `<!--` een geldige
  /// (legacy) regelcommentaar en `<\!--` een syntaxfout, dus die ontsnapping
  /// zou de gebundelde bibliotheken slopen. Nodig is het ook niet — deze code is
  /// vendored en vast, geen inhoud uit een deck.
  static String _guardScript(String s) =>
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

  // ── Question → HTML ───────────────────────────────────────────────────────

  static final RegExp _questionFence = RegExp(
    r'```question[ \t]*\n([\s\S]*?)\n```',
    multiLine: true,
  );

  /// Vervangt een ```question-blok door de vraag met zijn antwoordopties.
  ///
  /// Zonder deze stap viel het blok terug op de gewone codeweergave van marked,
  /// en stond de hele specificatie leesbaar op de dia — inclusief
  /// `"correct": true`, in de volgorde waarin de antwoorden zijn ingevoerd. Wie
  /// een quizdeck als HTML rondstuurde, deelde de antwoordsleutel mee. In de app
  /// ziet de auteur een nette vraagkaart, dus er was niets aan te merken.
  ///
  /// De export is een leesbaar document, geen quiz: er valt niets te klikken en
  /// niets af te tellen. Daarom de vraag en de opties, en het goede antwoord
  /// juist niet — dat is de enige informatie die hier niet thuishoort.
  static String renderQuestionBlocks(String slideMarkdown) {
    return slideMarkdown.replaceAllMapped(_questionFence, (m) {
      final spec = QuestionSpec.parse(m.group(1)!);
      final b = StringBuffer('\n<div class="question">');
      if (spec.prompt.trim().isNotEmpty) {
        b.write('<p class="question-prompt">${_htmlText(spec.prompt)}</p>');
      }
      final options = spec.kind == QuestionKind.trueFalse
          ? const ['Waar', 'Niet waar']
          : [
              for (final a in spec.answers)
                if (a.text.trim().isNotEmpty) a.text,
            ];
      if (options.isNotEmpty) {
        b.write('<ul class="question-options">');
        for (final o in options) {
          b.write('<li>${_htmlText(o)}</li>');
        }
        b.write('</ul>');
      }
      b.write('</div>\n');
      return b.toString();
    });
  }

  /// Tekst als HTML-inhoud: alleen de drie tekens die de parser van gedachten
  /// doen veranderen. Niet [_htmlAttr] — dat is voor attribuutwaarden.
  static String _htmlText(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  // ── Cockpit → inline SVG ──────────────────────────────────────────────────

  static final RegExp _cockpitFence = RegExp(
    r'```cockpit[ \t]*\n([\s\S]*?)\n```',
    multiLine: true,
  );

  /// Replace ```cockpit fenced blocks with a self-contained inline SVG, so the
  /// portable HTML export shows the actual dashboard instead of raw JSON.
  static String renderCockpitBlocks(
    String slideMarkdown, {
    ThemeProfile? theme,
    CockpitColorScheme scheme = CockpitColorScheme.standard,
  }) {
    return slideMarkdown.replaceAllMapped(_cockpitFence, (m) {
      final spec = CockpitSpec.parse(m.group(1)!);
      return '\n<div class="cockpit">${_cockpitSvg(spec, theme, scheme)}</div>\n';
    });
  }

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
        'background:${t.slideBackgroundColor};color:${t.textColor};padding:48px;'
        'overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,.4);border-radius:4px;'
        'font-family:$family}'
        '.slide h1{font-size:48px;margin:.15em 0;'
        'color:var(--ocideck-title-color,${t.textColor})}'
        '.slide h2{font-size:34px;margin:.15em 0;color:${t.accentColor}}'
        '.slide a{color:${t.accentColor}}'
        '.slide p,.slide li{font-size:24px;line-height:1.45}'
        // Cat-paw bullet markers (only on slides tagged .paw-bullets). The dot
        // is removed and an inline-SVG paw is absolutely positioned in the gutter
        // so it scales with the text and never disturbs the line box.
        '.slide.paw-bullets ul{list-style:none;padding-left:1.5em}'
        '.slide.paw-bullets ul li{position:relative}'
        '.slide.paw-bullets ul li::before{content:"";position:absolute;'
        'left:-1.4em;top:.5em;width:.78em;height:.78em;'
        'background:url("${_pawDataUri(t.accentColor)}") center/contain no-repeat}'
        '.slide pre{background:${t.codeBackgroundColor};color:${t.codeTextColor};'
        'border:1px solid ${t.codeTextColor}38;border-radius:6px;'
        'padding:16px;overflow:auto;font-size:18px;font-family:$codeFamily}'
        '.slide pre code{color:${t.codeTextColor};background:transparent}'
        '.slide code{font-family:$codeFamily}'
        '.slide pre.mermaid{background:transparent;border:0;text-align:center}'
        '.slide img{max-width:100%}'
        '.slide blockquote{border-left:4px solid ${t.accentColor};margin:.5em 0;'
        'padding-left:16px;opacity:.85}'
        '.slide table{border-collapse:collapse;width:100%}'
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

  /// Gecachte @font-face (de base64 van ~0,5 MB font liep anders bij elke
  /// export opnieuw); alleen gevuld via de default loader, zie
  /// [_usesDefaultBytesLoader].
  static String? _ebGaramondFaceCache;

  /// Embed the bundled EB Garamond variable font as base64 so it works offline.
  /// Returns an empty string for any other (system) font.
  Future<String> _ebGaramondFontFace(String font) async {
    if (font != 'EB Garamond') return '';
    final cached = _usesDefaultBytesLoader ? _ebGaramondFaceCache : null;
    if (cached != null) return cached;
    try {
      final bytes = await loadBytes('assets/fonts/EBGaramond-Variable.ttf');
      final b64 = base64Encode(bytes);
      final face =
          "@font-face{font-family:'EB Garamond';font-weight:400 800;"
          "font-style:normal;src:url(data:font/ttf;base64,$b64) "
          "format('truetype');}";
      if (_usesDefaultBytesLoader) _ebGaramondFaceCache = face;
      return face;
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
.slide{position:relative;width:1280px;min-height:720px;margin:24px auto;background:#fff;padding:48px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,.4);border-radius:4px}
.slide h1{font-size:48px;margin:.15em 0;color:var(--ocideck-title-color,inherit)}
.slide h2{font-size:34px;margin:.15em 0}
.slide p,.slide li{font-size:24px;line-height:1.45}
.slide pre{background:#f6f8fa;border:1px solid #e1e4e8;border-radius:6px;padding:16px;overflow:auto;font-size:18px}
.slide code{font-family:SFMono-Regular,Consolas,"Liberation Mono",monospace}
.slide pre.mermaid{background:transparent;border:0;text-align:center}
.slide img{max-width:100%}
.slide blockquote{border-left:4px solid #ccc;margin:.5em 0;padding-left:16px;color:#555}
.slide table{border-collapse:collapse;width:100%}.slide th,.slide td{border:1px solid #ccc;padding:6px 12px;font-size:20px}
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
  // Defence-in-depth: mermaid injects its SVG into the DOM AFTER DOMPurify has
  // run on the markdown, so sanitise the produced SVG ourselves too (mirrors
  // the in-app sanitize_svg.dart). Mermaid also runs with securityLevel strict.
  function sanitizeMermaid(){
    if(!window.DOMPurify)return;
    document.querySelectorAll('.mermaid svg').forEach(function(svg){
      try{
        var clean=DOMPurify.sanitize(svg.outerHTML,{USE_PROFILES:{svg:true,svgFilters:true}});
        var tpl=document.createElement('template');tpl.innerHTML=clean;
        var node=tpl.content.firstElementChild;
        if(node)svg.replaceWith(node);
      }catch(e){}
    });
  }
  if(window.marked&&marked.setOptions){marked.setOptions({gfm:true,breaks:false});}
  document.querySelectorAll('section.slide').forEach(function(sec){
    var holder=sec.querySelector('script[type="text/markdown"]');
    var src=holder?holder.textContent:'';
    // De ontsnapping uit _guardMarkdown terugdraaien: die bestaat alleen om de
    // HTML-tokenizer binnen dit script-element te houden, niet om de markdown
    // te veranderen.
    src=src.split('<\\/').join('</').split('<\\!--').join('<!--');
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
  if(window.mermaid){try{
    mermaid.initialize({startOnLoad:false,securityLevel:'strict'});
    var mres=mermaid.run();
    if(mres&&mres.then){mres.then(sanitizeMermaid).catch(function(e){});}else{sanitizeMermaid();}
  }catch(e){}}
  if(window.MathJax&&MathJax.typesetPromise){MathJax.typesetPromise();}
})();
''';
}
