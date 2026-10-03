// Een inzending naar een server sturen (FORM_INTAKE.md §6.6, §5.8): bevestigen, versturen en zeggen hoe
// het ging.
//
// **De tweede keer dat de invuller kan oordelen**, en de laatste: voor de eerste byte weg is, staat
// er in één zin naar wie de inzending gaat — "de redactie van {naam}", met de server — en dat alleen
// zij hem kunnen openen. De vingerafdruk staat onder *Details*. Het venster ziet het pakket al
// verzegeld: wat hier wordt gezegd is waar de inzending aan is dichtgemaakt.
//
// Wat erna komt is eerlijk over wat het bericht van de server is: een **aankomstbericht**, geen
// bewijs tegen de server. De invuller kan er de tijd en een controlegetal aan noemen, en bewaart een
// bewijs met het geheim waarmee hij de inzending kan intrekken. Mislukt het, dan blijven de
// antwoorden gewoon in het formulier, en kan hij het opnieuw proberen of de verzegelde inzending
// bewaren en mailen — met hetzelfde nummer en dezelfde bytes, dus een herhaling is veilig.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../../l10n/app_localizations.dart';
import '../../services/form/form_submission_export.dart';
import '../../services/form/form_submission_seal.dart';
import '../../services/form/intake/intake_client.dart';
import 'form_send_text.dart';

/// Bewaart [bytes] onder [fileName]; geeft de naam waaronder het is opgeslagen, `null` als de
/// invuller annuleert. Een mislukte schrijfactie is een uitzondering.
typedef FormSaveFile =
    Future<String?> Function(String fileName, Uint8List bytes);

