import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/cvss_builder.dart';
import '../../models/scope_matrix_spec.dart';
import '../../models/slide.dart';
import '../../state/deck_provider.dart';
import '../../theme/app_theme.dart';
import '_editor_field.dart';

/// Editor for a `scopeMatrix` slide (PENTEST_MIAUW §2.2 / §4.4): a title plus a
/// list of scope objects, each with a type that fixes its test standard (§10.7,
/// shown read-only), a coverage status, and a note. Emits the slide title and
/// `tableRows` via [ScopeMatrixSpec]; storage stays a Markdown table.
///
/// A one-click **Generate checklists** action creates a `checklist` slide per
/// scope object that lacks one (feedback #8), via
/// [DeckNotifier.generateScopeChecklists].
class ScopeMatrixEditor extends ConsumerStatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  const ScopeMatrixEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
  });

  @override
  ConsumerState<ScopeMatrixEditor> createState() => _ScopeMatrixEditorState();
}

class _RowControllers {
  _RowControllers(ScopeRow row, VoidCallback onChanged)
    : object = TextEditingController(text: row.object)..addListener(onChanged),
      note = TextEditingController(text: row.note)..addListener(onChanged),
      type = row.type,
      status = row.status,
      cia = row.cia;

  final TextEditingController object;
  final TextEditingController note;
  ScopeObjectType type;
  ScopeStatus status;
  CiaRating cia;

  ScopeRow toRow() => ScopeRow(
    object: object.text.trim(),
    type: type,
    status: status,
    note: note.text.trim(),
    cia: cia,
  );

  void dispose() {
    object.dispose();
    note.dispose();
  }
}

class _ScopeMatrixEditorState extends ConsumerState<ScopeMatrixEditor> {
  late final TextEditingController _title;
  late List<_RowControllers> _rows;

  @override
  void initState() {
    super.initState();
    final spec = ScopeMatrixSpec.fromSlide(
      widget.slide.title,
      widget.slide.tableRows,
    );
    _title = TextEditingController(text: spec.title)..addListener(_emit);
    _rows = spec.rows.map((r) => _RowControllers(r, _emit)).toList();
    if (_rows.isEmpty) _rows = [_RowControllers(const ScopeRow(), _emit)];
  }

  @override
  void dispose() {
    _title.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final spec = ScopeMatrixSpec(
      title: _title.text.trim(),
      rows: _rows.map((r) => r.toRow()).toList(),
    );
    widget.onUpdate(
      widget.slide.copyWith(title: spec.title, tableRows: spec.toTableRows()),
    );
  }

  void _addRow() {
    setState(() => _rows.add(_RowControllers(const ScopeRow(), _emit)));
    _emit();
  }

  void _removeRow(int index) {
    setState(() => _rows.removeAt(index).dispose());
    _emit();
  }

