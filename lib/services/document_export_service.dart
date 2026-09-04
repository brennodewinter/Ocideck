import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../models/privacy_disposition.dart';
import '../models/deck.dart';
import '../models/settings.dart' show ThemeProfile;
import '../models/page_size.dart';
import 'table_of_contents.dart';
import '../utils/atomic_file.dart';
import 'document_chart_hydration.dart';
import 'classification_enforcement_policy.dart';
import 'document_deck_bridge.dart';
import 'download_delivery.dart';
import 'document_footnote_setup.dart';
import 'document_page_setup.dart';
import 'footnotes_html.dart';
import 'export_bundle.dart';
import 'export_metadata.dart';
import 'latex/latex_preamble.dart';
import 'latex/markdown_to_latex.dart';
import 'markdown_service.dart';
import 'marp_html_service.dart';
import 'pdf/document_pdf_export.dart';
import 'epub/document_epub_export.dart';
import 'odt/document_odt_export.dart';
import 'docx/document_docx_export.dart';
import 'privacy/privacy_own_identity.dart';
import '../utils/document_front_matter.dart';

/// De uitvoervormen van een plat-Markdown-**document** (DOCUMENT_MODE.md
/// §11.2): het geprojecteerde `.md` zelf, één doorlopend HTML-document, een
/// LaTeX `article`, een PDF met een echte tekstlaag, een ePub 3 met
/// herflowbare tekst voor e-readers, een ODT (OpenDocument Text) als
/// bewerkbaar open formaat, en een DOCX (WordprocessingML) als bewerkbaar
/// Word-bestand met Mermaid-diagrammen als hoogwaardige afbeeldingen. Alle
/// zeven dragen de geredigeerde body — nooit de rauwe bron.
enum DocumentExportFormat { md, html, latex, pdf, epub, odt, docx }

/// Ruim onder de gangbare limiet van 255 bytes per padcomponent.
const maxSuggestedDocumentExportFileNameBytes = 240;

/// De veilige voorgestelde bestandsnaam voor een documentexport.
///
/// De aanroeper geeft hier de titel uit het geprojecteerde deck door; daardoor
/// kan een geredigeerde titel niet via de bestandskiezer alsnog uitlekken.
String suggestedDocumentExportFileName({
  required String title,
  required DocumentExportFormat format,
  required PrivacyExportProfile profile,
  required String redactedLabel,
  required String fullLabel,
  required String fallbackLabel,
}) {
  final ext = switch (format) {
    DocumentExportFormat.md => 'md',
    DocumentExportFormat.html => 'html',
    DocumentExportFormat.latex => 'tex',
    DocumentExportFormat.pdf => 'pdf',
    DocumentExportFormat.epub => 'epub',
    DocumentExportFormat.odt => 'odt',
    DocumentExportFormat.docx => 'docx',
  };
  final tag = profile == PrivacyExportProfile.redacted
      ? redactedLabel
      : fullLabel;
  final source = title.isEmpty ? fallbackLabel : title;
  final cleaned = source
      .replaceAll(RegExp(r'[^\p{L}\p{N}\- ]+', unicode: true), '')
      .trim()
      .replaceAll(RegExp(r'[\s]+'), '-');
  final base = cleaned.isEmpty ? fallbackLabel : cleaned;
  final suffix = '-$tag.$ext';
  final budget =
      maxSuggestedDocumentExportFileNameBytes - utf8.encode(suffix).length;
  final boundedBase = _truncateUtf8(
    base,
    budget,
  ).replaceFirst(RegExp(r'-+$'), '');
  return '${boundedBase.isEmpty ? 'd' : boundedBase}$suffix';
}

String _truncateUtf8(String value, int maxBytes) {
  if (maxBytes <= 0) return '';
  final out = StringBuffer();
  var bytes = 0;
  for (final rune in value.runes) {
    final encoded = utf8.encode(String.fromCharCode(rune)).length;
    if (bytes + encoded > maxBytes) break;
    out.writeCharCode(rune);
    bytes += encoded;
  }
  return out.toString();
}

