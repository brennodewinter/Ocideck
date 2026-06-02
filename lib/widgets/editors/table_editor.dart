import 'package:flutter/material.dart';
import '../../models/slide.dart';
import '_editor_field.dart';

/// Editor for a table slide. Stores cells as a rectangular grid of
/// [TextEditingController]s where the first row is the header.
class TableEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;

  const TableEditor({super.key, required this.slide, required this.onUpdate});

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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        EditorField(label: 'Titel', controller: _title, hint: 'Slide titel'),
        const SizedBox(height: 16),
        const SectionLabel('Tabel'),
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text(
            'Tip: druk op Enter binnen een cel voor een nieuwe regel.',
            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
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
              label: const Text('Rij toevoegen'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _addColumn,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Kolom toevoegen'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildColumnControls() {
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
                    color: Color(0xFF94A3B8),
                  ),
                  onPressed: _colCount > 1 ? () => _removeColumn(c) : null,
                  tooltip: 'Kolom ${c + 1} verwijderen',
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
                    fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: isHeader,
                    fillColor: isHeader ? const Color(0xFFF1F5F9) : null,
                    hintText: isHeader ? 'Kolom ${c + 1}' : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
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
                color: Color(0xFF94A3B8),
              ),
              onPressed: _cells.length > 1 ? () => _removeRow(r) : null,
              tooltip: isHeader ? 'Koprij verwijderen' : 'Rij verwijderen',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28),
            ),
          ),
        ],
      ),
    );
  }
}
