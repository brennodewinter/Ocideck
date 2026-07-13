// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (checklists tab); all imports live in the main
// library file. The tab manages the user's reusable checklist templates
// (feedback #9): create, edit and delete named test lists that can be loaded
// into any checklist slide and per scope object.
part of '../settings_dialog.dart';

extension _SettingsChecklists on _SettingsDialogState {
  Widget _checklistsTab() {
    final l10n = context.l10n;
    final templates = ref.watch(
      settingsProvider.select((s) => s.customChecklists),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d(
            'Maak herbruikbare testlijsten die je per scope-object in een checklist kunt laden, naast de gebundelde WSTG-lijst.',
          ),
          style: const TextStyle(fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 20),
        _sectionTitle(l10n.d('Eigen checklists')),
        if (templates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.d('Nog geen eigen checklists.'),
              style: TextStyle(fontSize: 12, color: AppTheme.slate400),
            ),
          )
        else
          for (var i = 0; i < templates.length; i++)
            _checklistTemplateCard(i, templates[i]),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _openChecklistTemplateEditor(),
            icon: const Icon(Icons.add, size: 16),
            label: Text(l10n.d('Nieuw sjabloon')),
          ),
        ),
      ],
    );
  }

  Widget _checklistTemplateCard(int index, ChecklistTemplate template) {
    final l10n = context.l10n;
    final subtitle = [
      if (template.standardLabel.isNotEmpty) template.standardLabel,
      '${template.items.length} ${l10n.d('testen')}',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.slate300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  template.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: AppTheme.slate400),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.d('Bewerken'),
            onPressed: () =>
                _openChecklistTemplateEditor(index: index, initial: template),
            icon: const Icon(Icons.edit_outlined, size: 18),
            color: AppTheme.slate500,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: l10n.d('Verwijderen'),
            onPressed: () =>
                ref.read(settingsProvider.notifier).removeCustomChecklist(index),
            icon: const Icon(Icons.delete_outline, size: 18),
            color: AppTheme.slate500,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// Open the modal editor for a new template ([initial] null) or the one at
  /// [index]; on save, persist it via the settings notifier.
  Future<void> _openChecklistTemplateEditor({
    int? index,
    ChecklistTemplate? initial,
  }) async {
    final result = await showDialog<ChecklistTemplate>(
      context: context,
      builder: (_) => _ChecklistTemplateDialog(initial: initial),
    );
    if (result == null) return;
    final notifier = ref.read(settingsProvider.notifier);
    if (index == null) {
      await notifier.addCustomChecklist(result);
    } else {
      await notifier.updateCustomChecklist(index, result);
    }
  }
}

/// Modal editor for one [ChecklistTemplate]: its name, standard label and the
/// test items (id + title), with add/remove. Returns the edited template via
/// `Navigator.pop`, or null on cancel.
class _ChecklistTemplateDialog extends StatefulWidget {
  final ChecklistTemplate? initial;

  const _ChecklistTemplateDialog({this.initial});

  @override
  State<_ChecklistTemplateDialog> createState() =>
      _ChecklistTemplateDialogState();
}

class _ChecklistItemControllers {
  _ChecklistItemControllers(ChecklistTemplateItem item)
    : id = TextEditingController(text: item.id),
      title = TextEditingController(text: item.title);

  final TextEditingController id;
  final TextEditingController title;

  ChecklistTemplateItem toItem() =>
      ChecklistTemplateItem(id: id.text.trim(), title: title.text.trim());

  void dispose() {
    id.dispose();
    title.dispose();
  }
}

class _ChecklistTemplateDialogState extends State<_ChecklistTemplateDialog> {
  late final TextEditingController _name;
  late final TextEditingController _standard;
  late List<_ChecklistItemControllers> _items;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _name = TextEditingController(text: t?.name ?? '');
    _standard = TextEditingController(text: t?.standardLabel ?? '');
    _items = [
      for (final i in t?.items ?? const <ChecklistTemplateItem>[])
        _ChecklistItemControllers(i),
    ];
    if (_items.isEmpty) {
      _items = [
        _ChecklistItemControllers(const ChecklistTemplateItem(id: '', title: '')),
      ];
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _standard.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  void _save() {
    final template = ChecklistTemplate(
      name: _name.text.trim(),
      standardLabel: _standard.text.trim(),
      items: [
        for (final c in _items)
          if (c.id.text.trim().isNotEmpty || c.title.text.trim().isNotEmpty)
            c.toItem(),
      ],
    );
    Navigator.of(context).pop(template);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canSave = _name.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(l10n.d('Checklist-sjabloon')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                decoration: InputDecoration(labelText: l10n.d('Naam')),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _standard,
                decoration: InputDecoration(labelText: l10n.d('Standaard')),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.d('Testen'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slate500,
                ),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _items.length; i++) _itemRow(i),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(
                    () => _items.add(
                      _ChecklistItemControllers(
                        const ChecklistTemplateItem(id: '', title: ''),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(l10n.d('Test toevoegen')),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Annuleren')),
        ),
        FilledButton(
          onPressed: canSave ? _save : null,
          child: Text(l10n.d('Opslaan')),
        ),
      ],
    );
  }

  Widget _itemRow(int index) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 130,
            child: TextField(
              controller: _items[index].id,
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.d('ID'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _items[index].title,
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.d('Test'),
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.d('Test verwijderen'),
            onPressed: _items.length > 1
                ? () => setState(() => _items.removeAt(index).dispose())
                : null,
            icon: const Icon(Icons.delete_outline, size: 18),
            color: AppTheme.slate500,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