/// Bouwt de exportbundel voor een plat-Markdown-**document**, langs exact
/// dezelfde privacygrens als het deck-exportpad.
///
/// Headless: de enige IO is de grafiek-hydratatie (die externe `data/*.json`
/// binnen de projectmap inleest, §11.2 stap 1). De rest is zuivere compositie —
/// hydrateer de charts, deconstrueer het document verliesloos tot een getypeerd
/// [Deck] (`DocumentDeckBridge.documentToDeck`), en laat dat door
/// [buildExportBundle] gaan. Vanaf die bundel raakt geen enkel uitvoerpad de
/// bron nog aan: de geprojecteerde (geredigeerde) body komt uit
/// `bundle.audience.deck`.
///
/// `includeDetail` staat vast op `true`: een document is één stroom en kent geen
/// verdiepingsdia's om weg te laten.
Future<ExportBundle> buildDocumentExportBundle(
  String body, {
  required String? projectPath,
  required PrivacyExportProfile profile,
  required OwnIdentity ownIdentity,
  required Set<String> regions,
  required Set<String> disabledRules,
  required MarkdownService markdownService,
  String title = '',
  ThemeProfile? theme,
  TlpLevel tlp = TlpLevel.none,
  Map<String, String> fields = const {},
}) async {
  final hydrated = await hydrateDocumentChartData(
    body,
    projectPath: projectPath,
  );
  final baseDeck = DocumentDeckBridge.documentToDeck(
    hydrated,
    projectPath: projectPath,
    title: title,
    tlp: tlp,
    fields: fields,
  );
  final deck = theme == null
      ? baseDeck
      : baseDeck.copyWith(themeProfile: theme);
  return buildExportBundle(
    deck,
    deck.slides,
    profile: profile,
    includeDetail: true,
    // Een document is één stroom en kent geen dia-pagina's; geen enkel
    // documentuitvoerpad rasteriseert (md/html/latex). Uitklappen zou hier N
    // kopieën van dezelfde body over de projectiegrens duwen (#1589).
    expandPages: false,
    disabledRules: disabledRules,
    ownIdentity: ownIdentity,
    regions: regions,
    markdownService: markdownService,
  );
}

/// De geprojecteerde (geredigeerde) documentbody, gelezen uit de bundel.
///
/// Leest defensief over álle dia's van het geprojecteerde deck — nooit
/// `.single`. Een document dat door de bridge is gegaan, valt uiteen in een dia
/// per kop-sectie, elke tabel en elk grafiekblok apart; `deckToDocumentMarkdown`
/// naait die weer aaneen tot één vloeiend document.
String projectedDocumentBody(ExportBundle bundle) =>
    DocumentDeckBridge.deckToDocumentMarkdown(bundle.audience.deck);

