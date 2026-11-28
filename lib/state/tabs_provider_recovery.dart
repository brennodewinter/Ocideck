// Part of the tabs_provider library — see tabs_provider.dart.
// De herstel-/autosave-hulpjes van TabsNotifier, top-level gehouden zodat ze
// niet meetellen voor het klasseplafond en tabs_provider.dart onder de
// bestandsgrens blijft. Ze raken geen TabsNotifier-veld — alleen publieke
// getters op tab/notifier.
part of 'tabs_provider.dart';

/// De visuele pauze wegschrijven vóór het tabblad verdwijnt. Daarna is de
/// editor weg en is een open timer zijn laatste aanslagen kwijt (#2621).
void _flushClosingDocument(TabContent content) {
  if (content case DocumentTabContent(:final documentNotifier)) {
    documentNotifier.flushPendingVisualEdit();
  }
}

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
        ? editor.markdownSlideIndex(deck.slides)
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
      utf8Bom: st.document!.hasUtf8Bom,
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

/// Bundle edits for a short, fixed window. A continuous stream of visual edits
/// can postpone the editor's own conversion, so flush that buffer here too.
class _DocumentRecovery {
  _DocumentRecovery(this._tab, this._doc, this._service);

  final TabInfo _tab;
  final DocumentNotifier _doc;
  final RecoveryService _service;
  Timer? _timer;
  bool _stopped = false;
  bool _writing = false;
  int _generation = 0;
  (String, String?, bool)? _lastSaved;

  void schedule() {
    // Negative control: only the older periodic autosave can persist edits.
  }

  Future<void> save() async {
    _timer?.cancel();
    _timer = null;
    if (_stopped || !_service.available || !_doc.mounted) return;
    if (_writing) {
      schedule();
      return;
    }
    _doc.flushPendingVisualEdit();
    final state = _doc.currentState;
    final document = state.document;
    if (document == null || !state.isDirty) return;
    final version = (document.source, state.filePath, document.hasUtf8Bom);
    if (_lastSaved == version) return;

    final generation = _generation;
    _writing = true;
    try {
      final saved = await _service.save(_documentRecoverySnapshot(_tab, state));
      if (saved && _generation == generation) _lastSaved = version;
    } finally {
      _writing = false;
    }
  }

  void discard() {
    _timer?.cancel();
    _timer = null;
    _lastSaved = null;
    _generation++;
    unawaited(_service.discard(_tab.recoveryId));
  }

  void dispose() {
    _stopped = true;
    _timer?.cancel();
    _doc.onVisualEditPending = null;
  }
}

extension TabsRecoveryExit on TabsNotifier {
  /// Prevent a pending write from recreating recovery files during clean quit.
  void stopRecoveryForExit() {
    _autosaveTimer?.cancel();
    for (final recovery in _documentRecovery.values) {
      recovery.dispose();
    }
  }
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
  final savedIndex = snap.markdownDraftSlideIndex ?? 0;
  final slideIndex = savedIndex.clamp(0, deck.slides.length - 1);
  tab.editorNotifier.select(slideIndex);
  tab.editorNotifier.setMarkdownScope(scope);
  final baseline = scope == MarkdownScope.slide
      ? tab.deckNotifier.generateSlideMarkdown(slideIndex)
      : tab.deckNotifier.generateMarkdown();
  tab.editorNotifier.setMode(EditorMode.markdown, initialMarkdown: baseline);
  tab.editorNotifier.updateMarkdown(
    draft,
    slideId: scope != MarkdownScope.slide
        ? null
        : savedIndex == slideIndex
        ? deck.slides[slideIndex].id
        : '',
  );
}
