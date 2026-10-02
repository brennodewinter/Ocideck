// Het boek samenstellen, vanuit de Inbox (FORM_INTAKE.md §7.5): kies het formulier, het
// hoofdstuksjabloon, welke inzendingen erin komen (op status), hoe ze geordend en
// gegroepeerd worden en hoe het boek heet. De keuzes worden in geen enkel bestand
// bewaard: het dialoogvenster is het commando, het boek is een gewoon document.
//
// De zuivere kern staat in het pakket (`compileBook`), het werk eromheen in
// `form_book.dart`. Hier staan de keuzes en de zinnen die zeggen hoe het ging.

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../../l10n/app_localizations.dart';
import '../../platform/platform_features.dart';
import '../../services/form/form_book.dart';
import '../../services/form/form_workspace.dart';
import 'form_text_helpers.dart' show formTextOf;

/// De kiezer van het hoofdstuksjabloon: naam en tekst van het gekozen bestand, of `null`.
/// Een naad voor de test.
typedef FormTemplatePick =
    Future<({String name, String text})?> Function(String title);

Future<({String name, String text})?> _systemTemplatePick(String title) async {
  if (!supportsLocalProjectFolders) return null;
  final file = await FilePicker.pickFile(
    dialogTitle: title,
    type: FileType.custom,
    allowedExtensions: const ['md', 'markdown'],
  );
  if (file == null) return null;
  final text = formTextOf(await file.readAsBytes());
  return text == null ? null : (name: file.name, text: text);
}

Future<void> showFormBookDialog(
  BuildContext context, {
  required FormWorkspace workspace,
  required List<PublishedForm> forms,
  ValueChanged<String>? onOpenFile,
  FormTemplatePick? pickTemplate,
  DateTime Function()? now,
}) => showDialog<void>(
  context: context,
  builder: (_) => FormBookDialog(
    workspace: workspace,
    forms: forms,
    onOpenFile: onOpenFile,
    pickTemplate: pickTemplate,
    now: now,
  ),
);

class FormBookDialog extends StatefulWidget {
  const FormBookDialog({
    super.key,
    required this.workspace,
    required this.forms,
    this.onOpenFile,
    this.pickTemplate,
    this.now,
  });

  final FormWorkspace workspace;

  /// De gepubliceerde formulieren van de werkmap.
  final List<PublishedForm> forms;
  final ValueChanged<String>? onOpenFile;
  final FormTemplatePick? pickTemplate;
  final DateTime Function()? now;

  @override
  State<FormBookDialog> createState() => _FormBookDialogState();
}

class _FormBookDialogState extends State<FormBookDialog> {
  late final List<PublishedForm> _versions = _distinct(widget.forms);
  late PublishedForm? _form = _versions.isEmpty ? null : _versions.last;
  late FormSpec? _spec = _form == null ? null : _specOf(_form!);
  late Set<String> _states = _defaultStates(_spec);
  String? _templateName;
  String? _template;
  String? _orderBy;
  String? _groupBy;
  final TextEditingController _name = TextEditingController(text: 'boek');
  bool _busy = false;
  String? _message;
  String? _written;

  /// Eén per formulier en versie: de talen van één versie delen hun regels, dus welke
  /// taal de keuze draagt maakt voor het boek niet uit.
  static List<PublishedForm> _distinct(List<PublishedForm> forms) {
    final seen = <String>{};
    return [
      for (final form in forms)
        if (seen.add('${form.id}@${form.version}')) form,
    ];
  }

  static FormSpec? _specOf(PublishedForm form) =>
      switch (parseForm(form.text)) {
        ParsedForm(:final spec) => spec,
        _ => null,
      };

  /// `maker-approved` als het formulier die status kent; anders niets: een boek maken
  /// van inzendingen die niemand heeft goedgekeurd is een keuze, geen standaard (§7.4).
  static Set<String> _defaultStates(FormSpec? spec) =>
      spec != null && formStatesOf(spec).contains('maker-approved')
      ? {'maker-approved'}
      : <String>{};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _chooseForm(PublishedForm? form) {
    setState(() {
      _form = form;
      _spec = form == null ? null : _specOf(form);
      _states = _defaultStates(_spec);
      _orderBy = null;
      _groupBy = null;
    });
  }

