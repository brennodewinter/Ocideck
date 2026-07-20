import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../platform/launch_files.dart';
import '../platform/platform_features.dart';
import '../utils/display_path.dart';
import '../utils/log.dart';
import '../models/deck.dart';
import '../models/privacy_disposition.dart';
import '../models/recent_file.dart';
import '../models/settings.dart' show AppSettings;
import '../models/slide.dart';
import '../models/used_tool.dart';
import '../models/slide_quality.dart';
import '../models/storage_connection.dart';
import '../models/webdav_settings.dart';
import '../models/s3_settings.dart';
import '../models/storage_origin.dart';
import '../services/audit_dossier.dart';
import '../services/caption_service.dart';
import '../services/description_service.dart';
import '../services/classification_enforcement_policy.dart';
import '../services/finding_context_score.dart';
import '../services/finding_pagination.dart';
import '../services/evidence_hash_service.dart';
import '../services/management_summary.dart';
import '../services/scope_coverage.dart';
import '../services/classification_policy.dart';
import '../services/document_integrity.dart';
import '../services/export_readiness.dart';
import '../services/open_file_channel.dart';
import '../services/export_service.dart';
import '../services/file_service.dart';
import '../services/image_service.dart';
import '../services/privacy/privacy_export_policy.dart';
import '../services/privacy/privacy_own_identity.dart';
import '../services/export_bundle.dart';
import '../services/privacy/privacy_projection.dart';
import '../services/privacy/privacy_scanner.dart';
import '../services/privacy/redaction_manifest_service.dart';
import '../services/web_asset_store.dart';
import '../services/quality_export_policy.dart';
import '../services/recovery_service.dart';
import '../services/mermaid_render_service.dart';
import '../models/git_settings.dart';
import '../services/git/asset_index.dart';
import '../services/git/deck_merge.dart';
import '../services/git/deck_search.dart';
import '../services/git/git_forge.dart';
import '../services/git/version_diff.dart';
import '../services/git/native_git_mirror_api.dart';
import '../services/s3/s3_service.dart';
import '../services/webdav_service.dart';
import '../state/deck_provider.dart';
import '../state/deck_quality_provider.dart';
import '../state/image_contrast_provider.dart';
import '../state/image_privacy_provider.dart';
import '../state/privacy_provider.dart';
import '../state/provider_warmup.dart';
import '../state/info_safety_provider.dart';
import '../state/editor_provider.dart';
import '../state/settings_provider.dart';
import '../state/tabs_provider.dart';
import '../state/git_provider.dart';
import '../state/s3_provider.dart';
import '../state/webdav_provider.dart';
import '../utils/project_path.dart';
import '../utils/error_snackbar.dart';
import '../utils/user_facing_error.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../l10n/slide_quality_localization.dart';
import 'dialogs/command_palette.dart';
import 'dialogs/duplicate_cleanup_dialog.dart';
import 'dialogs/management_summary_dialog.dart';
import 'dialogs/miauw_compliance_panel.dart';
import 'dialogs/scope_coverage_dialog.dart';
import 'dialogs/slide_diff_dialog.dart';
import 'dialogs/export_dialog.dart';
import 'dialogs/finalize_seal_dialog.dart';
import 'dialogs/find_replace_dialog.dart';
import 'dialogs/image_carousel_picker.dart';
import 'dialogs/import_security_alarm_dialog.dart';
import 'dialogs/new_deck_dialog.dart';
import 'dialogs/open_presentation_dialog.dart';
import 'dialogs/package_encrypt_dialog.dart';
import 'dialogs/package_password_dialog.dart';
import 'dialogs/presentation_info_dialog.dart';
import 'dialogs/save_destination_dialog.dart';
import 'dialogs/scan_library_dialog.dart';
import 'dialogs/seal_timestamp_dialog.dart';
import 'dialogs/settings_dialog.dart';
import 'dialogs/git_browser_dialog.dart';
import 'dialogs/storage_connection_picker.dart';
import 'dialogs/s3_browser_dialog.dart';
import 'dialogs/webdav_browser_dialog.dart';
import '../services/trash_service.dart';
import 'panels/editor_panel.dart';
import 'panels/preview_panel.dart';
import 'panels/slide_list_panel.dart';
import 'privacy_badge.dart';
import 'presentation/fullscreen_presenter.dart';
import 'slides/slide_preview.dart';

