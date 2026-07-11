import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/checklist_spec.dart';
import '../../models/slide.dart';
import '../../theme/app_theme.dart';
import '_editor_field.dart';

/// Editor for a `checklist` slide (PENTEST_MIAUW §3.2): a standard label plus a
/// list of tests, each with an id, name, MIAUW **tri-state** status, an optional
/// link to a finding id, and a note. Emits the slide's title (the standard
/// label) and `tableRows` via [ChecklistSpec]; storage stays a Markdown table.
class ChecklistEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  const ChecklistEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
  });

  @override
  State<ChecklistEditor> createState() => _ChecklistEditorState();
}

/// The controllers + status for one editable checklist row.
class _RowControllers {
  _RowControllers(ChecklistRow row, VoidCallback onChanged)
    : id = TextEditingController(text: row.id)..addListener(onChanged),
      test = TextEditingController(text: row.test)..addListener(onChanged),
      finding = TextEditingController(text: row.findingId)
        ..addListener(onChanged),
      note = TextEditingController(text: row.note)..addListener(onChanged),
      status = row.status;

  final TextEditingController id;
  final TextEditingController test;
  final TextEditingController finding;
  final TextEditingController note;
  ChecklistStatus status;

  ChecklistRow toRow() => ChecklistRow(
    id: id.text.trim(),
    test: test.text.trim(),
    status: status,
    findingId: finding.text.trim(),
    note: note.text.trim(),
  );

  void dispose() {
    id.dispose();
    test.dispose();
    finding.dispose();
    note.dispose();
  }
}

class _ChecklistEditorState extends State<ChecklistEditor> {
  late final TextEditingController _standard;
  late List<_RowControllers> _rows;

  @override
  void initState() {
    super.initState();
    final spec = ChecklistSpec.fromSlide(
      widget.slide.title,
      widget.slide.tableRows,
    );
    _standard = TextEditingController(text: spec.standardLabel)
      ..addListener(_emit);
    _rows = spec.rows.map((r) => _RowControllers(r, _emit)).toList();
    if (_rows.isEmpty) _rows = [_RowControllers(const ChecklistRow(), _emit)];
  }

  @override
  void dispose() {
    _standard.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final spec = ChecklistSpec(
      standardLabel: _standard.text.trim(),
      rows: _rows.map((r) => r.toRow()).toList(),
    );
    widget.onUpdate(
      widget.slide.copyWith(
        title: spec.standardLabel,
        tableRows: spec.toTableRows(),
      ),
    );
  }

  void _addRow() {
    setState(() => _rows.add(_RowControllers(const ChecklistRow(), _emit)));
    _emit();
  }

  void _removeRow(int index) {
    setState(() => _rows.removeAt(index).dispose());
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(
          label: 'Standaard',
          controller: _standard,
          hint: 'Checklist — OWASP WSTG',
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < _rows.length; i++) ...[
          _rowCard(context, i),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _addRow,
            icon: const Icon(Icons.add, size: 16),
            label: Text(l10n.d('Test toevoegen')),
          ),
        ),
      ],
    );
  }

  Widget _rowCard(BuildContext context, int index) {
    final l10n = context.l10n;
    final row = _rows[index];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.slate300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: EditorField(
                  label: 'ID',
                  controller: row.id,
                  hint: 'WSTG-ATHN-07',
                ),
              ),
              IconButton(
                tooltip: l10n.d('Test verwijderen'),
                onPressed: _rows.length > 1 ? () => _removeRow(index) : null,
                icon: const Icon(Icons.delete_outline, size: 18),
                color: AppTheme.slate500,
              ),
            ],
          ),
          const SizedBox(height: 8),
          EditorField(
            label: 'Test',
            controller: row.test,
            hint: 'Testing for Weak Password Policy',
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _statusDropdown(context, index)),
              const SizedBox(width: 8),
              Expanded(
                child: EditorField(
                  label: 'Bevinding',
                  controller: row.finding,
                  hint: 'F-03',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          EditorField(label: 'Notitie', controller: row.note),
        ],
      ),
    );
  }

  Widget _statusDropdown(BuildContext context, int index) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Status'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate500,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<ChecklistStatus>(
          initialValue: _rows[index].status,
          isDense: true,
          items: [
            for (final status in ChecklistStatus.values)
              DropdownMenuItem(
                value: status,
                child: Text(l10n.d(status.dutchLabel)),
              ),
          ],
          onChanged: (status) {
            if (status == null) return;
            setState(() => _rows[index].status = status);
            _emit();
          },
        ),
      ],
    );
  }
}
