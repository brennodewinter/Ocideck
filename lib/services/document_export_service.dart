import 'dart:io';

import '../models/privacy_disposition.dart';
import '../models/settings.dart' show ThemeProfile, TableBorderStyle;
import '../models/page_size.dart';
import 'table_of_contents.dart';
import '../utils/atomic_file.dart';
import 'document_chart_hydration.dart';
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
import 'privacy/privacy_own_identity.dart';

/// De uitvoervormen van een plat-Markdown-**document** (DOCUMENT_MODE.md
/// §11.2): het geprojecteerde `.md` zelf, één doorlopend HTML-document, een
/// LaTeX `article`, of een OciDeck-pakket. Alle vier dragen de geredigeerde
/// body — nooit de rauwe bron.
enum DocumentExportFormat { md, html, latex, ocideck }

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
}) async {
  final hydrated = await hydrateDocumentChartData(
    body,
    projectPath: projectPath,
  );
  final baseDeck = DocumentDeckBridge.documentToDeck(
    hydrated,
    projectPath: projectPath,
    title: title,
  );
  final deck = theme == null
      ? baseDeck
      : baseDeck.copyWith(themeProfile: theme);
  return buildExportBundle(
    deck,
    deck.slides,
    profile: profile,
    includeDetail: true,
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
  ThemeProfile? theme,
  ExportDocumentMetadata? metadata,
  HtmlImageResolver? embedImage,
  bool chapterPageBreak = false,
  bool cropMarks = false,
  PageSizeSpec? pageSize,
  PageMargins? pageMargins,
  FootnotePlacement footnotePlacement = FootnotePlacement.page,
  String footnotesTitle = 'Noten',
  required String outputPath,
}) async {
  switch (format) {
    case DocumentExportFormat.md:
      // Feature 4: vervang de `<!-- toc -->`-marker door de gegenereerde
      // GFM-lijst (zonder marker) — een platte `.md`-ontvanger krijgt een
      // leesbare inhoudsopgave.
      final mdBody = projectedDocumentBody(bundle);
      final toc = generateTocMarkdown(mdBody);
      // keepMarker: false laat de marker weg maar houdt de TOC op zijn plek.
      // Eerder ging dat via een losse `replaceAll('<!-- toc -->\n\n', '')`, en
      // die trof niets wanneer het document wél een marker draagt maar (nog)
      // geen koppen: dan blijft de kale marker over, zónder de twee regeleindes,
      // en lekte hij het geëxporteerde bestand in.
      final mdOut = hasTocMarker(mdBody)
          ? replaceTocMarker(mdBody, toc, keepMarker: false)
          : mdBody;
      // De paginaopmaak reist wél mee, de stijl niet — en dat is geen
      // inconsistentie maar het verschil tussen een verwijzing en een maat.
      // `theme:` noemt een stijlprofiel dat alleen op déze machine bestaat: bij
      // de ontvanger zou de naam nergens naar wijzen, dus wordt de stijl vóór
      // export opgelost en in de uitvoer zelf gerenderd (§14.5). `papersize:` en
      // `geometry:` zijn geen verwijzing maar het vel zelf, in millimeters die
      // overal hetzelfde betekenen, en ze horen bij hoe dít drukwerk eruit moet
      // komen — een afloop is een eigenschap van de opdracht, niet van de lezer.
      // Daarom schrijven we hier de opmaak die op dit moment geldt
      // (`effectiveDocumentPageSetup`: document boven instelling), juist ook
      // wanneer die alleen in de instellingen stond: de ontvanger heeft die
      // instellingen niet. Zie FILE_FORMAT.md §14.4.
      final mdWithPageSetup = withDocumentPageSetup(
        mdOut,
        size: pageSize,
        margins: pageMargins,
      );
      // Om dezelfde reden als de paginaopmaak reist de plaatsing van de noten
      // mee (#1569): `reference-location:` is geen verwijzing naar iets dat
      // alleen hier bestaat maar een instructie die Pandoc en Quarto zelf
      // uitvoeren — een maat, geen verwijzing (§14.4). De body komt uit de
      // projectie en draagt dus geen front matter meer, dus wat de auteur koos
      // moet hier opnieuw worden gezet, net als het vel.
      //
      // `page` schrijft niets, en dat is geen vergeetachtigheid: onderaan de
      // bladzijde is wat elke lezer zonder aanwijzing al doet, dus een document
      // dat niets bijzonders wil houdt een export zonder front matter (§14.9).
      final mdOutFinal = withDocumentFootnotePlacement(
        mdWithPageSetup,
        footnotePlacement,
      );
      await writeStringAtomic(File(outputPath), mdOutFinal);
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
        metadata: metadata,
        embedImage: embedImage,
        pageSize: pageSize,
        pageMargins: pageMargins,
      );
      await writeStringAtomic(File(outputPath), out);
      return outputPath;
    case DocumentExportFormat.latex:
      final meta = metadata ?? const ExportDocumentMetadata();
      final body = markdownToLatex(
        projectedDocumentBody(bundle),
        chapterPageBreak: chapterPageBreak,
        tableBorderStyle: theme?.tableBorderStyle ?? TableBorderStyle.lined,
        footnotePlacement: footnotePlacement,
        endnotesTitle: footnotesTitle,
      );
      final tex =
          '${articlePreamble(meta, pageSize: pageSize ?? PageSizeSpec.a4, pageMargins: pageMargins ?? const PageMargins(), cropMarks: cropMarks)}\n$body\n$articlePostamble\n';
      await writeStringAtomic(File(outputPath), tex);
      return outputPath;
    case DocumentExportFormat.ocideck:
      // Pakketexport loopt via FileService.exportPackage (versleuteling,
      // assets) — niet via deze tekstschrijver.
      throw UnsupportedError(
        'DocumentExportFormat.ocideck hoort bij exportPackage, niet writeDocumentExport',
      );
  }
}
