// De desktophelft van de OpenKAT-import (#767). De webhelft is een lege romp:
// de scanner leest een map van schijf (dart:io), en het menu-item bestaat op
// web niet eens — weglaten, niet grijs maken.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../platform/platform_features.dart';
import '../../services/openkat/openkat_import_service.dart';
import '../../state/openkat_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/tabs_provider.dart';
import '../../utils/error_snackbar.dart';
import '../../utils/log.dart';
import 'openkat_import_summary.dart';

/// OpenKAT-rapportages importeren: mapkiezer → scanner → deck.
///
/// Is het actieve deck zelf een OpenKAT-deck (herkenbaar aan de
/// `ocideck_openkat_view`-markering in de notities), dan wordt dát bijgewerkt
/// — de gegenereerde dia's vernieuwd, handmatige dia's behouden. Anders opent
/// het resultaat in een nieuwe tab. De melding telt uit het manifest wat er
/// werkelijk gebeurde: geladen, en overgeslagen (dubbel, onherkend, kapot of
/// te groot) — een import die stil half slaagt is erger dan een die faalt.
///
/// De map komt uit Instellingen → Integraties wanneer die daar is aangewezen;
/// pas zonder die instelling verschijnt de mapkiezer. Dat is het verschil dat
/// deze actie bruikbaar maakt bij dagelijks gebruik: een OpenKAT-overzicht
/// wordt telkens opnieuw bijgewerkt uit dezelfde exportmap, en elke keer
/// dezelfde map aanwijzen is werk dat de app zelf kan onthouden.
///
/// [directoryOverride] slaat beide over; dat is de testroute — de statische
/// FilePicker laat zich onder `flutter test` niet aansturen.
///
/// Met [announce] uit blijven de meldingen achterwege en meldt de aanroeper de
/// uitkomst zelf. Dat is er voor het instellingenvenster: een snackbar achter
/// een modale dialoog is geen melding, en het venster sluiten zou de nog niet
/// opgeslagen instellingen weggooien — dus vertelt het paneel het ter plekke.
/// De teruggegeven uitkomst is `null` wanneer er niets is geprobeerd (web, of
/// de mapkiezer weggeklikt); `failed` onderscheidt een mislukte import van een
/// map waarin niets bruikbaars stond.
Future<OpenKatImportOutcome?> importOpenKatReports(
  BuildContext context,
  WidgetRef ref, {
  String? directoryOverride,
  bool announce = true,
}) async {
  // Zelfde poort als elke andere getDirectoryPath-aanroep: op web bestaat de
  // mapkiezer niet en geeft hij stil null terug (#150).
  if (!supportsLocalProjectFolders) return null;
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final path =
      directoryOverride ??
      ref.read(openKatDirectoryProvider) ??
      await FilePicker.getDirectoryPath(
        dialogTitle: l10n.d('Map met OpenKAT-rapportages kiezen'),
        initialDirectory: ref.read(settingsProvider).homeDirectory,
      );
  if (path == null) return null;

  const service = OpenKatImportService();
  final current = ref.read(tabsProvider).current;
  final activeDeck = current?.deckNotifier.currentState.deck;
  final isOpenKatDeck =
      activeDeck?.slides.any(
        (s) => s.notes.contains('<!-- ocideck_openkat_view:'),
      ) ??
      false;

  try {
    final result = isOpenKatDeck
        ? await service.updateDeck(activeDeck!, path)
        : await service.importDirectory(path);
    final loaded = result.manifest.entries
        .where((e) => e.status == 'ok')
        .length;
    final skipped = result.manifest.entries.length - loaded;
    if (loaded == 0) {
      final outcome = (
        loaded: 0,
        skipped: skipped,
        updatedDeck: false,
        failed: false,
      );
      if (announce) {
        showErrorSnackBar(messenger, l10n, openKatImportSummary(l10n, outcome));
      }
      return outcome;
    }
    if (isOpenKatDeck) {
      current!.deckNotifier.loadDeck(result.deck);
    } else {
      final tabs = ref.read(tabsProvider.notifier);
      tabs.newEmptyTab();
      ref.read(tabsProvider).current!.deckNotifier.loadDeck(result.deck);
    }
    final outcome = (
      loaded: loaded,
      skipped: skipped,
      updatedDeck: isOpenKatDeck,
      failed: false,
    );
    if (announce) {
      messenger.showSnackBar(
        SnackBar(content: Text(openKatImportSummary(l10n, outcome))),
      );
    }
    return outcome;
  } catch (e, s) {
    logError('importOpenKatReports', e, s);
    const outcome = (loaded: 0, skipped: 0, updatedDeck: false, failed: true);
    if (announce) {
      showErrorSnackBar(messenger, l10n, openKatImportSummary(l10n, outcome));
    }
    return outcome;
  }
}

/// Het menulabel, hier en niet in de menu-extensie: _MainLayoutState zit
/// tegen zijn klasseplafond, en dit hoort inhoudelijk bij de import.
String openKatLabel(AppLocalizations l10n) =>
    l10n.d('OpenKAT-rapportages importeren…');
