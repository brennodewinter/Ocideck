// Part of the tabs_provider library — see tabs_provider.dart.
// De leeg-bestand-wissel van #3107 als top-level functies: extension-leden
// tellen mee voor het klasseplafond van TabsNotifier, top-level niet — het
// patroon dat _closeTab al volgt.

part of 'tabs_provider.dart';

/// Wisselt een leeg documenttabblad naar een lege presentatie in hetzelfde
/// tabblad (#3107). Doet niets zodra de body inhoud heeft — de knop die dit
/// aanbiedt is dan óók weg, dus bereiken is een defect, geen invoer om te
/// weerstaan. De metadata (tlp, vrije velden, projectmap) reist mee: "leeg"
/// is geen reden die te laten vallen.
void swapEmptyDocumentForDeck(TabsNotifier notifier) {
  final tab = notifier.currentState.current;
  final content = tab?.content;
  if (tab == null || content is! DocumentTabContent) return;
  final docState = content.documentNotifier.currentState;
  final doc = docState.document;
  if (doc == null || doc.body.trim().isNotEmpty) return;
  final newTab = notifier._createTab(recoveryId: tab.recoveryId);
  newTab.deckNotifier.loadDeck(
    DocumentDeckBridge.documentToDeck(
      doc.body,
      tlp: doc.tlp,
      fields: doc.fields,
      projectPath: docState.projectPath,
    ),
  );
  notifier._disposeTab(tab);
  notifier._replacementState = notifier.currentState.copyWith(
    tabs: [...notifier.currentState.tabs]
      ..[notifier.currentState.clampedIndex] = newTab,
  );
}

/// De omgekeerde wissel: een deck zonder eigen inhoud
/// ([DocumentDeckBridge.deckIsEmpty]) wordt een leeg document in hetzelfde
/// tabblad (#3107). De deckbrede classificatie en de projectmap reizen mee.
void swapEmptyDeckForDocument(TabsNotifier notifier) {
  final tab = notifier.currentState.current;
  final content = tab?.content;
  if (tab == null || content is! DeckTabContent) return;
  final deck = content.deckNotifier.currentState.deck;
  if (deck == null || !DocumentDeckBridge.deckIsEmpty(deck)) return;
  // deckIsEmpty staat borg voor een lege body: daarom letterlijk `''`, niet
  // deckToDocumentMarkdown — die geeft `'\n'` terug, een document met
  // inhoudloze witruimte i.p.v. echt niets.
  final newTab = _createDocumentTab(
    notifier,
    MarkdownDocument.parse('').withTlp(deck.tlp),
    projectPath: deck.projectPath,
    recoveryId: tab.recoveryId,
  );
  notifier._disposeTab(tab);
  notifier._replacementState = notifier.currentState.copyWith(
    tabs: [...notifier.currentState.tabs]
      ..[notifier.currentState.clampedIndex] = newTab,
  );
}
