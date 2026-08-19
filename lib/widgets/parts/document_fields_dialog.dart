// Part of the document_editor_screen library — see ../document_editor_screen.dart.
part of '../document_editor_screen.dart';

Future<Map<String, String>?> _showDocumentFieldsDialog(
  BuildContext context,
  Map<String, String> fields,
) => showDialog<Map<String, String>>(
  context: context,
  builder: (context) => _DocumentFieldsDialog(fields: fields),
);

class _DocumentFieldsDialog extends StatefulWidget {
  const _DocumentFieldsDialog({required this.fields});

  final Map<String, String> fields;

  @override
  State<_DocumentFieldsDialog> createState() => _DocumentFieldsDialogState();
}

class _DocumentFieldRow {
  _DocumentFieldRow(String name, String value)
    : name = TextEditingController(text: name),
      value = TextEditingController(text: value);

  final TextEditingController name;
  final TextEditingController value;

  void dispose() {
    name.dispose();
    value.dispose();
  }
}

class _DocumentFieldsDialogState extends State<_DocumentFieldsDialog> {
  static const _known = ['title', 'subtitle', 'author'];
  late final Map<String, TextEditingController> _knownValues;
  late final List<_DocumentFieldRow> _custom;
  late final bool _sourceOverLimit;

  @override
  void initState() {
    super.initState();
    _knownValues = {
      for (final key in _known)
        key: TextEditingController(text: widget.fields[key] ?? ''),
    };
    final duplicateCount = switch (widget.fields) {
      final DocumentFields fields => fields.duplicateValues.values.fold(
        0,
        (count, values) => count + values.length - 1,
      ),
      _ => 0,
    };
    _sourceOverLimit =
        widget.fields.length + duplicateCount > kMaxDocumentFields;
    _custom = _sourceOverLimit
        ? []
        : [
            for (final entry in widget.fields.entries)
              if (!_known.contains(entry.key))
                _DocumentFieldRow(entry.key, entry.value),
            if (widget.fields case final DocumentFields fields)
              for (final entry in fields.duplicateValues.entries)
                for (final value in entry.value.skip(1))
                  _DocumentFieldRow(entry.key, value),
          ];
  }

  @override
  void dispose() {
    for (final controller in _knownValues.values) {
      controller.dispose();
    }
    for (final row in _custom) {
      row.dispose();
    }
    super.dispose();
  }

  String _label(AppLocalizations l10n, String key) => switch (key) {
    'title' => l10n.d('Titel'),
    'subtitle' => l10n.d('Ondertitel'),
    'author' => l10n.d('Auteur'),
    _ => key,
  };

  List<String> get _names => [
    ..._known,
    for (final row in _custom) row.name.text.trim(),
  ];

  bool _validName(String name) =>
      isValidDocumentFieldKey(name) && !isReservedDocumentFieldKey(name);

