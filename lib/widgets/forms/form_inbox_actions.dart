// Wat een organisator in de Inbox met één inzending doet (FORM_INTAKE.md §7.3): de
// status wisselen, haar intrekken, haar verwijderen. Het werk zelf staat in
// `form_submission_actions.dart`; hier staan de knoppen, de bevestigingen — verwijderen
// zegt eerst wat er blijft en dat het niet terug kan — en de zin die zegt hoe het ging.

import 'package:material_ui/material_ui.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../../l10n/app_localizations.dart';
import '../../services/form/form_submission_actions.dart';
import '../../services/form/form_workspace.dart';
import 'form_maker_check_dialog.dart';

/// De zin bij een actie op het register die niet is gelukt.
String formActionFailedMessage(
  AppLocalizations l10n,
  FormActionOutcome outcome,
) => switch (outcome) {
  FormActionOutcome.registerDamaged => l10n.d(
    'Het register kan niet worden gelezen. Herstel overview.md; er is niets gewijzigd.',
  ),
  FormActionOutcome.notSaved => l10n.d(
    'Het register kon niet worden bijgewerkt.',
  ),
  _ => l10n.d(
    'Deze wijziging kon niet worden doorgevoerd: de inzending staat niet in het register.',
  ),
};

class FormInboxActions extends StatelessWidget {
  const FormInboxActions({
    super.key,
    required this.workspace,
    required this.sid,
    required this.row,
    required this.spec,
    required this.onDone,
    this.now,
    this.delete = deleteSubmission,
    this.onOpenFile,
    this.canEdit = false,
    this.makerCheck,
  });

  final FormWorkspace workspace;
  final String sid;

  /// De rij van de inzending in het register, of `null` als ze er geen heeft.
  final FormRegisterRow? row;

  /// Het formulier waartegen is beoordeeld: de statuslijst en de velden die bij
  /// verwijderen blijven komen daaruit. `null` als het formulier niet bekend is.
  final FormSpec? spec;

  /// Er is iets gedaan: de zin die zegt hoe het ging. De lijst leest zich opnieuw.
  final ValueChanged<String> onDone;

  /// De klok voor de voorgestelde dag; in een test een vaste waarde.
  final DateTime Function()? now;

  /// Het verwijderen zelf. Een naad voor de test: dat een geannuleerde bevestiging
  /// niets verwijdert is de belangrijkste eigenschap van dit venster, en een echte
  /// schijf laat zich niet op "er is niets gebeurd" betrappen zonder te wachten.
  final Future<FormDeleteOutcome> Function(
    FormWorkspace workspace,
    String sid, {
    List<String> keep,
  })
  delete;

  /// Opent een bestand van de werkmap in OciDeck. `null`: de knop voor de werkkopie
  /// ontbreekt.
  final ValueChanged<String>? onOpenFile;

  /// De inzending is te lezen, dus er is iets om een werkkopie van te maken.
  final bool canEdit;

  /// Het venster voor de controle door de maker. Een naad voor de test: dat wat het
  /// meegeeft goed wordt afgehandeld is te bewijzen zonder het venster te doorlopen.
  final Future<FormMakerCheckResult?> Function(BuildContext context)?
  makerCheck;

  bool get _deleted => row?.isDeleted ?? false;

  /// Maakt de werkkopie als ze er nog niet is en opent haar. Nooit wat binnenkwam:
  /// dat blijft zoals het was, en een bewerking in de editor of de invulpagina zou
  /// het wijzigen.
  Future<void> _openWorkingCopy(BuildContext context) async {
    final l10n = context.l10n;
    switch (await workspace.workingCopy(sid)) {
      case FormWorkingCopy(:final path):
        onOpenFile!(path);
      case FormWorkingCopyUnavailable():
        onDone(l10n.d('De inzending is niet gevonden in de werkmap.'));
      case FormWorkingCopyFailed():
        onDone(l10n.d('De werkkopie kon niet worden aangemaakt.'));
    }
  }

  Future<FormMakerCheckResult?> _showMakerCheck(BuildContext context) =>
      showFormMakerCheckDialog(
        context,
        workspace: workspace,
        sid: sid,
        spec: spec!,
        now: now,
      );

  /// De controle door de maker: het venster maakt het hoofdstuk, schrijft de mail en
  /// zet de status; wat het meegeeft handelt de Inbox af.
  Future<void> _makerCheck(BuildContext context) async {
    final result = await (makerCheck ?? _showMakerCheck)(context);
    switch (result) {
      case FormMakerCheckOpened(:final path):
        onOpenFile!(path);
      case FormMakerCheckStatusSet(:final message):
        onDone(message);
      case null:
        break;
    }
  }

  Future<void> _status(BuildContext context, String status) async {
    final l10n = context.l10n;
    final outcome = await setSubmissionStatus(
      workspace,
      sid,
      status,
      formStatesOf(spec!),
    );
    onDone(
      outcome == FormActionOutcome.done
          ? l10n
                .d('Status gewijzigd naar {status}.')
                .replaceAll('{status}', status)
          : formActionFailedMessage(l10n, outcome),
    );
  }

  Future<void> _withdraw(BuildContext context) async {
    final l10n = context.l10n;
    final today = formDay((now ?? DateTime.now)());
    final day = await showDialog<String>(
      context: context,
      builder: (_) => _WithdrawDialog(example: today),
    );
    if (day == null) return;
    final outcome = await setSubmissionWithdrawal(workspace, sid, day);
    onDone(
      outcome == FormActionOutcome.done
          ? l10n.d('Intrekking opgeslagen.')
          : formActionFailedMessage(l10n, outcome),
    );
  }

