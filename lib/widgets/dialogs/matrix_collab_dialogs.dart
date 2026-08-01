// The two small dialogs that bracket a realtime Matrix session
// (SELF_ENCRYPTED_RELAY.md §6.5): the host shares an invite link, a guest pastes
// one. The link *is* the room secret (a private, non-directory-listed room), so
// it carries the access to the session — but not to the content, which stays
// end-to-end encrypted by our own keys regardless of who holds the link.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
