// Een uitnodiging openen (FORM_INTAKE.md §6.4, §6.6): de link plakken, het formulier ophalen en
// laten zien van wie het komt, voor de invuller het opent.
//
// Twee momenten waarop de invuller kan oordelen, en geen daarvan is een prompt met iets dat de
// server zelf bedacht. **Vóór** het verzoek staat het adres in beeld waar het formulier vandaan
// komt: de tik op *Formulier ophalen* is het "ja". **Erna** — nadat de handtekening, de
// vingerafdruk uit de link, het adres en de pins zijn getoetst — staat de naam van de organisator
// uit de ondertekende bundel in beeld, met de vingerafdruk onder *Details*.
//
// Een link zonder vingerafdruk komt hier niet verder: er is geen "toch doorgaan".

import 'dart:math';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/language_registry.dart';
import '../../services/form/intake/intake_client.dart';
import 'form_invitation_text.dart';

/// Wat de invuller koos: de geopende uitnodiging en het sjabloon dat hij invult.
class FormInvitationChoice {
  const FormInvitationChoice({required this.opened, required this.variant});

  final IntakeOpened opened;
  final IntakeOpenedVariant variant;
}

/// Toont het venster. [readPins] geeft wat de invuller eerder zag; [now] is de klok (een test
/// zet hem vast); [initialLink] slaat de klembord-stap over.
Future<FormInvitationChoice?> showFormInvitationDialog(
  BuildContext context, {
  required IntakeClient client,
  required Future<FormBundlePins> Function() readPins,
  DateTime Function()? now,
  String? initialLink,
}) => showDialog<FormInvitationChoice>(
  context: context,
  barrierDismissible: false,
  builder: (_) => FormInvitationDialog(
    client: client,
    readPins: readPins,
    now: now ?? DateTime.now,
    initialLink: initialLink,
  ),
);

enum _Step { input, checking, failed, opened }

class FormInvitationDialog extends StatefulWidget {
  const FormInvitationDialog({
    super.key,
    required this.client,
    required this.readPins,
    required this.now,
    this.initialLink,
  });

  final IntakeClient client;
  final Future<FormBundlePins> Function() readPins;
  final DateTime Function() now;
  final String? initialLink;

  @override
  State<FormInvitationDialog> createState() => _FormInvitationDialogState();
}

class _FormInvitationDialogState extends State<FormInvitationDialog> {
  final TextEditingController _text = TextEditingController();
  _Step _step = _Step.input;
  IntakeFailed? _failed;
  IntakeOpened? _opened;

