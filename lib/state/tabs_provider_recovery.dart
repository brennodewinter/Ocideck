// Part of the tabs_provider library — see tabs_provider.dart.
// De herstel-/autosave-hulpjes van TabsNotifier, top-level gehouden zodat ze
// niet meetellen voor het klasseplafond en tabs_provider.dart onder de
// bestandsgrens blijft. Ze raken geen TabsNotifier-veld — alleen publieke
// getters op tab/notifier.
part of 'tabs_provider.dart';

/// Bouwt de herstel-momentopname van een presentatietabblad. Top-level (raakt
/// geen [TabsNotifier]-veld, alleen publieke getters) om de klassenratchet niet
/// te tarten; zie [TabsNotifier._autosaveTick].
RecoverySnapshot _deckRecoverySnapshot(
  TabInfo tab,
  DeckState st,
  DeckNotifier dn,
  EditorState editor,
  String? markdownDraft,
) {
  final deck = st.deck!;
  return RecoverySnapshot(
    id: tab.recoveryId,
    savedAt: DateTime.now(),
    filePath: st.filePath,
    label: tab.label,
    markdown: dn.generateMarkdown(),
    markdownDraft: markdownDraft,
    markdownDraftScope: markdownDraft == null
        ? null
        : editor.markdownScope.name,
    markdownDraftSlideIndex:
        markdownDraft != null && editor.markdownScope == MarkdownScope.slide
        ? editor.selectedIndex
        : null,
    userNotes: UserNotesCodec.encode(deck.slides, deck.userNotes),
    miauw: MiauwCodec.encodeDisposition(deck.miauw),
    seal: SealCodec.encode(SealRecord.of(deck)),
    // Tekeningen staan niet in de markdown (eigen sidecar), en tekenen maakt het
    // deck wél vuil. Zonder deze regel kwam een herstelde presentatie stil
    // zonder annotaties terug.
    annotations: AnnotationCodec.encode(deck.slides, deck.annotations),
  );
}

/// Bouwt de herstel-momentopname van een documenttabblad. Een document *ís* zijn
/// bron, dus de momentopname is simpel: de ruwe `.md` (byte-getrouw, inclusief
/// het stijl-frontmatter-blok), geen deck-sidecars. [RecoverySnapshot.kind]
/// markeert hem als document zodat het herstel het juiste soort tabblad terugzet.
/// Top-level (raakt geen [TabsNotifier]-veld) om de klassenratchet niet te tarten.
RecoverySnapshot _documentRecoverySnapshot(TabInfo tab, DocumentState st) =>
    RecoverySnapshot(
      id: tab.recoveryId,
      savedAt: DateTime.now(),
      filePath: st.filePath,
      label: tab.label,
      markdown: st.document!.source,
      kind: MarkdownKind.document,
    );

/// Niet-toegepaste bron die afwijkt van het laatste geldige deck. Alleen voor
/// presentatietabbladen: een document kent geen aparte, ongetoepaste bron — het
/// bewerkt zijn bron live. Top-level (raakt geen [TabsNotifier]-veld) om de
/// klassenratchet niet te tarten.
String? _markdownDraftFor(TabInfo tab) {
  final dn = tab.deckNotifierOrNull;
  if (dn == null || !dn.mounted) return null;
  final deckState = dn.currentState;
  final deck = deckState.deck;
  if (!deckState.isOpen || deck == null) return null;
  final editor = tab.editorNotifier.currentState;
  return editor.hasMarkdownDraft ? editor.markdownBuffer : null;
}
