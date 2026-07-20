import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/actions_spec.dart';
import '../../models/slide.dart';
import '../../theme/app_theme.dart';
import '_editor_field.dart';

/// Editor for an `actions` slide: a title plus up to [actionsMaxItems] lines,
/// each with what has to happen, who carries it, by when, where it stands and
/// what is being asked. Emits the slide title and `tableRows` via [ActionsSpec];
/// storage stays a Markdown table.
///
/// Rows are **not** re-ordered by kind. The move buttons would be meaningless if
/// the slide sorted the list behind the author's back; the escalations stand out
/// by their marker instead.
class ActionsEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  const ActionsEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
  });

  @override
  State<ActionsEditor> createState() => _ActionsEditorState();
}

class _ItemControllers {
  _ItemControllers(ActionItem item, VoidCallback onChanged)
    : action = TextEditingController(text: item.action)..addListener(onChanged),
      owner = TextEditingController(text: item.owner)..addListener(onChanged),
      due = TextEditingController(text: formatActionDate(item.due))
        ..addListener(onChanged),
      since = TextEditingController(text: formatActionDate(item.since))
        ..addListener(onChanged),
      status = item.status,
      kind = item.kind;

  final TextEditingController action;
  final TextEditingController owner;
  final TextEditingController due;
  final TextEditingController since;
  ActionStatus status;
  ActionKind kind;

  ActionItem toItem() => ActionItem(
    action: action.text.trim(),
    owner: owner.text.trim(),
    due: parseActionDate(due.text),
    since: parseActionDate(since.text),
    status: status,
    kind: kind,
  );

  void dispose() {
    action.dispose();
    owner.dispose();
    due.dispose();
    since.dispose();
  }
}

class _ActionsEditorState extends State<ActionsEditor> {
  late final TextEditingController _title;
  late List<_ItemControllers> _items;

  @override
  void initState() {
    super.initState();
    final spec = ActionsSpec.fromSlide(
      widget.slide.title,
      widget.slide.tableRows,
    );
    _title = TextEditingController(text: spec.title)..addListener(_emit);
    _items = spec.items.map((i) => _ItemControllers(i, _emit)).toList();
    if (_items.isEmpty) {
      _items = [_ItemControllers(const ActionItem(), _emit)];
    }
  }

  @override
  void dispose() {
    _title.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final spec = ActionsSpec(
      title: _title.text.trim(),
      items: _items.map((i) => i.toItem()).toList(),
    );
    widget.onUpdate(
      widget.slide.copyWith(title: spec.title, tableRows: spec.toTableRows()),
    );
  }

  void _addItem() {
    setState(() => _items.add(_ItemControllers(const ActionItem(), _emit)));
    _emit();
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index).dispose());
    _emit();
  }

  void _moveItem(int from, int to) {
    if (to < 0 || to >= _items.length) return;
    setState(() => _items.insert(to, _items.removeAt(from)));
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final full = _items.length >= actionsMaxItems;
    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(label: 'Titel', controller: _title, hint: 'Wat we vragen'),
        const SizedBox(height: 16),
        for (var i = 0; i < _items.length; i++) ...[
          _itemCard(context, i),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: full
                ? l10n.d(
                    'Een actieslide draagt hoogstens acht regels; daarna gaat de zaal skimmen in plaats van besluiten.',
                  )
                : '',
            child: OutlinedButton.icon(
              onPressed: full ? null : _addItem,
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.d('Actie toevoegen')),
            ),
          ),
        ),
      ],
    );
  }

  Widget _itemCard(BuildContext context, int index) {
    final l10n = context.l10n;
    final item = _items[index];
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
                  label: 'Actie',
                  controller: item.action,
                  hint: 'Testomgeving uit de lucht halen',
                ),
              ),
              IconButton(
                tooltip: l10n.d('Omhoog'),
                onPressed: index > 0 ? () => _moveItem(index, index - 1) : null,
                icon: const Icon(Icons.arrow_upward, size: 18),
                color: AppTheme.slate500,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: l10n.d('Omlaag'),
                onPressed: index < _items.length - 1
                    ? () => _moveItem(index, index + 1)
                    : null,
                icon: const Icon(Icons.arrow_downward, size: 18),
                color: AppTheme.slate500,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: l10n.d('Actie verwijderen'),
                onPressed: _items.length > 1 ? () => _removeItem(index) : null,
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
              Expanded(
                flex: 2,
                child: EditorField(
                  label: 'Eigenaar',
                  controller: item.owner,
                  hint: 'Team Platform',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: EditorField(
                  label: 'Deadline',
                  controller: item.due,
                  hint: '2026-08-15',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: EditorField(
                  label: 'Op de lijst sinds',
                  controller: item.since,
                  hint: '2026-05-12',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.d(
              'Datums als jjjj-mm-dd. Een andere schrijfwijze wordt niet geraden: 05-08-2026 is twee verschillende dagen.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _kindDropdown(context, index)),
              const SizedBox(width: 8),
              Expanded(child: _statusDropdown(context, index)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.d(
              'Alleen een besluit of escalatie krijgt een label op de slide; "te laat" volgt uit de deadline en zet u niet zelf.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ],
      ),
    );
  }

  Widget _kindDropdown(BuildContext context, int index) {
    final l10n = context.l10n;
    return _labeledDropdown<ActionKind>(
      label: l10n.d('Wat vraagt u'),
      value: _items[index].kind,
      items: [
        for (final kind in ActionKind.values)
          DropdownMenuItem(
            value: kind,
            child: Text(l10n.d(actionKindDutchLabel(kind))),
          ),
      ],
      onChanged: (v) {
        setState(() => _items[index].kind = v ?? ActionKind.info);
        _emit();
      },
    );
  }

  Widget _statusDropdown(BuildContext context, int index) {
    final l10n = context.l10n;
    return _labeledDropdown<ActionStatus>(
      label: l10n.d('Stand'),
      value: _items[index].status,
      items: [
        for (final status in ActionStatus.values)
          DropdownMenuItem(
            value: status,
            child: Text(l10n.d(actionStatusDutchLabel(status))),
          ),
      ],
      onChanged: (v) {
        setState(() => _items[index].status = v ?? ActionStatus.open);
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
