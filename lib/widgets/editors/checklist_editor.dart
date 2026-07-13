import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/checklist_spec.dart';
import '../../models/slide.dart';
import '../../services/finding_context_score.dart';
import '../../services/wstg_catalog.dart';
import '../../state/deck_provider.dart';
import '../../theme/app_theme.dart';
import '_editor_field.dart';

/// Editor for a `checklist` slide (PENTEST_MIAUW §3.2): a standard label plus a
/// list of tests, each with an id, name, MIAUW **tri-state** status, an optional
/// link to a finding id, and a note. Emits the slide's title (the standard
/// label) and `tableRows` via [ChecklistSpec]; storage stays a Markdown table.
///
/// A one-click **Load WSTG tests** action fills the list from the bundled
/// [WstgCatalog] (the full OWASP WSTG v4.2 checklist), non-destructively: it
/// only appends the tests whose id is not already present, so existing rows and
/// their statuses are preserved. The standard label then carries the version.
///
/// A **scope-object** field links the checklist to a scope-matrix object
/// (feedback #8, "per scope-object heb je een checklist"): free text plus a
/// dropdown filled from the deck's scope matrix. It stores [Slide.checklistScope].
class ChecklistEditor extends ConsumerStatefulWidget {
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
  ConsumerState<ChecklistEditor> createState() => _ChecklistEditorState();
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

class _ChecklistEditorState extends ConsumerState<ChecklistEditor> {
  late final TextEditingController _standard;
  late final TextEditingController _scope;
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
    _scope = TextEditingController(text: widget.slide.checklistScope)
      ..addListener(_emit);
    _rows = spec.rows.map((r) => _RowControllers(r, _emit)).toList();
    if (_rows.isEmpty) _rows = [_RowControllers(const ChecklistRow(), _emit)];
  }

  @override
  void dispose() {
    _standard.dispose();
    _scope.dispose();
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
        checklistScope: _scope.text.trim(),
      ),
    );
  }

  void _addRow() {
    setState(() => _rows.add(_RowControllers(const ChecklistRow(), _emit)));
    _emit();
  }

  /// Append every WSTG test not already present (matched by id), preserving the
  /// current rows and their statuses. Replaces a lone blank starter row, and
  /// sets the standard label to the versioned WSTG label when it is still empty.
  void _loadWstg() {
    final blankStarter =
        _rows.length == 1 &&
        _rows.first.id.text.trim().isEmpty &&
        _rows.first.test.text.trim().isEmpty &&
        _rows.first.finding.text.trim().isEmpty &&
        _rows.first.note.text.trim().isEmpty;
    final present = {for (final r in _rows) r.id.text.trim().toUpperCase()}
      ..remove('');
    final additions = [
      for (final t in WstgCatalog.instance.tests)
        if (!present.contains(t.id.toUpperCase()))
          _RowControllers(ChecklistRow(id: t.id, test: t.title), _emit),
    ];
    if (additions.isEmpty) return;
    setState(() {
      if (blankStarter) _rows.removeAt(0).dispose();
      _rows.addAll(additions);
      if (_standard.text.trim().isEmpty) {
        _standard.text = WstgCatalog.instance.standardLabel;
      }
    });
    _emit();
  }

  void _removeRow(int index) {
    setState(() => _rows.removeAt(index).dispose());
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final deck = ref.watch(deckProvider.select((s) => s.deck));
    final scopeObjects = <String>{
      for (final r in deckScopeRows(deck?.slides ?? const []))
        if (r.object.trim().isNotEmpty) r.object.trim(),
    }.toList();
    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        _scopeField(context, scopeObjects),
        const SizedBox(height: 12),
        EditorField(
          label: 'Standaard',
          controller: _standard,
          hint: WstgCatalog.instance.standardLabel,
        ),
        const SizedBox(height: 12),
        _wstgLoadRow(context),
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

  /// The scope-object this checklist covers: a free-text field plus a dropdown
  /// filled from the deck's scope matrix, mirroring the finding editor's scope
  /// picker. Stored on [Slide.checklistScope]; typing an object not (yet) in the
  /// matrix stays allowed.
  Widget _scopeField(BuildContext context, List<String> scopeObjects) {
    final l10n = context.l10n;
    // Via a variable so the URL example is not scanned as a translatable literal.
    const hint = 'https://app.voorbeeld/login';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Scope-object'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate500,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _scope,
                minLines: 1,
                maxLines: 1,
                decoration: InputDecoration(hintText: l10n.d(hint)),
              ),
            ),
            if (scopeObjects.isNotEmpty)
              PopupMenuButton<String>(
                icon: Icon(Icons.arrow_drop_down, color: AppTheme.slate500),
                tooltip: l10n.d('Kies uit de scope'),
                onSelected: (v) => _scope.text = v,
                itemBuilder: (_) => [
                  for (final o in scopeObjects)
                    PopupMenuItem(
                      value: o,
                      child: Text(o, style: const TextStyle(fontSize: 13)),
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  /// The "load the standard's tests" affordance: a button plus a caption naming
  /// the bundled standard version, so the version is visible before any load.
  Widget _wstgLoadRow(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Tooltip(
          message: l10n.d(
            'Voegt ontbrekende WSTG-testen toe; bestaande blijven staan.',
          ),
          child: OutlinedButton.icon(
            onPressed: _loadWstg,
            icon: const Icon(Icons.playlist_add_check, size: 16),
            label: Text(l10n.d('WSTG-testen laden')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${WstgCatalog.instance.standardLabel} · '
            '${WstgCatalog.instance.tests.length} '
            '${l10n.d('testen')}',
            style: TextStyle(fontSize: 12, color: AppTheme.slate500),
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
