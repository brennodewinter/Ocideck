import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';

/// Show a snackbar whose text the user can COPY: a **Kopiëren (Copy)** action
/// puts the exact text on the clipboard — so a URL, path, git result or error
/// can be forwarded without retyping it. Pass the [messenger] the caller
/// already holds (captured before an await, or `ScaffoldMessenger.of(context)`),
/// so it is safe after async gaps.
void showCopyableSnackBar(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  String message, {
  Duration duration = const Duration(seconds: 5),
}) {
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration,
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

/// Show an error message the user can COPY — [showCopyableSnackBar] with a
/// longer dwell so there is time to read and copy a failure.
void showErrorSnackBar(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  String message,
) => showCopyableSnackBar(
  messenger,
  l10n,
  message,
  duration: const Duration(seconds: 8),
);