  Future<void> _undoWithdrawal(BuildContext context) async {
    final l10n = context.l10n;
    final outcome = await setSubmissionWithdrawal(workspace, sid, '');
    onDone(
      outcome == FormActionOutcome.done
          ? l10n.d('Intrekking ongedaan gemaakt.')
          : formActionFailedMessage(l10n, outcome),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final l10n = context.l10n;
    final keep = spec?.keepRecord ?? const <String>[];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteDialog(keep: keep),
    );
    if (confirmed != true) return;
    final outcome = await delete(workspace, sid, keep: keep);
    onDone(switch (outcome) {
      FormDeleteOutcome.deleted => l10n.d(
        'Inzending verwijderd; het record blijft staan.',
      ),
      FormDeleteOutcome.deletedRegisterNotUpdated => l10n.d(
        'Inzending verwijderd, maar het register kon niet worden bijgewerkt. Pas overview.md met de hand aan.',
      ),
      FormDeleteOutcome.notFound => l10n.d(
        'De inzending is niet gevonden in de werkmap.',
      ),
      FormDeleteOutcome.failed => l10n.d(
        'De inzending kon niet worden verwijderd.',
      ),
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final current = row;
    final states = spec == null ? null : formStatesOf(spec!);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (current != null && states != null)
            DropdownButton<String>(
              hint: Text(l10n.d('Status wijzigen')),
              value: states.contains(current.status) ? current.status : null,
              items: [
                for (final state in states)
                  DropdownMenuItem(value: state, child: Text(state)),
              ],
              // `onChanged` komt niet voor dezelfde keuze nog eens: wat hier aankomt is
              // een wijziging.
              onChanged: (state) {
                if (state != null) _status(context, state);
              },
            ),
          if (canEdit && onOpenFile != null && !_deleted)
            Tooltip(
              message: l10n.d(
                'Opent een kopie van de inzending om in te verbeteren. Wat binnenkwam blijft ongewijzigd.',
              ),
              child: OutlinedButton(
                onPressed: () => _openWorkingCopy(context),
                child: Text(l10n.d('Werkkopie openen')),
              ),
            ),
          if (canEdit &&
              onOpenFile != null &&
              spec != null &&
              !_deleted &&
              !(current?.isWithdrawn ?? false))
            Tooltip(
              message: l10n.d(
                'Maakt het hoofdstuk van deze inzending en bereidt de mail voor waarmee de maker het controleert.',
              ),
              child: OutlinedButton(
                onPressed: () => _makerCheck(context),
                child: Text(l10n.d('Controle door de maker…')),
              ),
            ),
          if (current != null)
            current.isWithdrawn
                ? OutlinedButton(
                    onPressed: () => _undoWithdrawal(context),
                    child: Text(l10n.d('Intrekking ongedaan maken')),
                  )
                : OutlinedButton(
                    onPressed: () => _withdraw(context),
                    child: Text(l10n.d('Intrekken…')),
                  ),
          if (!_deleted)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => _delete(context),
              child: Text(l10n.d('Verwijderen…')),
            ),
        ],
      ),
    );
  }
}

/// Vraagt de dag waarop de inzender de inzending introk.
class _WithdrawDialog extends StatefulWidget {
  const _WithdrawDialog({required this.example});

  final String example;

  @override
  State<_WithdrawDialog> createState() => _WithdrawDialogState();
}

class _WithdrawDialogState extends State<_WithdrawDialog> {
  late final TextEditingController _day = TextEditingController(
    text: widget.example,
  );
  bool _invalid = false;

  @override
  void dispose() {
    _day.dispose();
    super.dispose();
  }

  void _submit() {
    final day = _day.text.trim();
    if (!isValidCalendarDate(day)) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(day);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Inzending intrekken')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d(
              'Vul de dag in waarop de inzender de inzending introk. Een ingetrokken inzending komt nooit in het boek.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _day,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.d('Dag (jjjj-mm-dd)'),
              errorText: _invalid
                  ? l10n
                        .d(
                          'Ongeldige dag. Gebruik jaar-maand-dag, bijvoorbeeld {voorbeeld}.',
                        )
                        .replaceAll('{voorbeeld}', widget.example)
                  : null,
            ),
            onChanged: (_) {
              if (_invalid) setState(() => _invalid = false);
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Annuleren')),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.d('Intrekken'))),
      ],
    );
  }
}

/// Zegt wat verwijderen doet — en wat blijft — voordat het gebeurt.
class _DeleteDialog extends StatelessWidget {
  const _DeleteDialog({required this.keep});

  final List<String> keep;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(l10n.d('Inzending verwijderen')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d(
              'De antwoorden, de werkkopie en de foto’s van deze inzending worden uit de werkmap gewist. Alleen een minimaal record blijft over: het nummer, de dagen van ontvangst en toestemming en de status. Dit kan niet ongedaan worden gemaakt.',
            ),
          ),
          if (keep.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n
                  .d(
                    'Ook blijft staan wat het formulier vooraf aankondigde: {velden}.',
                  )
                  .replaceAll('{velden}', keep.join(', ')),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.d('Annuleren')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.d('Verwijderen')),
        ),
      ],
    );
  }
}
