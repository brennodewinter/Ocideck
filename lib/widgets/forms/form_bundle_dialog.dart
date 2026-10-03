// Een bundel publiceren, vanuit de Inbox (FORM_INTAKE.md §5.1, §7.6): kies het formulier (een taal is
// een eigen tekst en dus een eigen bundel), de naam die de invuller te zien krijgt en tot wanneer de
// bundel geldt. De bundel wordt ondertekend met de redactiesleutel en naast het formulier bewaard;
// daarna staat hier de vingerafdruk die de invuller langs een andere weg moet krijgen.
//
// Het werk staat in `form_bundle_publish.dart`. Hier staan de keuzes en de zinnen die zeggen waarom
// het niet ging.

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../../l10n/app_localizations.dart';
import '../../services/form/form_bundle_publish.dart';
import '../../services/form/form_keys.dart' show FormKeyProblem, FormKeyService;
import '../../services/form/form_workspace.dart';

Future<void> showFormBundleDialog(
  BuildContext context, {
  required FormWorkspace workspace,
  required List<PublishedForm> forms,
  required FormKeyService keys,
  DateTime Function()? now,
}) => showDialog<void>(
  context: context,
  builder: (_) => FormBundleDialog(
    workspace: workspace,
    forms: forms,
    keys: keys,
    now: now,
  ),
);

class FormBundleDialog extends StatefulWidget {
  const FormBundleDialog({
    super.key,
    required this.workspace,
    required this.forms,
    required this.keys,
    this.now,
  });

  final FormWorkspace workspace;

  /// De gepubliceerde formulieren van de werkmap, één per taal.
  final List<PublishedForm> forms;
  final FormKeyService keys;
  final DateTime Function()? now;

  @override
  State<FormBundleDialog> createState() => _FormBundleDialogState();
}

class _FormBundleDialogState extends State<FormBundleDialog> {
  late PublishedForm? _form = widget.forms.isEmpty ? null : widget.forms.last;
  final TextEditingController _name = TextEditingController();
  final TextEditingController _expires = TextEditingController();
  bool _busy = false;
  String? _message;
  FormBundlePublished? _published;

