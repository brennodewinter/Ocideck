// The recovery-key dialogs (COLLABORATION Phase 2 "Blok B";
// SELF_ENCRYPTED_RELAY.md §5.3). One shows the key to save — with the plain
// warning that losing it means losing this identity on a device switch — and one
// takes a key to restore. Decoupled from the settings panel so both are plain,
// widget-testable dialogs.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// Show the [recoveryKey] to save, with a one-tap copy and the honest warning
/// that this is the only way to carry the identity to another device.
Future<void> showRecoveryKeyDialog(
  BuildContext context,
  AppLocalizations l10n,
  String recoveryKey,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.d('Herstelsleutel')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Bewaar deze herstelsleutel op een veilige plek — bijvoorbeeld in je wachtwoordkluis. Het is de enige manier om dezelfde identiteit op een ander apparaat te herstellen; zonder deze sleutel begin je daar als een nieuw, nog niet geverifieerd apparaat. Deel hem met niemand.',
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.slate100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                recoveryKey,
                style: const TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 16),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: recoveryKey));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.d('Herstelsleutel gekopieerd.'))),
              );
            }
          },
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

/// Prompt for a recovery key to restore. Returns the entered text (untrimmed
/// decoding is tolerant of spacing/case), or null on cancel.
Future<String?> promptRecoveryKey(BuildContext context, AppLocalizations l10n) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _RecoveryKeyPrompt(),
  );
}

class _RecoveryKeyPrompt extends StatefulWidget {
  const _RecoveryKeyPrompt();

  @override
  State<_RecoveryKeyPrompt> createState() => _RecoveryKeyPromptState();
}

class _RecoveryKeyPromptState extends State<_RecoveryKeyPrompt> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Identiteit herstellen')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Plak de herstelsleutel die je eerder bewaarde. Dit apparaat neemt dan dezelfde identiteit over — mede-auteurs die je eerder verifieerden herkennen je vingerafdruk weer.',
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 3,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: l10n.d('ABCD-EFGH-…'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.d('Annuleren')),
        ),
        FilledButton(
          onPressed: () {
            final text = _controller.text.trim();
            Navigator.pop(context, text.isEmpty ? null : text);
          },
          child: Text(l10n.d('Herstellen')),
        ),
      ],
    );
  }
}