/// Bouwt de bytes voor een document-export in [format]. Headless: geen IO.
///
/// Op desktop schrijft [writeDocumentExport] deze bytes atomisch weg; op web
/// biedt hij ze via `deliverAsDownload` als browser-download aan. De
/// PDF-callbacks ([onPdfUnsupportedCharacters], [onPdfCoarseLogo]) vuren in
/// beide paden — een teken dat de tekstlaag niet kent, of een te grof logo,
/// is geen schrijffout maar een bronprobleem dat de auteur hoort te weten.
///
/// Een **audience**-oppervlak: de inhoud die de deur uit gaat komt uit
/// [projectedDocumentBody] — de geprojecteerde body via de bundel, nooit de
/// rauwe bron. Daarom neemt deze functie een [ExportBundle] en geen `Deck` of
/// `List<Slide>`; die vorm is precies wat de compile-time projectiegrens
/// (`tool/check_audience_boundary.dart`) verlangt.
@visibleForTesting
Future<Uint8List> buildDocumentExportBytes(
  ExportBundle bundle,
  DocumentExportFormat format, {
  required MarpHtmlService html,
  ExportDocumentMetadata? metadata,
  HtmlImageResolver? embedImage,
  bool chapterPageBreak = false,
  bool cropMarks = false,
  PageSizeSpec? pageSize,
  PageMargins? pageMargins,
  FootnotePlacement footnotePlacement = FootnotePlacement.page,
  String footnotesTitle = 'Noten',
  DocumentPdfLabels? pdfLabels,
  List<ByteData> pdfFallbackFonts = const [],
  MermaidSvgResolver? renderMermaid,
  MathSvgResolver? renderMath,
  void Function(Set<int> runes)? onPdfUnsupportedCharacters,
  void Function(LogoResolution logo)? onPdfCoarseLogo,
  void Function(int count)? onPdfTablesTooWide,
  String? sourcePath,
  String? outputPath,
}) async {
  final theme = bundle.audience.deck.themeProfile;
  final projectedMetadata = ExportDocumentMetadata.fromDeck(bundle.audience);
  final exportMetadata = metadata == null
      ? projectedMetadata
      : projectedMetadata.withLanguage(metadata.language);
  final documentFields = bundle.audience.deck.documentFields;
  final chromeFields = _documentChromeFields(bundle.audience.deck);
  switch (format) {
    case DocumentExportFormat.md:
      final md = _projectedMarkdown(
        bundle,
        pageSize: pageSize,
        pageMargins: pageMargins,
        footnotePlacement: footnotePlacement,
        documentFields: documentFields,
      );
      return Uint8List.fromList(
        utf8.encode(_rebaseImagePaths(md, sourcePath, outputPath ?? '')),
      );
    case DocumentExportFormat.html:
      // Feature 4: regenereer de TOC op de geprojecteerde body vóór renderen.
      // De marker blijft staan; marked rendert de GFM-lijst als klikbare nav.
      final htmlBody = projectedDocumentBody(bundle);
      final toc = generateTocMarkdown(htmlBody);
      final htmlBodyWithToc = hasTocMarker(htmlBody)
          ? replaceTocMarker(htmlBody, toc)
          : htmlBody;
      // `marked` kent geen voetnoten, dus die worden hier al omgezet: merkteken
      // met een sprong, en de noten achteraan. Achteraan ook wanneer het
      // document om onderaan-de-bladzijde vraagt — een HTML-pagina heeft geen
      // bladzijden (KNOWN_LIMITATIONS.md).
      final out = await html.build(
        documentWithHtmlFootnotes(htmlBodyWithToc, title: footnotesTitle),
        continuous: true,
        chapterPageBreak: chapterPageBreak,
        theme: theme,
        metadata: exportMetadata,
        documentFields: chromeFields,
        embedImage: embedImage,
        pageSize: pageSize,
        pageMargins: pageMargins,
      );
      return Uint8List.fromList(utf8.encode(out));
    case DocumentExportFormat.latex:
      final meta = exportMetadata;
      final body = markdownToLatex(
        _rebaseImagePaths(
          projectedDocumentBody(bundle),
          sourcePath,
          outputPath ?? '',
        ),
        chapterPageBreak: chapterPageBreak,
        tableBorderStyle: theme.tableBorderStyle,
        tableTheme: theme,
        footnotePlacement: footnotePlacement,
        endnotesTitle: footnotesTitle,
      );
      final tex =
          '${articlePreamble(meta, theme: theme, documentFields: chromeFields, pageSize: pageSize ?? PageSizeSpec.a4, pageMargins: pageMargins ?? const PageMargins(), cropMarks: cropMarks)}\n$body\n$articlePostamble\n';
      return Uint8List.fromList(utf8.encode(tex));
    case DocumentExportFormat.pdf:
      return _buildPdfBytes(
        bundle,
        exportMetadata: exportMetadata,
        pdfLabels: pdfLabels,
        pdfFallbackFonts: pdfFallbackFonts,
        embedImage: embedImage,
        renderMermaid: renderMermaid,
        renderMath: renderMath,
        chapterPageBreak: chapterPageBreak,
        cropMarks: cropMarks,
        pageSize: pageSize,
        pageMargins: pageMargins,
        footnotesTitle: footnotesTitle,
        onPdfUnsupportedCharacters: onPdfUnsupportedCharacters,
        onPdfCoarseLogo: onPdfCoarseLogo,
        onPdfTablesTooWide: onPdfTablesTooWide,
      );
    case DocumentExportFormat.epub:
      // ePub 3: herflowbare XHTML in een EPUB-ZIP. Afbeeldingen worden als
      // aparte entries opgeslagen en via relatieve paden gereferend — niet
      // als data-URI's zoals HTML. De `embedImage`-callback levert hier de
      // ruwe bytes op via een aparte resolver (zie document_epub_export.dart).
      return buildDocumentExportEpub(
        bundle,
        metadata: exportMetadata,
        chapterPageBreak: chapterPageBreak,
        footnotesTitle: footnotesTitle,
        embedImage: embedImage,
        sourcePath: sourcePath,
        outputPath: outputPath ?? '',
      );
    case DocumentExportFormat.odt:
      // ODT (OpenDocument Text, ISO 26300): bewerkbare OpenDocument-XML in
      // een ZIP. Native voetnoten, koppen met outline-levels, tabellen en
      // afbeeldingen als aparte entries — hetzelfde `embedImage`-pad als ePub.
      return buildDocumentExportOdt(
        bundle,
        metadata: exportMetadata,
        chapterPageBreak: chapterPageBreak,
        footnotePlacement: footnotePlacement,
        footnotesTitle: footnotesTitle,
        embedImage: embedImage,
        sourcePath: sourcePath,
        outputPath: outputPath ?? '',
      );
    case DocumentExportFormat.docx:
      return _buildDocxBytes(
        bundle,
        exportMetadata: exportMetadata,
        chapterPageBreak: chapterPageBreak,
        footnotePlacement: footnotePlacement,
        footnotesTitle: footnotesTitle,
        embedImage: embedImage,
        renderMermaid: renderMermaid,
        renderMath: renderMath,
        sourcePath: sourcePath,
        outputPath: outputPath ?? '',
      );
  }
}

