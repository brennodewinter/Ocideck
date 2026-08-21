import 'package:flutter_riverpod/legacy.dart';

import '../models/markdown_document.dart';
import '../services/document_integrity.dart';

/// De bewerkbare toestand van één documenttabblad: het [MarkdownDocument] zelf,
/// plus of het gewijzigd is, waar het op schijf vandaan komt, en of
/// ongedaan/opnieuw beschikbaar is.
///
/// Bewust naast `DeckState` en niet erin (docs/design/DOCUMENT_MODE.md §2): een
/// document is de bron zélf, geen tot slides gedeconstrueerd model. De vorm
/// spiegelt `DeckState` zodat de tab-, herstel- en statusbalklaag beide gelijk
/// kunnen behandelen.
class DocumentState {
  final MarkdownDocument? document;
  final bool isDirty;
  final String? filePath;
  final String? error;

  /// Naam waaronder het document voor het laatst als download is weggeschreven
  /// (web), voor de statusbalk. Op desktop null.
  final String? downloadName;

  final bool canUndo;
  final bool canRedo;

  /// Telt op bij elke aanvaarde wijziging en bij undo/redo. De editor-subtree is
  /// erop gesleuteld en herleest zijn tekst wanneer een wijziging van búiten de
  /// editor binnenkomt (undo/redo). Het is geen documentversie.
  final int revision;

  /// De bron zoals die op schijf stond bij het laden — vóór de visuele editor
  /// er een round-trip overheen haalt. Bij opslaan vanuit Visueel gebruikt
  /// `saveDocumentWithDestination` deze om alleen de echte bewerkingen terug
  /// te schrijven, niet de normalisatiedrift (#1613).
  final String? savedSource;

  /// Of de huidige bron uit de visuele editor komt (Quill → Markdown). Als
  /// `true`, dan is [document.source] niet byte-getrouw aan [savedSource] —
  /// de round-trip heeft witregels, tabelscheidingsregels en lijstvolgorde
  /// genormaliseerd. Bij opslaan patcht `saveDocumentWithDestination` de
  /// echte bewerkingen op [savedSource] in plaats van de hele genormaliseerde
  /// bron weg te schrijven (#1613).
  final bool visualEdited;

  /// De SHA-512-hash van het bestand op schijf bij het laden of de laatste
  /// opslag. Bij opslaan vergelijkt `saveDocumentWithDestination` deze met
  /// de huidige bestandsinhoud — wijkt hij af, dan is het bestand buiten
  /// OciDeck gewijzigd en vraagt een dialoog wat te doen (#1699, #1683).
  final String? savedFileHash;

  const DocumentState({
    this.document,
    this.isDirty = false,
    this.filePath,
    this.error,
    this.downloadName,
    this.canUndo = false,
    this.canRedo = false,
    this.revision = 0,
    this.savedSource,
    this.visualEdited = false,
    this.savedFileHash,
  });

  bool get hasUnsavedChanges => isDirty;
  bool get isOpen => document != null;

  DocumentState copyWith({
    MarkdownDocument? document,
    bool? isDirty,
    String? filePath,
    String? error,
    String? downloadName,
    bool? canUndo,
    bool? canRedo,
    int? revision,
    String? savedSource,
    bool? visualEdited,
    String? savedFileHash,
    bool clearError = false,
    bool clearFilePath = false,
  }) {
    return DocumentState(
      document: document ?? this.document,
      isDirty: isDirty ?? this.isDirty,
      filePath: clearFilePath ? null : (filePath ?? this.filePath),
      error: clearError ? null : (error ?? this.error),
      downloadName: downloadName ?? this.downloadName,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      revision: revision ?? this.revision,
      savedSource: savedSource ?? this.savedSource,
      visualEdited: visualEdited ?? this.visualEdited,
      savedFileHash: savedFileHash ?? this.savedFileHash,
    );
  }
}

/// Houdt het document dat op dit moment wordt bewerkt, en is het enige dat het
/// mag wijzigen — de documenttegenhanger van `DeckNotifier`.
///
/// Ongedaan maken werkt op momentopnamen van het hele [MarkdownDocument]; dat is
/// goedkoop, want de bron is één string en de blokstructuur wordt eromheen
/// afgeleid. Snel typen wordt tot één stap samengevoegd binnen [_coalesceWindow]
/// zolang de bewerkingen dezelfde `coalesceKey` delen; een `null`-sleutel
/// markeert een losse, discrete stap. Dezelfde coalescing als `DeckNotifier`,
/// bewust identiek zodat undo overal hetzelfde aanvoelt.
class DocumentNotifier extends StateNotifier<DocumentState> {
  DocumentNotifier() : super(const DocumentState());

  /// Documenten zijn immutable (withSource maakt een nieuw exemplaar), dus dit
  /// zijn goedkope referenties.
  final List<MarkdownDocument> _undoStack = [];
  final List<MarkdownDocument> _redoStack = [];

  static const _maxHistory = 200;
  static const _coalesceWindow = Duration(milliseconds: 700);
  DateTime? _lastEditAt;
  String? _lastCoalesceKey;

