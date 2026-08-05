import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/deck.dart';
import '../../models/openkat/openkat_wizard_models.dart';
import '../../platform/platform_features.dart';
import '../../services/openkat/openkat_wizard_service.dart';
import '../../state/openkat_provider.dart';
import '../../state/openkat_wizard_controller.dart';
import '../../state/settings_provider.dart';
import '../../state/tabs_provider.dart';
import '../../widgets/dialogs/openkat_report_wizard/openkat_report_wizard.dart';
import '../../widgets/dialogs/openkat_report_wizard/openkat_wizard_steps.dart';
import '../../widgets/dialogs/openkat_installation_wizard.dart';
import '../../widgets/dialogs/openkat_server_report_dialog.dart';
import 'openkat_import_summary.dart';

/// De ene desktoproute voor menu, welkom en Instellingen.
///
/// De mapkiezer is de IO-grens. Scan, scenarioselectie en generatie lopen via
/// één controller en een injecteerbare gateway; widgets bevatten geen
/// OpenKAT-berekeningen.
Future<OpenKatImportOutcome?> importOpenKatReports(
  BuildContext context,
  WidgetRef ref, {
  String? directoryOverride,
  bool announce = true,
  OpenKatWizardGateway? gatewayOverride,
}) async {
  if (!supportsLocalProjectFolders) return null;
  final l10n = context.l10n;
  final current = ref.read(tabsProvider).current;
  final activeDeck = current?.deckNotifier.currentState.deck;
  final updating = activeDeck != null && isOpenKatGeneratedDeck(activeDeck);
  final remembered = updating && current != null
      ? ref.read(openKatProvider.notifier).sessionForDeck(current.recoveryId)
      : null;
  final controller = OpenKatWizardController(
    gateway: gatewayOverride ?? OpenKatWizardService(),
    existingDeck: updating ? activeDeck : null,
    initialRecipe:
        updating &&
            remembered != null &&
            _recipeMatchesDeck(remembered.recipe, activeDeck)
        ? remembered.recipe
        : null,
  );
  final initialDirectory =
      directoryOverride ??
      (updating ? remembered?.directory : ref.read(openKatDirectoryProvider));
  final result = await OpenKatReportWizard.show(
    context,
    controller: controller,
    initialDirectory: initialDirectory,
    chooseDirectory: () => FilePicker.getDirectoryPath(
      dialogTitle: l10n.d('Map met OpenKAT-rapportages kiezen'),
      initialDirectory:
          ref.read(openKatDirectoryProvider) ??
          ref.read(settingsProvider).homeDirectory,
    ),
    // Een keuze is nog geen geslaagde import. Pas na de bevestigde build
    // bewaren we de map, zodat annuleren of een bouwfout geen pad achterlaat.
    onDirectorySelected: (_) {},
  );
  if (result == null) return null;
  final deck = result.report.deck!;
  late final String targetDeckId;
  if (result.updated && current != null) {
    current.deckNotifier.loadDeck(deck);
    targetDeckId = current.recoveryId;
  } else {
    final tabs = ref.read(tabsProvider.notifier);
    tabs.newEmptyTab();
    final target = ref.read(tabsProvider).current!;
    target.deckNotifier.loadDeck(deck);
    targetDeckId = target.recoveryId;
  }
  final openKat = ref.read(openKatProvider.notifier);
  openKat.rememberDeckSession(
    deckId: targetDeckId,
    directory: result.scan.directory,
    recipe: result.recipe,
  );
  await openKat.setReportDirectory(result.scan.directory);
  final outcome = (
    loaded: result.usedReports,
    skipped: result.skippedReports,
    updatedDeck: result.updated,
    failed: false,
  );
  if (announce && context.mounted) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(openKatImportSummary(l10n, outcome)),
        action: SnackBarAction(
          label: l10n.d('Bekijk verslag'),
          onPressed: () => showOpenKatImportReport(context, result.scan),
        ),
      ),
    );
  }
  return outcome;
}

bool isOpenKatGeneratedDeck(Deck deck) => deck.slides.any(
  (slide) => slide.notes.contains('<!-- ocideck_openkat_view:'),
);

bool _recipeMatchesDeck(OpenKatWizardRecipe recipe, Deck deck) {
  if (recipe.scenarioId == OpenKatWizardScenarioId.portfolio) return true;
  return deck.slides.any(
    (slide) =>
        slide.notes.contains('report.${recipe.scenarioId.reportScenarioId}.'),
  );
}

bool hasActiveOpenKatReport(WidgetRef ref) {
  final deck = ref.read(tabsProvider).current?.deckNotifier.currentState.deck;
  return deck != null && isOpenKatGeneratedDeck(deck);
}

String openKatLabel(AppLocalizations l10n, {bool updating = false}) => updating
    ? l10n.d('OpenKAT-rapport bijwerken…')
    : l10n.d('OpenKAT-rapport maken…');

Future<void> showOpenKatInstallationWizard(BuildContext context) =>
    OpenKatInstallationWizard.show(context);

Future<void> showOpenKatServerReportDialog(BuildContext context) =>
    OpenKatServerReportDialog.show(context);