  Future<void> _chooseTemplate() async {
    final l10n = context.l10n;
    final picked = await (widget.pickTemplate ?? _systemTemplatePick)(
      l10n.d('Kies het hoofdstuksjabloon'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _templateName = picked.name;
      _template = picked.text;
    });
  }

  Future<void> _compile() async {
    final l10n = context.l10n;
    final spec = _spec;
    final template = _template;
    if (spec == null) return;
    if (template == null) {
      setState(() => _message = l10n.d('Kies eerst een hoofdstuksjabloon.'));
      return;
    }
    if (_states.isEmpty) {
      setState(() => _message = l10n.d('Kies minstens één status.'));
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _written = null;
    });
    final outcome = await compileFormBook(
      widget.workspace,
      form: spec,
      template: template,
      states: _states,
      name: _name.text.trim(),
      now: (widget.now ?? DateTime.now)(),
      orderBy: _orderBy,
      groupBy: _groupBy,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = _say(l10n, outcome);
      _written = outcome is FormBookWritten ? outcome.path : null;
    });
  }

  String _say(
    AppLocalizations l10n,
    FormBookOutcome outcome,
  ) => switch (outcome) {
    FormBookWritten() => [
      l10n
          .d('Boek samengesteld. Hoofdstukken: {n}. Foto’s: {m}.')
          .replaceAll('{n}', '${outcome.chapters}')
          .replaceAll('{m}', '${outcome.images}'),
      if (outcome.withdrawn > 0)
        l10n
            .d('Ingetrokken en dus weggelaten: {n}.')
            .replaceAll('{n}', '${outcome.withdrawn}'),
      if (outcome.skipped > 0)
        l10n
            .d('Overgeslagen (andere versie of niet te lezen): {n}.')
            .replaceAll('{n}', '${outcome.skipped}'),
      if (outcome.missingImages > 0)
        l10n
            .d('Foto’s die in de werkmap ontbraken: {n}.')
            .replaceAll('{n}', '${outcome.missingImages}'),
    ].join(' '),
    FormBookBadName() => l10n.d(
      'Gebruik voor de naam alleen letters, cijfers, streepjes en underscores (hoogstens 64 tekens).',
    ),
    FormBookNameTaken() => l10n.d(
      'Er staat al een boek met deze naam. Kies een andere naam.',
    ),
    FormBookUnknownFields(:final ids) =>
      l10n
          .d(
            'Het sjabloon noemt velden die het formulier niet heeft: {velden}.',
          )
          .replaceAll('{velden}', ids.join(', ')),
    FormBookEmpty() =>
      l10n
          .d(
            'Er is niets om in het boek te zetten: geen inzending met een gekozen status. Ingetrokken: {w}; overgeslagen: {s}.',
          )
          .replaceAll('{w}', '${outcome.withdrawn}')
          .replaceAll('{s}', '${outcome.skipped}'),
    FormBookRegisterDamaged() => l10n.d(
      'Het register kan niet worden gelezen. Herstel overview.md.',
    ),
    FormBookFailed() => l10n.d('Het boek kon niet worden geschreven.'),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final spec = _spec;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          l10n.d('Boek samenstellen…'),
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.d(
                          'Het boek komt in de map book van de werkmap en blijft een gewoon document dat je daarna zelf kunt bewerken.',
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      if (_form == null || spec == null)
                        Text(
                          l10n.d(
                            'Er is geen bruikbaar formulier in de werkmap.',
                          ),
                        )
                      else
                        ..._choices(l10n, theme, spec),
                    ],
                  ),
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Semantics(liveRegion: true, child: Text(_message!)),
              ],
              const SizedBox(height: 20),
              _buttons(l10n, spec != null),
            ],
          ),
        ),
      ),
    );
  }

  /// De keuzes: formulier, sjabloon, statussen, ordenen, groeperen en de naam.
  List<Widget> _choices(
    AppLocalizations l10n,
    ThemeData theme,
    FormSpec spec,
  ) => [
    _label(theme, l10n.d('Formulier')),
    DropdownButton<PublishedForm>(
      isExpanded: true,
      value: _form,
      items: [
        for (final form in _versions)
          DropdownMenuItem(
            value: form,
            child: Text(
              l10n
                  .d('{id} · v{versie}')
                  .replaceAll('{id}', form.id)
                  .replaceAll('{versie}', '${form.version}'),
            ),
          ),
      ],
      onChanged: _busy ? null : _chooseForm,
    ),
    const SizedBox(height: 12),
    _label(theme, l10n.d('Hoofdstuksjabloon')),
    Text(_templateName ?? l10n.d('Nog geen sjabloon gekozen.')),
    const SizedBox(height: 4),
    Text(
      l10n.d('In het sjabloon staat {veld-id} voor het antwoord op dat veld.'),
      style: theme.textTheme.bodySmall,
    ),
    const SizedBox(height: 8),
    OutlinedButton(
      onPressed: _busy ? null : _chooseTemplate,
      child: Text(l10n.d('Hoofdstuksjabloon kiezen…')),
    ),
    const SizedBox(height: 16),
    _label(theme, l10n.d('Welke inzendingen?')),
    Text(
      l10n.d(
        'Alleen inzendingen met een van deze statussen komen in het boek. Ingetrokken inzendingen blijven er altijd uit.',
      ),
      style: theme.textTheme.bodySmall,
    ),
    const SizedBox(height: 4),
    Wrap(
      spacing: 8,
      children: [
        for (final state in formStatesOf(spec))
          FilterChip(
            label: Text(state),
            selected: _states.contains(state),
            onSelected: _busy
                ? null
                : (on) => setState(
                    () => _states = on
                        ? {..._states, state}
                        : ({..._states}..remove(state)),
                  ),
          ),
      ],
    ),
    const SizedBox(height: 16),
    Row(
      children: [
        Expanded(
          child: _fieldChoice(
            l10n.d('Ordenen op'),
            spec,
            _orderBy,
            (v) => setState(() => _orderBy = v),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _fieldChoice(
            l10n.d('Groeperen op'),
            spec,
            _groupBy,
            (v) => setState(() => _groupBy = v),
          ),
        ),
      ],
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _name,
      enabled: !_busy,
      decoration: InputDecoration(labelText: l10n.d('Naam van het boek')),
    ),
  ];

  /// De knoppen onder het scrollvlak, zodat *Samenstellen* altijd bereikbaar is.
  Widget _buttons(AppLocalizations l10n, bool hasForm) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n.d('Sluiten')),
      ),
      if (_written != null && widget.onOpenFile != null) ...[
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () {
            final path = _written!;
            Navigator.of(context).pop();
            widget.onOpenFile!(path);
          },
          child: Text(l10n.d('Boek openen')),
        ),
      ],
      if (hasForm) ...[
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _busy ? null : _compile,
          child: Text(l10n.d('Samenstellen')),
        ),
      ],
    ],
  );

  Widget _label(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Semantics(
      header: true,
      child: Text(text, style: theme.textTheme.titleSmall),
    ),
  );

  /// Een keuze uit de velden van het formulier, of geen.
  Widget _fieldChoice(
    String label,
    FormSpec spec,
    String? value,
    ValueChanged<String?> onChanged,
  ) {
    final l10n = context.l10n;
    final fields = [
      for (final field in spec.fields)
        if (field.type != 'image' &&
            field.type != 'consent' &&
            field.type != 'table')
          field.id,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(Theme.of(context), label),
        DropdownButton<String?>(
          isExpanded: true,
          value: value,
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(l10n.d('Geen'))),
            for (final id in fields)
              DropdownMenuItem(value: id, child: Text(id)),
          ],
          onChanged: _busy ? null : onChanged,
        ),
      ],
    );
  }
}