/// DOCX (WordprocessingML / OOXML): bewerkbare Word-XML in een ZIP, met
/// native voetnoten, koppen met outline-levels, en Mermaid-diagrammen
/// als hoogwaardige PNG-afbeeldingen (gerasteriseerd via flutter_svg).
/// Hetzelfde `embedImage`-pad als ODT/ePub; `renderMermaid`/`renderMath`
/// hetzelfde als de PDF.
Future<Uint8List> _buildDocxBytes(
  ExportBundle bundle, {
  required ExportDocumentMetadata exportMetadata,
  required bool chapterPageBreak,
  required FootnotePlacement footnotePlacement,
  required String footnotesTitle,
  required HtmlImageResolver? embedImage,
  required MermaidSvgResolver? renderMermaid,
  required MathSvgResolver? renderMath,
  required String? sourcePath,
  required String outputPath,
}) => buildDocumentExportDocx(
  bundle,
  metadata: exportMetadata,
  chapterPageBreak: chapterPageBreak,
  footnotePlacement: footnotePlacement,
  footnotesTitle: footnotesTitle,
  embedImage: embedImage,
  renderMermaid: renderMermaid,
  renderMath: renderMath,
  sourcePath: sourcePath,
  outputPath: outputPath,
);

/// PDF-export met tekstlaag. De callbacks melden tekens die geen snede kent,
/// een te grof logo, en te brede tabellen — zeggen is het enige wat er nog
/// aan te doen valt (#1789).
Future<Uint8List> _buildPdfBytes(
  ExportBundle bundle, {
  required ExportDocumentMetadata exportMetadata,
  required DocumentPdfLabels? pdfLabels,
  required List<ByteData> pdfFallbackFonts,
  required HtmlImageResolver? embedImage,
  required MermaidSvgResolver? renderMermaid,
  required MathSvgResolver? renderMath,
  required bool chapterPageBreak,
  required bool cropMarks,
  required PageSizeSpec? pageSize,
  required PageMargins? pageMargins,
  required String footnotesTitle,
  required void Function(Set<int> runes)? onPdfUnsupportedCharacters,
  required void Function(LogoResolution logo)? onPdfCoarseLogo,
  required void Function(int count)? onPdfTablesTooWide,
}) async {
  final result = await buildDocumentExportPdf(
    bundle,
    labels:
        pdfLabels ??
        DocumentPdfLabels(
          footnotesTitle: footnotesTitle,
          mathLabel: 'math',
          mermaidLabel: 'mermaid',
          chartLabel: 'chart',
        ),
    fallbackFonts: pdfFallbackFonts,
    embedImage: embedImage,
    renderMermaid: renderMermaid,
    renderMath: renderMath,
    chapterPageBreak: chapterPageBreak,
    cropMarks: cropMarks,
    pageSize: pageSize,
    pageMargins: pageMargins,
    metadata: exportMetadata,
  );
  if (!result.isComplete) {
    onPdfUnsupportedCharacters?.call(result.unsupportedCharacters);
  }
  final coarse = result.coarseLogo;
  if (coarse != null) onPdfCoarseLogo?.call(coarse);
  if (result.tablesTooWide > 0) {
    onPdfTablesTooWide?.call(result.tablesTooWide);
  }
  return result.bytes;
}

