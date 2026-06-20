import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/slide.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/table_clipboard.dart';
import '_editor_field.dart';

/// Editor for a table slide. Stores cells as a rectangular grid of
/// [TextEditingController]s where the first row is the header.
class TableEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  const TableEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
  });

  @override
  State<TableEditor> createState() => _TableEditorState();
}

class _TableEditorState extends State<TableEditor> {
  static const double _rowActionWidth = 40;

  late final TextEditingController _title;
  late List<List<TextEditingController>> _cells;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.slide.title);
    _title.addListener(_emit);
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
      return List<TextEditingController>.generate(
        colCount,
        (c) => _makeCtrl(c < row.length ? row[c] : ''),
      );
    }).toList();
  }

  TextEditingController _makeCtrl(String text) {
    final c = TextEditingController(text: text);
    c.addListener(_emit);
    return c;
  }

  int get _colCount => _cells.isEmpty ? 0 : _cells.first.length;

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(
        title: _title.text,
        tableRows: _cells
            .map((row) => row.map((c) => c.text).toList())
            .toList(),
      ),
    );
  }

  void _addRow() {
    setState(() {
      _cells.add(
        List<TextEditingController>.generate(_colCount, (_) => _makeCtrl('')),
      );
    });
    _emit();
  }

  void _removeRow(int r) {
    if (_cells.length <= 1) return;
    setState(() {
      for (final c in _cells[r]) {
        c.removeListener(_emit);
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
        row[c].removeListener(_emit);
        row[c].dispose();
        row.removeAt(c);
      }
    });
    _emit();
  }

  /// Intercepts the paste shortcut on a cell: Cmd+V (macOS), Ctrl+V
  /// (Windows/Linux) and Shift+Insert (Windows/Linux). The clipboard can only
  /// be read asynchronously, so the event is always claimed and [_pasteIntoCell]
  /// decides between a table fill and a plain in-cell paste.
  KeyEventResult _onCellKey(int r, int c, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final pasteCombo =
        (event.logicalKey == LogicalKeyboardKey.keyV &&
            (keys.isControlPressed || keys.isMetaPressed)) ||
        (event.logicalKey == LogicalKeyboardKey.insert && keys.isShiftPressed);
    if (!pasteCombo) return KeyEventResult.ignored;
    Clipboard.getData(Clipboard.kTextPlain).then((data) {
      final text = data?.text;
      if (text == null || text.isEmpty || !mounted) return;
      _pasteIntoCell(r, c, text);
    });
    return KeyEventResult.handled;
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
          List<TextEditingController>.generate(_colCount, (_) => _makeCtrl('')),
        );
      }
      for (var i = 0; i < table.length; i++) {
        for (var j = 0; j < table[i].length; j++) {
          final ctrl = _cells[r + i][c + j];
          // Rewrite without notifying per cell; one _emit follows below.
          ctrl.removeListener(_emit);
          ctrl.text = table[i][j];
          ctrl.addListener(_emit);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(label: 'Titel', controller: _title, hint: 'Slide titel'),
        const SizedBox(height: 16),
        const SectionLabel('Tabel'),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '${l10n.d('Tip: druk op Enter binnen een cel voor een nieuwe regel.')}\n'
            '${l10n.d('Tip: plak met Cmd/Ctrl+V een tabel uit je spreadsheet in een cel om de hele tabel te vullen.')}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
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
            Expanded(
              child: Center(
                child: IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: Color(0xFF64748B),
                  ),
                  onPressed: _colCount > 1 ? () => _removeColumn(c) : null,
                  tooltip:
                      '${l10n.d('Kolom')} ${c + 1} ${l10n.d('verwijderen')}',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              ),
            ),
          const SizedBox(width: _rowActionWidth),
        ],
      ),
    );
  }

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
                      fillColor: isHeader ? const Color(0xFFF1F5F9) : null,
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
          // Verwijderknop op de hoogte van de eerste regel houden.
          SizedBox(
            width: _rowActionWidth,
            height: 40,
            child: IconButton(
              icon: const Icon(
                Icons.remove_circle_outline,
                size: 18,
                color: Color(0xFF64748B),
              ),
              onPressed: _cells.length > 1 ? () => _removeRow(r) : null,
              tooltip: isHeader
                  ? l10n.d('Koprij verwijderen')
                  : l10n.d('Rij verwijderen'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28),
            ),
          ),
        ],
      ),
    );
  }
}
