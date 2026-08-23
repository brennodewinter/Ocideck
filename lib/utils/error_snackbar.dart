import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';

/// Show an error message the user can COPY: a SnackBar that carries a
/// **Kopiëren (Copy)** action putting the exact text on the clipboard — so a
/// failure can be forwarded (e.g. reported here) without retyping it — and that
/// stays a little longer than a normal notification so there is time to read and
/// copy it. Pass the [messenger] the caller already holds (captured before an
/// await, or `ScaffoldMessenger.of(context)`), so it is safe after async gaps.
void showErrorSnackBar(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  String message,
) {
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: l10n.d('Kopiëren'),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: message));
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(l10n.d('Gekopieerd')),
                duration: const Duration(seconds: 2),
              ),
            );
        },
      ),
    ),
  );
}
