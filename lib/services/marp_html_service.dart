import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;

import '../l10n/app_localizations.dart';
import '../models/asset_overview_spec.dart';
import '../models/chart.dart';
import '../models/image_callout.dart';
import 'improvement/chart_derivation.dart';
import '../models/checklist_spec.dart';
import '../models/cockpit.dart';
import 'cockpit_layout.dart';
import '../models/discoveries_spec.dart';
import '../models/findings_summary_spec.dart';
import '../models/question.dart';
import '../models/deck.dart';
import '../models/improvement_y01.dart';
import '../models/marp_style.dart';
import '../models/menu.dart';
import '../models/scope_matrix_spec.dart';
import '../models/scorecard_spec.dart';
import '../models/settings.dart';
import '../models/page_size.dart';
import '../models/slide.dart';
import '../models/timeline.dart';
import '../utils/log.dart';
import '../utils/bundled_asset.dart';
import '../utils/markdown_blocks.dart';
import '../utils/inline_markdown.dart';
import '../utils/marp_emoji.dart';
import '../utils/marp_style_values.dart';
import '../models/document_signature.dart';
import 'bundled_licenses.dart';
import 'cvss/cvss4.dart';
import 'export_metadata.dart';
import 'document_chrome_template.dart';
import 'improvement/matrix_layout.dart';
import 'improvement/matrix_slide.dart';
import 'improvement/matrix_spec.dart';
import 'improvement/canvas_layout.dart';
import 'improvement/canvas_slide.dart';
import 'improvement/canvas_spec.dart';
import 'improvement/tree_layout.dart';
import 'improvement/tree_spec.dart';
import 'improvement/flow_layout.dart';
import 'improvement/flow_slide.dart';
import 'improvement/flow_spec.dart';
import 'markdown_table_codec.dart';
import 'document_timeline.dart';
import 'menu_blocks.dart';
import 'rich_text_layout.dart';
import 'scene/scene.dart';
import 'markdown_service.dart';

part 'marp_html/marp_html_service_cockpit.dart';
part 'marp_html/marp_html_service_charts.dart';
part 'marp_html/marp_html_service_charts_radial.dart';
part 'marp_html/marp_html_service_charts_bullet.dart';
part 'marp_html/marp_html_service_reporting.dart';
part 'marp_html/marp_html_service_reporting_miauw.dart';
part 'marp_html/marp_html_service_matrix.dart';
part 'marp_html/marp_html_service_canvas.dart';
part 'marp_html/marp_html_service_tree.dart';
part 'marp_html/marp_html_service_flow.dart';
part 'marp_html/marp_html_service_menu.dart';
part 'marp_html/marp_html_service_css.dart';
part 'marp_html/marp_html_service_render_script.dart';
part 'marp_html/marp_html_service_images.dart';
part 'marp_html/marp_html_service_markup.dart';
part 'marp_html/marp_html_service_callouts.dart';
part 'marp_html/marp_html_service_notices.dart';

/// Maakt van een afbeeldingsverwijzing uit een deck een `data:`-URI, of geeft
/// null wanneer de afbeelding niet in te sluiten is (niet gevonden, buiten de
/// projectmap, of niet te decoderen).
///
/// Geïnjecteerd in plaats van hier uitgevoerd: het lezen van een bestand en het
/// hercoderen van beeld horen niet in een service die ook op web moet draaien,
/// en de projectbegrenzing die een deck ervan weerhoudt willekeurige bestanden
/// mee te exporteren, hoort bij de laag die het bestandssysteem kent.
typedef HtmlImageResolver = Future<String?> Function(String source);

/// Cumulatief plafond op de ingesloten `data:`-URI-bytes van één self-contained
/// HTML-export. Elke afbeelding heeft al een grens per stuk, maar de som was
/// onbegrensd: twintig toegestane GIF's van 64 MiB bouwen samen ~1,67 GiB base64
/// op — op web nog op de hoofd-isolate, vóór het einddocument als String bestaat
/// (#1045). Boven dit plafond faalt de export met een duidelijke melding in
/// plaats van het geheugen uit te putten. 512 MiB sluit aan op de overige
/// export-plafonds (`FileService.maxPackageBytes`).
const int kMaxHtmlEmbedTotalBytes = 512 * 1024 * 1024; // 512 MiB

