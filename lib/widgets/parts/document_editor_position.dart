// Part of the document-editor library — see ../document_editor_screen.dart.
//
// Je plek bewaren bij het wisselen tussen Visueel en Bron (#2322): één logisch
// Markdown-anker — de caret als die in beeld is, anders het eerste zichtbare
// blok — dat in de doelstand weer in beeld komt. Losgeknipt van
// document_editor_screen.dart omdat dat bestand op zijn regelplafond zit.
part of '../document_editor_screen.dart';

/// De standwissel met plekbewaring. Het echte werk zit in [_DocPosition];
/// deze extensie bestaat zodat bestaande aanroepen als
/// `onModeChanged: _changeViewMode` en `_revealAnchor()` ongewijzigd blijven.
extension _DocEditorPosition on _DocumentEditorScreenState {
  /// Wissel van weergave — en neem je plek in de tekst mee.
  void _changeViewMode(_DocViewMode mode) => _position.changeViewMode(mode);

  /// Brengt de huidige caret van de actieve schrijfstand in beeld — na een
  /// standwissel, maar ook na een zoeksprong die de cursor verplaatste.
  void _revealAnchor() => _position.reveal();
}

/// Meet en springt de documentplek bij standwissels tussen Visueel en Bron
/// (#2322). Eigen klasse, geen extensie op het scherm: de methoden horen bij
/// één verantwoordelijkheid (waar sta je, en die plek weer in beeld krijgen)
/// en `_DocumentEditorScreenState` zit op zijn regelplafond.
class _DocPosition {
  _DocPosition(this._state);

  final _DocumentEditorScreenState _state;

