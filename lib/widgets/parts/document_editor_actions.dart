part of '../document_editor_screen.dart';

/// De vensteracties van het documentscherm die niets aan de staat zetten —
/// ze lezen `ref` en `context`, openen een dialoog en schrijven via de
/// notifier. Top-level zoals de andere helpers in de parts: de staat komt
/// mee als parameter, zoals bij [_sourceTableFor].
///
/// Open de document-export-dialoog (DOCUMENT_MODE.md §11.2). De dialoog kiest
/// profiel en formaat; het echte bouwen-en-wegschrijven gebeurt in de closure
/// hieronder, die de bron langs `buildDocumentExportBundle → AudienceDeck`
/// projecteert (nooit de rauwe bron), een pad laat kiezen en atomisch
/// wegschrijft. De bron zelf blijft ongemoeid — export is een afgeleid
/// bestand.
Future<void> _exportDocument(_DocumentEditorScreenState s) async {
  final state = s.ref.read(documentProvider);
  final document = state.document;
  if (document == null) return;
  final settings = s.ref.read(settingsProvider);
  await DocumentExportDialog.show(
    s.context,
    privacyChecksEnabled: settings.privacyChecksEnabled,
    onExport: (profile, format) =>
        _writeDocumentExport(s.ref, s.context, profile, format),
  );
}

/// Converteer dit document naar een NIEUWE presentatie in een nieuw tabblad
/// (DOCUMENT_MODE.md §11.3). De dialoog toont het voorgestelde aantal dia's
/// en de drop-lijst vóór het committen; pas bij bevestigen ontstaat het
/// nieuwe tabblad.
Future<void> _convertDocumentToPresentation(
  _DocumentEditorScreenState s,
) async {
  final state = s.ref.read(documentProvider);
  // De body zonder het stijl-frontmatter-blok: de `theme:`-regel is geen
  // slide-inhoud. Een presentatie krijgt zijn eigen thema; de documentstijl
  // reist bewust niet mee (§11.3).
  final body = state.document?.body ?? '';
  final title = _documentTitle(body, state.filePath);
  // De getypeerde, zero-loss deconstructie ís de bron van waarheid — voor het
  // voorgestelde aantal dia's én voor het nieuwe deck. Bewust niet
  // generateDeck→parseDeck: dat zou een kop-geleide sectie via `_inferSlideType`
  // weer stil kunnen laten vallen (§11.3, §11.5). De nieuwe presentatie is een
  // kopie. De documentclassificatie blijft gelden voor alle ontstane dia's;
  // alleen documentvelden en documentstijl zijn geen presentatiegegevens.
  final documentTlp = state.document?.tlp ?? TlpLevel.none;
  // Grafiekdata inline vouwen vóór de brug, gelijk aan het exportpad
  // (buildDocumentExportBundle). Zonder dit staat een `source: data/….json`
  // chart-dia leeg in het nieuwe tabblad — de cijfers reizen niet mee (#1639).
  final projectPath = _documentProjectPath(s.ref);
  final hydrated = await hydrateDocumentChartData(
    body,
    projectPath: projectPath,
  );
  if (!s.mounted) return;
  final deck = DocumentDeckBridge.documentToDeck(
    hydrated,
    projectPath: projectPath,
    title: title,
    tlp: documentTlp,
  );
  final confirmed = await ConvertToPresentationDialog.show(
    s.context,
    slideCount: deck.slides.length,
  );
  if (confirmed != true || !s.mounted) return;
  s.ref
      .read(tabsProvider.notifier)
      .newDeckInNewTab(
        title,
        tlp: deck.tlp,
        slides: deck.slides,
        projectPath: projectPath,
      );
}
