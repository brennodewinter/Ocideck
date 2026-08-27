import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/slide.dart';
import '../../l10n/app_localizations.dart';
import '../../state/collab_session_provider.dart';
import '../../utils/table_cell_navigation.dart';
import '../../utils/table_clipboard.dart';
import '_editor_field.dart';
import '../../theme/app_theme.dart';
import 'editor_text_controller.dart';

/// Editor for a table slide. Stores cells as a rectangular grid of
/// [EditorTextController]s where the first row is the header.
///
/// Per-rij- en per-kolomacties (invoegen, verplaatsen, verwijderen) leven in
/// één popup-menu per rij/kolom in plaats van vier knoppen naast elke cel —
/// dat houdt de rijhoogte bij de cel, niet bij de bediening.
enum _RowAction { insertBelow, moveUp, moveDown, delete }

enum _ColumnAction {
  insertRight,
  moveLeft,
  moveRight,
  delete,
  alignLeft,
  alignCenter,
  alignRight,
  toggleNumber,
}

class TableEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  /// In een plat document bestaat er geen dia: dan verbergt de editor de
  /// dia-specifieke onderdelen (het 'Slide titel'-veld en de deck-preset), zodat
  /// er geen presentatie-woordenschat in een documentcontext lekt. Alleen het
  /// tabelraster telt daar.
  final bool documentContext;

  const TableEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
    this.documentContext = false,
  });

  @override
  State<TableEditor> createState() => _TableEditorState();
}

class _TableEditorState extends State<TableEditor> {
  static const double _rowActionWidth = 40;

  late final EditorTextController _title;
  late List<List<EditorTextController>> _cells;

  /// Eén [FocusNode] per cel, parallel aan [_cells], zodat Tab/Shift+Tab een
  /// specifieke cel kan focussen in plaats van op de standaard-traversie te
  /// leunen (die op de laatste cel de tabel uit loopt in plaats van een rij
  /// bij te maken). Gesynchroniseerd in [build] via [_syncFocusNodes].
  final List<List<FocusNode>> _focusNodes = [];

  /// Cel die na de volgende rebuild focus moet pakken (na "rij toevoegen").
  int? _pendingFocusRow;
  int? _pendingFocusCol;

  @override
  void initState() {
    super.initState();
    _title = EditorTextController(text: widget.slide.title);
    _title.addTextListener(_emit);
    _initCells(widget.slide.tableRows);
  }

  void _initCells(List<List<String>> raw) {
    final rows = raw.isEmpty
        ? <List<String>>[
            // Lege koppen; de hint in het invoerveld toont 'Kolom 1' etc.
            ['', ''],
            ['', ''],
          ]
        : raw.map((r) => List<String>.from(r)).toList();
    final colCount = rows.fold<int>(1, (m, r) => r.length > m ? r.length : m);
    _cells = rows.map((row) {
      return List<EditorTextController>.generate(
        colCount,
        (c) => _makeCtrl(c < row.length ? row[c] : ''),
      );
    }).toList();
  }

  EditorTextController _makeCtrl(String text) {
    final c = EditorTextController(text: text);
    c.addTextListener(_emit);
    return c;
  }

  int get _colCount => _cells.isEmpty ? 0 : _cells.first.length;