  /// Wissel van weergave — en neem je plek in de tekst mee.
  ///
  /// Wisselen doe je omdat je op één plek iets in de bron wilt zien of zetten.
  /// De caret vertaalt [MarkdownCaretMap] al sinds #1566; wat ontbrak was de
  /// viewport: de doelstand opende bovenaan, dus een goed gezette cursor kon
  /// toch buiten beeld landen, en "alleen gescrold" ging helemaal verloren.
  /// Daarom één anker in bron-offsets — de caret als die zichtbaar is, anders
  /// het eerste zichtbare blok — dat na de opbouw expliciet in beeld komt.
  void changeViewMode(_DocViewMode mode) {
    if (mode == _state._viewMode) return;
    _state.ref.read(documentProvider.notifier).flushPendingVisualEdit();
    if (_state._viewMode == _DocViewMode.visual ||
        _state._viewMode == _DocViewMode.source) {
      final offset = _viewAnchor().clamp(0, _state._controller.text.length);
      // Alleen de cursor verzet, geen bewerking: de luisteraar mag hier niets
      // naar de notifier schrijven.
      _state._applyingExternal = true;
      _state._controller.selection = TextSelection.collapsed(offset: offset);
      _state._applyingExternal = false;
    }
    _state._rebuild(() => _state._viewMode = mode);
    if (mode != _DocViewMode.pages) {
      // Het schrijfvlak bestaat pas ná deze opbouw; focussen kan dus niet
      // eerder, en zonder [reveal] zou een cursor die goed staat toch
      // buiten het venster kunnen liggen — elke stand opent bovenaan.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_state.mounted) return;
        _state._editorFocus.requestFocus();
        reveal();
      });
    }
  }

  /// De plek die de gebruiker in beeld heeft, als offset in de bron: de caret
  /// als die in het venster staat, anders het eerste zichtbare blok. Zo reist
  /// ook "alleen gescrold, cursor niet verzet" mee naar de andere stand —
  /// logisch, geen pixelafstand, dus soft-wrap en zoom verstoren het niet.
  int _viewAnchor() => switch (_state._viewMode) {
    _DocViewMode.visual => _visualViewAnchor(),
    _DocViewMode.source => _sourceViewAnchor(),
    _ =>
      _state._controller.selection.isValid
          ? _state._controller.selection.baseOffset
          : 0,
  };

  /// De [EditableTextState] van het bron-schrijfvlak, of `null` zolang de
  /// Bron-stand niet opgebouwd is. Andere velden op het scherm (zoekbalk,
  /// dialogen) delen deze vorm; het documentveld herkennen we aan zijn
  /// controller.
  EditableTextState? _sourceEditableText() {
    EditableTextState? hit;
    void visit(Element el) {
      if (hit != null) return;
      final state = el is StatefulElement ? el.state : null;
      if (state is EditableTextState &&
          state.widget.controller == _state._controller) {
        hit = state;
        return;
      }
      el.visitChildren(visit);
    }

    _state.context.visitChildElements(visit);
    return hit;
  }

  /// De bron-offset die nu in beeld is in de Bron-stand: de caret als er niet
  /// is gescrold of als diens regel zichtbaar is, anders het begin van de
  /// eerste zichtbare regel. De meting gebruikt de scroll-offset van het
  /// veld zelf — document- en scrollruimte vallen samen — dus soft-wrap en
  /// regelhoogte vragen geen eigen rekenwerk.
  int _sourceViewAnchor() {
    final text = _state._controller.text;
    final sel = _state._controller.selection;
    final caret = sel.isValid ? sel.baseOffset.clamp(0, text.length) : 0;
    final editable = _sourceEditableText();
    final sc = editable?.widget.scrollController;
    if (editable == null || sc == null || !sc.hasClients) return caret;
    final render = editable.renderEditable;
    final top = sc.offset;
    final bottom = top + sc.position.viewportDimension;
    if (sel.isValid &&
        (top == 0 ||
            _rectVisible(
              render.getLocalRectForCaret(
                TextPosition(offset: caret, affinity: sel.affinity),
              ),
              top,
              bottom,
            ))) {
      return caret;
    }
    // Het eerste zichtbare teken, teruggesprongen naar het begin van zijn
    // logische regel — het anker hoort op een regelgrens, niet halverwege.
    final hit = render.getPositionForPoint(
      render.localToGlobal(Offset(4, top + 4)),
    );
    final upto = hit.offset.clamp(1, text.length);
    return text.lastIndexOf('\n', upto - 1) + 1;
  }

  /// Hetzelfde voor de visuele stand: de Quill-caret als er niet is gescrold
  /// of als die in beeld is, anders het eerste zichtbare teken — vertaald
  /// naar de bron.
  int _visualViewAnchor() {
    final text = _state._controller.text;
    final map = MarkdownCaretMap.of(text);
    int toSource(int visual) =>
        map.sourceOffsetOf(visual).clamp(0, text.length);
    final state = _state._visualEditorKey.currentState;
    final sc = state?.scrollController;
    if (state == null || sc == null || !sc.hasClients) {
      return toSource(_state._visualCaret);
    }
    final render = state.renderEditor;
    final top = sc.offset;
    final bottom = top + sc.position.viewportDimension;
    final docEnd = render.document.length - 1;
    final caret = _state._visualCaret.clamp(0, docEnd);
    if (top == 0 ||
        _rectVisible(
          render.getLocalRectForCaret(TextPosition(offset: caret)),
          top,
          bottom,
        )) {
      return toSource(caret);
    }
    final hit = render.getPositionForOffset(
      render.localToGlobal(Offset(4, top + 4)),
    );
    return toSource(hit.offset.clamp(0, docEnd));
  }

  /// Komt een streep van de rect binnen de scroll-ruimte `[top, bottom)`? De
  /// rect staat in documentruimte; de scroll-offset meet in dezelfde ruimte.
  bool _rectVisible(Rect rect, double top, double bottom) =>
      rect.bottom > top && rect.top < bottom;

  /// Brengt de caret van de net opgebouwde stand in beeld. Beide editors
  /// openen bovenaan; de wel-goed-gezette cursor zou anders buiten het venster
  /// kunnen liggen. De scroll gebeurt direct op de controller — de
  /// ingebouwde caret-reveal van de editors hangt aan focus en timing van de
  /// input-verbinding en is hier onzeker.
  void reveal() {
    final sel = _state._controller.selection;
    if (!sel.isValid) return;
    switch (_state._viewMode) {
      case _DocViewMode.source:
        final editable = _sourceEditableText();
        final sc = editable?.widget.scrollController;
        if (editable == null || sc == null || !sc.hasClients) return;
        final render = editable.renderEditable;
        _scrollRectIntoView(
          sc,
          render.getLocalRectForCaret(
            TextPosition(
              offset: sel.baseOffset.clamp(0, _state._controller.text.length),
              affinity: sel.affinity,
            ),
          ),
        );
      case _DocViewMode.visual:
        final state = _state._visualEditorKey.currentState;
        final sc = state?.scrollController;
        if (state == null || sc == null || !sc.hasClients) return;
        final render = state.renderEditor;
        final visual = MarkdownCaretMap.of(
          _state._controller.text,
        ).visualOffsetOf(sel.baseOffset).clamp(0, render.document.length - 1);
        _scrollRectIntoView(
          sc,
          render.getLocalRectForCaret(TextPosition(offset: visual)),
        );
      case _DocViewMode.pages || _DocViewMode.fill:
        return;
    }
  }

  /// Springt de scrollbare zodat `rect` (documentruimte) midden in het venster
  /// valt — document- en scrollruimte vallen samen, dus dit is rechtlijnige
  /// rekenkunde zonder renderobject-wandeling.
  void _scrollRectIntoView(ScrollController sc, Rect rect) {
    final dim = sc.position.viewportDimension;
    final target = (rect.top + rect.height / 2 - dim / 2).clamp(
      sc.position.minScrollExtent,
      sc.position.maxScrollExtent,
    );
    sc.jumpTo(target);
  }
}