  DocumentState get currentState => state;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void _clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
    _lastEditAt = null;
    _lastCoalesceKey = null;
  }

  /// Sluit het document: geschiedenis wissen en terug naar de lege toestand.
  /// Het documenttabblad zelf blijft staan (als enige tabblad), net als een
  /// presentatie die `closeDeck()` aanroept — maar dan voor een document.
  void closeDocument() {
    _clearHistory();
    state = const DocumentState();
  }

  /// Laad een reeds ingelezen document (door de tabbeheerder), vers en schoon.
  void loadDocument(MarkdownDocument document, {String? filePath}) {
    _clearHistory();
    state = DocumentState(
      document: document,
      filePath: filePath,
      isDirty: false,
      savedSource: document.source,
      visualEdited: false,
      savedFileHash: DocumentIntegrity.hashMarkdown(document.source),
    );
  }

  /// Neem een bewerking uit de editor over. De bron *ís* de waarheid: er wordt
  /// niets genormaliseerd. Een bewerking die de bron niet verandert is een no-op
  /// (geen ongedaan-stap, geen 'gewijzigd'-vlag).
  ///
  /// [visualEdit] markeert of de bewerking uit de visuele editor komt (Quill →
  /// Markdown). In dat geval is [nextSource] niet byte-getrouw aan de originele
  /// bron — de round-trip normaliseert. Bij opslaan gebruikt
  /// `saveDocumentWithDestination` deze vlag om alleen de echte bewerkingen
  /// terug te schrijven (#1613).
  void edit(String nextSource, {String? coalesceKey, bool visualEdit = false}) {
    final current = state.document;
    if (current == null || current.source == nextSource) return;
    final now = DateTime.now();
    final canCoalesce =
        coalesceKey != null &&
        coalesceKey == _lastCoalesceKey &&
        _lastEditAt != null &&
        now.difference(_lastEditAt!) < _coalesceWindow &&
        _undoStack.isNotEmpty;
    if (!canCoalesce) {
      _undoStack.add(current);
      if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
    }
    _lastEditAt = now;
    _lastCoalesceKey = coalesceKey;
    _redoStack.clear();
    state = state.copyWith(
      document: current.withSource(nextSource),
      isDirty: true,
      canUndo: true,
      canRedo: false,
      visualEdited: visualEdit,
    );
  }

  /// Draai de laatste (samengevoegde) bewerking terug.
  void undo() {
    final current = state.document;
    if (current == null || _undoStack.isEmpty) return;
    _redoStack.add(current);
    final previous = _undoStack.removeLast();
    // Volgende bewerking begint een verse ongedaan-stap.
    _lastEditAt = null;
    _lastCoalesceKey = null;
    state = state.copyWith(
      document: previous,
      isDirty: true,
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
      revision: state.revision + 1,
    );
  }

  /// Voer een teruggedraaide bewerking opnieuw uit.
  void redo() {
    final current = state.document;
    if (current == null || _redoStack.isEmpty) return;
    _undoStack.add(current);
    final next = _redoStack.removeLast();
    _lastEditAt = null;
    _lastCoalesceKey = null;
    state = state.copyWith(
      document: next,
      isDirty: true,
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
      revision: state.revision + 1,
    );
  }

  /// Markeer het document als (nog) niet opgeslagen. Voor herstel na een crash:
  /// [TabsNotifier.restoreRecovered] laadt de bron en markeert hem vuil, zodat de
  /// herstelde inhoud niet als 'al opgeslagen' voorbijgaat — de tegenhanger van
  /// `DeckNotifier.markDirty`.
  void markDirty() {
    if (state.document == null || state.isDirty) return;
    state = state.copyWith(isDirty: true);
  }

  /// Markeer het document als opgeslagen; onthoud waar het nu leeft.
  /// [savedSource] wordt bijgewerkt naar de huidige bron, zodat een volgende
  /// opslag vanuit Visueel weer tegen de juiste basis diff't (#1613).
  /// [savedFileHash] wordt bijgewerkt naar de hash van de weggeschreven bytes
  /// (#1699).
  void markSaved({String? filePath, String? savedFileHash}) {
    state = state.copyWith(
      isDirty: false,
      filePath: filePath ?? state.filePath,
      clearError: true,
      savedSource: state.document?.source,
      visualEdited: false,
      savedFileHash: savedFileHash ?? DocumentIntegrity.hashMarkdown(
        state.document?.source ?? '',
      ),
    );
  }

  void setError(String message) => state = state.copyWith(error: message);
  void clearError() => state = state.copyWith(clearError: true);

  /// Vervangt de bron door de byte-getrouwe versie na een visuele opslag
  /// (#1613). De editor en de notifier zien dan dezelfde bron — geen drift
  /// meer tussen wat op schijf staat en wat in het geheugen leeft. Dit is
  /// géén bewerking: het voegt geen ongedaan-stap toe en markeert niet vuil.
  void replaceSource(String nextSource) {
    final current = state.document;
    if (current == null || current.source == nextSource) return;
    state = state.copyWith(
      document: current.withSource(nextSource),
      visualEdited: false,
    );
  }
}

/// De document-notifier van het actieve documenttabblad.
///
/// Per tab overschreven in `_tabScope` (app_shell.dart) met de `DocumentNotifier`
/// van dat tabblad — de tegenhanger van `deckProvider`. De root-fabriek is
/// alleen een vangnet voor als er (nog) geen documenttabblad actief is.
final documentProvider = StateNotifierProvider<DocumentNotifier, DocumentState>(
  (ref) => DocumentNotifier(),
);
