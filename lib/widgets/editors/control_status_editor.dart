import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/control_status_spec.dart';
import '../../models/management_system.dart';
import '../../models/slide.dart';
import '../../services/management_system_catalog.dart';
import '../../state/deck_provider.dart';
import '../../theme/app_theme.dart';
import '_editor_field.dart';

/// Editor for a `controlStatus` slide (ISO_MANAGEMENTSYSTEEM §4): a section
/// heading plus a list of controls, each with an implementation status, an
/// optional maturity (0–5), an owner, a target date/period, an evidence
/// reference and a note. Emits the slide title and `tableRows` via
/// [ControlStatusSpec]; storage stays a plain Markdown table.
///
/// A one-click **Load controls** action appends the index of a chosen ISO
/// standard (optionally one section) from [ManagementSystemCatalog], so an
/// author never types 93 control ids by hand.
class ControlStatusEditor extends ConsumerStatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  const ControlStatusEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
  });

  @override
  ConsumerState<ControlStatusEditor> createState() =>
      _ControlStatusEditorState();
}

class _RowControllers {
  _RowControllers(ControlStatusRow row, VoidCallback onChanged)
    : id = TextEditingController(text: row.id)..addListener(onChanged),
      control = TextEditingController(text: row.control)
        ..addListener(onChanged),
      owner = TextEditingController(text: row.owner)..addListener(onChanged),
      target = TextEditingController(text: row.target)..addListener(onChanged),
      evidence = TextEditingController(text: row.evidence)
        ..addListener(onChanged),
      note = TextEditingController(text: row.note)..addListener(onChanged),
      status = row.status,
      maturity = row.maturity;

  final TextEditingController id;
  final TextEditingController control;
  final TextEditingController owner;
  final TextEditingController target;
  final TextEditingController evidence;
  final TextEditingController note;
  ControlStatus status;
  int maturity;

  ControlStatusRow toRow() => ControlStatusRow(
    id: id.text.trim(),
    control: control.text.trim(),
    status: status,
    maturity: maturity,
    owner: owner.text.trim(),
    target: target.text.trim(),
    evidence: evidence.text.trim(),
    note: note.text.trim(),
  );

  void dispose() {
    id.dispose();
    control.dispose();
    owner.dispose();
    target.dispose();
    evidence.dispose();
    note.dispose();
  }
}

class _ControlStatusEditorState extends ConsumerState<ControlStatusEditor> {
  late final TextEditingController _title;
  late List<_RowControllers> _rows;

  @override
  void initState() {
    super.initState();
    final spec = ControlStatusSpec.fromSlide(
      widget.slide.title,
      widget.slide.tableRows,
    );
    _title = TextEditingController(text: spec.heading)..addListener(_emit);
    _rows = spec.rows.map((r) => _RowControllers(r, _emit)).toList();
    if (_rows.isEmpty) {
      _rows = [_RowControllers(const ControlStatusRow(), _emit)];
    }
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
    final spec = ControlStatusSpec(
      heading: _title.text.trim(),
      rows: _rows.map((r) => r.toRow()).toList(),
    );
    widget.onUpdate(
      widget.slide.copyWith(title: spec.heading, tableRows: spec.toTableRows()),
    );
  }

