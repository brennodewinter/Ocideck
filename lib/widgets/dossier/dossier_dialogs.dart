import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';

/// Small, focused prompts used by the dossier overview.
abstract final class DossierDialogs {
  static Future<String?> editTitle(
    BuildContext context, {
    required String initialTitle,
    bool creating = false,
  }) async {
    final controller = TextEditingController(text: initialTitle);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          final l10n = dialogContext.l10n;
          void submit() {
            final value = controller.text.trim();
            if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
          }

          return AlertDialog(
            title: Text(
              creating ? l10n.d('Nieuw dossier') : l10n.d('Titel wijzigen'),
            ),
            content: SizedBox(
              width: 420,
              child: TextField(
                controller: controller,
                autofocus: true,
                maxLength: 160,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: l10n.d('Titel')),
                onSubmitted: (_) => submit(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.d('Annuleren')),
              ),
              FilledButton(
                onPressed: submit,
                child: Text(
                  creating ? l10n.d('Dossier maken') : l10n.d('Opslaan'),
                ),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

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
