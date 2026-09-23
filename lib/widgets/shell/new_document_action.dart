// Nieuw-document-actie: vraagt op desktop eerst naam en map
// (new_document_dialog.dart, #2177) en maakt het bestand daar meteen aan —
// de document-tegenhanger van `_createDeckFromDialog` voor presentaties.
// "Nog niet opslaan" of web levert een klad-tabblad in het geheugen; de
// eerste opslaan vraagt dan alsnog om een pad via 'Opslaan als…'.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../platform/platform_features.dart';
import '../../state/settings_provider.dart';
import '../../state/tabs_provider.dart';
import '../../utils/error_snackbar.dart';
import '../dialogs/new_document_dialog.dart';

/// Testhaak voor de aanmaak-aanroep achter de dialoog — zelfde reden als
/// `debugImportTaskRunner` in document_import_action.dart: echte schijf-IO
/// (de exclusieve `File.create` in `newDocument`) beantwoordt de fake klok
/// van `flutter test` niet, dus een widgettest vervangt deze stap.
Future<bool> Function(String? filePath)? debugNewDocumentRunner;

/// Maakt een nieuw, leeg document aan. Op desktop loopt dat via de
/// naam/map-dialoog; op web (geen bestandssysteem) direct als klad. Leest
/// de providers zelf via de container, zoals [importDocument], zodat de
/// aanroepplekken — welkomstscherm, menubalk — geen `ref` hoeven door te
/// geven.
Future<void> newDocumentFromDialog(BuildContext context) async {
  final container = ProviderScope.containerOf(context);
  if (!supportsLocalProjectFolders) {
    await container.read(tabsProvider.notifier).newDocument();
    return;
  }
  final choice = await NewDocumentDialog.show(
    context,
    libraries: container.read(settingsProvider).libraries,
  );
  if (choice == null || !context.mounted) return;
  final runner =
      debugNewDocumentRunner ??
      (String? path) =>
          container.read(tabsProvider.notifier).newDocument(filePath: path);
  final created = await runner(choice.path);
  // `false` = het bestand kon niet aangemaakt worden (naamconflict dat de
  // dialoog-voorshow miste, of een schijffout). Er is dan ook geen tabblad —
  // zeg wat er mis is; de gebruiker probeert het opnieuw.
  if (!created && context.mounted) {
    showErrorSnackBar(
      ScaffoldMessenger.of(context),
      context.l10n,
      context.l10n.d('Kon het bestand niet aanmaken.'),
    );
  }
}
