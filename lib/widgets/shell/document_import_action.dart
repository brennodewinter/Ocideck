// Document-import-actie: kiest een .docx of .odt, zet het om naar Markdown,
// en opent het resultaat als een nieuw document-tabblad.
//
// Bewust lichter dan de presentatie-import (presentation_import_action.dart):
// een document kent geen dia's, geen probleemdia's, geen logo-detectie en geen
// stijlkeuze. De enige stap is: bestand kiezen → omzetten → openen. De
// fail-closed safety-scan zit in de service (document_import_service.dart),
// niet hier — dezelfde plek als bij het openen van een vreemd `.md`.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/import/document_import_service.dart';
import '../../state/settings_provider.dart';
import '../../state/tabs_provider.dart';
import '../../utils/error_snackbar.dart';
import '../../utils/log.dart';

/// Importeert een `.docx` of `.odt` als een nieuw Markdown-document: kiest een
/// bestand, zet het om, en opent het resultaat in een nieuw tabblad.
///
/// Leest de providers zelf via de container (zoals `app_shell_menu.dart`),
/// zodat de aanroepers — het welkomstscherm, de documenttoolbar — geen `ref`
/// hoeven door te geven. [fileOverride] slaat de bestandskiezer over; dat is
/// de testroute, net als bij de presentatie-import.
Future<void> importDocument(
  BuildContext context, {
  ({Uint8List bytes, String name})? fileOverride,
}) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context);

  final picked =
      fileOverride ??
      await _pickDocument(
        l10n,
        initialDirectory: container.read(settingsProvider).homeDirectory,
      );
  if (picked == null || !context.mounted) return;

  final result = importDocumentBytes(picked.bytes, filename: picked.name);
  if (!context.mounted) return;

  if (result.isSuccess) {
    container
        .read(tabsProvider.notifier)
        .newDocumentFromMarkdown(result.markdown!);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.d('Document geïmporteerd.'))),
    );
  } else {
    final failure = result.failure!;
    logWarning('importDocument: ${failure.message}', failure.cause);
    showErrorSnackBar(messenger, l10n, failure.message);
  }
}

/// De bestandskiezer, apart gehouden zodat de import zelf één rechte lijn
/// blijft. `null` betekent: niets gekozen.
Future<({Uint8List bytes, String name})?> _pickDocument(
  AppLocalizations l10n, {
  String? initialDirectory,
}) async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: documentImportExtensions,
    dialogTitle: l10n.d('Document kiezen'),
    initialDirectory: initialDirectory,
  );
  if (picked.isEmpty) return null;
  final file = picked.first;
  return (bytes: Uint8List.fromList(await file.readAsBytes()), name: file.name);
}

/// Het menulabel voor de document-import.
String documentImportLabel(AppLocalizations l10n) =>
    l10n.d('Document importeren…');