part 'app_shell_main_layout.dart';
part 'app_shell_menu.dart';

// ── Shared helpers ──────────────────────────────────────────────────────────

// Shell sub-widgets and helpers, split into part files for navigability.
// These parts share this library's imports and private scope.
part 'shell/shell_actions.dart';
part 'shell/shell_actions_connections.dart';
part 'shell/shell_actions_s3.dart';
part 'shell/shell_actions_git.dart';
part 'shell/shell_actions_git_dialogs.dart';
part 'shell/shell_actions_git_assets.dart';
part 'shell/shell_actions_git_search.dart';
part 'shell/ai_actions.dart';
part 'shell/command_palette_actions.dart';
part 'shell/tab_bar.dart';
part 'shell/welcome_screen.dart';
part 'shell/play_only_screen.dart';
part 'shell/status_bar.dart';
part 'shell/shell_overlays.dart';

/// Keuze uit de "niet-opgeslagen wijzigingen"-dialoog bij het sluiten.
enum _CloseChoice { cancel, discard, save }

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WindowListener {
  late final OpenFileChannel _openFileChannel;

  /// Het tabblad waar de zichtbare Informatieveiligheid-melding bij hoort, of
  /// null als er geen staat. De melding is niet zomaar een mededeling maar een
  /// uitspraak over déze presentatie, dus hij mag een tabwissel of het sluiten
  /// van het deck niet overleven — dan gaat hij namelijk over iets anders dan
  /// wat de gebruiker ziet. Zie [_syncSecurityBannerWithTabs].
  int? _securityPromptTabId;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // Warm up the Informatieveiligheid-module state at shell startup so that by
    // the time a deck is opened its `loading` flag has cleared. Without this the
    // very first security-deck open would read the still-loading module and skip
    // the discovery prompt (which only ever appears when the module is known
    // off). See the [securityModulePromptProvider] listener in [build].
    ref.read(infoSafetyProvider);
    _openFileChannel = OpenFileChannel(_onFilesDropped);
    // De TabsNotifier kent geen BuildContext; de shell levert de dialoog die
    // om het wachtwoord van een versleuteld pakket vraagt (met retry-melding).
    ref
        .read(tabsProvider.notifier)
        .packagePasswordResolver = ({required bool retry}) async {
      if (!mounted) return null;
      return PackagePasswordDialog.show(context, retry: retry);
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeRestore();
      // Open any file the app was launched with, and start listening for files
      // opened from Finder while the app is running.
      _openFileChannel.start();
      // Windows/Linux: bestandsassociatie-argumenten van deze start.
      _openLaunchFiles();
      // Web: ?deck=<url>-deeplink die OciDeck én een presentatie tegelijk
      // opent (zelfde security-gate als de importdialoog).
      _openDeckDeepLink();
    });
  }

  /// Open de bestanden waarmee de app via commandoregel-argumenten is gestart
  /// (Windows/Linux-bestandsassociaties; zie [pendingLaunchFiles]).
  Future<void> _openLaunchFiles() async {
    if (pendingLaunchFiles.isEmpty) return;
    final paths = List<String>.from(pendingLaunchFiles);
    pendingLaunchFiles.clear();
    await _onFilesDropped(paths);
  }

  /// Web-deeplink: `?deck=<url>` haalt de presentatie op en opent haar —
  /// één link deelt zo de app én de inhoud. De volledige importpoort
  /// (CORS/hulppunt, veiligheidsscan met alarm, marp-controle) blijft gelden.
  Future<void> _openDeckDeepLink() async {
    if (!isWebPlatform || !mounted) return;
    final deckUrl = deckDeepLinkFrom(Uri.base);
    if (deckUrl == null) return;
    await _importUrlWeb(context, ref, deckUrl);
  }

  /// Bij opstart: zijn er herstelbestanden van een vorige (gecrashte) sessie?
  Future<void> _maybeRestore() async {
    final recovery = ref.read(recoveryServiceProvider);
    final snapshots = await recovery.loadAll();
    if (snapshots.isEmpty || !mounted) return;

    final restore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final l10n = ctx.l10n;
        return AlertDialog(
          title: Text(l10n.d('Niet-opgeslagen werk herstellen?')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                snapshots.length == 1
                    ? l10n.d(
                        'Er is een presentatie met niet-opgeslagen wijzigingen gevonden van een vorige sessie:',
                      )
                    : '${l10n.d('Er zijn')} ${snapshots.length} ${l10n.d('presentaties met niet-opgeslagen wijzigingen gevonden van een vorige sessie:')}',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              // Scrollbaar en begrensd: bij veel snapshots mag de lijst de
              // dialoogknoppen niet uit beeld drukken.
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final s in snapshots)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            '•  ${s.label}  ·  ${_formatWhen(s.savedAt)}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.slate600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.d('Verwijderen')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.d('Herstellen')),
            ),
          ],
        );
      },
    );

    if (restore == true) {
      ref.read(tabsProvider.notifier).restoreRecovered(snapshots);
    } else {
      await recovery.clearAll();
    }
  }

  String _formatWhen(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}-${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (ref.read(tabsProvider).anyDirty) {
      final choice = await _confirmSaveBeforeClose(
        context.l10n.d(
          'Er zijn presentaties met niet-opgeslagen wijzigingen. Sla ze op voordat de app sluit.',
        ),
      );
      switch (choice) {
        case _CloseChoice.cancel:
          return;
        case _CloseChoice.discard:
          // Wijzigingen verwerpen: herstelbestanden weg, niets opslaan.
          await _destroy();
        case _CloseChoice.save:
          final saved = await _saveAllDirtyTabs();
          if (saved) await _destroy();
      }
    } else {
      await _destroy();
    }
  }

  /// Nette afsluiting: herstelbestanden opruimen (alles is opgeslagen) en sluiten.
  Future<void> _destroy() async {
    await ref.read(recoveryServiceProvider).clearAll();
    await windowManager.destroy();
  }

  Future<_CloseChoice> _confirmSaveBeforeClose(String message) =>
      _confirmSaveBeforeCloseDialog(context, message);

  Future<bool> _saveAllDirtyTabs() async {
    for (final tab in ref.read(tabsProvider).tabs) {
      if (!tab.isDirty) continue;
      final saved = await saveDeckWithDestination(
        context,
        ref,
        tab.deckNotifier,
      );
      if (!saved) return false;
    }
    return true;
  }

  Future<void> _onCloseTab(int index) => requestCloseTab(context, ref, index);

  /// Sla het actieve tabblad op. App-breed zodat Ctrl/Cmd+S altijd werkt,
  /// ongeacht waar de focus zit.
  void _saveActive() {
    final tab = ref.read(tabsProvider).current;
    if (tab != null) saveDeckWithDestination(context, ref, tab.deckNotifier);
  }

  /// Open een presentatie via de zoek-/kies-dialoog. App-breed zodat Ctrl/Cmd+O
  /// altijd werkt, ongeacht waar de focus zit.
  void _openActive() {
    _openWithSearch(context, ref);
  }

  bool _dragging = false;

  static const _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
    '.heic',
    '.tiff',
    '.tif',
  };

  /// Drag-drop op web: er is geen pad, alleen inhoud. Een `.md` of
  /// `.ocideck`-pakket wordt via het in-memory pad geopend (zelfde
  /// security-gate; pakketten worden in het geheugen uitgepakt);
  /// afbeeldingen gaan na dezelfde validatie als pickImage de WebAssetStore
  /// in en worden slides met een mem:-pad. Overige typen worden — net als op
  /// desktop — genegeerd.
  Future<void> _onWebFilesDropped(List<DropItem> files) async {
    final tabs = ref.read(tabsProvider.notifier);
    final images = <String>[];
    for (final file in files) {
      final ext = p.extension(file.name.toLowerCase());
      if (ext == '.md' || ext == '.ocideck' || ext == '.zip') {
        final bytes = await file.readAsBytes();
        await tabs.openDeckFromBytes(bytes, file.name);
      } else if (_imageExtensions.contains(ext)) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty ||
            bytes.length > ImageService.maxImageBytes ||
            !ImageService.looksLikeImage(bytes)) {
          logWarning(
            'AppShell._onWebFilesDropped: afbeelding geweigerd '
            '(te groot of geen afbeelding)',
            file.name,
          );
          continue;
        }
        images.add(WebAssetStore.put(bytes, name: file.name));
      }
    }
    if (images.isNotEmpty) _addImagesToActiveDeck(images);
  }

  /// Verwerk gesleepte bestanden: presentaties/pakketten openen, afbeeldingen
  /// als nieuwe slide(s) toevoegen aan het actieve deck.
  Future<void> _onFilesDropped(List<String> paths) async {
    final homeDir = ref.read(settingsProvider).homeDirectory;
    final tabs = ref.read(tabsProvider.notifier);
    final images = <String>[];
    for (final path in paths) {
      final ext = p.extension(path).toLowerCase();
      if (ext == '.md') {
        await tabs.openFileByPath(path);
      } else if (ext == '.ocideck' || ext == '.zip') {
        final failure = await tabs.importPackageFile(path, homeDir: homeDir);
        if (failure != null && mounted) {
          showErrorSnackBar(
            ScaffoldMessenger.of(context),
            context.l10n,
            importFailureMessage(context.l10n, failure),
          );
        }
      } else if (_imageExtensions.contains(ext)) {
        final adopted = await _adoptDroppedImage(path);
        if (adopted != null) images.add(adopted);
      }
    }
    if (images.isNotEmpty) _addImagesToActiveDeck(images);
  }

  /// Neem een gesleepte afbeelding op in het deck in plaats van naar de plek op
  /// schijf te blijven wijzen: die plek heeft de volgende lezer niet.
  ///
  /// Valideert eerst op magic bytes, net als de bestandskiezer en de
  /// webvariant hierboven — de extensie van een gesleept bestand is niet meer
  /// dan een bewering. Lukt het kopiëren niet, dan gaat het bronpad alsnog mee:
  /// een zichtbare afbeelding met een waarschuwingsbadge is beter dan een
  /// slide die stil leeg blijft.
  Future<String?> _adoptDroppedImage(String path) async {
    final service = ref.read(imageServiceProvider);
    if (!await service.isAcceptableImageFile(path)) {
      logWarning(
        'AppShell._onFilesDropped: afbeelding geweigerd '
        '(te groot of geen afbeelding)',
        path,
      );
      return null;
    }
    final projectPath = ref
        .read(tabsProvider)
        .current
        ?.deckNotifier
        .currentState
        .deck
        ?.projectPath;
    return service.importIntoDeck(path, projectPath: projectPath);
  }

  void _addImagesToActiveDeck(List<String> paths) {
    final tab = ref.read(tabsProvider).current;
    if (tab == null || !tab.isOpen) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.d(
                'Open eerst een presentatie om afbeeldingen toe te voegen.',
              ),
            ),
          ),
        );
      }
      return;
    }
    final deckN = tab.deckNotifier;
    final editorN = tab.editorNotifier;
    var idx = editorN.currentState.selectedIndex;
    for (final path in paths) {
      deckN.addSlide(SlideType.image, afterIndex: idx);
      idx += 1;
      deckN.updateSlide(
        idx,
        Slide.create(SlideType.image).copyWith(imagePath: path),
      );
    }
    editorN.select(idx);
  }

  /// Eén tab-paneel, met alle providers die het deck lezen per tab opnieuw
  /// gescoped.
  ///
  /// Alles wat het deck leest hoort in deze `overrides` te staan. Een afgeleide
  /// provider die ontbreekt, lost op in de root-container, ziet een leeg deck en
  /// doet stilletjes niets — geen fout, geen melding, gewoon niets. Zo ging
  /// `imageContrastIssuesProvider` ooit stuk. `provider_scope_test.dart` scant
  /// `lib/state` en faalt als er hier een mist.
  Widget _tabScope(TabInfo tab) => ProviderScope(
    key: ValueKey(tab.id),
    overrides: [
      deckProvider.overrideWith((ref) => tab.deckNotifier),
      editorProvider.overrideWith((ref) => tab.editorNotifier),
      deckQualityRawProvider.overrideWith(computeDeckQualityRaw),
      deckQualityProvider.overrideWith(computeDeckQuality),
      imageContrastIssuesProvider.overrideWith(computeImageContrastIssues),
      privacyRawScanProvider.overrideWith(computePrivacyRawScan),
      imagePrivacyIssuesProvider.overrideWith(computeImagePrivacyIssues),
      privacyScanProvider.overrideWith(computePrivacyScan),
      privacyQualityIssuesProvider.overrideWith(computePrivacyQualityIssues),
      privacyExportSummaryProvider.overrideWith(computePrivacyExportSummary),
    ],
    child: const _TabContent(),
  );

  /// Een grafiek verwijst naar een databestand dat niet gelezen kon worden:
  /// ontbrekend, onleesbaar, of buiten de projectmap.
  ///
  /// Melden is hier het hele punt. Zo'n grafiek tekent leeg, en een lege
  /// grafiek is niet te onderscheiden van een grafiek waar nog geen cijfers in
  /// staan — zonder deze melding is het probleem dus onzichtbaar.
  void _listenChartDataWarning(BuildContext context, WidgetRef ref) {
    ref.listen<ChartDataWarning?>(chartDataWarningProvider, (_, warning) {
      if (warning == null) return;
      ref.read(chartDataWarningProvider.notifier).state = null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            '${context.l10n.d('Grafiekdata kon niet worden gelezen; die grafieken blijven leeg:')} '
            '${warning.sources.join(', ')}',
          ),
        ),
      );
    });
  }

  /// Een zojuist geopende presentatie bevat Informatieveiligheid-slidetypes
  /// terwijl de module uit staat: bied aan de module aan te zetten (puur
  /// discovery — de slides renderen sowieso gewoon, MODUS-REGEL). De state-laag
  /// seint dit alleen bij het OPENEN; edits raken dit pad nooit, dus de melding
  /// komt precies één keer per open. De module-stand toetsen we hier, op het
  /// verse moment: nog aan het laden of al aan → niets tonen.
  ///
  /// Bewust een [MaterialBanner] en geen snackbar: de gebruiker heeft hier drie
  /// antwoorden — eerst kijken, aanzetten, of wegklikken — en een snackbar
  /// draagt er maar één. Hij verdwijnt ook niet vanzelf na een paar tellen,
  /// want een aanbod dat wegtikt terwijl je nog aan het kijken bent is geen
  /// aanbod. Wegblijven doet hij op precies twee manieren: de gebruiker kiest
  /// iets, of de presentatie waar het over gaat verdwijnt uit beeld.
  void _listenSecurityModulePrompt(BuildContext context) {
    ref.listen<SecurityModulePrompt?>(securityModulePromptProvider, (
      _,
      prompt,
    ) {
      if (prompt == null) return;
      ref.read(securityModulePromptProvider.notifier).state = null;
      final sec = ref.read(infoSafetyProvider);
      if (sec.loading || sec.enabled) return;
      final l10n = context.l10n;
      final messenger = ScaffoldMessenger.of(context);
      // Een tweede open zet de vorige balk opzij in plaats van erachter in de
      // rij: die ging over een presentatie die niet meer voorgrond is.
      messenger.hideCurrentMaterialBanner();
      _securityPromptTabId = prompt.tabId;
      messenger.showMaterialBanner(
        MaterialBanner(
          content: Text(
            l10n.d(
              'Deze presentatie bevat onderdelen van de Informatieveiligheidsmodule. Zet de module aan om ze te bewerken.',
            ),
          ),
          actions: [
            // Sluit de melding niet: je gaat kijken om te beslissen, dus het
            // aanbod moet er nog staan als je terugkomt.
            TextButton(
              onPressed: _showSecuritySlide,
              child: Text(l10n.d('Naar de slide')),
            ),
            TextButton(
              onPressed: () {
                _hideSecurityBanner();
                ref.read(infoSafetyProvider.notifier).enable();
              },
              child: Text(l10n.d('Inschakelen')),
            ),
            IconButton(
              tooltip: l10n.d('Sluiten'),
              icon: const Icon(Icons.close),
              onPressed: _hideSecurityBanner,
            ),
          ],
        ),
      );
    });
  }

  /// Spring naar de eerste Informatieveiligheid-slide, zodat de gebruiker de
  /// bewering van de melding kan controleren vóórdat hij de module aanzet.
  /// Alleen als het bijbehorende tabblad nog vóór staat — anders zou de sprong
  /// in een andere presentatie landen.
  ///
  /// De index wordt hier opnieuw uit het deck gelezen en niet bij het openen
  /// onthouden: tussen de melding en de klik kan de gebruiker slides hebben
  /// verwijderd of verplaatst, en dan wijst een oude index de verkeerde slide
  /// aan.
  void _showSecuritySlide() {
    final tab = ref.read(tabsProvider).current;
    if (tab == null || tab.id != _securityPromptTabId) return;
    if (!tab.deckNotifier.mounted) return;
    final index =
        tab.deckNotifier.currentState.deck?.firstSecuritySlideIndex ?? -1;
    if (index < 0) return;
    tab.editorNotifier.select(index);
  }

  void _hideSecurityBanner() {
    if (_securityPromptTabId == null) return;
    _securityPromptTabId = null;
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
  }

  /// Haal de melding weg zodra ze niet meer waar is. Dat gebeurt op twee
  /// manieren, en allebei laten ze een blijvende balk iets beweren dat niet
  /// klopt:
  ///
  /// 1. De presentatie staat niet meer vóór — een andere tab gekozen, het
  ///    tabblad gesloten, of het deck dichtgeklapt. De balk zou dan over de
  ///    volgende presentatie hangen.
  /// 2. De laatste Informatieveiligheid-slide is weggehaald. De balk zegt dat
  ///    deze presentatie module-onderdelen bevat; verwijder je ze, dan is dat
  ///    simpelweg niet meer zo, en biedt hij aan iets aan te zetten waar niets
  ///    meer voor te bewerken valt.
  ///
  /// Dit draait op elke wijziging van [tabsProvider], en die volgt ook de
  /// deck-stream — een verwijderde slide komt hier dus vanzelf langs.
  void _syncSecurityBannerWithTabs(TabsState tabs) {
    if (_securityPromptTabId == null) return;
    final current = tabs.current;
    if (current == null ||
        current.id != _securityPromptTabId ||
        !current.isOpen ||
        !current.deckNotifier.mounted) {
      _hideSecurityBanner();
      return;
    }
    final deck = current.deckNotifier.currentState.deck;
    if (deck == null || !deck.hasSecuritySlides) _hideSecurityBanner();
  }

  @override
  Widget build(BuildContext context) {
    final tabsState = ref.watch(tabsProvider);
    ref.listen<TabsState>(tabsProvider, (_, next) {
      _syncSecurityBannerWithTabs(next);
    });

    // A blocked import (executable content) raises the alarm from the state
    // layer; show it here so it covers every entry point (open, recent,
    // drag-drop, URL/package import) with one listener, then clear it.
    ref.listen<ImportSecurityAlarm?>(importSecurityAlarmProvider, (_, alarm) {
      if (alarm == null) return;
      ImportSecurityAlarmDialog.show(context, alarm);
      ref.read(importSecurityAlarmProvider.notifier).state = null;
    });

    // Een instelling kon niet naar schijf worden weggeschreven: niet-blokkerend
    // melden. De wijziging geldt wel voor deze sessie (de state is al
    // bijgewerkt), maar ging mogelijk verloren voor de volgende start.
    ref.listen(settingsPersistErrorProvider, (_, next) {
      if (!next.hasValue) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.d('Instelling opslaan is mislukt.')),
        ),
      );
    });

    // Een geheim kon niet in de sleutelhanger worden bewaard. Apart van de
    // melding hierboven, want hier komt de fout later terug vermomd als een
    // afgewezen wachtwoord — zeg er daarom bij wat er straks gebeurt.
    ref.listen(settingsSecretErrorProvider, (_, next) {
      if (!next.hasValue) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.d(
              'Opslaan in de sleutelhanger is mislukt. De verbinding blijft om je wachtwoord vragen tot dit lukt.',
            ),
          ),
        ),
      );
    });

    _listenSecurityModulePrompt(context);

    _listenChartDataWarning(context, ref);

    // Een zojuist geopend bestand heeft elders een byte-identieke kopie:
    // niet-blokkerend melden (de gebruiker wilde gewoon openen), met de
    // opruimdialoog als directe ingang.
    ref.listen<DuplicateCopyNotice?>(duplicateCopyNoticeProvider, (_, notice) {
      if (notice == null) return;
      ref.read(duplicateCopyNoticeProvider.notifier).state = null;
      final l10n = context.l10n;
      final homeDir = ref.read(settingsProvider).homeDirectory;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 7),
          content: Text(
            '${l10n.d('Deze presentatie staat ook op een andere plek:')} '
            '${displayFolder(notice.copyPath, homeDir: homeDir, osHome: osHomeDirectory)}',
          ),
          action: TrashService().isSupported
              ? SnackBarAction(
                  label: l10n.d('Opruimen…'),
                  onPressed: () => DuplicateCleanupDialog.show(
                    context,
                    groups: [
                      CleanupGroup(
                        title: p.basenameWithoutExtension(notice.openedPath),
                        paths: [notice.openedPath, notice.copyPath],
                      ),
                    ],
                    homeDir: homeDir,
                  ),
                )
              : null,
        ),
      );
    });

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _saveActive,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _saveActive,
        const SingleActivator(LogicalKeyboardKey.keyO, control: true):
            _openActive,
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true): _openActive,
      },
      child: FocusScope(
        autofocus: true,
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (detail) {
            setState(() => _dragging = false);
            if (isWebPlatform) {
              _onWebFilesDropped(detail.files);
            } else {
              _onFilesDropped(detail.files.map((f) => f.path).toList());
            }
          },
          child: Material(
            child: Stack(
              children: [
                Column(
                  children: [
                    _AppTabBar(
                      tabsState: tabsState,
                      onSelect: (i) =>
                          ref.read(tabsProvider.notifier).selectTab(i),
                      onClose: _onCloseTab,
                      onAdd: () =>
                          ref.read(tabsProvider.notifier).newEmptyTab(),
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: tabsState.clampedIndex,
                        children: [
                          for (final tab in tabsState.tabs) _tabScope(tab),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_dragging) const _DropOverlay(),
                const MermaidRenderHostLayer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