  DateTime get _today => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _fillDefaults();
  }

  @override
  void dispose() {
    _name.dispose();
    _expires.dispose();
    super.dispose();
  }

  FormSpec? _specOf(PublishedForm? form) => form == null
      ? null
      : switch (parseForm(form.text)) {
          ParsedForm(:final spec) => spec,
          _ => null,
        };

  /// Wat het formulier zelf zegt als beginwaarde: wie het verwerkt (`controller`) en zijn
  /// sluitingsdag.
  void _fillDefaults() {
    final spec = _specOf(_form);
    _name.text = spec == null ? 'Redactie' : defaultBundleOrganiserName(spec);
    _expires.text = defaultBundleExpiry(_today, spec?.closes);
  }

  void _chooseForm(PublishedForm? form) {
    setState(() {
      _form = form;
      _published = null;
      _message = null;
      _fillDefaults();
    });
  }

  Future<void> _publish() async {
    final form = _form;
    if (form == null || _busy) return;
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _message = null;
      _published = null;
    });
    final outcome = await publishFormBundle(
      widget.workspace,
      form,
      keys: widget.keys,
      organiserName: _name.text,
      expires: _expires.text.trim(),
      now: _today,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (outcome is FormBundlePublished) {
        _published = outcome;
        _message = l10n
            .d('Bundel gemaakt (volgnummer {n}): {pad}')
            .replaceAll('{n}', '${outcome.bundle.bundleSeq}')
            .replaceAll('{pad}', outcome.path);
      } else {
        _message = _refusal(l10n, outcome);
      }
    });
  }

  String _refusal(
    AppLocalizations l10n,
    FormBundleOutcome outcome,
  ) => switch (outcome) {
    FormBundleNeedsKey(:final problem) => switch (problem) {
      FormKeyProblem.unavailable => l10n.d(
        'Dit platform heeft geen sleutelhanger voor de redactiesleutel; een bundel kan hier niet worden ondertekend.',
      ),
      FormKeyProblem.absent => l10n.d(
        'Er is nog geen redactiesleutel. Maak er een aan onder Redactiesleutel… voordat je een bundel publiceert.',
      ),
      FormKeyProblem.unreadable => l10n.d(
        'De sleutelhanger is niet te lezen. Er is niets ondertekend.',
      ),
      FormKeyProblem.damaged => l10n.d(
        'De bewaarde redactiesleutel is niet te lezen. Verwijder hem onder Redactiesleutel… en herstel hem uit je herstelsleutel.',
      ),
    },
    FormBundleRecoveryNotChecked() => l10n.d(
      'Controleer eerst je herstelsleutel onder Redactiesleutel…. Zonder herstelweg zijn alle inzendingen onleesbaar als dit apparaat stuk gaat.',
    ),
    FormBundleExistingUnreadable(:final paths) =>
      l10n
          .d(
            'Een bundel van dit formulier in de werkmap is niet te lezen of hoort niet bij de andere. Daarmee is het volgnummer niet te bepalen en wordt er niets ondertekend. Controleer: {pad}',
          )
          .replaceAll('{pad}', paths.first),
    FormBundleBadInput(:final field) => switch (field) {
      FormBundleInputField.name => l10n.d(
        'Vul een naam in van hooguit 80 tekens.',
      ),
      FormBundleInputField.expires => l10n.d(
        'Geldig tot moet een bestaande datum zijn, als jjjj-mm-dd.',
      ),
      FormBundleInputField.expiresBeforeCloses => l10n.d(
        'Geldig tot mag niet vóór de sluitingsdag van het formulier liggen.',
      ),
    },
    FormBundleRefusedByCore(:final detail) =>
      l10n
          .d(
            'De bundel kon niet worden gemaakt ({veld}). Kijk of het formulier een geldige sluitingsdag en bewaartermijn noemt.',
          )
          .replaceAll('{veld}', detail ?? l10n.d('formulier')),
    FormBundleNotWritten() => l10n.d(
      'De bundel kon niet worden opgeslagen in de werkmap.',
    ),
    FormBundlePublished() => '',
  };

  String _label(PublishedForm form) =>
      '${form.id} · v${form.version}${form.lang == null ? '' : ' · ${form.lang}'}';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
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
                          l10n.d('Bundel publiceren…'),
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.d(
                          'De bundel is wat een invuller van jullie redactie gelooft: naar welke sleutel hij verzegelt en welke tekst erbij hoort. Hij komt naast het formulier te staan.',
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      if (_form == null)
                        Text(
                          l10n.d(
                            'Er is geen formulier in de werkmap om een bundel voor te maken.',
                          ),
                        )
                      else
                        ..._fields(l10n, theme),
                      if (_message != null) ...[
                        const SizedBox(height: 16),
                        Semantics(liveRegion: true, child: Text(_message!)),
                      ],
                      if (_published != null) ..._fingerprint(l10n, theme),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.d('Sluiten')),
                  ),
                  if (_form != null) ...[
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _busy ? null : _publish,
                      child: Text(l10n.d('Bundel maken')),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _fields(AppLocalizations l10n, ThemeData theme) => [
    Text(l10n.d('Formulier'), style: theme.textTheme.titleSmall),
    DropdownButton<PublishedForm>(
      isExpanded: true,
      value: _form,
      items: [
        for (final form in widget.forms)
          DropdownMenuItem(value: form, child: Text(_label(form))),
      ],
      onChanged: _busy ? null : _chooseForm,
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _name,
      decoration: InputDecoration(labelText: l10n.d('Naam voor de invuller')),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _expires,
      decoration: InputDecoration(
        labelText: l10n.d('Geldig tot (jjjj-mm-dd)'),
        helperText: l10n.d(
          'De laatste dag waarop een invuller deze bundel gelooft. Niet vóór de sluitingsdag van het formulier.',
        ),
        helperMaxLines: 3,
      ),
    ),
  ];

  List<Widget> _fingerprint(AppLocalizations l10n, ThemeData theme) {
    final published = _published!;
    return [
      const SizedBox(height: 16),
      Text(l10n.d('Vingerafdruk'), style: theme.textTheme.titleSmall),
      SelectableText(
        published.fingerprint,
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      const SizedBox(height: 8),
      Text(
        l10n.d(
          'Geef de vingerafdruk de invuller langs een andere weg dan het bundelbestand, bijvoorbeeld in de uitnodiging. Wie alleen het bundelbestand heeft, kan niet nagaan van wie het komt.',
        ),
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: published.fingerprint)),
          child: Text(l10n.d('Vingerafdruk kopiëren')),
        ),
      ),
    ];
  }
}