  void _addRow() {
    setState(() => _rows.add(_RowControllers(const ControlStatusRow(), _emit)));
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
        EditorField(
          label: 'Kop',
          controller: _title,
          hint: 'ISO 27001 · Annex A — Organisatorisch (A.5)',
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
            label: Text(l10n.d('Beheersmaatregel toevoegen')),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: l10n.d(
              'Voegt de beheersmaatregelen van een ISO-norm toe (alleen de index; alleen nieuwe ids).',
            ),
            child: OutlinedButton.icon(
              onPressed: _loadControls,
              icon: const Icon(Icons.playlist_add, size: 16),
              label: Text(l10n.d('Beheersmaatregelen laden…')),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: l10n.d(
              'Maakt of vernieuwt een overzichtsdia met de voortgang per sectie (afgeleid uit alle beheersmaatregel-dia\'s).',
            ),
            child: OutlinedButton.icon(
              onPressed: _generateOverview,
              icon: const Icon(Icons.summarize_outlined, size: 16),
              label: Text(l10n.d('Genereer voortgangsoverzicht')),
            ),
          ),
        ),
      ],
    );
  }

  /// Regenerate the deck-wide progress overview from every `controlStatus`
  /// slide, then report the outcome via a SnackBar.
  void _generateOverview() {
    final l10n = context.l10n;
    final made = generateManagementSystemOverview(
      ref.read(deckProvider.notifier),
      overviewTitle: l10n.d('Voortgang managementsysteem'),
      sectionHeader: l10n.d('Sectie'),
      applicableHeader: l10n.d('Van toepassing'),
      implementedHeader: l10n.d('Geïmplementeerd'),
      progressHeader: l10n.d('Voortgang'),
      totalLabel: l10n.d('Totaal'),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          made > 0
              ? l10n.d('Voortgangsoverzicht bijgewerkt')
              : l10n.d('Nog geen beheersmaatregel-dia\'s om samen te vatten'),
        ),
      ),
    );
  }

  /// Ask which standard (and optionally which section) to append, then add every
  /// control whose id is not already present. Existing rows are never touched.
  Future<void> _loadControls() async {
    final l10n = context.l10n;
    final standard = await _pickStandard();
    if (!mounted || standard == null) return;
    final section = await _pickSection(standard);
    if (!mounted || section == null) return;

    final cat = ManagementSystemCatalog.instance;
    final entries = section.isEmpty
        ? cat.controlsFor(standard)
        : cat.controlsInSection(standard, section);
    final present = _rows.map((r) => r.id.text.trim()).toSet();
    var added = 0;
    // Replace a single blank starter row so a fresh slide fills cleanly.
    final onlyBlank = _rows.length == 1 && _rows.first.toRow().id.isEmpty;
    setState(() {
      if (onlyBlank) _rows.removeAt(0).dispose();
      for (final e in entries) {
        if (present.contains(e.id)) continue;
        _rows.add(
          _RowControllers(ControlStatusRow(id: e.id, control: e.title), _emit),
        );
        added++;
      }
    });
    _emit();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$added ${l10n.d('beheersmaatregelen geladen')}')),
    );
  }

  Future<ManagementSystemStandard?> _pickStandard() {
    final l10n = context.l10n;
    return showDialog<ManagementSystemStandard>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.d('Kies een norm')),
        children: [
          for (final s in ManagementSystemStandard.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s),
              child: Text(s.label),
            ),
        ],
      ),
    );
  }

  /// Returns the chosen section id, or an empty string for "all sections", or
  /// null when the dialog is dismissed.
  Future<String?> _pickSection(ManagementSystemStandard standard) {
    final l10n = context.l10n;
    final sections = ManagementSystemCatalog.instance.sectionsFor(standard);
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.d('Welk deel?')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ''),
            child: Text(l10n.d('Alle secties')),
          ),
          for (final s in sections)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s.id),
              child: Text('${s.id} · ${s.title}'),
            ),
        ],
      ),
    );
  }

  Widget _rowCard(BuildContext context, int index) {
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
              SizedBox(
                width: 90,
                child: EditorField(
                  label: 'ID',
                  controller: row.id,
                  hint: 'A.5.1',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: EditorField(
                  label: 'Beheersmaatregel',
                  controller: row.control,
                ),
              ),
              _rowButtons(context, index),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _statusDropdown(context, index)),
              const SizedBox(width: 8),
              Expanded(child: _maturityDropdown(context, index)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: EditorField(label: 'Eigenaar', controller: row.owner),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: EditorField(
                  label: 'Streefdatum',
                  controller: row.target,
                  hint: '2026-Q4',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          EditorField(label: 'Bewijs', controller: row.evidence),
          const SizedBox(height: 8),
          EditorField(label: 'Notitie', controller: row.note),
        ],
      ),
    );
  }

  Widget _rowButtons(BuildContext context, int index) {
    final l10n = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
          tooltip: l10n.d('Verwijderen'),
          onPressed: _rows.length > 1 ? () => _removeRow(index) : null,
          icon: const Icon(Icons.delete_outline, size: 18),
          color: AppTheme.slate500,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _statusDropdown(BuildContext context, int index) {
    final l10n = context.l10n;
    return _labeledDropdown<ControlStatus>(
      label: l10n.d('Status'),
      value: _rows[index].status,
      items: [
        for (final status in ControlStatus.values)
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

  Widget _maturityDropdown(BuildContext context, int index) {
    final l10n = context.l10n;
    return _labeledDropdown<int>(
      label: l10n.d('Niveau'),
      value: _rows[index].maturity,
      items: [
        DropdownMenuItem(value: 0, child: Text(l10n.d('Niet gescoord'))),
        for (var m = 1; m <= controlMaturityMax; m++)
          DropdownMenuItem(value: m, child: Text('$m')),
      ],
      onChanged: (m) {
        if (m == null) return;
        setState(() => _rows[index].maturity = m);
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
