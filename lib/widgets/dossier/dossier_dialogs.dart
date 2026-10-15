import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/document_dossier.dart';

/// Small, focused prompts used by the dossier overview.
abstract final class DossierDialogs {
  static Future<(String, String)?> createDossier(BuildContext context) =>
      showDialog<(String, String)>(
        context: context,
        builder: (_) => const _CreateDossierDialog(),
      );

  static Future<String?> editDescription(
    BuildContext context, {
    required String initialDescription,
  }) => showDialog<String>(
    context: context,
    builder: (_) =>
        _TextDialog(initialValue: initialDescription, description: true),
  );

  static Future<int?> editNumber(
    BuildContext context, {
    required int initialNumber,
    required String title,
    bool allowAutomatic = false,
    Set<int> usedNumbers = const {},
  }) => showDialog<int>(
    context: context,
    builder: (_) => _NumberDialog(
      initialNumber: initialNumber,
      title: title,
      allowAutomatic: allowAutomatic,
      usedNumbers: usedNumbers,
    ),
  );

  static Future<void> showHashHistory(
    BuildContext context, {
    required DossierEntry entry,
  }) => showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final l10n = dialogContext.l10n;
      return AlertDialog(
        title: Text(l10n.d('Eerdere SHA-256-waarden')),
        content: SizedBox(
          width: 560,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: entry.hashHistory.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final revision = entry.hashHistory[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    revision.recordedAt.toLocal().toString(),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    revision.sha256,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.d('Sluiten')),
          ),
        ],
      );
    },
  );

  static Future<String?> editTitle(
    BuildContext context, {
    required String initialTitle,
    bool creating = false,
  }) => showDialog<String>(
    context: context,
    builder: (_) => _TextDialog(initialValue: initialTitle, creating: creating),
  );

  static Future<bool> confirmRemove(
    BuildContext context, {
    required String title,
  }) async {
    final l10n = context.l10n;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.d('Uit dossier verwijderen?')),
            content: Text(
              '${l10n.d('De vermelding verdwijnt uit het dossier. Het documentbestand blijft bewaard.')}\n\n$title',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.d('Annuleren')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.d('Verwijderen')),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _CreateDossierDialog extends StatefulWidget {
  const _CreateDossierDialog();

  @override
  State<_CreateDossierDialog> createState() => _CreateDossierDialogState();
}

class _CreateDossierDialogState extends State<_CreateDossierDialog> {
  final _title = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isNotEmpty) {
      Navigator.of(context).pop((title, _description.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Nieuw dossier')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              maxLength: 160,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l10n.d('Titel')),
              onSubmitted: (_) => _submit(),
            ),
            TextField(
              controller: _description,
              maxLines: 3,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.d('Omschrijving (optioneel)'),
                hintText: l10n.d('Waar gaat dit dossier over?'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Annuleren')),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.d('Dossier maken'))),
      ],
    );
  }
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.initialValue,
    this.description = false,
    this.creating = false,
  });

  final String initialValue;
  final bool description;
  final bool creating;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (widget.description || value.isNotEmpty) {
      Navigator.of(context).pop(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final description = widget.description;
    return AlertDialog(
      title: Text(
        description
            ? l10n.d('Omschrijving wijzigen')
            : widget.creating
            ? l10n.d('Nieuw dossier')
            : l10n.d('Titel wijzigen'),
      ),
      content: SizedBox(
        width: description ? 460 : 420,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: description ? 4 : 1,
          maxLength: description ? 1000 : 160,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: description
                ? l10n.d('Omschrijving (optioneel)')
                : l10n.d('Titel'),
          ),
          onSubmitted: description ? null : (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Annuleren')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(
            widget.creating ? l10n.d('Dossier maken') : l10n.d('Opslaan'),
          ),
        ),
      ],
    );
  }
}

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({
    required this.initialNumber,
    required this.title,
    required this.allowAutomatic,
    required this.usedNumbers,
  });

  final int initialNumber;
  final String title;
  final bool allowAutomatic;
  final Set<int> usedNumbers;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.initialNumber}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value != null &&
        value > 0 &&
        value <= 999999 &&
        !widget.usedNumbers.contains(value)) {
      Navigator.of(context).pop(value);
    } else {
      setState(() {
        _error = widget.usedNumbers.contains(value)
            ? context.l10n.d('Dit nummer is al in gebruik.')
            : context.l10n.d('Gebruik een positief getal.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: l10n.d('Nummer'),
            helperText: l10n.d('Gebruik een positief getal.'),
            errorText: _error,
          ),
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        if (widget.allowAutomatic)
          TextButton(
            onPressed: () => Navigator.of(context).pop(-1),
            child: Text(l10n.d('Automatisch nummer')),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Annuleren')),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.d('Opslaan'))),
      ],
    );
  }
}