/// Toont het venster. Wat er gebeurde zegt het venster zelf; de aanroeper heeft er niets aan terug
/// te krijgen.
Future<void> showFormSendDialog(
  BuildContext context, {
  required InviteLink invite,
  required IntakeClient client,
  required FormSubmissionBuilt built,
  required FormSubmissionSealed sealed,
  required String fingerprint,
  required FormSaveFile saveFile,
  Random? random,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => FormSendDialog(
    invite: invite,
    client: client,
    built: built,
    sealed: sealed,
    fingerprint: fingerprint,
    saveFile: saveFile,
    random: random ?? Random.secure(),
  ),
);

enum _Step { confirm, sending, done, failed }

class FormSendDialog extends StatefulWidget {
  const FormSendDialog({
    super.key,
    required this.invite,
    required this.client,
    required this.built,
    required this.sealed,
    required this.fingerprint,
    required this.saveFile,
    required this.random,
  });

  final InviteLink invite;
  final IntakeClient client;
  final FormSubmissionBuilt built;
  final FormSubmissionSealed sealed;
  final String fingerprint;
  final FormSaveFile saveFile;
  final Random random;

  @override
  State<FormSendDialog> createState() => _FormSendDialogState();
}

class _FormSendDialogState extends State<FormSendDialog> {
  _Step _step = _Step.confirm;

  /// Het geheugen van de invuller voor deze inzending: bij elke poging hetzelfde, want de server
  /// kent een herhaling aan het nummer en de bytes.
  late final String _secret = newWithdrawalSecret(widget.random);

  IntakeSubmitted? _done;
  IntakeFailed? _failure;

  /// Wat er onder het venster is opgeslagen (het bewijs, het verzegelde bestand), als zin.
  String? _saved;
  bool _saving = false;

  Future<void> _send() async {
    setState(() => _step = _Step.sending);
    final result = await widget.client.submit(
      invite: widget.invite,
      sid: widget.built.sid,
      sealed: widget.sealed.bytes,
      withdrawalSecret: _secret,
    );
    if (!mounted) return;
    setState(() {
      switch (result) {
        case IntakeSubmitted():
          _done = result;
          _step = _Step.done;
        case IntakeFailed():
          _failure = result;
          _step = _Step.failed;
      }
    });
  }

  /// Het bewijs: wat de server zei en het geheim waarmee de inzending is in te trekken.
  Future<void> _saveReceipt() async {
    final note = _done!.note;
    final receipt = IntakeReceipt(
      host: widget.invite.apiHost,
      fid: widget.invite.fid,
      withdrawalSecret: _secret,
      note: note,
    );
    final stem = widget.built.fileName.endsWith('.zip')
        ? widget.built.fileName.substring(0, widget.built.fileName.length - 4)
        : widget.built.fileName;
    await _saveAnd(
      '$stem$kIntakeReceiptSuffix',
      Uint8List.fromList(utf8.encode(receipt.toJsonText())),
      (l10n, name) =>
          l10n.d('Bewijs opgeslagen als {naam}.').replaceAll('{naam}', name),
      failure: (l10n) => l10n.d('Het bewijs kon niet worden opgeslagen.'),
    );
  }

  /// Het verzegelde bestand, om te mailen als het versturen niet lukt.
  Future<void> _saveSealed() => _saveAnd(
    widget.sealed.fileName,
    widget.sealed.bytes,
    (l10n, name) => l10n
        .d(
          'Verzegeld opgeslagen als {naam}, alleen te openen door: {organisatoren}.',
        )
        .replaceAll('{naam}', name)
        .replaceAll('{organisatoren}', widget.sealed.organisers.join(', ')),
    failure: (l10n) => l10n.d('De inzending kon niet worden opgeslagen.'),
  );

  Future<void> _saveAnd(
    String fileName,
    Uint8List bytes,
    String Function(AppLocalizations l10n, String name) saved, {
    required String Function(AppLocalizations l10n) failure,
  }) async {
    final l10n = context.l10n;
    setState(() => _saving = true);
    String? message;
    try {
      final name = await widget.saveFile(fileName, bytes);
      if (name != null) message = saved(l10n, name);
    } on Object {
      // Een schijf die vol zit, een map zonder schrijfrechten: voor de invuller is het één ding.
      message = failure(l10n);
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (message != null) _saved = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return switch (_step) {
      _Step.confirm => _confirm(l10n),
      _Step.sending => AlertDialog(
        title: Text(l10n.d('Versturen')),
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(l10n.d('De inzending wordt verstuurd…'))),
          ],
        ),
      ),
      _Step.done => _doneDialog(l10n),
      _Step.failed => _failedDialog(l10n),
    };
  }

  Widget _confirm(AppLocalizations l10n) {
    final names = widget.sealed.organisers;
    return AlertDialog(
      title: Text(l10n.d('Versturen')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                key: const Key('send-confirm'),
                l10n
                    .d(
                      'Naar de redactie van {naam} versturen? Je inzending gaat versleuteld naar {host}; alleen {namen} kunnen hem openen.',
                    )
                    .replaceAll('{naam}', names.first)
                    .replaceAll('{host}', widget.invite.apiHost)
                    .replaceAll('{namen}', names.join(', ')),
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                key: const Key('send-details'),
                tilePadding: EdgeInsets.zero,
                title: Text(l10n.d('Details')),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(l10n.d('Vingerafdruk van de organisator')),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      formatFingerprint(widget.fingerprint),
                      key: const Key('send-fingerprint'),
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.d('Annuleren')),
        ),
        FilledButton(
          key: const Key('send-go'),
          onPressed: _send,
          child: Text(l10n.d('Versturen')),
        ),
      ],
    );
  }

  Widget _doneDialog(AppLocalizations l10n) {
    final note = _done!.note;
    return AlertDialog(
      title: Text(l10n.d('Je inzending is aangekomen.')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                key: const Key('send-arrived'),
                l10n
                    .d(
                      'Aangekomen op {tijd}. Heb je vragen, schrijf dan naar {contact}.',
                    )
                    .replaceAll('{tijd}', _readable(note.at))
                    .replaceAll('{contact}', note.contact),
              ),
              const SizedBox(height: 8),
              Text(
                l10n
                    .d(
                      'Het controlegetal van wat de server ontving begint met {hash}. Noem het als je erover schrijft.',
                    )
                    .replaceAll(
                      '{hash}',
                      note.ciphertextSha256.substring(0, 12),
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.d(
                  'Het bewijs bevat het geheim waarmee je de inzending kunt intrekken. Bewaar het op een veilige plek.',
                ),
              ),
              if (_saved != null) ...[
                const SizedBox(height: 8),
                Text(key: const Key('send-saved'), _saved!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('send-receipt'),
          onPressed: _saving ? null : _saveReceipt,
          child: Text(l10n.d('Bewijs bewaren…')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.d('Sluiten')),
        ),
      ],
    );
  }

  Widget _failedDialog(AppLocalizations l10n) {
    return AlertDialog(
      title: Text(l10n.d('Versturen')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                key: const Key('send-failure'),
                intakeSendFailureText(
                  l10n,
                  _failure!,
                  host: widget.invite.apiHost,
                ),
              ),
              if (_saved != null) ...[
                const SizedBox(height: 8),
                Text(key: const Key('send-saved'), _saved!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.d('Sluiten')),
        ),
        TextButton(
          key: const Key('send-save-sealed'),
          onPressed: _saving ? null : _saveSealed,
          child: Text(l10n.d('Verzegeld opslaan…')),
        ),
        FilledButton(
          key: const Key('send-retry'),
          onPressed: _send,
          child: Text(l10n.d('Opnieuw proberen')),
        ),
      ],
    );
  }
}

/// `2026-10-04T09:30:12Z` → `2026-10-04 09:30:12 UTC`: de server zegt UTC, en dat blijft zo staan.
String _readable(String at) =>
    at.replaceFirst('T', ' ').replaceFirst('Z', ' UTC');