/// Print-CSS voor 'nieuw hoofdstuk op een nieuwe pagina': elke H1 breekt naar een
/// nieuw blad, behalve de eerste (anders een leeg eerste blad). Alleen ingespoten
/// wanneer de instelling aanstaat; op het scherm blijft het document doorlopend.
const _chapterPageBreakCss =
    '@media print{.document h1{page-break-before:always;break-before:page}'
    '.document h1:first-child{page-break-before:auto;break-before:auto}}';

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
    Map<String, String> documentFields = const {},
    String fallbackTitle = 'Presentatie',
    HtmlImageResolver? embedImage,
    int maxEmbedBytes = kMaxHtmlEmbedTotalBytes,
    String htmlLang = 'nl', // <html lang>: inhoudstaal (WCAG 3.1.1) #1249
    // Documentmodus: render de body als één doorlopende stroom
    // (`<section class="document">`) i.p.v. losse 16:9-dia's (§11.2). Loopt door
    // exact dezelfde inerte `<script type="text/markdown">`-poort als de dia's.
    bool continuous = false,
    // Documentmodus: laat elk hoofdstuk (H1) bij afdrukken op een nieuwe pagina
    // beginnen (instelling). Alleen zinvol met [continuous]; het eerste hoofdstuk
    // krijgt geen breuk zodat er geen leeg eerste blad ontstaat.
    bool chapterPageBreak = false,
    // Feature 3: paginamaat en marges voor de @page-CSS (alleen zinvol met
    // [continuous] — de documentmodus). `null` = geen @page-regel.
    PageSizeSpec? pageSize,
    PageMargins? pageMargins,
  }) async {
    final [marked, purify, hljs, hljsCss, mathjax, mermaid, css] =
        await _loadExportBundles(theme);

    // Wie een export doorstuurt, verspreidt vijf JavaScript-bundels en — als het
    // gebundelde lettertype is ingesloten — ook een font. Dat mag alleen mét de
    // kennisgevingen erbij, dus die reizen mee in het bestand zelf.
    final notices = await thirdPartyNotices(
      embedsFont: css.contains('data:font/ttf;base64,'),
    );

    // Per-export CSP nonce. Every executable <script> we emit carries it; the
    // CSP then allows only nonce'd scripts, so an injected inline <script> that
    // somehow survives DOMPurify can't execute when the file is opened. The
    // per-slide `<script type="text/markdown">` data holders are inert (never
    // executed) and intentionally carry no nonce.
    final nonce = _htmlNonce();

    final docMeta = metadata ?? const ExportDocumentMetadata();
    final embedded = await _embedHtmlImages(
      deckMarkdown,
      embedImage,
      maxEmbedBytes,
      continuous,
      theme,
      docMeta.tlp,
      documentFields,
      this,
    );
    // De ondertekening komt van het deck mee (het zegelblok staat sinds 0.1.0
    // niet meer in de front matter). Een `.md` van vóór die verhuizing draagt
    // hem nog wél in de kop, en die blijft leesbaar: [signatureFields] is het
    // terugvalpad, niet de hoofdroute.
    final signature = docMeta.signature != null
        ? signatureFieldsOf(docMeta.signature!, sealedAt: docMeta.sealedAt)
        : signatureFields(embedded.markdown);
    final renderMarkdown = expandMarpEmojiShortcodes(embedded.markdown);
    final parsedDeck = MarkdownService().parseDeck(renderMarkdown);
    final sections = _renderSections(
      renderMarkdown,
      theme: theme,
      cockpitColorScheme: cockpitColorScheme,
      signature: signature,
      continuous: continuous,
      deckMarpStyle: parsedDeck?.marpStyle ?? const MarpStyle(),
      slideMarpStyles:
          parsedDeck?.slides.map((slide) => slide.marpStyle).toList() ??
          const [],
      slides: parsedDeck?.slides ?? const [],
    );

    // Elke ingesloten bundel krijgt een licentiebanner, ook als de geminificeerde
    // upstream-build er geen heeft. marked, highlight.js en DOMPurify dragen er
    // zelf een; MathJax en Mermaid niet, en zonder banner kan de ontvanger van
    // een export niet zien wat hij doorstuurt. [notices] draagt de volledige
    // teksten; deze regel wijst erheen.
    String inline(String code, [String? npm]) {
      final head = npm == null ? '' : notices.bannerFor(npm);
      return '<script nonce="$nonce">$head${_guardScript(code)}</script>';
    }

    final meta = docMeta;
    final title = _htmlAttr(meta.displayTitle(fallbackTitle));
    // WCAG 1.3.1/2.4.1: een documenttitel boven de dia's, voor de schermlezer.
    // Visueel verborgen (ocideck-sr-only) zodat de export nog direct op de
    // eerste dia opent — de titel staat al in <title>, dit is het
    // documentstructuur-anker dat een schermlezer bij binnenkomst aankondigt.
    // _htmlText, niet _htmlAttr: dit is tekstinhoud van <h1>, geen attribuut.
    final h1Title = _htmlText(meta.displayTitle(fallbackTitle));
    final headMeta = _htmlHeadMeta(meta, fallbackTitle: fallbackTitle);
    final classificationBanner = (!continuous && meta.htmlClassification != null
        ? '<div class="tlp-export-banner">${_htmlAttr(meta.htmlClassification!)}</div>'
        : '');
    final banner =
        classificationBanner +
        _aiBanner(meta, classificationBanner: classificationBanner.isNotEmpty);

    // Het presentatielogo op elke logo-dia, zoals de app, de beamer en de
    // PDF/PPTX het tonen. Alleen in de dia-modus: de doorlopende documentmodus
    // draagt hetzelfde logo al als kop/voetband (zie [_withDocumentChrome]).
    final logoCss = theme == null || continuous
        ? ''
        : await _presentationLogoCss(theme, embedImage, loadBytes);

    return '<!doctype html>\n'
        '<html lang="$htmlLang"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '${_cspMeta(nonce)}'
        '<title>$title</title>'
        '$headMeta'
        '<style>${exportBaseCss()}\n$css\n$hljsCss\n$_printCss'
        '${chapterPageBreak ? _chapterPageBreakCss : ''}'
        '${_pageAtRuleCss(pageSize, pageMargins)}$logoCss</style>'
        '<script nonce="$nonce">$_mathjaxConfig</script>'
        '${inline(marked, 'marked')}'
        '${inline(purify, 'dompurify')}'
        '${inline(hljs, 'highlight.js')}'
        '${inline(mathjax, 'mathjax')}'
        '${inline(mermaid, 'mermaid')}'
        '</head><body>'
        '$banner'
        '<main><h1 class="ocideck-sr-only">$h1Title</h1>'
        '$sections'
        '</main>'
        '${inline(_renderScript(embedded.dataUris))}'
        '${notices.html}'
        '</body></html>';
  }

  /// De zes gevendorde webbundels en de themed CSS voor één export. Ze zijn
  /// onafhankelijk, dus ze laden samen. Uitgetild uit [build] zodat die methode
  /// onder de lengte-ratchet blijft; de aanroeper ontbindt de lijst op volgorde.
  Future<List<String>> _loadExportBundles(ThemeProfile? theme) => Future.wait([
    loadAsset('$_assetDir/marked.min.js'),
    loadAsset('$_assetDir/purify.min.js'),
    loadAsset('$_assetDir/highlight.min.js'),
    loadAsset('$_assetDir/highlight.css'),
    loadAsset('$_assetDir/tex-svg.js'),
    loadAsset('$_assetDir/mermaid.min.js'),
    theme == null ? Future.value(_defaultThemeCss) : _themedCss(theme),
  ]);

  /// De Content-Security-Policy voor één export, als `<meta>`-element met de
  /// per-export [nonce] erin gebakken.
  ///
  /// Neutralise injected inline scripts (defence-in-depth behind DOMPurify)
  /// without over-restricting style, which would break locally opened
  /// exports. No default-src: the inline <style> block must keep working
  /// (adding one would force 'unsafe-inline' for style). Instead every
  /// network-capable resource type is pinned to local sources so nothing a
  /// crafted deck smuggles past DOMPurify can beacon home when the file is
  /// opened: connect-src 'none' (fetch/XHR/beacon), img-src/media-src
  /// self/data/blob/file (a surviving <img>/<video src="https://…">),
  /// font-src self/data (a hostile @font-face url()), and form-action
  /// 'none' (a planted <form action="https://…"> on submit). MathJax is
  /// tex-svg (no web fonts) and the bundled theme/highlight CSS carry no
  /// url()/@font-face, so these limits never bite a legitimate export.
  ///
  /// style-src 'unsafe-inline' sluit het laatste gat: zónder die richtlijn
  /// valt stijl helemaal buiten de CSP, en kon een `@import url(https://…)`
  /// in een `<style>`-blok alsnog naar buiten bellen — precies wat de rest
  /// van deze regel belooft te verhinderen. 'unsafe-inline' klinkt ruimer
  /// dan het is: het staat inline stijl toe (die er al was, want er stond
  /// niets) maar géén enkele externe herkomst, dus het import-verzoek
  /// wordt geweigerd. Een nonce zou strenger zijn, maar breekt de stijl
  /// die MathJax en mermaid tijdens het renderen zelf injecteren.
  static String _cspMeta(String nonce) =>
      '<meta http-equiv="Content-Security-Policy" '
      'content="script-src \'nonce-$nonce\'; object-src \'none\'; '
      'base-uri \'none\'; frame-src \'none\'; form-action \'none\'; '
      'img-src \'self\' data: blob: file:; '
      'media-src \'self\' data: blob: file:; font-src \'self\' data:; '
      'style-src \'unsafe-inline\'; '
      'connect-src \'none\'">';

  /// Collects the third-party notices for one export: the per-script licence
  /// banners and the collapsible block carrying the full licence texts.
  ///
  /// Versions and source URLs come from `assets/web_export/MANIFEST.json`, the
  /// same pinned inventory `make deps-check` verifies, so a bundle upgrade
  /// updates the notice with it instead of leaving a stale version behind.
  /// [embedsFont] adds the EB Garamond notice, which only applies when the deck
  /// theme actually inlines the font (OFL-1.1 §2 — the licence must accompany
  /// the font, and in a base64 `@font-face` the font is right there).
  ///
  /// An unreadable manifest or licence asset degrades to *no* notices with a
  /// warning in the log, the same way a missing font asset falls back to the CSS
  /// stack: a broken asset must not cost the user their export. That silence is
  /// covered by `marp_html_service_licenses_test.dart`, which builds against the
  /// real assets and fails if a bundle reaches the export without its notice.
  @visibleForTesting
  Future<ExportNotices> thirdPartyNotices({required bool embedsFont}) async {
    final banners = <String, String>{};
    final texts = <(String, String)>[];
    // De banner wijst de lezer naar de licentiesectie bij naam; die naam is
    // gelokaliseerd (zie [_noticesHtml]), dus de verwijzing hoort mee te
    // bewegen met de exporttaal. #1249
    const l10n = AppLocalizations(Locale('nl'));
    final licencesHeading = l10n.d('Licenties van derden');
    try {
      final manifest =
          jsonDecode(await loadAsset('$_assetDir/MANIFEST.json'))
              as Map<String, dynamic>;
      final bundles = (manifest['bundles'] as List)
          .cast<Map<String, dynamic>>();

      for (final b in bundles) {
        final npm = b['npm'] as String?;
        if (npm == null) continue; // hash-pinned CSS, covered by highlight.js
        final entry = BundledLicenses.forNpm(npm);
        if (entry == null) continue;
        final version = b['version'] as String? ?? '';
        final label = '${entry.component} $version';
        banners[npm] =
            '/*! @license $label — ${entry.license}. '
            'Full licence text: see "$licencesHeading" at the end of this '
            'file, or ${entry.source} */\n';
        texts.add((label, await loadAsset(entry.licenseAsset)));
      }

      if (embedsFont) {
        final font = BundledLicenses.all.firstWhere(
          (e) => e.component.startsWith('EB Garamond'),
        );
        texts.add((font.component, await loadAsset(font.licenseAsset)));
      }
    } catch (e) {
      logWarning('MarpHtmlService.thirdPartyNotices: load notice assets', e);
      return const ExportNotices(banners: {}, html: '');
    }

    return ExportNotices(banners: banners, html: _noticesHtml(texts));
  }

  /// The collapsible notice block appended to every export.
  ///
  /// A `<details>` rather than an HTML comment for two reasons: a comment may
  /// not contain `--`, which the OFL text does three times, and a notice nobody
  /// can read is not much of a notice. It is collapsed by default and hidden in
  /// print, so a deck still prints as a deck.
  static String _noticesHtml(List<(String, String)> texts) {
    if (texts.isEmpty) return '';
    const l10n = AppLocalizations(Locale('nl'));
    final body = StringBuffer();
    for (final (label, text) in texts) {
      body
        ..write('<h3>${_htmlText(label)}</h3>')
        ..write('<pre>${_htmlText(text.trimRight())}</pre>');
    }
    return '<style>'
        '.ocideck-licenses{max-width:1280px;margin:24px auto 48px;padding:0 24px;'
        'color:#c8c8c8;font:12px/1.5 -apple-system,"Segoe UI",Roboto,sans-serif}'
        '.ocideck-licenses h3{font-size:12px;margin:14px 0 4px}'
        '.ocideck-licenses pre{white-space:pre-wrap;font-size:11px}'
        '@media print{.ocideck-licenses{display:none}}'
        '</style>'
        '<details class="ocideck-licenses">'
        '<summary>${_htmlText(l10n.d('Licenties van derden'))}</summary>'
        '<p>${_htmlText(l10n.d('Dit bestand bevat software van derden en soms een lettertype. Hieronder staan de volledige licentieteksten die daarbij horen; stuur ze mee als je dit bestand doorgeeft.'))}</p>'
        '$body'
        '</details>';
  }

  static List<String> marpSlides(String markdown) {
    // Front matter weg (dezelfde strip als de documentmodus, zie
    // [_stripFrontMatter]), daarna splitsen op de `---`-scheidingen.
    final text = _stripFrontMatter(markdown);
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

  // ── Charts → inline SVG ────────────────────────────────────────────────────

  /// Y-01 uit de export-markdown (resolve-at-draw voor histogramlimieten).
  static ImprovementY01Metric _y01FromExportMarkdown(String markdown) =>
      MarkdownService().parseDeck(markdown)?.improvementY01Metric ??
      ImprovementY01Metric.empty;

  /// Replace ```chart fenced blocks with a self-contained inline SVG, so the
  /// exported HTML renders charts without any JS chart library.
  static String renderChartBlocks(
    String slideMarkdown, {
    ThemeProfile? theme,
    ImprovementY01Metric y01 = ImprovementY01Metric.empty,
  }) {
    return slideMarkdown.replaceAllMapped(chartFencePattern, (m) {
      final spec = ChartSpec.parse(m.group(1)!);
      return '\n<div class="chart">${_chartSvg(spec, theme, y01: y01)}</div>\n';
    });
  }

  /// De zelfstandige SVG van één grafiek-spec voor de documentweergave (zelfde
  /// renderlaag als de HTML-export, §4.2). [background] = kaartkleur, zie [_chartSvg].
  static String chartSpecSvg(
    ChartSpec spec,
    ThemeProfile? theme, {
    ImprovementY01Metric y01 = ImprovementY01Metric.empty,
    String? background,
  }) => _chartSvg(spec, theme, y01: y01, background: background);

  // ── Question → HTML ───────────────────────────────────────────────────────

  static final RegExp _questionFence = RegExp(
    r'```question[ \t]*\n([\s\S]*?)\n```',
    multiLine: true,
  );

  /// Maak een bijschrift veilig als alt-tekst in Markdown: de haken zouden de
  /// afbeeldingsverwijzing anders vroegtijdig afsluiten.
  static String _markdownAltText(String raw) => raw
      .replaceAll('[', '(')
      .replaceAll(']', ')')
      .replaceAll('\n', ' ')
      .trim();

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
      if (!spec.hasValidAnswerCount) {
        const l10n = AppLocalizations(Locale('nl'));
        return '\n<div class="question question-invalid">'
            '<p class="question-prompt">'
            '${l10n.d('Ongeldige vraag')} · '
            '${l10n.d('Maximaal aantal items')}: '
            '${spec.answerCountLimit} · ${l10n.d('Antwoorden')}: '
            '${spec.sourceAnswerCount}'
            '</p></div>\n';
      }
      final b = StringBuffer('\n<div class="question">');
      if (spec.prompt.trim().isNotEmpty) {
        b.write('<p class="question-prompt">${_htmlText(spec.prompt)}</p>');
      }
      final options = switch (spec.kind) {
        QuestionKind.trueFalse => const ['Waar', 'Niet waar'],
        // Een getypt antwoord heeft geen opties om te tonen — en de goed
        // gerekende antwoorden zijn hier juist de antwoordsleutel. Die horen
        // niet in een document dat rondgestuurd wordt.
        QuestionKind.openText => const <String>[],
        // Bij een beeldparen-vraag zíjn de antwoorden de afbeeldingen; de
        // tekst is hooguit bijschrift en zonder het beeld betekenisloos.
        QuestionKind.imagePair => const <String>[],
        _ => [
          for (final a in spec.answers)
            if (a.text.trim().isNotEmpty) a.text,
        ],
      };
      if (options.isNotEmpty) {
        b.write('<ul class="question-options">');
        for (final o in options) {
          b.write('<li>${_htmlText(o)}</li>');
        }
        b.write('</ul>');
      }
      b.write('</div>\n');
      // Bij een beeldparen-vraag zijn de twee afbeeldingen de opties. Ze gaan
      // er als gewone Markdown achteraan en niet als HTML in de kaart: zo
      // worden hun paden precies zo opgelost als elke andere afbeelding in het
      // deck, zonder een tweede route die apart bijgehouden moet worden.
      if (spec.kind == QuestionKind.imagePair) {
        final images = [
          for (final a in spec.answers)
            if (a.image.trim().isNotEmpty)
              '![${_markdownAltText(a.text)}](${a.image})',
        ];
        if (images.isNotEmpty) b.write('\n${images.join(' ')}\n');
      }
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

  /// De velden die [renderSignOffBlock] verwacht, uit een [DocumentSignature].
  ///
  /// De sleutelnamen zijn die van de oude front matter. Dat is geen nostalgie
  /// maar het punt: zo blijven de nieuwe route (het deck levert de
  /// handtekening) en het terugvalpad ([signatureFields], een `.md` van vóór
  /// 0.1.0) door dezelfde renderer lopen, en kan de akkoordpagina er niet op
  /// twee manieren uit gaan zien.
  static Map<String, String> signatureFieldsOf(
    DocumentSignature sig, {
    String sealedAt = '',
  }) {
    final out = <String, String>{};
    void put(String key, String value) {
      if (value.trim().isNotEmpty) out[key] = value.trim();
    }

    put('ocideck_sig_name', sig.name);
    put('ocideck_sig_role', sig.role);
    put('ocideck_sig_cert', sig.certification);
    put('ocideck_sig_date', sig.date);
    put('ocideck_sig_statement', sig.statement);
    put('ocideck_sig_typed', sig.typedSignature);
    put('ocideck_seal_at', sealedAt);
    return out;
  }

  /// Leest de `ocideck_sig_*`- en `ocideck_seal_at`-regels uit de voorpagina
  /// van [deckMarkdown].
  ///
  /// Alleen nog het terugvalpad voor een `.md` van vóór 0.1.0, toen die regels
  /// daar stonden. Een deck dat door OciDeck komt levert zijn handtekening via
  /// [ExportDocumentMetadata]; deze route bestaat voor markdown die van elders
  /// komt en de oude kop nog draagt.
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
        '.slide td{color:${t.tableTextColor};border:1px solid #ccc;padding:6px 12px;font-size:20px}'
        '\n${_themedDocumentCss(t, family, codeFamily)}';
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
    // AI-verordening art. 50: de markering moet machineleesbaar zijn. Een
    // `<meta>` is dat; de balk hierboven is voor de lezer.
    final aiMarking = meta.htmlAiMarking;
    if (aiMarking != null) {
      tag('ai-generated', aiMarking);
      tag('ai-generated-slides', '${meta.unreviewedAiSlideCount}');
    }
    tag('generator', meta.producer);
    return buf.toString();
  }
}
