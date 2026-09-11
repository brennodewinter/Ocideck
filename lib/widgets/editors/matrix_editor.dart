import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/slide.dart';
import '../../services/improvement/matrix_slide.dart';
import '../../services/improvement/matrix_spec.dart';
import '../../theme/app_theme.dart';
import '../reader/table_edit_controller.dart';
import '../reader/table_edit_scaffold.dart';
import '../reader/table_editable_cell.dart';
import '_editor_field.dart';
import 'editor_text_controller.dart';

/// Editor for a Procesverbetering `matrix` slide (PROCESS_IMPROVEMENT §3.1).
///
/// Storage is a Markdown table plus `<!-- ocideck_template: … -->`. The template
/// picker remaps columns by key so switching SIPOC → FMEA does not wipe cells
/// that still make sense. Derived columns (RPN) are shown read-only and never
/// written into [Slide.tableRows].
///
/// Het raster is hetzelfde rekenblad als een documenttabel: ter plekke
/// invullen, Tab/Enter, plakken vanaf de cel. De kop en de kolommen blijven
/// het sjablooncontract — die groeien niet mee.
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
  late TableEditController _grid;
  late String _templateId;

  @override
  void initState() {
    super.initState();
    _title = EditorTextController(text: widget.slide.title)
      ..addTextListener(_emit);
    _templateId = widget.slide.improvementTemplateId.isEmpty
        ? kDefaultImprovementTemplateId
        : widget.slide.improvementTemplateId;
    _initGrid(widget.slide.tableRows);
  }

  @override
  void didUpdateWidget(covariant MatrixEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slide.id != widget.slide.id) {
      _title.text = widget.slide.title;
      _templateId = widget.slide.improvementTemplateId.isEmpty
          ? kDefaultImprovementTemplateId
          : widget.slide.improvementTemplateId;
      _grid.dispose();
      _initGrid(widget.slide.tableRows);
    }
  }

  void _initGrid(List<List<String>> raw) {
    final rows = raw.isEmpty
        ? improvementTemplateStarterRows(_templateId)
        : raw.map((r) => List<String>.from(r)).toList();
    final colCount = rows.fold<int>(1, (m, r) => r.length > m ? r.length : m);
    _grid = TableEditController(
      rows: rows,
      alignments: List<TableAlign>.filled(colCount, TableAlign.left),
      lockHeader: true,
      lockColumns: true,
      onChanged: (_, _) => _emit(),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _grid.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(
        title: _title.text,
        tableRows: _grid.rows,
        improvementTemplateId: _templateId,
      ),
    );
  }

  void _setTemplate(String id) {
    if (id == _templateId) return;
    final remapped = matrixRowsForTemplate(
      widget.slide.copyWith(
        tableRows: _grid.rows,
        improvementTemplateId: _templateId,
      ),
      id,
    );
    setState(() {
      _templateId = id;
      _grid.dispose();
      _initGrid(remapped);
    });
    _emit();
  }

  void _addRow() {
    _grid.insertRowAt(_grid.rowCount);
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) return;
    // Vanaf de eerste body-cel: de kop is het sjabloon en blijft staan.
    _grid.pasteAt(1, 0, text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;

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
        TableEditScaffold(
          editor: _grid,
          allowColumnEdits: false,
          builder: (_) => _matrixTable(context),
        ),
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

  Widget _matrixTable(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final displayCols = matrixDisplayColumns(
      widget.slide.copyWith(improvementTemplateId: _templateId),
    );
    final storedCount = matrixStoredColumns(
      widget.slide.copyWith(improvementTemplateId: _templateId),
    ).length;
    final showRpn = displayCols.any((c) => c.derived);
    final style = theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 13);
    final headerStyle = style.copyWith(fontWeight: FontWeight.w600);
    final caret = theme.colorScheme.primary;
    final rows = _grid.rows;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: theme.dividerColor),
        children: [
          for (var r = 0; r < _grid.rowCount; r++)
            TableRow(
              decoration: BoxDecoration(
                color: r == 0 ? AppTheme.slate100 : null,
              ),
              children: [
                for (var c = 0; c < storedCount && c < _grid.colCount; c++)
                  TableEditableCell(
                    editor: _grid,
                    row: r,
                    column: c,
                    style: r == 0 ? headerStyle : style,
                    pad: 6,
                    caretColor: caret,
                    linkColor: theme.colorScheme.primary,
                  ),
                if (showRpn)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Text(
                      r == 0
                          ? l10n.d('RPN')
                          : '${matrixRowRpn(widget.slide.copyWith(tableRows: rows, improvementTemplateId: _templateId), rows[r]) ?? ''}',
                      style: headerStyle,
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