/// Schrijft een document-export naar [outputPath] (desktop) of als
/// browser-download via [webFileName] (web), in het gevraegde [format].
///
/// Een **audience**-oppervlak: de inhoud die de deur uit gaat komt uit
/// [projectedDocumentBody] — de geprojecteerde body via de bundel, nooit de
/// rauwe bron. Daarom neemt deze functie een [ExportBundle] en geen `Deck` of
/// `List<Slide>`; die vorm is precies wat de compile-time projectiegrens
/// (`tool/check_audience_boundary.dart`) verlangt van een schrijver die
/// `writeBytesAtomic` of `deliverAsDownload` raakt.
///
/// - [DocumentExportFormat.md] schrijft de geprojecteerde body atomisch weg,
///   met de geldende paginaopmaak ([pageSize]/[pageMargins]) in Pandoc-front
///   matter ervoor — anders dan de stijl reist de maat wél mee (zie de
///   toelichting in die tak, en FILE_FORMAT.md §14.4).
/// - [DocumentExportFormat.html] rendert die body als één doorlopend HTML-
///   document (`continuous: true`) en schrijft het resultaat atomisch weg.
/// - [DocumentExportFormat.latex] zet de geprojecteerde body om naar een
///   LaTeX `article`-document (preamble + body + postamble) en schrijft het
///   resultaat atomisch weg. Afbeeldingen worden op relatief pad
///   gereferentieerd — LaTeX kent geen data-URI-inlining.
/// - [DocumentExportFormat.pdf] zet de geprojecteerde body als een PDF met een
///   echte tekstlaag (te selecteren, te doorzoeken). De tekstlaag is met een
///   gewone lezer uit te pakken, dus een geredigeerd gegeven dat er tóch in
///   belandt is even leesbaar als in de `.md` — de fail-closed test meet dan
///   ook op de geleverde bytes (test/pdf/document_pdf_export_privacy_test.dart).
/// - [DocumentExportFormat.epub] verpakt de geprojecteerde body als ePub 3:
///   herflowbare XHTML in een EPUB-ZIP, met koppen als navigatie en noten
///   achterin. De XHTML-tekst is leesbaar in de ZIP, dus de fail-closed test
///   kan op de geleverde bytes meten — vergelijkbaar met PDF.
/// - [DocumentExportFormat.odt] verpakt de geprojecteerde body als ODT
///   (OpenDocument Text, ISO 26300): bewerkbare OpenDocument-XML in een ZIP,
///   met native voetnoten en koppen met outline-levels. De XML-tekst is
///   leesbaar in de ZIP, dus de fail-closed test kan op de geleverde bytes
///   meten — vergelijkbaar met PDF en ePub.
/// - [DocumentExportFormat.docx] verpakt de geprojecteerde body als DOCX
///   (WordprocessingML / OOXML): bewerkbare Word-XML in een ZIP, met native
///   voetnoten, koppen met outline-levels, en Mermaid-diagrammen als
///   hoogwaardige PNG-afbeeldingen. Opent in Word, Pages en LibreOffice.
///
/// Op web ([deliversByDownload]) is er geen bestandssysteem: [webFileName]
/// wordt dan de bestandsnaam van de browser-download, en [outputPath] wordt
/// genegeerd. Op desktop is [outputPath] het pad dat atomisch wordt beschreven,
/// en [webFileName] wordt genegeerd.
///
/// Geeft het geschreven pad (desktop) of de bestandsnaam (web) terug, of
/// `null` bij een geblokkeerde classificatie of wanneer het doel gelijk is
/// aan de bron.
Future<String?> writeDocumentExport(
  ExportBundle bundle,
  DocumentExportFormat format, {
  required MarpHtmlService html,
  required ClassificationEnforcementPolicy enforcementPolicy,
  ExportDocumentMetadata? metadata,
  HtmlImageResolver? embedImage,
  bool chapterPageBreak = false,
  bool cropMarks = false,
  PageSizeSpec? pageSize,
  PageMargins? pageMargins,
  FootnotePlacement footnotePlacement = FootnotePlacement.page,
  String footnotesTitle = 'Noten',
  DocumentPdfLabels? pdfLabels,
  List<ByteData> pdfFallbackFonts = const [],
  MermaidSvgResolver? renderMermaid,
  MathSvgResolver? renderMath,
  void Function(Set<int> runes)? onPdfUnsupportedCharacters,
  void Function(LogoResolution logo)? onPdfCoarseLogo,
  void Function(int count)? onPdfTablesTooWide,
  String? outputPath,
  String? sourcePath,
  String? webFileName,
}) async {
  if (!deliversByDownload) {
    if (outputPath == null) return null;
    if (await _sameFile(sourcePath, outputPath)) return null;
  }
  if (!enforcementPolicy.evaluate(bundle.audience.deck.tlp).allowed) {
    return null;
  }
  final bytes = await buildDocumentExportBytes(
    bundle,
    format,
    html: html,
    metadata: metadata,
    embedImage: embedImage,
    chapterPageBreak: chapterPageBreak,
    cropMarks: cropMarks,
    pageSize: pageSize,
    pageMargins: pageMargins,
    footnotePlacement: footnotePlacement,
    footnotesTitle: footnotesTitle,
    pdfLabels: pdfLabels,
    pdfFallbackFonts: pdfFallbackFonts,
    renderMermaid: renderMermaid,
    renderMath: renderMath,
    onPdfUnsupportedCharacters: onPdfUnsupportedCharacters,
    onPdfTablesTooWide: onPdfTablesTooWide,
    onPdfCoarseLogo: onPdfCoarseLogo,
    sourcePath: sourcePath,
    outputPath: deliversByDownload ? null : outputPath,
  );
  if (deliversByDownload) {
    // Web: geen bestandssysteem — de bytes vertrekken als browserdownload.
    // `null` betekent dat de browser hem niet aannam; de schil zegt dat dan
    // ook, in plaats van een bestandsnaam te melden die nergens staat (#1902).
    return deliverAsDownload([
      (name: webFileName!, bytes: bytes),
    ], bundleName: bundleNameFor(webFileName));
  }
  await writeBytesAtomic(File(outputPath!), bytes);
  return outputPath;
}

