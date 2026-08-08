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

/// Bewaar een niet-opgeslagen documenttabblad naar zijn herstelbestand. Slaat een
/// schoon of ongewijzigd document over; de discard-abonnee in [_createDocumentTab]
/// wist het bestand zodra het tabblad schoon is. Top-level (bewaart alleen via de
/// meegegeven [recovery] en [lastAutosaved]) om de klassenratchet niet te tarten;
/// zie [TabsNotifier._autosaveTick]. De deck-tegenhanger staat inline in de tik.
void _autosaveDocument(
  TabInfo tab,
  DocumentNotifier doc,
  RecoveryService recovery,
  Map<int, String> lastAutosaved,
) {
  if (!doc.mounted) return;
  final st = doc.currentState;
  if (!(st.isOpen && st.isDirty)) return;
  final source = st.document!.source;
  if (lastAutosaved[tab.id] == source) return; // niets nieuws
  recovery.save(_documentRecoverySnapshot(tab, st));
  lastAutosaved[tab.id] = source;
}

/// De inverse van [_deckRecoverySnapshot]: bouwt het deck terug uit een
/// presentatie-momentopname — parseert de markdown en legt de sidecars
/// (gebruikersnotities, MIAUW-schikking, zegel, tekeningen) er weer overheen.
/// `null` betekent onleesbaar; de aanroeper laat zo'n momentopname dan op schijf
/// staan. Top-level (raakt geen [TabsNotifier]-veld) om de klassenratchet niet te
/// tarten; zie [TabsNotifier.restoreRecovered].
Deck? _deckFromRecoverySnapshot(RecoverySnapshot snap, MarkdownService md) {
  final parsed = md.parseDeck(snap.markdown, filePath: snap.filePath);
  if (parsed == null) return null;
  var deck = parsed;
  if (snap.userNotes != null && snap.userNotes!.isNotEmpty) {
    final notes = UserNotesCodec.decode(snap.userNotes!, deck.slides);
    if (notes.isNotEmpty) deck = deck.copyWith(userNotes: notes);
  }
  if (snap.miauw != null && snap.miauw!.isNotEmpty) {
    final d = MiauwCodec.decode(snap.miauw!);
    if (!d.isEmpty) deck = deck.copyWith(miauw: d);
  }
  if (snap.seal != null && snap.seal!.isNotEmpty) {
    final record = SealCodec.decode(snap.seal!);
    if (record != null) deck = record.applyTo(deck);
  }
  final ink = snap.annotations;
  if (ink != null && ink.isNotEmpty) {
    try {
      final strokes = AnnotationCodec.decode(ink, deck.slides);
      if (strokes.isNotEmpty) deck = deck.copyWith(annotations: strokes);
    } catch (e) {
      // Een kapotte tekenlaag mag het herstel van de tekst nooit blokkeren;
      // hetzelfde als bij een onleesbare sidecar op schijf.
      logWarning('restoreRecovered: annotaties onleesbaar', e);
    }
  }
  return deck;
}

/// Zet het niet-toegepaste markdown-klad terug in de editor van een hersteld
/// presentatietabblad. Raakt alleen publieke getters op [tab] — top-level om de
/// klassenratchet niet te tarten; zie [TabsNotifier.restoreRecovered].
void _applyRecoveredMarkdownDraft(
  TabInfo tab,
  RecoverySnapshot snap,
  Deck deck,
) {
  final draft = snap.markdownDraft;
  if (draft == null) return;
  final scope = snap.markdownDraftScope == MarkdownScope.slide.name
      ? MarkdownScope.slide
      : MarkdownScope.deck;
  final slideIndex = (snap.markdownDraftSlideIndex ?? 0).clamp(
    0,
    deck.slides.length - 1,
  );
  tab.editorNotifier.select(slideIndex);
  tab.editorNotifier.setMarkdownScope(scope);
  final baseline = scope == MarkdownScope.slide
      ? tab.deckNotifier.generateSlideMarkdown(slideIndex)
      : tab.deckNotifier.generateMarkdown();
  tab.editorNotifier.setMode(EditorMode.markdown, initialMarkdown: baseline);
  tab.editorNotifier.updateMarkdown(draft);
}
