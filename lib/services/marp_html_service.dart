import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart' show rootBundle;

import '../l10n/app_localizations.dart';
import '../models/asset_overview_spec.dart';
import '../models/chart.dart';
import '../models/checklist_spec.dart';
import '../models/cockpit.dart';
import '../models/discoveries_spec.dart';
import '../models/findings_summary_spec.dart';
import '../models/question.dart';
import '../models/deck.dart';
import '../models/scope_matrix_spec.dart';
import '../models/scorecard_spec.dart';
import '../models/settings.dart';
import '../models/timeline.dart';
import '../utils/log.dart';
import 'cvss/cvss4.dart';
import 'export_metadata.dart';
import 'markdown_table_codec.dart';

part 'parts/marp_html_service_cockpit.dart';
part 'parts/marp_html_service_charts.dart';
part 'parts/marp_html_service_charts_radial.dart';
part 'parts/marp_html_service_charts_bullet.dart';
part 'parts/marp_html_service_reporting.dart';
part 'parts/marp_html_service_reporting_miauw.dart';
part 'parts/marp_html_service_reporting_css.dart';

/// Maakt van een afbeeldingsverwijzing uit een deck een `data:`-URI, of geeft
/// null wanneer de afbeelding niet in te sluiten is (niet gevonden, buiten de
/// projectmap, of niet te decoderen).
///
/// Geïnjecteerd in plaats van hier uitgevoerd: het lezen van een bestand en het
/// hercoderen van beeld horen niet in een service die ook op web moet draaien,
/// en de projectbegrenzing die een deck ervan weerhoudt willekeurige bestanden
/// mee te exporteren, hoort bij de laag die het bestandssysteem kent.
typedef HtmlImageResolver = Future<String?> Function(String source);

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
  ///
  /// [embedImage] maakt van een afbeeldingsverwijzing een `data:`-URI. Zonder
  /// deze functie blijven de paden staan zoals ze in de markdown stonden, en
  /// dan is de uitvoer géén self-contained document — zie [_embedImages].
  Future<String> build(
    String deckMarkdown, {
    ThemeProfile? theme,
    CockpitColorScheme cockpitColorScheme = CockpitColorScheme.standard,
    ExportDocumentMetadata? metadata,
    String fallbackTitle = 'Presentatie',
    HtmlImageResolver? embedImage,
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
      theme == null ? Future.value(_defaultThemeCss) : _themedCss(theme),
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

    final embedded = await _embedImages(deckMarkdown, embedImage);
    final signature = signatureFields(embedded.markdown);
    final sections = StringBuffer();
    for (final slide in marpSlides(embedded.markdown)) {
      // De keten van omzettingen, van binnen naar buiten. Elke stap laat een
      // dia die haar niet aangaat onveranderd, dus de volgorde is vrij; het
      // rapportagetype gaat als eerste omdat het de hele body vervangt.
      var body = renderReportingSlide(slide, theme: theme);
      body = renderChartBlocks(body, theme: theme);
      body = renderQuestionBlocks(body);
      body = renderMediaRedacted(body);
      body = renderVideoNotice(body);
      body = renderTimelineBlocks(body);
      body = renderSignOffBlock(
        body,
        signature,
        sealedAt: signature['ocideck_seal_at'] ?? '',
      );
      final renderedBlocks = renderCockpitBlocks(
        body,
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
        '<style>$_structuralCss\n$_reportingCss\n$css\n$hljsCss</style>'
        '<script nonce="$nonce">$_mathjaxConfig</script>'
        '${inline(marked)}'
        '${inline(purify)}'
        '${inline(hljs)}'
        '${inline(mathjax)}'
        '${inline(mermaid)}'
        '</head><body>'
        '$banner'
        '$sections'
        '${inline(_renderScript(embedded.dataUris))}'
        '</body></html>';
  }

  // ── Afbeeldingen → data:-URI ──────────────────────────────────────────────

  /// Een afbeeldingsverwijzing (`![alt](hier)`), zoals de serialiser hem
  /// schrijft. Geen haakjes of regeleindes in het pad — dat is ook wat Markdown
  /// zelf toestaat zonder aanhalingstekens.
  static final RegExp _imageRef = RegExp(r'!\[([^\]]*)\]\(([^)\n]+)\)');

  /// De plaatshouder die in de markdown komt te staan in plaats van het pad.
  ///
  /// Een fragment (`#…`) en geen `data:`-URI ter plekke, om één reden: dedupe.
  /// Een achtergrondafbeelding die op veertig dia's staat, zou anders veertig
  /// keer als base64 in het bestand belanden. Nu staat elke afbeelding precies
  /// één keer in het document en dragen de dia's er een verwijzing naar.
  ///
  /// Een fragment overleeft bovendien DOMPurify ongeschonden — een eigen
  /// URI-schema zou eruit gefilterd worden.
  static const _imagePlaceholder = '#ocideck-img-';

  /// Vervangt elke afbeeldingsverwijzing in [markdown] door een plaatshouder, en
  /// levert de bijbehorende `data:`-URI's.
  ///
  /// Dit is wat "self-contained" waarmaakt. De README belooft een offline
  /// HTML-deck; zonder deze stap wees elke `![…](images/foto.png)` naar een
  /// bestand dat de ontvanger niet heeft, en kreeg hij een rij kapotte
  /// afbeeldingspictogrammen met de bestandsnamen van de auteur eronder.
  ///
  /// Zonder [resolve] blijft alles staan zoals het stond — dat pad bestaat voor
  /// tests en voor aanroepers zonder toegang tot een bestandssysteem.
  Future<({String markdown, List<String> dataUris})> _embedImages(
    String markdown,
    HtmlImageResolver? resolve,
  ) async {
    const unchanged = <String>[];
    if (resolve == null) return (markdown: markdown, dataUris: unchanged);
    final sources = {
      for (final m in _imageRef.allMatches(markdown)) m.group(2)!.trim(),
    };
    if (sources.isEmpty) return (markdown: markdown, dataUris: unchanged);

    final index = <String, int>{};
    final dataUris = <String>[];
    for (final source in sources) {
      // Een bron die al een data:-URI is (of een lege verwijzing) hoeft niets:
      // die reist per definitie al mee.
      if (source.isEmpty || source.startsWith('data:')) continue;
      final uri = await resolve(source);
      if (uri == null) continue;
      index[source] = dataUris.length;
      dataUris.add(uri);
    }

    const l10n = AppLocalizations(Locale('nl'));
    final missing = _htmlAttr(l10n.d('Afbeelding niet ingesloten'));
    final rewritten = markdown.replaceAllMapped(_imageRef, (m) {
      final source = m.group(2)!.trim();
      if (source.isEmpty || source.startsWith('data:')) return m.group(0)!;
      final at = index[source];
      // Niet in te sluiten: liever een zichtbare melding dan een verwijzing naar
      // een bestand dat de ontvanger niet heeft. Het pad zelf blijft eruit — dat
      // is de map van de auteur, en die hoeft de ontvanger niet te kennen.
      if (at == null) {
        return '<span class="image-missing" role="img" '
            'aria-label="$missing">$missing</span>';
      }
      return '![${m.group(1)}]($_imagePlaceholder$at)';
    });
    return (markdown: rewritten, dataUris: dataUris);
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

  // ── Tijdlijn → HTML ───────────────────────────────────────────────────────

  static final RegExp _timelineClass = RegExp(
    r'<!--\s*_class:\s*timeline\s*-->',
  );
  static final RegExp _bulletLine = RegExp(r'^[\t ]*-[\t ]+(.*)$');

  /// Zet de opgeslagen tijdlijnpunten om in een echte tijdlijn.
  ///
  /// Een tijdlijndia bewaart zijn punten als `marker :: titel :: toelichting`.
  /// In de app tekent de preview daar een tijdlijn van; de HTML-export liet de
  /// opsomming staan zoals hij op schijf stond, dus in het document dat de
  /// lezer krijgt stond letterlijk "2024-01 :: Start". De dubbele dubbele punt
  /// is een interne scheiding en hoort niet in een opgeleverd rapport.
  static String renderTimelineBlocks(String slideMarkdown) {
    if (!_timelineClass.hasMatch(slideMarkdown)) return slideMarkdown;
    final lines = slideMarkdown.split('\n');
    final out = StringBuffer();
    var events = <TimelineEvent>[];

    void flush() {
      if (events.isEmpty) return;
      out.writeln('<ol class="timeline">');
      for (final e in events) {
        out.write('<li>');
        if (e.marker.trim().isNotEmpty) {
          out.write('<span class="tl-marker">${_htmlText(e.marker)}</span>');
        }
        if (e.title.trim().isNotEmpty) {
          out.write('<span class="tl-title">${_htmlText(e.title)}</span>');
        }
        if (e.description.trim().isNotEmpty) {
          out.write('<span class="tl-desc">${_htmlText(e.description)}</span>');
        }
        out.writeln('</li>');
      }
      out.writeln('</ol>');
      events = <TimelineEvent>[];
    }

    for (final line in lines) {
      final m = _bulletLine.firstMatch(line);
      if (m != null) {
        final event = TimelineEvent.fromBullet(m.group(1)!);
        if (!event.isEmpty) {
          events.add(event);
          continue;
        }
      }
      flush();
      out.writeln(line);
    }
    flush();
    return out.toString();
  }

  // ── Media-redactie → HTML ─────────────────────────────────────────────────

  static final RegExp _mediaRedactedMarker = RegExp(
    r'<!--\s*ocideck_media_redacted\s*-->',
  );

  /// Vervangt de media-redactiemarkering door een zichtbaar zwart vlak.
  ///
  /// De privacyprojectie haalt beeld, video en audio van een slide af en zet
  /// [Slide.mediaRedacted]. De widget-exports tekenen daar een zwart vlak; de
  /// HTML-export werkt op de markdown en liet alleen een lege plek staan,
  /// terwijl de tekst ernaast wél zwarte blokken toonde. Nu ziet de ontvanger
  /// dát er beeld is weggehaald, net als in het rapport dat de auteur zag.
  static String renderMediaRedacted(String slideMarkdown) {
    if (!_mediaRedactedMarker.hasMatch(slideMarkdown)) return slideMarkdown;
    const l10n = AppLocalizations(Locale('nl'));
    final box =
        '\n<div class="media-redacted" role="img" '
        'aria-label="${_htmlAttr(l10n.d('Media verwijderd om privacyredenen'))}">'
        '${_htmlText(l10n.d('Media verwijderd om privacyredenen'))}</div>\n';
    return slideMarkdown.replaceAll(_mediaRedactedMarker, box);
  }

  // ── Video → melding ───────────────────────────────────────────────────────

  static final RegExp _videoElement = RegExp(
    r'<video\b[^>]*>\s*</video>',
    caseSensitive: false,
  );
  static final RegExp _embedElement = RegExp(
    r'<iframe\b[^>]*class="ocideck-embed"[^>]*>\s*</iframe>',
    caseSensitive: false,
  );

  /// Zet een videospeler om in een zichtbare melding.
  ///
  /// De andere helft van dezelfde belofte als [_embedImages], en de enige die
  /// niet in te lossen is. Een videobestand insluiten maakt een document van
  /// honderden megabytes; een YouTube- of Vimeo-speler kan per definitie niet
  /// werken in een export die niets van internet mag halen — de eigen CSP van
  /// het bestand zet `frame-src 'none'` en laat `media-src` alleen lokale
  /// bronnen toe.
  ///
  /// Wat er stond was dus een speler die zwart bleef en niets deed, zonder dat
  /// de ontvanger kon weten dat er iets ontbrak. Nu staat het er. Bij een
  /// online bron schrijft de serialiser er al een aanklikbare URL onder, dus de
  /// bron zelf blijft bereikbaar.
  static String renderVideoNotice(String slideMarkdown) {
    if (!_videoElement.hasMatch(slideMarkdown) &&
        !_embedElement.hasMatch(slideMarkdown)) {
      return slideMarkdown;
    }
    const l10n = AppLocalizations(Locale('nl'));
    final label = l10n.d('Video niet ingesloten');
    final box =
        '<div class="media-absent" role="img" '
        'aria-label="${_htmlAttr(label)}">${_htmlText(label)}</div>';
    return slideMarkdown
        .replaceAll(_videoElement, box)
        .replaceAll(_embedElement, box);
  }

  // ── Ondertekening → HTML ──────────────────────────────────────────────────

  static final RegExp _signOffClass = RegExp(
    r'<!--\s*_class:\s*sign-off\s*-->',
  );

  /// Leest de `ocideck_sig_*`- en `ocideck_seal_at`-regels uit de voorpagina
  /// van [deckMarkdown].
  ///
  /// De ondertekening staat op dekniveau, niet op de dia — zie
  /// `_writeSignOffSlide`. De export krijgt alleen de markdown mee, dus wordt
  /// hij hier teruggelezen uit de front matter.
  static Map<String, String> signatureFields(String deckMarkdown) {
    final text = deckMarkdown.replaceAll('\r\n', '\n');
    if (!text.startsWith('---\n')) return const {};
    final close = text.indexOf('\n---', 4);
    if (close == -1) return const {};
    final fields = <String, String>{};
    for (final line in text.substring(4, close).split('\n')) {
      if (!line.startsWith('ocideck_sig_') &&
          !line.startsWith('ocideck_seal_at')) {
        continue;
      }
      final colon = line.indexOf(':');
      if (colon == -1) continue;
      var value = line.substring(colon + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      if (value.isNotEmpty) fields[line.substring(0, colon).trim()] = value;
    }
    return fields;
  }

  /// Zet de ondertekeningsverklaring op de sign-off-dia.
  ///
  /// De dia zelf bewaart alleen een kop; de verklaring, de rapporteur en de
  /// zegelstatus staan op dekniveau. In de app tekent de preview ze erbij, maar
  /// de HTML-export deed dat niet — dus in het document dat de klant krijgt was
  /// de akkoordpagina een kop met wit eronder, precies de pagina waar de
  /// verklaring hoort te staan.
  static String renderSignOffBlock(
    String slideMarkdown,
    Map<String, String> signature, {
    String sealedAt = '',
  }) {
    if (!_signOffClass.hasMatch(slideMarkdown)) return slideMarkdown;
    const l10n = AppLocalizations(Locale('nl'));
    String field(String key) => signature[key]?.trim() ?? '';

    // Dezelfde opbouw als de preview: verklaring, ondertekening, naam · rol ·
    // certificering, datum, zegel. Zo leest de akkoordpagina in de export
    // hetzelfde als de pagina die de auteur in de app heeft goedgekeurd.
    final b = StringBuffer('\n<div class="signoff">');
    final statement = field('ocideck_sig_statement');
    if (statement.isNotEmpty) {
      b.write('<p class="signoff-statement">${_htmlText(statement)}</p>');
    }
    final mark = field('ocideck_sig_typed').isNotEmpty
        ? field('ocideck_sig_typed')
        : field('ocideck_sig_name');
    if (mark.isNotEmpty) {
      b.write('<p class="signoff-mark">${_htmlText(mark)}</p>');
    } else if (statement.isEmpty) {
      b.write(
        '<p class="signoff-none">${_htmlText(l10n.d('Nog niet ondertekend'))}</p>',
      );
    }
    final meta = [
      for (final key in const [
        'ocideck_sig_name',
        'ocideck_sig_role',
        'ocideck_sig_cert',
        'ocideck_sig_date',
      ])
        if (field(key).isNotEmpty) field(key),
    ];
    if (meta.isNotEmpty) {
      b.write('<p class="signoff-meta">${_htmlText(meta.join(' · '))}</p>');
    }
    b.write(
      '<p class="signoff-seal">${_htmlText(sealedAt.trim().isNotEmpty ? '${l10n.d('Verzegeld op')} ${sealedAt.trim()}' : l10n.d('Nog niet verzegeld'))}</p>',
    );
    b.write('</div>\n');
    return '$slideMarkdown\n$b';
  }

  /// Tekst als HTML-inhoud: alleen de drie tekens die de parser van gedachten
  /// doen veranderen. Niet [_htmlAttr] — dat is voor attribuutwaarden.
  static String _htmlText(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  // ── Rapportagedia's → HTML ────────────────────────────────────────────────

  /// Vervangt de body van een rapportagedia door zijn eigen weergave.
  ///
  /// Zes slidetypes bewaren hun inhoud als een gewone Markdown-tabel, en de
  /// export liet die tabel staan. In de app heeft elk van de zes een eigen
  /// weergave — kaarten met een verandering, balken op één gedeelde schaal,
  /// een dekkingsteller, gekleurde statuspillen — en juist bij de MIAUW-types
  /// draagt die weergave de boodschap. Een klant kreeg in de HTML dus iets
  /// anders dan de auteur had goedgekeurd.
  ///
  /// Een dia die geen rapportagetype is, komt onveranderd terug.
  static String renderReportingSlide(
    String slideMarkdown, {
    ThemeProfile? theme,
  }) {
    final slide = _readReportingSlide(slideMarkdown);
    if (slide == null) return slideMarkdown;
    final html = switch (slide.cssClass) {
      'scorecard' => _repScorecard(slide, theme),
      'assets' => _repAssets(slide, theme),
      'discoveries' => _repDiscoveries(slide, theme),
      'checklist' => _repChecklist(slide, theme),
      'scope-matrix' => _repScopeMatrix(slide, theme),
      'findings-summary' => _repFindingsSummary(slide, theme),
      _ => null,
    };
    if (html == null) return slideMarkdown;
    // De kop en de tabel gaan op in de weergave; de overige regels (de
    // `_class`-regel, notities, andere markeringen) blijven staan zodat de
    // stappen na deze ze nog zien.
    final kept = [
      for (final line in slideMarkdown.split('\n'))
        if (!isMarkdownTableLine(line) &&
            _repHeading.firstMatch(line.trim()) == null)
          line,
    ];
    return '${kept.join('\n')}\n\n$html\n';
  }

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
  ///
  /// Alleen de thema-afhankelijke helft. De rest — tijdlijn, ondertekening,
  /// media-redactie, de classificatiebanner en de printregels — staat in
  /// [_structuralCss] en wordt altijd meegestuurd. Toen dit één blok was dat de
  /// ongethematiseerde variant *verving*, verloor elke export mét thema (dus
  /// elke export uit de app) die opmaak: de tijdlijn viel terug op een kale
  /// genummerde lijst en de TLP-banner werd een regel zwarte tekst op de
  /// achtergrond in plaats van een balk bovenaan het document.
  Future<String> _themedCss(ThemeProfile t) async {
    final fontFace = await _ebGaramondFontFace(t.fontFamily);
    final family = _cssFontStack(t.fontFamily);
    final codePrefix = t.codeFontFamily == 'monospace'
        ? ''
        : "'${t.codeFontFamily}',";
    final codeFamily =
        '${codePrefix}SFMono-Regular,Consolas,"Liberation Mono",monospace';
    return '$fontFace\n'
        ':root{--ocideck-accent:${t.accentColor}}'
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
        '.slide td{color:${t.tableTextColor};border:1px solid #ccc;padding:6px 12px;font-size:20px}';
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

  /// De opmaak die van geen enkel thema afhangt: de dia-doos, de tijdlijn, de
  /// ondertekening, het media-redactievlak, de classificatiebanner en de
  /// printregels. Deze gaat **altijd** mee, vóór [_defaultThemeCss] of
  /// [_themedCss], zodat een gethematiseerde export dezelfde structuur houdt en
  /// een thema alleen de kleuren en de letter overneemt.
  ///
  /// `--ocideck-accent` is de enige haak die het thema hier binnenkomt: de
  /// tijdlijn en de ondertekening tekenen ermee, met EU-blauw als waarde voor
  /// een export zonder thema.
  static const _structuralCss = r'''
:root{--ocideck-accent:#003399}
*{box-sizing:border-box}
html,body{margin:0;padding:0}
.slide{position:relative;width:1280px;min-height:720px;margin:24px auto;padding:48px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,.4);border-radius:4px}
.slide h1{font-size:48px;margin:.15em 0}
.slide h2{font-size:34px;margin:.15em 0}
.slide p,.slide li{font-size:24px;line-height:1.45}
.slide pre.mermaid{background:transparent;border:0;text-align:center}
.slide img{max-width:100%}
.slide table{border-collapse:collapse;width:100%}
.slide ol.timeline{list-style:none;margin:.6em 0;padding:0 0 0 24px;border-left:3px solid #ccc}
.slide ol.timeline li{position:relative;margin:0 0 .9em;padding-left:16px}
.slide ol.timeline li::before{content:"";position:absolute;left:-31px;top:.45em;width:11px;height:11px;border-radius:50%;background:var(--ocideck-accent)}
.slide .tl-marker{display:block;font-size:18px;font-weight:700;color:var(--ocideck-accent);letter-spacing:.04em}
.slide .tl-title{display:block;font-size:26px;font-weight:600;line-height:1.3}
.slide .tl-desc{display:block;font-size:20px;opacity:.7;line-height:1.35}
.slide .signoff{margin-top:.8em;max-width:900px}
.slide .signoff-statement{font-style:italic;opacity:.85;font-size:22px}
.slide .signoff-mark{font-family:Georgia,"Times New Roman",serif;font-style:italic;font-size:40px;color:var(--ocideck-accent);margin:.35em 0 .1em}
.slide .signoff-none{font-style:italic;opacity:.6;font-size:22px}
.slide .signoff-meta{font-size:20px;opacity:.8;margin:.1em 0}
.slide .signoff-seal{font-size:18px;opacity:.6;letter-spacing:.03em;margin-top:.7em}
.slide .media-redacted{display:flex;align-items:center;justify-content:center;min-height:200px;margin:.6em 0;background:#000;color:#fff;font-size:20px;letter-spacing:.05em;border-radius:4px;text-align:center;padding:24px}
.slide .image-missing{display:inline-block;padding:14px 20px;border:2px dashed rgba(100,116,139,.5);border-radius:6px;font-size:19px;opacity:.6;font-style:italic}
.slide .media-absent{display:flex;align-items:center;justify-content:center;min-height:180px;margin:.6em 0;border:2px dashed rgba(100,116,139,.5);border-radius:6px;font-size:20px;opacity:.6;font-style:italic;text-align:center;padding:24px}
.slide .mermaid-error{margin:.6em 0;padding:16px 20px;border:1px solid #B91C1C;border-left-width:6px;border-radius:6px;background:#FEE2E2;color:#7F1D1D;text-align:left}
.slide .mermaid-error-title{font-size:22px;font-weight:700;margin:0 0 .3em;color:#7F1D1D}
.slide .mermaid-error-label{font-size:16px;font-weight:600;margin:.7em 0 .2em;opacity:.8;color:#7F1D1D}
.slide .mermaid-error-detail,.slide .mermaid-error-source{margin:0;padding:10px 12px;background:rgba(255,255,255,.65);border:0;border-radius:4px;font-size:15px;line-height:1.35;white-space:pre-wrap;overflow:auto;max-height:220px;color:#7F1D1D}
.tlp-export-banner{position:fixed;top:0;left:0;right:0;background:#000;color:#ffc000;text-align:center;font:700 14px/2.4 monospace;z-index:9999;letter-spacing:.06em}
@media print{body{background:#fff}.slide{margin:0;box-shadow:none;border-radius:0;page-break-after:always;width:100%;min-height:100vh}}
''';

  /// De kleuren en letters voor een export zonder [ThemeProfile] — de
  /// tegenhanger van [_themedCss], op dezelfde plek in de cascade.
  static const _defaultThemeCss = r'''
body{background:#1e1e1e;font-family:-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;color:#1a1a1a}
.slide{background:#fff}
.slide h1{color:var(--ocideck-title-color,inherit)}
.slide pre{background:#f6f8fa;border:1px solid #e1e4e8;border-radius:6px;padding:16px;overflow:auto;font-size:18px}
.slide code{font-family:SFMono-Regular,Consolas,"Liberation Mono",monospace}
.slide blockquote{border-left:4px solid #ccc;margin:.5em 0;padding-left:16px;color:#555}
.slide th,.slide td{border:1px solid #ccc;padding:6px 12px;font-size:20px}
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

  /// De labels die het renderscript in het document zet, als JSON. Het script
  /// is vaste, vendorloze code; alleen deze woorden zijn zichtbare tekst en gaan
  /// dus door [AppLocalizations.d]. Een `</script` in een vertaling wordt door
  /// [_guardScript] afgevangen, net als bij de bibliotheken.
  static String _renderScriptLabels() {
    const l10n = AppLocalizations(Locale('nl'));
    return jsonEncode({
      'mermaidFailed': l10n.d('Dit diagram kon niet worden getekend'),
      'mermaidSource': l10n.d('Brontekst van het diagram'),
    });
  }

  /// Het script dat de ingesloten markdown in het geopende document omzet.
  ///
  /// Een functie en geen constante, omdat de zichtbare woorden erin
  /// gelokaliseerd worden (zie [_renderScriptLabels]) en omdat de ingesloten
  /// afbeeldingen als [dataUris] meegaan — één keer, hoe vaak een dia er ook
  /// naar verwijst.
  static String _renderScript(List<String> dataUris) =>
      'var OCIDECK_L=${_renderScriptLabels()};\n'
      'var OCIDECK_IMG=${jsonEncode(dataUris)};\n'
      '$_renderScriptBody';

  static const _renderScriptBody = r'''
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
  // De ingesloten afbeeldingen terugzetten. Ze staan één keer in OCIDECK_IMG en
  // de dia's dragen alleen een verwijzing, zodat dezelfde achtergrond op veertig
  // dia's het bestand niet veertig keer zo groot maakt. Alleen een echte
  // data:image/-waarde uit onze eigen lijst wordt gezet — de index komt uit het
  // document en moet dus als onbetrouwbaar worden behandeld.
  document.querySelectorAll('img[src^="#ocideck-img-"]').forEach(function(el){
    var n=parseInt(el.getAttribute('src').replace('#ocideck-img-',''),10);
    var uri=OCIDECK_IMG[n];
    if(typeof uri==='string'&&uri.indexOf('data:image/')===0){el.setAttribute('src',uri);}
    else{el.removeAttribute('src');}
  });
  document.querySelectorAll('code.language-mermaid').forEach(function(code){
    var pre=code.closest('pre');if(!pre)return;
    var holder=document.createElement('pre');holder.className='mermaid';
    holder.textContent=code.textContent;pre.replaceWith(holder);
  });
  if(window.hljs){document.querySelectorAll('pre code').forEach(function(el){try{hljs.highlightElement(el);}catch(e){}});}
  // Een diagram dat mermaid niet kan lezen wordt een leesbare melding IN het
  // document. De ontvanger van een export heeft geen console: zonder dit zag hij
  // mermaids eigen Engelse bom-plaatje ("Syntax error in text") zonder enige
  // aanwijzing wélk diagram het betrof of wat eraan mankeerde, en de auteur zag
  // helemaal niets. Alles gaat via textContent, dus de brontekst van het
  // diagram kan hier nooit opmaak of markup worden.
  function mermaidNotice(pre,err){
    var box=document.createElement('div');box.className='mermaid-error';
    var title=document.createElement('p');
    title.className='mermaid-error-title';
    title.textContent=OCIDECK_L.mermaidFailed;
    box.appendChild(title);
    var detail=err&&err.message?String(err.message):'';
    if(detail){
      var d=document.createElement('pre');
      d.className='mermaid-error-detail';d.textContent=detail;
      box.appendChild(d);
    }
    var label=document.createElement('p');
    label.className='mermaid-error-label';
    label.textContent=OCIDECK_L.mermaidSource;
    var src=document.createElement('pre');
    src.className='mermaid-error-source';src.textContent=pre.textContent;
    box.appendChild(label);box.appendChild(src);
    pre.replaceWith(box);
  }
  function noticeForUnrendered(err){
    document.querySelectorAll('pre.mermaid').forEach(function(pre){
      if(!pre.querySelector('svg'))mermaidNotice(pre,err);
    });
  }
  function runMermaid(){
    // htmlLabels UIT, per diagramsoort én globaal. Mermaid tekent labels
    // anders in een <foreignObject> met HTML erin, en juist dat element haalt
    // de sanitisatie hieronder weg (het is de plek waar HTML een SVG binnen kan
    // komen). Het resultaat waren lege vakjes en pijlen zonder één woord erbij
    // — een diagram dat er wél stond maar niets meer zei.
    mermaid.initialize({startOnLoad:false,securityLevel:'strict',
      htmlLabels:false,flowchart:{htmlLabels:false},class:{htmlLabels:false}});
    // Elk diagram eerst apart laten controleren. Zo tekent mermaid zijn eigen
    // foutplaatje niet, blijft een kapot diagram beperkt tot zijn eigen dia, en
    // draait de sanitisatie hieronder ALTIJD — bij de oude stille catch sloeg
    // die voor het hele document over zodra er één diagram omviel, ook voor de
    // diagrammen die het wél deden.
    var checked=[];
    document.querySelectorAll('pre.mermaid').forEach(function(pre){
      checked.push(Promise.resolve()
        .then(function(){return mermaid.parse(pre.textContent);})
        .catch(function(e){mermaidNotice(pre,e);}));
    });
    return Promise.all(checked)
      .then(function(){return mermaid.run();})
      .catch(noticeForUnrendered)
      .then(sanitizeMermaid);
  }
  if(window.mermaid){try{runMermaid();}catch(e){noticeForUnrendered(e);}}
  if(window.MathJax&&MathJax.typesetPromise){MathJax.typesetPromise();}
})();
''';
}