Future<bool> _sameFile(String? sourcePath, String outputPath) async {
  if (sourcePath == null) return false;
  final source = p.normalize(p.absolute(sourcePath));
  final output = p.normalize(p.absolute(outputPath));
  if (p.equals(source, output)) return true;
  try {
    return await FileSystemEntity.identical(source, output);
  } on FileSystemException {
    return false;
  }
}

/// Herbaset relatieve afbeeldingspaden in [markdown] van de bronmap naar de
/// uitvoermap, zodat een .md- of .tex-export buiten de projectmap de beelden
/// blijft vinden (#1673). Absolute paden, URL's en data-URI's blijven staan.
///
/// [pathContext] bestaat alleen voor de toets: daarmee kan een macOS-machine de
/// Windows-padstijl doorrekenen. Laat hem weg en de stijl van het draaiende
/// platform geldt.
@visibleForTesting
String rebaseImagePathsForTesting(
  String markdown,
  String? sourcePath,
  String outputPath, {
  p.Context? pathContext,
}) => _rebaseImagePaths(
  markdown,
  sourcePath,
  outputPath,
  pathContext: pathContext,
);

String _rebaseImagePaths(
  String markdown,
  String? sourcePath,
  String outputPath, {
  p.Context? pathContext,
}) {
  if (sourcePath == null) return markdown;
  final ctx = pathContext ?? p.context;
  final sourceDir = ctx.dirname(sourcePath);
  final outputDir = ctx.dirname(outputPath);
  if (ctx.equals(sourceDir, outputDir)) return markdown;
  return markdown.replaceAllMapped(RegExp(r'!\[([^\]]*)\]\(([^)]+)\)'), (m) {
    final alt = m.group(1)!;
    final raw = m.group(2)!;
    // Alleen relatieve paden zonder schema — URL's en data-URI's blijven.
    if (raw.startsWith('http://') ||
        raw.startsWith('https://') ||
        raw.startsWith('data:') ||
        ctx.isAbsolute(raw)) {
      return m[0]!;
    }
    // Scheid bron en titel (`bron "titel"`).
    final space = raw.indexOf(RegExp(r'\s'));
    final src = space < 0 ? raw : raw.substring(0, space);
    final title = space < 0 ? '' : raw.substring(space);
    final abs = ctx.normalize(ctx.join(sourceDir, src));
    final rebased = ctx.relative(abs, from: outputDir);
    // Een Markdown-verwijzing is een URL, geen bestandspad: daar scheidt '/',
    // ook op Windows. `relative` levert de padstijl van het platform, dus zonder
    // deze omzetting schreef een export op Windows `![Alt](..\\map\\foto.png)` —
    // een link die geen enkele renderer volgt en die in LaTeX bovendien als
    // ontsnappingsteken leest. Kan er geen relatief pad bestaan (op Windows: een
    // ander station), dan geeft `relative` het absolute pad terug; dat wordt een
    // file-URL in plaats van een half omgezet pad.
    final target = ctx.isAbsolute(rebased)
        ? ctx.toUri(rebased).toString()
        : p.url.joinAll(ctx.split(rebased));
    return '![$alt]($target$title)';
  });
}

