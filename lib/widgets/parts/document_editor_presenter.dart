// Part of the document-editor library — see ../document_editor_screen.dart.
//
// De documentpresentatie van #2487 zoals de editor hem start: de
// tweede-scherm-grens en de afhandeling van de afsluitkeuze. Tabellen
// starten alleen-lezen; bewerkbaar maken doet de presentator per tabel
// (#2743). Allemaal top-level-functies — ze raken geen veld van de
// State, dus ze horen ook niet in de klasse te tellen; de State houdt
// alleen de dunne `_presentDocument`-delegator vast.
part of '../document_editor_screen.dart';

/// De presentatie-route van #2487. In tegenstelling tot de document→
/// presentatie-conversie is dit geen kopie maar de bron zelf; wat de sessie
/// aan edits opleverde wordt bij het sluiten expliciet bewaard, als kopie
/// bewaard of verworpen.
Future<void> _presentDocumentSession(_DocumentEditorScreenState s) async {
  s.ref.read(documentProvider.notifier).flushPendingVisualEdit();
  final context = s.context;
  final ref = s.ref;
  final body = s._controller.text;
  // #2743: geen aanwijsdialoog vóór de eerste pagina meer — presenteren
  // opent meteen, tabellen starten alleen-lezen en worden per tabel in
  // de sessie bewerkbaar via "Deze tabel bewerken".
  const editable = <int>{};
  final settings = ref.read(settingsProvider);
  final doc = ref.read(documentProvider);
  // Dezelfde tweede-scherm-grens als de diapresentatie: op één scherm is er
  // geen beamer — een publieksvenster zou dan het enige scherm dekken.
  // getAllDisplays faalt intern fail-closed (logt + lege lijst).
  final dualScreen =
      supportsDualScreenPresenter && getAllDisplays().length >= 2;
  final result = await presentDocument(
    context,
    body: body,
    projectPath: doc.projectPath,
    themeProfile: resolveDocumentStyleProfile(
      settings,
      doc.document?.styleName,
    ),
    editableTables: editable,
    dualScreen: dualScreen,
    // Dezelfde pagina-einden als de export (FILE_FORMAT.md §14.6).
    chapterBreaks: settings.documentChapterPageBreak,
  );
  if (result == null || !context.mounted) return;
  switch (result.choice) {
    case DocumentExitChoice.keep:
      // De sessie als één discrete stap — dezelfde bronroute als elke andere
      // documentedit, zodat undo/redo en de externe-wijziging-poort bij
      // opslaan onverkort gelden.
      if (result.body != body) {
        _commitDocumentBody(ref, result.body, coalesceKey: null);
      }
    case DocumentExitChoice.copy:
      ref
          .read(tabsProvider.notifier)
          .newDocumentFromMarkdown(
            result.body,
            projectPath: ref.read(documentProvider).projectPath,
            suggestedName: ref.read(documentProvider).suggestedName,
          );
    case DocumentExitChoice.discard:
      break;
  }
}
