// The dialogs of a realtime Matrix session (SELF_ENCRYPTED_RELAY.md §6.5): the
// host shares an invite link, a guest pastes one, and either can compare device
// fingerprints. The link *is* the room secret (a private, non-directory-listed
// room), so it carries access to the session — but not to the content, which
// stays end-to-end encrypted by our own keys regardless of who holds the link.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../collab/collab_participant.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// Show the invite link to share, with a one-tap copy. Shown to the host the
/// moment the session goes active.
Future<void> showMatrixInviteDialog(
  BuildContext context,
  AppLocalizations l10n,
  String inviteLink,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.d('Nodig mede-auteurs uit')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d(
              'Deel deze link met wie je mee wil laten werken. Wie de link heeft, kan de sessie binnenkomen — deel hem dus alleen met mensen die je vertrouwt. De inhoud blijft end-to-end versleuteld; de homeserver ziet alleen versleutelde gegevens.',
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.slate100,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.slate300),
            ),
            child: SelectableText(
              inviteLink,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: inviteLink));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.d('Uitnodigingslink gekopieerd.'))),
            );
          },
          icon: const Icon(Icons.copy, size: 16),
          label: Text(l10n.d('Kopiëren')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.d('Klaar')),
        ),
      ],
    ),
  );
}

/// Ask the guest to paste an invite link. Returns the trimmed link, or null when
/// cancelled or empty.
Future<String?> promptMatrixInvite(
  BuildContext context,
  AppLocalizations l10n,
) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _MatrixInvitePrompt(),
  );
}

/// List the devices in the session with their identity-key fingerprints, so
/// co-authors can compare them out-of-band and catch a substituted key (§4.3).
Future<void> showMatrixParticipantsDialog(
  BuildContext context,
  AppLocalizations l10n,
  List<CollabParticipant> participants,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.d('Deelnemers verifiëren')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Vergelijk de vingerafdruk van elk apparaat via een vertrouwd kanaal — lees hem elkaar voor, of stuur hem langs een weg die je vertrouwt. Komen ze overeen, dan werk je met de echte apparaten en heeft niemand ertussen gezeten. Wijken ze af, verbreek dan de samenwerking.',
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in participants)
                    _participantTile(context, l10n, p),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.d('Sluiten')),
        ),
      ],
    ),
  );
}

Widget _participantTile(
  BuildContext context,
  AppLocalizations l10n,
  CollabParticipant p,
) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              p.isSelf ? Icons.smartphone : Icons.person_outline,
              size: 16,
              color: AppTheme.slate400,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                p.isSelf ? '${p.userId} ${l10n.d('(dit apparaat)')}' : p.userId,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 22, top: 2),
          child: SelectableText(
            p.fingerprint,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
      ],
    ),
  );
}

class _MatrixInvitePrompt extends StatefulWidget {
  const _MatrixInvitePrompt();

  @override
  State<_MatrixInvitePrompt> createState() => _MatrixInvitePromptState();
}

class _MatrixInvitePromptState extends State<_MatrixInvitePrompt> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final link = _controller.text.trim();
    Navigator.pop(context, link.isEmpty ? null : link);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Deelnemen via een link')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d(
              'Plak de uitnodigingslink die de gastheer je stuurde. Je opent daarmee dezelfde presentatie en werkt live mee.',
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              labelText: l10n.d('Uitnodigingslink'),
              hintText: l10n.d('https://matrix.to/#/…'),
              prefixIcon: const Icon(Icons.link, size: 18),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.d('Annuleren')),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.d('Deelnemen'))),
      ],
    );
  }
}