/// De geprojecteerde body plus alles wat als front matter meereist.
///
/// **De paginaopmaak reist wél mee, de stijl niet** — en dat is geen
/// inconsistentie maar het verschil tussen een verwijzing en een maat. `theme:`
/// noemt een stijlprofiel dat alleen op déze machine bestaat: bij de ontvanger
/// zou de naam nergens naar wijzen, dus wordt de stijl vóór export opgelost en
/// in de uitvoer zelf gerenderd (§14.5). `papersize:` en `geometry:` zijn geen
/// verwijzing maar het vel zelf, in millimeters die overal hetzelfde betekenen,
/// en ze horen bij hoe dít drukwerk eruit moet komen — een afloop is een
/// eigenschap van de opdracht, niet van de lezer. Daarom staat hier de opmaak
/// die op dit moment geldt, juist ook wanneer die alleen in de instellingen
/// stond: de ontvanger heeft die instellingen niet. Zie FILE_FORMAT.md §14.4.
///
/// Om dezelfde reden reist de plaatsing van de noten mee (#1569):
/// `reference-location:` is een instructie die Pandoc en Quarto zelf uitvoeren.
/// `page` schrijft niets, en dat is geen vergeetachtigheid — onderaan de
/// bladzijde is wat elke lezer zonder aanwijzing al doet, dus een document dat
/// niets bijzonders wil houdt een export zonder front matter (§14.9).
String _projectedMarkdown(
  ExportBundle bundle, {
  required PageSizeSpec? pageSize,
  required PageMargins? pageMargins,
  required FootnotePlacement footnotePlacement,
  required Map<String, String> documentFields,
}) {
  // Feature 4: vervang de `<!-- toc -->`-marker door de gegenereerde GFM-lijst
  // (zonder marker) — een platte `.md`-ontvanger krijgt een leesbare
  // inhoudsopgave.
  //
  // `keepMarker: false` laat de marker weg maar houdt de TOC op zijn plek.
  // Eerder ging dat via een losse `replaceAll('<!-- toc -->\n\n', '')`, en die
  // trof niets wanneer het document wél een marker draagt maar (nog) geen
  // koppen: dan blijft de kale marker over, zónder de twee regeleindes, en lekte
  // hij het geëxporteerde bestand in.
  final body = projectedDocumentBody(bundle);
  final withToc = hasTocMarker(body)
      ? replaceTocMarker(body, generateTocMarkdown(body), keepMarker: false)
      : body;
  final tlp = bundle.audience.deck.tlp;
  return withDocumentFields(
    withDocumentFrontMatterKey(
      withDocumentFootnotePlacement(
        withDocumentPageSetup(withToc, size: pageSize, margins: pageMargins),
        footnotePlacement,
      ),
      'tlp',
      tlp == TlpLevel.none ? null : tlp.key,
    ),
    documentFields,
  );
}

Map<String, String> _documentChromeFields(Deck deck) => {
  ...deck.documentFields,
  'title': deck.title,
  'subtitle': deck.description,
  'author': deck.author,
};
