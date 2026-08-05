import 'package:flutter_riverpod/legacy.dart';

import '../models/markdown_document.dart';

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

  const DocumentState({
    this.document,
    this.isDirty = false,
    this.filePath,
    this.error,
    this.downloadName,
    this.canUndo = false,
    this.canRedo = false,
    this.revision = 0,
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

  /// Begin een leeg, ongetiteld document.
  void newDocument() {
    _clearHistory();
    state = DocumentState(document: MarkdownDocument.parse(''), isDirty: true);
  }

  /// Laad een reeds ingelezen document (door de tabbeheerder), vers en schoon.
  void loadDocument(MarkdownDocument document, {String? filePath}) {
    _clearHistory();
    state = DocumentState(
      document: document,
      filePath: filePath,
      isDirty: false,
    );
  }

  /// Neem een bewerking uit de editor over. De bron *ís* de waarheid: er wordt
  /// niets genormaliseerd. Een bewerking die de bron niet verandert is een no-op
  /// (geen ongedaan-stap, geen 'gewijzigd'-vlag).
  void edit(String nextSource, {String? coalesceKey}) {
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

  /// Markeer het document als opgeslagen; onthoud waar het nu leeft.
  void markSaved({String? filePath}) {
    state = state.copyWith(
      isDirty: false,
      filePath: filePath ?? state.filePath,
      clearError: true,
    );
  }

  void setError(String message) => state = state.copyWith(error: message);
  void clearError() => state = state.copyWith(clearError: true);
}
