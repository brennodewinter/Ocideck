// Het team van de redactie, vanuit de Inbox (FORM_INTAKE.md §7.6): wie er naast de eigenaar in elke
// bundel staat, zodat ook zij de inzendingen kunnen openen.
//
// Iemand toevoegen gaat met zijn redacteurskaart (§5.1) en in twee stappen: de kaart plakken — het
// venster toont dan alleen de naam — en de vingerafdruk van die kaart terugtypen die de redacteur langs
// een andere weg gaf. De vingerafdruk van de kaart staat hier bewust **niet** in beeld voor hij is
// ingetikt: wie hem van het scherm overtikt, controleert niets.
//
// Het werk staat in `form_team_actions.dart`; hier staan de keuzes en de zinnen die zeggen hoe het ging.

import 'package:material_ui/material_ui.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../../l10n/app_localizations.dart';
import '../../services/form/form_keys.dart' show FormKeyProblem, FormKeyService;
import '../../services/form/form_team_actions.dart';
import '../../services/form/form_workspace.dart';

Future<void> showFormTeamDialog(
  BuildContext context, {
  required FormWorkspace workspace,
  required FormKeyService keys,
}) => showDialog<void>(
  context: context,
  builder: (_) => FormTeamDialog(workspace: workspace, keys: keys),
);

class FormTeamDialog extends StatefulWidget {
  const FormTeamDialog({
    super.key,
    required this.workspace,
    required this.keys,
  });

  final FormWorkspace workspace;
  final FormKeyService keys;

  @override
  State<FormTeamDialog> createState() => _FormTeamDialogState();
}

class _FormTeamDialogState extends State<FormTeamDialog> {
  final TextEditingController _cardText = TextEditingController();
  final TextEditingController _fingerprint = TextEditingController();
  final GlobalKey _messageKey = GlobalKey();
  FormTeamRead? _team;

