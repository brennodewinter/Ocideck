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
import 'privacy/privacy_own_identity.dart';
import '../utils/document_front_matter.dart';

/// De uitvoervormen van een plat-Markdown-**document** (DOCUMENT_MODE.md
/// §11.2): het geprojecteerde `.md` zelf, één doorlopend HTML-document, een
/// LaTeX `article`, en een PDF met een echte tekstlaag. Alle vier dragen de
/// geredigeerde body — nooit de rauwe bron.
enum DocumentExportFormat { md, html, latex, pdf }

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

/// Schrijft een document-export naar [outputPath] in het gevraagde [format].
///
/// Een **audience**-oppervlak: de inhoud die de deur uit gaat komt uit
/// [projectedDocumentBody] — de geprojecteerde body via de bundel, nooit de
/// rauwe bron. Daarom neemt deze functie een [ExportBundle] en geen `Deck` of
/// `List<Slide>`; die vorm is precies wat de compile-time projectiegrens
/// (`tool/check_audience_boundary.dart`) verlangt van een schrijver die
/// `writeStringAtomic` raakt.
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
///
/// Geeft het geschreven pad terug.
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
  ByteData? pdfFallbackFont,
  MermaidSvgResolver? renderMermaid,
  MathSvgResolver? renderMath,
  void Function(Set<int> runes)? onPdfUnsupportedCharacters,
  void Function(LogoResolution logo)? onPdfCoarseLogo,
  required String outputPath,
  String? sourcePath,
}) async {
  if (await _sameFile(sourcePath, outputPath)) return null;
  if (!enforcementPolicy.evaluate(bundle.audience.deck.tlp).allowed) {
    return null;
  }
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
      await writeStringAtomic(
        File(outputPath),
        _rebaseImagePaths(md, sourcePath, outputPath),
      );
      return outputPath;
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
      await writeStringAtomic(File(outputPath), out);
      return outputPath;
    case DocumentExportFormat.latex:
      final meta = exportMetadata;
      final body = markdownToLatex(
        _rebaseImagePaths(
          projectedDocumentBody(bundle),
          sourcePath,
          outputPath,
        ),
        chapterPageBreak: chapterPageBreak,
        tableBorderStyle: theme.tableBorderStyle,
        footnotePlacement: footnotePlacement,
        endnotesTitle: footnotesTitle,
      );
      final tex =
          '${articlePreamble(meta, theme: theme, documentFields: chromeFields, pageSize: pageSize ?? PageSizeSpec.a4, pageMargins: pageMargins ?? const PageMargins(), cropMarks: cropMarks)}\n$body\n$articlePostamble\n';
      await writeStringAtomic(File(outputPath), tex);
      return outputPath;
    case DocumentExportFormat.pdf:
      return _writeDocumentPdf(
        bundle,
        labels:
            pdfLabels ??
            DocumentPdfLabels(
              footnotesTitle: footnotesTitle,
              mathLabel: 'math',
              mermaidLabel: 'mermaid',
              chartLabel: 'chart',
            ),
        fallbackFont: pdfFallbackFont,
        embedImage: embedImage,
        renderMermaid: renderMermaid,
        renderMath: renderMath,
        chapterPageBreak: chapterPageBreak,
        cropMarks: cropMarks,
        pageSize: pageSize,
        pageMargins: pageMargins,
        metadata: exportMetadata,
        onUnsupportedCharacters: onPdfUnsupportedCharacters,
        onCoarseLogo: onPdfCoarseLogo,
        outputPath: outputPath,
      );
  }
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
@visibleForTesting
String rebaseImagePathsForTesting(
  String markdown,
  String? sourcePath,
  String outputPath,
) => _rebaseImagePaths(markdown, sourcePath, outputPath);

String _rebaseImagePaths(
  String markdown,
  String? sourcePath,
  String outputPath,
) {
  if (sourcePath == null) return markdown;
  final sourceDir = p.dirname(sourcePath);
  final outputDir = p.dirname(outputPath);
  if (p.equals(sourceDir, outputDir)) return markdown;
  return markdown.replaceAllMapped(RegExp(r'!\[([^\]]*)\]\(([^)]+)\)'), (m) {
    final alt = m.group(1)!;
    final raw = m.group(2)!;
    // Alleen relatieve paden zonder schema — URL's en data-URI's blijven.
    if (raw.startsWith('http://') ||
        raw.startsWith('https://') ||
        raw.startsWith('data:') ||
        p.isAbsolute(raw)) {
      return m[0]!;
    }
    // Scheid bron en titel (`bron "titel"`).
    final space = raw.indexOf(RegExp(r'\s'));
    final src = space < 0 ? raw : raw.substring(0, space);
    final title = space < 0 ? '' : raw.substring(space);
    final abs = p.normalize(p.join(sourceDir, src));
    final rebased = p.relative(abs, from: outputDir);
    return '![$alt]($rebased$title)';
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

/// Zet het document als PDF en schrijft het atomisch weg.
///
/// Anders dan de PDF van een deck — één bitmap per dia, zonder tekstlaag — wordt
/// deze *gezet*: de tekst is te selecteren, te doorzoeken en voor te lezen, en de
/// koppen staan in de bladwijzerboom. Zie `lib/services/pdf/` en
/// DOCUMENT_MODE.md §6.
///
/// Een **audience**-oppervlak, net als [writeDocumentExport] zelf: het neemt een
/// [ExportBundle] en geen `Deck`, zodat wat de deur uit gaat de geprojecteerde
/// (geredigeerde) body is. Het staat als zodanig geregistreerd in
/// `tool/check_audience_boundary.dart`.
Future<String?> _writeDocumentPdf(
  ExportBundle bundle, {
  required DocumentPdfLabels labels,
  required String outputPath,
  ByteData? fallbackFont,
  HtmlImageResolver? embedImage,
  MermaidSvgResolver? renderMermaid,
  MathSvgResolver? renderMath,
  bool chapterPageBreak = false,
  bool cropMarks = false,
  PageSizeSpec? pageSize,
  PageMargins? pageMargins,
  ExportDocumentMetadata? metadata,
  void Function(Set<int> runes)? onUnsupportedCharacters,
  void Function(LogoResolution logo)? onCoarseLogo,
}) async {
  final result = await buildDocumentExportPdf(
    bundle,
    labels: labels,
    fallbackFont: fallbackFont,
    embedImage: embedImage,
    renderMermaid: renderMermaid,
    renderMath: renderMath,
    chapterPageBreak: chapterPageBreak,
    cropMarks: cropMarks,
    pageSize: pageSize,
    pageMargins: pageMargins,
    metadata: metadata,
  );
  await writeBytesAtomic(File(outputPath), result.bytes);
  // Een teken dat geen enkele snede kent verdwijnt uit de tekstlaag zonder dat
  // het bestand ergens klaagt. De schil hoort dat te kunnen melden.
  if (!result.isComplete) {
    onUnsupportedCharacters?.call(result.unsupportedCharacters);
  }
  // Een logo dat te grof is voor drukwerk is geen fout in de export maar in het
  // bronbestand; zeggen is het enige wat er nog aan te doen valt.
  final coarse = result.coarseLogo;
  if (coarse != null) onCoarseLogo?.call(coarse);
  return outputPath;
}

Map<String, String> _documentChromeFields(Deck deck) => {
  ...deck.documentFields,
  'title': deck.title,
  'subtitle': deck.description,
  'author': deck.author,
};