  /// Het gekozen sjabloon; gezet zodra het formulier is geopend.
  late int _chosen;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    if (widget.initialLink != null) {
      _text.text = widget.initialLink!;
    } else {
      _prefillFromClipboard();
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// De uitnodiging staat vaak al op het klembord: de invuller kwam van zijn appje. Alleen iets
  /// dat op een uitnodiging lijkt wordt overgenomen, en het blijft zijn tekst om te veranderen.
  Future<void> _prefillFromClipboard() async {
    final String? clip;
    try {
      clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on PlatformException {
      return;
    }
    if (clip == null || !mounted || _text.text.isNotEmpty) return;
    final read = parseInviteLink(clip);
    final looksLikeOne =
        read is InviteLinkParsed ||
        (read is InviteLinkRefused &&
            read.issue != InviteLinkIssue.notALink &&
            read.issue != InviteLinkIssue.notHttps &&
            read.issue != InviteLinkIssue.noFormId);
    if (looksLikeOne) _text.text = clip.trim();
  }

  InviteLinkResult get _read => parseInviteLink(_text.text);

  Future<void> _fetch(InviteLink invite) async {
    setState(() => _step = _Step.checking);
    final result = await widget.client.openInvitation(
      invite,
      pins: await widget.readPins(),
      now: widget.now(),
    );
    // Na *Annuleren* is het venster weg: een antwoord dat dan nog binnenkomt is niet meer van belang.
    if (!mounted) return;
    setState(() {
      switch (result) {
        case IntakeOpened():
          _opened = result;
          _chosen = _preferredVariant(result);
          _step = _Step.opened;
        case IntakeFailed():
          _failed = result;
          _step = _Step.failed;
      }
    });
  }

  /// Het sjabloon in de taal van het programma, anders het eerste.
  int _preferredVariant(IntakeOpened opened) {
    final mine = context.l10n.languageCode;
    final at = opened.variants.indexWhere(
      (v) => _primaryTag(v.spec.lang) == mine,
    );
    return max(at, 0);
  }

  void _close() => Navigator.pop(context);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return switch (_step) {
      _Step.input => _inputDialog(l10n),
      _Step.checking => AlertDialog(
        title: Text(l10n.d('Uitnodiging openen')),
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(l10n.d('Het formulier wordt opgehaald…'))),
          ],
        ),
        actions: [
          TextButton(onPressed: _close, child: Text(l10n.d('Annuleren'))),
        ],
      ),
      _Step.failed => _failedDialog(l10n),
      _Step.opened => _openedDialog(l10n),
    };
  }

  Widget _inputDialog(AppLocalizations l10n) {
    final read = _read;
    final typed = _text.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(l10n.d('Uitnodiging openen')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.d(
                  'Plak de uitnodigingslink die je van de organisator kreeg. Het formulier wordt dan opgehaald bij de server die in de link staat.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('invitation-link'),
                controller: _text,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.d('Uitnodigingslink'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              if (typed)
                switch (read) {
                  InviteLinkParsed(:final link) => Text(
                    key: const Key('invitation-host'),
                    l10n
                        .d('Het formulier wordt opgehaald bij {host}.')
                        .replaceAll('{host}', link.apiHost),
                  ),
                  InviteLinkRefused(:final issue) => Text(
                    key: const Key('invitation-issue'),
                    inviteLinkIssueText(l10n, issue),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                },
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _close, child: Text(l10n.d('Annuleren'))),
        FilledButton(
          key: const Key('invitation-fetch'),
          onPressed: read is InviteLinkParsed ? () => _fetch(read.link) : null,
          child: Text(l10n.d('Formulier ophalen')),
        ),
      ],
    );
  }

  Widget _failedDialog(AppLocalizations l10n) {
    final read = _read;
    final host = read is InviteLinkParsed ? read.link.apiHost : '';
    return AlertDialog(
      title: Text(l10n.d('Uitnodiging openen')),
      content: SizedBox(
        width: 460,
        child: Text(
          key: const Key('invitation-failure'),
          intakeFailureText(l10n, _failed!, host: host),
        ),
      ),
      actions: [
        TextButton(onPressed: _close, child: Text(l10n.d('Sluiten'))),
        FilledButton(
          onPressed: () => setState(() => _step = _Step.input),
          child: Text(l10n.d('Opnieuw proberen')),
        ),
      ],
    );
  }

  Widget _openedDialog(AppLocalizations l10n) {
    final opened = _opened!;
    final variant = opened.variants[_chosen];
    final bundle = variant.verified.bundle;
    final closes = bundle.policy.closes;
    final today = formDay(widget.now());
    final closedBy = opened.state == IntakeFormState.closed
        ? l10n.d(
            'Dit formulier is gesloten voor nieuwe inzendingen. Neem contact op met de organisator.',
          )
        : closes != null && today.compareTo(closes) > 0
        ? l10n
              .d(
                'Dit formulier is gesloten: de laatste dag was {datum}. Neem contact op met de organisator.',
              )
              .replaceAll('{datum}', closes)
        : null;
    return AlertDialog(
      title: Text(
        l10n
            .d('Formulier van {naam}')
            .replaceAll('{naam}', variant.verified.owner.name),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (closedBy != null)
                Text(
                  key: const Key('invitation-closed'),
                  closedBy,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (opened.variants.length > 1) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.d('Taal'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                RadioGroup<int>(
                  groupValue: _chosen,
                  onChanged: (v) => setState(() => _chosen = v ?? _chosen),
                  child: Column(
                    children: [
                      for (var i = 0; i < opened.variants.length; i++)
                        RadioListTile<int>(
                          key: Key('invitation-variant-$i'),
                          value: i,
                          dense: true,
                          title: Text(
                            _languageName(opened.variants[i].spec.lang),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              ExpansionTile(
                key: const Key('invitation-details'),
                tilePadding: EdgeInsets.zero,
                title: Text(l10n.d('Details')),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      l10n
                          .d('Server: {host}')
                          .replaceAll('{host}', opened.invite.apiHost),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(l10n.d('Vingerafdruk van de organisator')),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      formatFingerprint(variant.verified.fingerprint),
                      key: const Key('invitation-fingerprint'),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _close, child: Text(l10n.d('Annuleren'))),
        FilledButton(
          key: const Key('invitation-open'),
          onPressed: closedBy != null
              ? null
              : () => Navigator.pop(
                  context,
                  FormInvitationChoice(opened: opened, variant: variant),
                ),
          child: Text(l10n.d('Formulier invullen')),
        ),
      ],
    );
  }

  /// De naam van een taal zoals het programma hem kent; een onbekende code blijft zoals hij is.
  String _languageName(String? lang) {
    final tag = _primaryTag(lang);
    if (tag == null) return context.l10n.d('Onbekende taal');
    return kLanguageNames[tag] ?? lang!;
  }
}

/// `nl-NL` → `nl`.
String? _primaryTag(String? lang) {
  if (lang == null || lang.trim().isEmpty) return null;
  return lang.trim().split(RegExp('[-_]')).first.toLowerCase();
}