  /// De kaart die is gelezen en op zijn vingerafdruk wacht.
  FormEditorCard? _pending;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _cardText.dispose();
    _fingerprint.dispose();
    super.dispose();
  }

  /// Zorgt dat de melding in beeld komt: bij een lang team staan de knoppen en de melding ver
  /// onder de bovenkant van het venster.
  void _revealMessage() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = _messageKey.currentContext;
    if (context != null) Scrollable.ensureVisible(context);
  });

  Future<void> _refresh() async {
    final team = await widget.workspace.readTeam();
    if (!mounted) return;
    setState(() => _team = team);
  }

  /// Stap één: de plak lezen. Het venster toont alleen de naam; de eigenlijke controle doet
  /// [addFormEditor] met de tekst zelf.
  void _check() {
    final l10n = context.l10n;
    switch (parseFormEditorCard(_cardText.text)) {
      case FormEditorCardParsed(:final card):
        setState(() {
          _pending = card;
          _fingerprint.clear();
          _message = null;
        });
      case FormEditorCardRefused(:final issue):
        setState(() => _message = _cardRefusal(l10n, issue));
        _revealMessage();
    }
  }

  Future<void> _add() async {
    if (_busy) return;
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _message = null;
    });
    final outcome = await addFormEditor(
      widget.workspace,
      widget.keys,
      cardText: _cardText.text,
      fingerprintText: _fingerprint.text,
    );
    if (!mounted) return;
    final added = outcome is FormEditorAdded;
    setState(() {
      _busy = false;
      _message = _say(l10n, outcome);
      if (added) {
        _pending = null;
        _cardText.clear();
      }
    });
    _revealMessage();
    if (added) await _refresh();
  }

  Future<void> _remove(FormEditorCard card) async {
    final l10n = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => _RemoveDialog(card: card),
    );
    if (sure != true || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final outcome = await removeFormEditor(widget.workspace, card.kid);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = _say(l10n, outcome);
    });
    _revealMessage();
    await _refresh();
  }

  String _name(AppLocalizations l10n, String text, String name) =>
      l10n.d(text).replaceAll('{naam}', name);

  String _say(AppLocalizations l10n, FormTeamEdit outcome) => switch (outcome) {
    FormEditorAdded(:final card) => _name(
      l10n,
      '{naam} is toegevoegd. Maak het uitnodigingspakket opnieuw om {naam} erin op te nemen.',
      card.name,
    ),
    FormEditorRemoved(:final card) => _name(
      l10n,
      '{naam} is verwijderd. Maak het uitnodigingspakket opnieuw om {naam} eruit te halen.',
      card.name,
    ),
    FormTeamNeedsKey(:final problem) => switch (problem) {
      FormKeyProblem.absent => l10n.d(
        'Maak eerst je eigen redactiesleutel aan onder Redactiesleutel….',
      ),
      FormKeyProblem.unavailable ||
      FormKeyProblem.unreadable ||
      FormKeyProblem.damaged => l10n.d(
        'Je redactiesleutel is niet te gebruiken. Kijk onder Redactiesleutel….',
      ),
    },
    FormTeamUnreadable() => l10n.d(
      'Het bestand team.json in de werkmap is niet te lezen. Er is niets aangepast; herstel of verwijder het.',
    ),
    FormTeamCardRefused(:final issue) => _cardRefusal(l10n, issue),
    FormTeamBadFingerprint() => l10n.d(
      'Dat is geen vingerafdruk. Hij bestaat uit 52 tekens, meestal in groepjes van vier.',
    ),
    FormTeamFingerprintWrong() => l10n.d(
      'Deze vingerafdruk past niet bij de kaart: de kaart is veranderd of niet van wie je denkt. Vraag de redacteur om de vingerafdruk en de kaart opnieuw.',
    ),
    FormTeamNotAdded(:final issue) => switch (issue) {
      FormTeamAddIssue.owner => l10n.d('Dit is je eigen kaart.'),
      FormTeamAddIssue.duplicate => l10n.d('Deze redacteur staat er al.'),
      FormTeamAddIssue.full => l10n.d(
        'Het team is vol: een bundel draagt hooguit 64 organisatoren, jou meegeteld.',
      ),
    },
    FormEditorUnknown() => l10n.d(
      'Deze redacteur staat niet meer in het team.',
    ),
    FormTeamNotSaved() => l10n.d('Het team kon niet worden opgeslagen.'),
  };

  String _cardRefusal(
    AppLocalizations l10n,
    FormEditorCardIssue issue,
  ) => switch (issue) {
    FormEditorCardIssue.notACard => l10n.d('Dit is geen redacteurskaart.'),
    FormEditorCardIssue.unsupportedVersion => l10n.d(
      'Deze kaart is van een nieuwere versie van OciDeck. Werk OciDeck bij.',
    ),
    FormEditorCardIssue.badName ||
    FormEditorCardIssue.badAge ||
    FormEditorCardIssue.badSign ||
    FormEditorCardIssue.badKid => l10n.d(
      'De kaart bevat iets wat niet kan. Vraag de redacteur om een nieuwe kaart.',
    ),
  };

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
                          l10n.d('Team'),
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.d(
                          'De redacteurs naast jou die in elke bundel staan, zodat ook zij de inzendingen kunnen openen. Je voegt iemand toe met zijn redacteurskaart en typt de vingerafdruk van die kaart terug.',
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      ..._body(l10n, theme),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.d('Sluiten')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(AppLocalizations l10n, ThemeData theme) {
    final team = _team;
    if (team == null) return const [LinearProgressIndicator()];
    if (team is! FormTeamStored) {
      return [
        Text(
          l10n.d(
            'Het bestand team.json in de werkmap is niet te lezen. Er is niets aangepast; herstel of verwijder het.',
          ),
        ),
      ];
    }
    // Eerst het toevoegen en wat het zegt, dan de lijst: bij een lang team staan de knoppen niet
    // onder dertig regels redacteurs.
    return [
      ..._adding(l10n, theme),
      if (_message != null) ...[
        const SizedBox(height: 16),
        Semantics(key: _messageKey, liveRegion: true, child: Text(_message!)),
      ],
      const SizedBox(height: 20),
      ..._editors(l10n, theme, team.team),
    ];
  }

  List<Widget> _editors(
    AppLocalizations l10n,
    ThemeData theme,
    FormTeam team,
  ) => [
    if (team.editors.isEmpty)
      Text(l10n.d('Er is nog niemand naast jou.'))
    else
      for (final editor in team.editors)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(editor.name, style: theme.textTheme.titleSmall),
                    SelectableText(
                      formatFingerprint(editor.fingerprint),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _busy ? null : () => _remove(editor),
                child: Text(l10n.d('Verwijderen')),
              ),
            ],
          ),
        ),
  ];

  List<Widget> _adding(AppLocalizations l10n, ThemeData theme) {
    final pending = _pending;
    return [
      TextField(
        controller: _cardText,
        enabled: pending == null && !_busy,
        minLines: 2,
        maxLines: 5,
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(fontFamily: 'monospace'),
        decoration: InputDecoration(
          labelText: l10n.d('Plak de kaart van de redacteur'),
        ),
      ),
      const SizedBox(height: 12),
      if (pending == null)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _busy ? null : _check,
            child: Text(l10n.d('Kaart controleren')),
          ),
        )
      else ...[
        Text(
          _name(
            l10n,
            'Kaart van {naam}. Typ de vingerafdruk van deze kaart die {naam} je langs een andere weg gaf, bijvoorbeeld aan de telefoon.',
            pending.name,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _fingerprint,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(
            labelText: l10n.d('Vingerafdruk van de kaart'),
          ),
          onSubmitted: (_) => _add(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: _busy ? null : _add,
              child: Text(l10n.d('Toevoegen')),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _pending = null;
                      _message = null;
                    }),
              child: Text(l10n.d('Annuleren')),
            ),
          ],
        ),
      ],
    ];
  }
}

class _RemoveDialog extends StatelessWidget {
  const _RemoveDialog({required this.card});

  final FormEditorCard card;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Redacteur verwijderen')),
      content: Text(
        l10n
            .d(
              'Verwijder {naam} uit het team? Uitnodigingspakketten die je al hebt gemaakt blijven zoals ze zijn tot je een nieuwe maakt; wat al voor {naam} is verzegeld blijft voor die persoon leesbaar.',
            )
            .replaceAll('{naam}', card.name),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.d('Annuleren')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.d('Verwijderen')),
        ),
      ],
    );
  }
}