  void _moveRow(int from, int to) {
    if (to < 0 || to >= _rows.length) return;
    setState(() => _rows.insert(to, _rows.removeAt(from)));
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(label: 'Titel', controller: _title, hint: 'Scope'),
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
            label: Text(l10n.d('Object toevoegen')),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: l10n.d(
              'Maakt per scope-object een checklist (WSTG voor web/API); '
              'bestaande blijven staan.',
            ),
            child: OutlinedButton.icon(
              onPressed: _generateChecklists,
              icon: const Icon(Icons.playlist_add_check, size: 16),
              label: Text(l10n.d('Genereer checklists voor scope-objecten')),
            ),
          ),
        ),
      ],
    );
  }

  /// Create a checklist slide per scope object that lacks one, then report how
  /// many were added via a SnackBar.
  void _generateChecklists() {
    final l10n = context.l10n;
    final added = ref.read(deckProvider.notifier).generateScopeChecklists();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added > 0
              ? '$added ${l10n.d('checklists toegevoegd')}'
              : l10n.d('Alle scope-objecten hebben al een checklist'),
        ),
      ),
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
                  label: 'Object',
                  controller: row.object,
                  hint: 'https://app.voorbeeld',
                ),
              ),
              IconButton(
                tooltip: l10n.d('Omhoog'),
                onPressed: index > 0 ? () => _moveRow(index, index - 1) : null,
                icon: const Icon(Icons.arrow_upward, size: 18),
                color: AppTheme.slate500,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: l10n.d('Omlaag'),
                onPressed: index < _rows.length - 1
                    ? () => _moveRow(index, index + 1)
                    : null,
                icon: const Icon(Icons.arrow_downward, size: 18),
                color: AppTheme.slate500,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: l10n.d('Object verwijderen'),
                onPressed: _rows.length > 1 ? () => _removeRow(index) : null,
                icon: const Icon(Icons.delete_outline, size: 18),
                color: AppTheme.slate500,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _typeDropdown(context, index)),
              const SizedBox(width: 8),
              Expanded(child: _statusDropdown(context, index)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${l10n.d('Standaard')}: ${row.type.standard.isEmpty ? '—' : row.type.standard}',
            style: TextStyle(fontSize: 12, color: AppTheme.slate500),
          ),
          const SizedBox(height: 8),
          EditorField(label: 'Notitie', controller: row.note),
          const SizedBox(height: 10),
          Text(
            l10n.d('CIA-rating (scope-object)'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate500,
            ),
          ),
          Text(
            l10n.d(
              'Bepaalt de contextscore van bevindingen op dit object; laat leeg als de weging niet bekend is.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
          const SizedBox(height: 6),
          _ciaRow(
            l10n.d('Vertrouwelijkheid'),
            row.cia.confidentiality,
            (v) => _setCia(index, row.cia.copyWith(confidentiality: v)),
          ),
          _ciaRow(
            l10n.d('Integriteit'),
            row.cia.integrity,
            (v) => _setCia(index, row.cia.copyWith(integrity: v)),
          ),
          _ciaRow(
            l10n.d('Beschikbaarheid'),
            row.cia.availability,
            (v) => _setCia(index, row.cia.copyWith(availability: v)),
          ),
        ],
      ),
    );
  }

  void _setCia(int index, CiaRating cia) {
    setState(() => _rows[index].cia = cia);
    _emit();
  }

  /// One CIA-dimension dropdown (`X`/`L`/`M`/`H`), styled like the finding
  /// wizard's builder: a fixed label beside a compact dropdown.
  Widget _ciaRow(
    String label,
    CiaLevel value,
    ValueChanged<CiaLevel> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            flex: 4,
            child: DropdownButton<CiaLevel>(
              isExpanded: true,
              isDense: true,
              value: value,
              style: TextStyle(fontSize: 12, color: AppTheme.ink),
              items: [
                for (final level in CiaLevel.values)
                  DropdownMenuItem(
                    value: level,
                    child: Text(
                      '${level.token} · ${context.l10n.d(level.dutchLabel)}',
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeDropdown(BuildContext context, int index) {
    final l10n = context.l10n;
    return _labeledDropdown<ScopeObjectType>(
      label: l10n.d('Type'),
      value: _rows[index].type,
      items: [
        for (final type in ScopeObjectType.values)
          DropdownMenuItem(value: type, child: Text(l10n.d(type.dutchLabel))),
      ],
      onChanged: (type) {
        if (type == null) return;
        setState(() => _rows[index].type = type);
        _emit();
      },
    );
  }

  Widget _statusDropdown(BuildContext context, int index) {
    final l10n = context.l10n;
    return _labeledDropdown<ScopeStatus>(
      label: l10n.d('Status'),
      value: _rows[index].status,
      items: [
        for (final status in ScopeStatus.values)
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
    );
  }

  Widget _labeledDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate500,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<T>(
          initialValue: value,
          isDense: true,
          items: items,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
