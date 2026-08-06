import 'dart:io';

import '../models/privacy_disposition.dart';
import '../models/settings.dart';
import '../utils/atomic_file.dart';
import 'document_chart_hydration.dart';
import 'document_deck_bridge.dart';
import 'export_bundle.dart';
import 'export_metadata.dart';
import 'markdown_service.dart';
import 'marp_html_service.dart';
import 'privacy/privacy_own_identity.dart';

/// De twee uitvoervormen van een plat-Markdown-**document** (DOCUMENT_MODE.md
/// §11.2): het geprojecteerde `.md` zelf, of één doorlopend HTML-document. Beide
/// dragen de geredigeerde body — nooit de rauwe bron.
enum DocumentExportFormat { md, html }

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
}) async {
  final hydrated = await hydrateDocumentChartData(
    body,
    projectPath: projectPath,
  );
  final deck = DocumentDeckBridge.documentToDeck(
    hydrated,
    projectPath: projectPath,
    title: title,
  );
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
/// - [DocumentExportFormat.md] schrijft de geprojecteerde body atomisch weg.
/// - [DocumentExportFormat.html] rendert die body als één doorlopend HTML-
///   document (`continuous: true`) en schrijft het resultaat atomisch weg.
///
/// Geeft het geschreven pad terug.
Future<String?> writeDocumentExport(
  ExportBundle bundle,
  DocumentExportFormat format, {
  required MarpHtmlService html,
  ThemeProfile? theme,
  ExportDocumentMetadata? metadata,
  HtmlImageResolver? embedImage,
  required String outputPath,
}) async {
  switch (format) {
    case DocumentExportFormat.md:
      await writeStringAtomic(File(outputPath), projectedDocumentBody(bundle));
      return outputPath;
    case DocumentExportFormat.html:
      final out = await html.build(
        projectedDocumentBody(bundle),
        continuous: true,
        theme: theme,
        metadata: metadata,
        embedImage: embedImage,
      );
      await writeStringAtomic(File(outputPath), out);
      return outputPath;
  }
}
