import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/document_dossier.dart';
import '../../models/privacy_disposition.dart';

typedef DossierEntryDetails = ({
  String title,
  String description,
  String? documentDate,
  String author,
});

typedef DossierPdfOptions = ({
  bool includeInterleaves,
  PrivacyExportProfile profile,
});

/// Small, focused prompts used by the dossier overview.
abstract final class DossierDialogs {
  static Future<DossierPdfOptions?> pdfExportOptions(BuildContext context) =>
      showDialog<DossierPdfOptions>(
        context: context,
        builder: (_) => const _DossierPdfOptionsDialog(),
      );

  static Future<DossierEntryDetails?> editEntryDetails(
    BuildContext context, {
    required DossierEntry entry,
    Future<DossierEntryDetails?> Function()? suggest,
  }) => showDialog<DossierEntryDetails>(
    context: context,
    builder: (_) => _EntryDetailsDialog(entry: entry, suggest: suggest),
  );

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

class _EntryDetailsDialog extends StatefulWidget {
  const _EntryDetailsDialog({required this.entry, this.suggest});

  final DossierEntry entry;
  final Future<DossierEntryDetails?> Function()? suggest;

  @override
  State<_EntryDetailsDialog> createState() => _EntryDetailsDialogState();
}

class _EntryDetailsDialogState extends State<_EntryDetailsDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _date;
  late final TextEditingController _author;
  bool _suggesting = false;
  bool _hasSuggestion = false;
  String? _dateError;
  String? _suggestionError;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.entry.title);
    _description = TextEditingController(text: widget.entry.description);
    _date = TextEditingController(text: widget.entry.documentDate ?? '');
    _author = TextEditingController(text: widget.entry.author);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _date.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<void> _suggest() async {
    final callback = widget.suggest;
    if (callback == null || _suggesting) return;
    setState(() {
      _suggesting = true;
      _suggestionError = null;
    });
    try {
      final result = await callback();
      if (!mounted) return;
      if (result == null) {
        setState(
          () => _suggestionError = context.l10n.d(
            'Er is geen bruikbaar voorstel gevonden. Vul de gegevens zelf in.',
          ),
        );
        return;
      }
      _title.text = result.title.trim().isEmpty ? _title.text : result.title;
      _description.text = result.description;
      _date.text = result.documentDate ?? '';
      _author.text = result.author;
      setState(() {
        _hasSuggestion = true;
        _dateError = null;
      });
    } on Exception {
      if (mounted) {
        setState(
          () => _suggestionError = context.l10n.d(
            'Het AI-voorstel kon niet worden opgehaald. Controleer de AI-instellingen of vul de gegevens zelf in.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }

  void _save() {
    final date = _date.text.trim();
    if (_title.text.trim().isEmpty) return;
    if (date.isNotEmpty && !_validDate(date)) {
      setState(
        () => _dateError = context.l10n.d(
          'Gebruik een geldige datum als JJJJ-MM-DD, of laat het veld leeg.',
        ),
      );
      return;
    }
    Navigator.of(context).pop((
      title: _title.text.trim(),
      description: _description.text.trim(),
      documentDate: date.isEmpty ? null : date,
      author: _author.text.trim(),
    ));
  }

  bool _validDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
    final date = DateTime.tryParse(value);
    return date != null &&
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}' ==
            value;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Documentgegevens')),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.d(
                  'Deze gegevens horen bij de vermelding in het dossier. Het bronbestand verandert niet.',
                ),
              ),
              const SizedBox(height: 16),
              if (widget.suggest != null) ...[
                OutlinedButton.icon(
                  onPressed: _suggesting ? null : _suggest,
                  icon: _suggesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_outlined),
                  label: Text(l10n.d('Gegevens voorstellen met AI')),
                ),
                if (_hasSuggestion)
                  Text(
                    l10n.d(
                      'AI-voorstel ingevuld. Controleer en wijzig het voordat je opslaat.',
                    ),
                  ),
                if (_suggestionError != null) Text(_suggestionError!),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _title,
                autofocus: true,
                maxLength: 160,
                decoration: InputDecoration(labelText: l10n.d('Titel')),
              ),
              TextField(
                controller: _description,
                maxLength: 500,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.d('Korte omschrijving'),
                  hintText: l10n.d('Waar gaat dit document over?'),
                ),
              ),
              TextField(
                controller: _date,
                keyboardType: TextInputType.datetime,
                maxLength: 10,
                decoration: InputDecoration(
                  labelText: l10n.d('Documentdatum'),
                  hintText: l10n.d('JJJJ-MM-DD'),
                  errorText: _dateError,
                ),
                onChanged: (_) => setState(() => _dateError = null),
              ),
              TextField(
                controller: _author,
                maxLength: 160,
                decoration: InputDecoration(labelText: l10n.d('Opsteller')),
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
          onPressed: _suggesting ? null : _save,
          child: Text(l10n.d('Opslaan')),
        ),
      ],
    );
  }
}

class _DossierPdfOptionsDialog extends StatefulWidget {
  const _DossierPdfOptionsDialog();

  @override
  State<_DossierPdfOptionsDialog> createState() =>
      _DossierPdfOptionsDialogState();
}

class _DossierPdfOptionsDialogState extends State<_DossierPdfOptionsDialog> {
  bool _includeInterleaves = true;
  PrivacyExportProfile _profile = PrivacyExportProfile.redacted;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Dossier als PDF exporteren')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'De PDF bevat een omslag, inhoudsopgave en alle documenten in dossiervolgorde.',
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _includeInterleaves,
              onChanged: (value) => setState(() => _includeInterleaves = value),
              title: Text(l10n.d('Tussenpagina vóór elk document')),
              subtitle: Text(
                l10n.d(
                  'Met nummer, titel, omschrijving, datum, opsteller en SHA-256.',
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _profile == PrivacyExportProfile.full,
              onChanged: (value) => setState(
                () => _profile = value
                    ? PrivacyExportProfile.full
                    : PrivacyExportProfile.redacted,
              ),
              title: Text(l10n.d('Volledige gegevens tonen')),
              subtitle: Text(
                l10n.d(
                  'Standaard worden gevonden persoonsgegevens afgeschermd. Kies volledig alleen voor de juiste ontvanger.',
                ),
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
        FilledButton.icon(
          onPressed: () => Navigator.of(
            context,
          ).pop((includeInterleaves: _includeInterleaves, profile: _profile)),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(l10n.d('PDF maken')),
        ),
      ],
    );
  }
}