  Map<String, int> get _nameCounts {
    final counts = <String, int>{};
    for (final name in _names) {
      if (name.isNotEmpty) {
        counts.update(name, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    return counts;
  }

  bool _tooLong(TextEditingController controller) =>
      controller.text.length > kMaxDocumentFieldValueLength;

  int get _filledFieldCount =>
      _knownValues.values
          .where((value) => value.text.trim().isNotEmpty)
          .length +
      _custom.where((row) => row.value.text.trim().isNotEmpty).length;

  bool _canSave(Map<String, int> nameCounts) =>
      !_sourceOverLimit &&
      _filledFieldCount <= kMaxDocumentFields &&
      !_knownValues.values.any(_tooLong) &&
      !_custom.any((row) {
        final name = row.name.text.trim();
        return !_validName(name) ||
            (nameCounts[name] ?? 0) > 1 ||
            _tooLong(row.value);
      });

  void _save() {
    if (_sourceOverLimit) return;
    final counts = _nameCounts;
    if (_custom.any((row) {
          final name = row.name.text.trim();
          return !_validName(name) ||
              (counts[name] ?? 0) > 1 ||
              _tooLong(row.value);
        }) ||
        _knownValues.values.any(_tooLong) ||
        _filledFieldCount > kMaxDocumentFields) {
      return;
    }
    Navigator.of(context).pop({
      for (final entry in _knownValues.entries)
        if (entry.value.text.trim().isNotEmpty)
          entry.key: entry.value.text.trim(),
      for (final row in _custom)
        if (row.value.text.trim().isNotEmpty)
          row.name.text.trim(): row.value.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final nameCounts = _nameCounts;
    final duplicateNames = nameCounts.entries
        .where((entry) => entry.value > 1)
        .map((entry) => entry.key)
        .toSet();
    final canSave = _canSave(nameCounts);
    final tooMany = _sourceOverLimit || _filledFieldCount > kMaxDocumentFields;
    return AlertDialog(
      key: const Key('document-fields-dialog'),
      title: Text('${l10n.d('Document')} · ${l10n.d('Eigenschappen')}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.d('Gebruik {naam} in de kop- of voettekst.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (duplicateNames.isNotEmpty) ...[
                Text(
                  l10n.d('Naam is ongeldig, gereserveerd of niet uniek.'),
                  key: const Key('document-fields-duplicate-warning'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 10),
              ],
              if (tooMany || _custom.length >= kMaxDocumentFields) ...[
                Text(
                  l10n.d(
                    'Een document kan maximaal 100 vrije velden bevatten.',
                  ),
                  key: const Key('document-fields-count-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 10),
              ],
              for (final entry in _knownValues.entries) ...[
                TextField(
                  key: Key('document-field-${entry.key}'),
                  controller: entry.value,
                  enabled: !_sourceOverLimit,
                  onChanged: (_) => setState(() {}),
                  maxLength: kMaxDocumentFieldValueLength,
                  maxLengthEnforcement: MaxLengthEnforcement.none,
                  decoration: InputDecoration(
                    labelText: '${_label(l10n, entry.key)} · {${entry.key}}',
                    errorText: _tooLong(entry.value)
                        ? l10n.d(
                            'Een veldwaarde mag maximaal 4096 tekens bevatten.',
                          )
                        : null,
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              for (var i = 0; i < _custom.length; i++)
                _customRow(l10n, i, duplicateNames),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('document-field-add'),
                  onPressed:
                      _sourceOverLimit || _custom.length >= kMaxDocumentFields
                      ? null
                      : () => setState(
                          () => _custom.add(_DocumentFieldRow('', '')),
                        ),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.d('Toevoegen')),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.t('cancel')),
        ),
        FilledButton(
          key: const Key('document-fields-save'),
          onPressed: canSave ? _save : null,
          child: Text(l10n.t('save')),
        ),
      ],
    );
  }

  Widget _customRow(
    AppLocalizations l10n,
    int index,
    Set<String> duplicateNames,
  ) {
    final row = _custom[index];
    final name = row.name.text.trim();
    final duplicate = duplicateNames.contains(name);
    final invalid = !_validName(name) || duplicate;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              key: Key('document-field-name-$index'),
              controller: row.name,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.d('Naam'),
                hintText: l10n.d('Bijvoorbeeld project-id'),
                errorText: invalid
                    ? l10n.d('Naam is ongeldig, gereserveerd of niet uniek.')
                    : null,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              key: Key('document-field-value-$index'),
              controller: row.value,
              onChanged: (_) => setState(() {}),
              maxLength: kMaxDocumentFieldValueLength,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              decoration: InputDecoration(
                labelText: l10n.d('Waarde'),
                errorText: _tooLong(row.value)
                    ? l10n.d(
                        'Een veldwaarde mag maximaal 4096 tekens bevatten.',
                      )
                    : null,
                isDense: true,
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.d('Verwijderen'),
            onPressed: () => setState(() {
              _custom.removeAt(index).dispose();
            }),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}