  List<List<String>> get _rows =>
      _cells.map((row) => row.map((c) => c.text).toList()).toList();

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(title: _title.text, tableRows: _rows),
    );
  }

  void _addRow() {
    setState(() {
      _cells.add(
        List<EditorTextController>.generate(_colCount, (_) => _makeCtrl('')),
      );
    });
    _emit();
  }

  void _removeRow(int r) {
    if (_cells.length <= 1) return;
    setState(() {
      for (final c in _cells[r]) {
        c.removeTextListener(_emit);
        c.dispose();
      }
      _cells.removeAt(r);
    });
    _emit();
  }

  void _addColumn() {
    setState(() {
      for (var r = 0; r < _cells.length; r++) {
        // Nieuwe kolom start overal leeg; de koptekst toont een hint.
        _cells[r].add(_makeCtrl(''));
      }
    });
    _emit();
  }

  void _removeColumn(int c) {
    if (_colCount <= 1) return;
    setState(() {
      for (final row in _cells) {
        row[c].removeTextListener(_emit);
        row[c].dispose();
        row.removeAt(c);
      }
    });
    _emit();
  }

  /// Voegt een lege rij in op index [at] (0 = bovenaan, _cells.length =
  /// onderaan). "Boven invoegen" is dit met at = r; "onder invoegen" met
  /// at = r + 1 — één methode, twee knoppen.
  void _insertRowAt(int at) {
    setState(() {
      _cells.insert(
        at.clamp(0, _cells.length),
        List<EditorTextController>.generate(_colCount, (_) => _makeCtrl('')),
      );
    });
    _emit();
  }

  /// Voegt een lege kolom in op index [at] in elke rij. "Links invoegen" is
  /// dit met at = c; "rechts invoegen" met at = c + 1.
  void _insertColumnAt(int at) {
    final idx = at.clamp(0, _colCount);
    setState(() {
      for (final row in _cells) {
        row.insert(idx, _makeCtrl(''));
      }
    });
    _emit();
  }

  /// Verplaatst rij [r] met [delta] (−1 omhoog, +1 omlaag). De koprij (index 0)
  /// blijft de kop: een body-rij kan niet boven de kop komen, en de kop zelf
  /// verplaatst niet. Buiten de rand gebeurt niets.
  void _moveRow(int r, int delta) {
    final target = r + delta;
    if (r <= 0 || target <= 0 || target >= _cells.length) return;
    setState(() {
      final row = _cells.removeAt(r);
      _cells.insert(target, row);
    });
    _emit();
  }

  /// Verplaatst kolom [c] met [delta] (−1 links, +1 rechts). Buiten de rand
  /// gebeurt niets.
  void _moveColumn(int c, int delta) {
    final target = c + delta;
    if (target < 0 || target >= _colCount) return;
    setState(() {
      for (final row in _cells) {
        final ctrl = row.removeAt(c);
        row.insert(target, ctrl);
      }
    });
    _emit();
  }

  /// Zet de uitlijning van kolom [c] op [align]. Werkt op het slide-model
  /// (niet op [_cells], want uitlijning is geen celinhoud) en emit direct.
  void _setColumnAlign(int c, TableAlign align) {
    final aligns = List<TableAlign>.from(widget.slide.tableColumnAlignments);
    while (aligns.length <= c) {
      aligns.add(TableAlign.left);
    }
    aligns[c] = align;
    widget.onUpdate(widget.slide.copyWith(tableColumnAlignments: aligns));
  }

  /// Zet getalnotatie voor kolom [c] aan of uit. Werkt op het slide-model
  /// (niet op [_cells], want notatie is geen celinhoud) en emit direct.
  void _toggleNumberColumn(int c) {
    final cols = List<bool>.from(widget.slide.tableNumberColumns);
    while (cols.length <= c) {
      cols.add(false);
    }
    cols[c] = !cols[c];
    widget.onUpdate(widget.slide.copyWith(tableNumberColumns: cols));
  }

  /// Intercepts the paste shortcut on a cell: Cmd+V (macOS), Ctrl+V
  /// (Windows/Linux) and Shift+Insert (Windows/Linux). The clipboard can only
  /// be read asynchronously, so the event is always claimed and [_pasteIntoCell]
  /// decides between a table fill and a plain in-cell paste. Tab/Shift+Tab
  /// loopt door de cellen — op de laatste cel wordt een rij bijgemaakt — zodat
  /// de bouwer dezelfde cel-navigatie heeft als de presentatiemodus.
  KeyEventResult _onCellKey(int r, int c, KeyEvent event) {
    final keys = HardwareKeyboard.instance;
    final arrow = _arrowOf(event.logicalKey);
    // Dezelfde rekenblad-navigatie als de tabel in de documentmodus: eerst door
    // de tekst, en aan de rand van de celinhoud naar de buurcel. De regel staat
    // in `tableArrowTarget`, gedeeld met die tabel — twee tabellen die anders
    // op een pijltje reageren is precies wat een mens niet begrijpt.
    if (arrow != null && (event is KeyDownEvent || event is KeyRepeatEvent)) {
      if (keys.isShiftPressed || keys.isControlPressed || keys.isMetaPressed) {
        return KeyEventResult.ignored;
      }
      return _moveByArrow(r, c, arrow);
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final pasteCombo =
        (event.logicalKey == LogicalKeyboardKey.keyV &&
            (keys.isControlPressed || keys.isMetaPressed)) ||
        (event.logicalKey == LogicalKeyboardKey.insert && keys.isShiftPressed);
    if (pasteCombo) {
      Clipboard.getData(Clipboard.kTextPlain).then((data) {
        final text = data?.text;
        if (text == null || text.isEmpty || !mounted) return;
        _pasteIntoCell(r, c, text);
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      // Handled teruggeven wóórt de standaard-traversie af, zodat Tab hier
      // cel-naar-cel loopt in plaats van de tabel uit.
      if (keys.isShiftPressed) {
        final prev = prevTableCell(r, c, _colCount);
        if (prev == null) return KeyEventResult.handled; // eerste cel: blijf
        _moveFocusTo(prev.row, prev.col);
        return KeyEventResult.handled;
      }
      final next = nextTableCell(r, c, _cells.length, _colCount);
      if (next == null) {
        _addRowAndFocusFirst();
        return KeyEventResult.handled;
      }
      _moveFocusTo(next.row, next.col);
      return KeyEventResult.handled;
    }
    // Cmd/Ctrl+C met geen tekst geselecteerd in de cel kopieert de hele tabel
    // als TSV (plakt in een rekenblad). Staat er wél een tekstselectie, dan
    // laten we het event los zodat het veld die tekst kopieert — de cel is ook
    // een tekstveld, en die twee mogen niet om dezelfde Cmd+C vechten.
    final copyCombo =
        event.logicalKey == LogicalKeyboardKey.keyC &&
        (keys.isControlPressed || keys.isMetaPressed);
    if (copyCombo) {
      final sel = _cells[r][c].selection;
      if (sel.isValid && !sel.isCollapsed) return KeyEventResult.ignored;
      final tsv = encodeClipboardTable(_rows);
      if (tsv.isNotEmpty) {
        Clipboard.setData(ClipboardData(text: tsv));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Tabular clipboard content (a spreadsheet selection, CSV, a markdown
  /// table) fills the grid starting at cell (r, c), growing it as needed;
  /// anything else is pasted into the cell at the cursor as usual.
  void _pasteIntoCell(int r, int c, String text) {
    final table = parseClipboardTable(text);
    if (table == null) {
      final ctrl = _cells[r][c];
      final value = ctrl.text;
      final sel = ctrl.selection;
      final start = sel.isValid ? sel.start : value.length;
      final end = sel.isValid ? sel.end : value.length;
      ctrl.value = TextEditingValue(
        text: value.replaceRange(start, end, text),
        selection: TextSelection.collapsed(offset: start + text.length),
      );
      return;
    }
    setState(() {
      final neededCols = c + table.first.length;
      final neededRows = r + table.length;
      while (_colCount < neededCols) {
        for (final row in _cells) {
          row.add(_makeCtrl(''));
        }
      }
      while (_cells.length < neededRows) {
        _cells.add(
          List<EditorTextController>.generate(_colCount, (_) => _makeCtrl('')),
        );
      }
      for (var i = 0; i < table.length; i++) {
        for (var j = 0; j < table[i].length; j++) {
          final ctrl = _cells[r + i][c + j];
          // Rewrite without notifying per cell; one _emit follows below.
          ctrl.removeTextListener(_emit);
          ctrl.text = table[i][j];
          ctrl.addTextListener(_emit);
        }
      }
    });
    _emit();
  }

  @override
  void dispose() {
    _title.dispose();
    for (final row in _cells) {
      for (final c in row) {
        c.dispose();
      }
    }
    for (final row in _focusNodes) {
      for (final n in row) {
        n.dispose();
      }
    }
    super.dispose();
  }

  /// Houdt [_focusNodes] parallel aan [_cells]: evenveel rijen, evenveel
  /// kolommen per rij. Eén synchronisatiepunt in [build] in plaats van
  /// mirroring in elke mutatie (_addRow/_addColumn/_pasteIntoCell/…), zodat een
  /// vergeten helft geen lege focusnode-rij achterlaat.
  void _syncFocusNodes() {
    final rowCount = _cells.length;
    final colCount = _colCount;
    while (_focusNodes.length < rowCount) {
      _focusNodes.add([for (var c = 0; c < colCount; c++) FocusNode()]);
    }
    while (_focusNodes.length > rowCount) {
      for (final n in _focusNodes.removeLast()) {
        n.dispose();
      }
    }
    for (final row in _focusNodes) {
      while (row.length < colCount) {
        row.add(FocusNode());
      }
      while (row.length > colCount) {
        row.removeLast().dispose();
      }
    }
  }

  /// Focust cel (r, c) direct als de node al bestaat (Tab naar een bestaande
  /// cel); de [build] hoeft dan niet opnieuw te draaien.
  void _moveFocusTo(int r, int c, {TableCaret? caret}) {
    if (r >= 0 &&
        r < _focusNodes.length &&
        c >= 0 &&
        c < _focusNodes[r].length) {
      _focusNodes[r][c].requestFocus();
      if (caret == null) return;
      final text = _cells[r][c].text;
      // Kom je met een pijltje binnen, dan loopt de tekst door en hoort de
      // cursor aan de kant te staan waar je vandaan komt; met ↑/↓ is het een
      // celsprong en staat de hele inhoud klaar om vervangen te worden.
      _cells[r][c].selection = switch (caret) {
        TableCaret.selectAll => TextSelection(
          baseOffset: 0,
          extentOffset: text.length,
        ),
        TableCaret.start => const TextSelection.collapsed(offset: 0),
        TableCaret.end => TextSelection.collapsed(offset: text.length),
      };
    }
  }

  static TableArrow? _arrowOf(LogicalKeyboardKey key) => switch (key) {
    LogicalKeyboardKey.arrowLeft => TableArrow.left,
    LogicalKeyboardKey.arrowRight => TableArrow.right,
    LogicalKeyboardKey.arrowUp => TableArrow.up,
    LogicalKeyboardKey.arrowDown => TableArrow.down,
    _ => null,
  };

  /// Springt naar de buurcel wanneer de cursor aan de rand van de celinhoud
  /// staat, en laat de toets anders door naar het tekstveld.
  KeyEventResult _moveByArrow(int r, int c, TableArrow arrow) {
    final controller = _cells[r][c];
    final text = controller.text;
    final selection = controller.selection;
    if (!selection.isValid) return KeyEventResult.ignored;
    final offset = selection.baseOffset.clamp(0, text.length);
    final collapsed = selection.isCollapsed;
    final target = tableArrowTarget(
      arrow: arrow,
      row: r,
      col: c,
      rowCount: _cells.length,
      colCount: _colCount,
      atTextStart: collapsed && offset <= 0,
      atTextEnd: collapsed && offset >= text.length,
      onFirstLine: collapsed && !text.substring(0, offset).contains('\n'),
      onLastLine: collapsed && !text.substring(offset).contains('\n'),
    );
    return switch (target.move) {
      // Binnen de cel: het tekstveld zet de cursor zelf.
      TableArrowMove.inCell => KeyEventResult.ignored,
      TableArrowMove.toCell => () {
        _moveFocusTo(target.row, target.col, caret: target.caret);
        return KeyEventResult.handled;
      }(),
      // Aan de rand van de tabel is er niets te bewegen — en doorlaten zou de
      // toets bij de omliggende editor laten belanden.
      TableArrowMove.atEdge => KeyEventResult.handled,
    };
  }

  /// Markeert cel (r, c) als de focus-doel ná de eerstvolgende rebuild —
  /// gebruikt na "rij toevoegen", wanneer de doel-cel (en haar [FocusNode])
  /// pas in [build] wordt aangemaakt.
  void _focusAfterBuild(int r, int c) {
    _pendingFocusRow = r;
    _pendingFocusCol = c;
  }

  /// Voegt onderaan een lege rij toe en focust nadien de eerste cel ervan —
  /// het gedrag dat Tab op de laatste cel hoort te geven, gespiegeld aan de
  /// presentatiemodus.
  void _addRowAndFocusFirst() {
    _addRow();
    _focusAfterBuild(_cells.length - 1, 0);
  }

  @override
  Widget build(BuildContext context) {
    _syncFocusNodes();
    final pr = _pendingFocusRow;
    final pc = _pendingFocusCol;
    if (pr != null) {
      _pendingFocusRow = null;
      _pendingFocusCol = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moveFocusTo(pr, pc!);
      });
    }
    final l10n = context.l10n;
    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        Consumer(
          builder: (context, ref, _) {
            final collab = ref.watch(collabSessionProvider);
            if (!collab.isActive) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: AppTheme.amber600.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 15,
                        color: AppTheme.amber600,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          l10n.d(
                            'Tabelcel-bewerkingen worden niet gesynchroniseerd naar medebewerkers. De titel en andere velden wel.',
                          ),
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        if (!widget.documentContext) ...[
          EditorField(label: 'Titel', controller: _title, hint: 'Slide titel'),
          const SizedBox(height: 16),
        ],
        const SectionLabel('Tabel'),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '${l10n.d('Tip: druk op Enter binnen een cel voor een nieuwe regel.')}\n'
            '${l10n.d('Tip: plak met Cmd/Ctrl+V een tabel uit je spreadsheet in een cel om de hele tabel te vullen.')}',
            style: TextStyle(fontSize: 11, color: AppTheme.slate500),
          ),
        ),
        _buildColumnControls(),
        for (int r = 0; r < _cells.length; r++) _buildRow(r),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(
              onPressed: _addRow,
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.d('Rij toevoegen')),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _addColumn,
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.d('Kolom toevoegen')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildColumnControls() {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          for (int c = 0; c < _colCount; c++)
            Expanded(child: Center(child: _columnMenu(l10n, c))),
          const SizedBox(width: _rowActionWidth),
        ],
      ),
    );
  }

  /// Eén menu per kolom: invoegen-rechts, verplaatsen, uitlijnen, verwijderen.
  /// Houdt de kolomkop-regel op één regel hoogte in plaats van knoppen gestapeld.
  Widget _columnMenu(AppLocalizations l10n, int c) {
    final current = c < widget.slide.tableColumnAlignments.length
        ? widget.slide.tableColumnAlignments[c]
        : TableAlign.left;
    return PopupMenuButton<_ColumnAction>(
      tooltip: '${l10n.d('Kolom')} ${c + 1}',
      icon: Icon(Icons.more_vert, size: 18, color: AppTheme.slate500),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _ColumnAction.insertRight,
          child: Text(l10n.d('Kolom rechts invoegen')),
        ),
        PopupMenuItem(
          enabled: c > 0,
          value: _ColumnAction.moveLeft,
          child: Text(l10n.d('Kolom naar links')),
        ),
        PopupMenuItem(
          enabled: c < _colCount - 1,
          value: _ColumnAction.moveRight,
          child: Text(l10n.d('Kolom naar rechts')),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _ColumnAction.alignLeft,
          child: _alignItem(
            l10n.d('Links uitlijnen'),
            current == TableAlign.left,
          ),
        ),
        PopupMenuItem(
          value: _ColumnAction.alignCenter,
          child: _alignItem(l10n.d('Centreren'), current == TableAlign.center),
        ),
        PopupMenuItem(
          value: _ColumnAction.alignRight,
          child: _alignItem(
            l10n.d('Rechts uitlijnen'),
            current == TableAlign.right,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _ColumnAction.toggleNumber,
          child: _alignItem(
            l10n.d('Getalnotatie'),
            c < widget.slide.tableNumberColumns.length &&
                widget.slide.tableNumberColumns[c],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          enabled: _colCount > 1,
          value: _ColumnAction.delete,
          child: Text('${l10n.d('Kolom')} ${c + 1} ${l10n.d('verwijderen')}'),
        ),
      ],
      onSelected: (action) => switch (action) {
        _ColumnAction.insertRight => _insertColumnAt(c + 1),
        _ColumnAction.moveLeft => _moveColumn(c, -1),
        _ColumnAction.moveRight => _moveColumn(c, 1),
        _ColumnAction.alignLeft => _setColumnAlign(c, TableAlign.left),
        _ColumnAction.alignCenter => _setColumnAlign(c, TableAlign.center),
        _ColumnAction.alignRight => _setColumnAlign(c, TableAlign.right),
        _ColumnAction.delete => _removeColumn(c),
        _ColumnAction.toggleNumber => _toggleNumberColumn(c),
      },
    );
  }

  /// Een uitlijn-item met een vinkje als [selected] aan staat — Flutter's
  /// `PopupMenuItem` heeft geen `checked`, dus tekenen we het zelf.
  Widget _alignItem(String label, bool selected) => Row(
    children: [
      if (selected)
        Icon(Icons.check, size: 18, color: AppTheme.slate500)
      else
        const SizedBox(width: 18),
      const SizedBox(width: 8),
      Text(label),
    ],
  );

  Widget _buildRow(int r) {
    final l10n = context.l10n;
    final isHeader = r == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      // Top-align so cells that grow to multiple lines stay lined up.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int c = 0; c < _cells[r].length; c++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Focus(
                  onKeyEvent: (node, event) => _onCellKey(r, c, event),
                  child: TextField(
                    controller: _cells[r][c],
                    focusNode: _focusNodes[r][c],
                    // Meerdere regels toestaan: het veld groeit mee en Enter
                    // voegt een nieuwe regel toe binnen de cel.
                    minLines: 1,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isHeader
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: isHeader,
                      fillColor: isHeader ? AppTheme.slate100 : null,
                      hintText: isHeader ? '${l10n.d('Kolom')} ${c + 1}' : null,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Eén menu per rij: invoegen-onder, omhoog/omlaag, verwijderen. Houdt
          // de rijhoogte bij de cel — vier knoppen gestapeld maakten een
          // éénregelige cel drie keer zo hoog als de bediening.
          SizedBox(
            width: _rowActionWidth,
            height: 40,
            child: _rowMenu(l10n, r, isHeader),
          ),
        ],
      ),
    );
  }

  /// Het per-rij-menu. De koprij (r == 0) kan niet omhoog of verwijderd worden
  /// — de kop is de kop. Body-rijen verplaatsen binnen de body.
  Widget _rowMenu(AppLocalizations l10n, int r, bool isHeader) =>
      PopupMenuButton<_RowAction>(
        tooltip: isHeader ? l10n.d('Koprij') : l10n.d('Rij'),
        icon: Icon(Icons.more_vert, size: 18, color: AppTheme.slate500),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: _RowAction.insertBelow,
            child: Text(l10n.d('Rij onder invoegen')),
          ),
          PopupMenuItem(
            enabled: r > 1,
            value: _RowAction.moveUp,
            child: Text(l10n.d('Rij omhoog')),
          ),
          PopupMenuItem(
            enabled: r > 0 && r < _cells.length - 1,
            value: _RowAction.moveDown,
            child: Text(l10n.d('Rij omlaag')),
          ),
          PopupMenuItem(
            enabled: !isHeader && _cells.length > 1,
            value: _RowAction.delete,
            child: Text(
              isHeader
                  ? l10n.d('Koprij verwijderen')
                  : l10n.d('Rij verwijderen'),
            ),
          ),
        ],
        onSelected: (action) => switch (action) {
          _RowAction.insertBelow => _insertRowAt(r + 1),
          _RowAction.moveUp => _moveRow(r, -1),
          _RowAction.moveDown => _moveRow(r, 1),
          _RowAction.delete => _removeRow(r),
        },
      );
}
