// De desktophelft van de OpenKAT-import (#767). De webhelft is een lege romp:
// de scanner leest een map van schijf (dart:io), en het menu-item bestaat op
// web niet eens — weglaten, niet grijs maken.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../platform/platform_features.dart';
import '../../services/openkat/openkat_import_service.dart';
import '../../state/settings_provider.dart';
import '../../state/tabs_provider.dart';
import '../../utils/error_snackbar.dart';
import '../../utils/log.dart';

/// OpenKAT-rapportages importeren: mapkiezer → scanner → deck.
///
/// Is het actieve deck zelf een OpenKAT-deck (herkenbaar aan de
/// `ocideck_openkat_view`-markering in de notities), dan wordt dát bijgewerkt
/// — de gegenereerde dia's vernieuwd, handmatige dia's behouden. Anders opent
/// het resultaat in een nieuwe tab. De melding telt uit het manifest wat er
/// werkelijk gebeurde: geladen, en overgeslagen (dubbel, onherkend, kapot of
/// te groot) — een import die stil half slaagt is erger dan een die faalt.
///
/// [directoryOverride] slaat de mapkiezer over; dat is de testroute — de
/// statische FilePicker laat zich onder `flutter test` niet aansturen.
Future<void> importOpenKatReports(
  BuildContext context,
  WidgetRef ref, {
  String? directoryOverride,
}) async {
  // Zelfde poort als elke andere getDirectoryPath-aanroep: op web bestaat de
  // mapkiezer niet en geeft hij stil null terug (#150).
  if (!supportsLocalProjectFolders) return;
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final path =
      directoryOverride ??
      await FilePicker.getDirectoryPath(
        dialogTitle: l10n.d('Map met OpenKAT-rapportages kiezen'),
        initialDirectory: ref.read(settingsProvider).homeDirectory,
      );
  if (path == null) return;

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
      showErrorSnackBar(
        messenger,
        l10n,
        '${l10n.d('Geen OpenKAT-rapportages gevonden in deze map.')} '
        '($skipped ${l10n.d('overgeslagen')})',
      );
      return;
    }
    if (isOpenKatDeck) {
      current!.deckNotifier.loadDeck(result.deck);
    } else {
      final tabs = ref.read(tabsProvider.notifier);
      tabs.newEmptyTab();
      ref.read(tabsProvider).current!.deckNotifier.loadDeck(result.deck);
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isOpenKatDeck
              ? '${l10n.d('OpenKAT-deck bijgewerkt; handmatige dia’s zijn behouden.')} '
                    '($loaded ${l10n.d('rapportages')}, $skipped ${l10n.d('overgeslagen')})'
              : '${l10n.d('OpenKAT-rapportages geïmporteerd.')} '
                    '($loaded ${l10n.d('rapportages')}, $skipped ${l10n.d('overgeslagen')})',
        ),
      ),
    );
  } catch (e, s) {
    logError('importOpenKatReports', e, s);
    showErrorSnackBar(messenger, l10n, l10n.d('OpenKAT-import mislukt.'));
  }
}

/// Het menulabel, hier en niet in de menu-extensie: _MainLayoutState zit
/// tegen zijn klasseplafond, en dit hoort inhoudelijk bij de import.
String openKatLabel(AppLocalizations l10n) =>
    l10n.d('OpenKAT-rapportages importeren…');
