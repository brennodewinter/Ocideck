import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/slide.dart';
import '../../services/improvement/matrix_slide.dart';
import '../../services/improvement/matrix_spec.dart';
import '../../theme/app_theme.dart';
import '../../utils/table_clipboard.dart';
import '_editor_field.dart';
import 'editor_text_controller.dart';

/// Editor for a Procesverbetering `matrix` slide (PROCESS_IMPROVEMENT §3.1).
///
/// Storage is a Markdown table plus `<!-- ocideck_template: … -->`. The template
/// picker remaps columns by key so switching SIPOC → FMEA does not wipe cells
/// that still make sense. Derived columns (RPN) are shown read-only and never
/// written into [Slide.tableRows].
class MatrixEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  const MatrixEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
  });

  @override
  State<MatrixEditor> createState() => _MatrixEditorState();
}

class _MatrixEditorState extends State<MatrixEditor> {
  late final EditorTextController _title;
  late List<List<EditorTextController>> _cells;
  late String _templateId;

  @override
  void initState() {
    super.initState();
    _title = EditorTextController(text: widget.slide.title)
      ..addTextListener(_emit);
    _templateId = widget.slide.improvementTemplateId.isEmpty
        ? kDefaultImprovementTemplateId
        : widget.slide.improvementTemplateId;
    _initCells(widget.slide.tableRows);
  }

  @override
  void didUpdateWidget(covariant MatrixEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slide.id != widget.slide.id) {
      _title.text = widget.slide.title;
      _templateId = widget.slide.improvementTemplateId.isEmpty
          ? kDefaultImprovementTemplateId
          : widget.slide.improvementTemplateId;
      _disposeCells();
      _initCells(widget.slide.tableRows);
    }
  }

  void _initCells(List<List<String>> raw) {
    final rows = raw.isEmpty
        ? improvementTemplateStarterRows(_templateId)
        : raw.map((r) => List<String>.from(r)).toList();
    final colCount = rows.fold<int>(1, (m, r) => r.length > m ? r.length : m);
    _cells = [
      for (final row in rows)
        List<EditorTextController>.generate(
          colCount,
          (c) => _makeCtrl(c < row.length ? row[c] : ''),
        ),
    ];
  }

  EditorTextController _makeCtrl(String text) {
    final c = EditorTextController(text: text);
    c.addTextListener(_emit);
    return c;
  }

  void _disposeCells() {
    for (final row in _cells) {
      for (final c in row) {
        c.removeTextListener(_emit);
        c.dispose();
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _disposeCells();
    super.dispose();
  }

  int get _colCount => _cells.isEmpty ? 0 : _cells.first.length;

  List<List<String>> get _rows =>
      _cells.map((row) => row.map((c) => c.text).toList()).toList();

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(
        title: _title.text,
        tableRows: _rows,
        improvementTemplateId: _templateId,
      ),
    );
  }

  void _setTemplate(String id) {
    if (id == _templateId) return;
    final remapped = matrixRowsForTemplate(
      widget.slide.copyWith(
        tableRows: _rows,
        improvementTemplateId: _templateId,
      ),
      id,
    );
    setState(() {
      _templateId = id;
      _disposeCells();
      _initCells(remapped);
    });
    _emit();
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
    // Keep the header; never drop the last data row (editors expect ≥1).
    if (r == 0 || _cells.length <= 2) return;
    setState(() {
      for (final c in _cells[r]) {
        c.removeTextListener(_emit);
        c.dispose();
      }
      _cells.removeAt(r);
    });
    _emit();
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) return;
    final parsed = parseClipboardTable(text);
    if (parsed == null || parsed.isEmpty) return;
    setState(() {
      _disposeCells();
      // Keep the template header; paste replaces data rows only when the
      // clipboard has no header of its own that matches column count.
      final header = _rows.isEmpty
          ? matrixHeaderRow(
              improvementTemplateById(_templateId) ??
                  bundledImprovementTemplates.first,
            )
          : _rows.first;
      final body = parsed.length > 1 && parsed.first.length == header.length
          ? parsed.skip(1)
          : parsed;
      _initCells([header, ...body]);
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final displayCols = matrixDisplayColumns(
      widget.slide.copyWith(improvementTemplateId: _templateId),
    );
    final storedCount = matrixStoredColumns(
      widget.slide.copyWith(improvementTemplateId: _templateId),
    ).length;
    final showRpn = displayCols.any((c) => c.derived);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditorField(controller: _title, label: l10n.d('Titel')),
        const SizedBox(height: 12),
        Text(l10n.d('Sjabloon'), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue:
              bundledImprovementTemplates.any((t) => t.id == _templateId)
              ? _templateId
              : kDefaultImprovementTemplateId,
          isExpanded: true,
          items: [
            for (final t in bundledImprovementTemplates)
              DropdownMenuItem(
                value: t.id,
                child: Text('${t.label(lang)} — ${t.guidance(lang)}'),
              ),
          ],
          onChanged: (v) {
            if (v != null) _setTemplate(v);
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _pasteClipboard,
            icon: const Icon(Icons.content_paste_outlined, size: 18),
            label: Text(l10n.d('Plakken uit klembord')),
          ),
        ),
        const SizedBox(height: 8),
        _grid(context, storedCount: storedCount, showRpn: showRpn),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addRow,
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.d('Rij toevoegen')),
          ),
        ),
      ],
    );

    if (widget.nestedInScrollView) return body;
    return SingleChildScrollView(child: body);
  }

  Widget _grid(
    BuildContext context, {
    required int storedCount,
    required bool showRpn,
  }) {
    final lang = Localizations.localeOf(context).languageCode;
    final cols = matrixDisplayColumns(
      widget.slide.copyWith(improvementTemplateId: _templateId),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var r = 0; r < _cells.length; r++)
            Row(
              children: [
                for (var c = 0; c < storedCount && c < _cells[r].length; c++)
                  SizedBox(
                    width: 110,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: TextField(
                        controller: _cells[r][c],
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: r == 0 && c < cols.length
                              ? (lang.startsWith('nl')
                                    ? cols[c].labelNl
                                    : cols[c].labelEn)
                              : null,
                          border: const OutlineInputBorder(),
                          filled: r == 0,
                          fillColor: r == 0 ? AppTheme.slate100 : null,
                        ),
                        // Header row is the English contract; keep it editable
                        // only when the template is unknown.
                        readOnly:
                            r == 0 &&
                            improvementTemplateById(_templateId) != null,
                        style: TextStyle(
                          fontWeight: r == 0
                              ? FontWeight.w600
                              : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                if (showRpn)
                  SizedBox(
                    width: 64,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.slate300),
                          color: r == 0 ? AppTheme.slate100 : AppTheme.slate50,
                        ),
                        child: Text(
                          r == 0
                              ? context.l10n.d('RPN')
                              : '${matrixRowRpn(widget.slide.copyWith(tableRows: _rows, improvementTemplateId: _templateId), _rows[r]) ?? ''}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppTheme.slate700,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (r > 0)
                  IconButton(
                    tooltip: context.l10n.d('Rij verwijderen'),
                    onPressed: () => _removeRow(r),
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                  )
                else
                  const SizedBox(width: 40),
              ],
            ),
        ],
      ),
    );
  }
}
