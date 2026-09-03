import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateController;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../l10n/export_block_localization.dart';
import '../platform/launch_files.dart';
import '../platform/native_window.dart' show setWillCloseCallback, quitApp;
import '../platform/native_shortcut_channel.dart';
import '../platform/platform_features.dart';
import '../platform/unsaved_work_guard.dart';
import '../utils/display_path.dart';
import '../utils/image_search_paths.dart';
import '../utils/log.dart';
import '../utils/physical_control_shortcut.dart';
import '../utils/safe_filename.dart';
import '../utils/shortcut_label.dart';
import '../models/asset_origin.dart';
import '../models/deck.dart';
import '../models/improvement_y01.dart';
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
import '../services/markdown_service.dart';
import '../services/evidence_hash_service.dart';
import '../services/management_summary.dart';
import '../services/scope_coverage.dart';
import '../services/classification_policy.dart';
import '../services/document_deck_bridge.dart';
import '../services/document_integrity.dart';
import '../services/download_delivery.dart';
import '../services/export_metadata.dart' show kOciDeckVersion;
import '../services/export_readiness.dart';
import '../services/open_file_channel.dart';
import '../services/export_service.dart';
import '../services/file_service.dart';
import '../services/template_content_service.dart';
import '../services/image_service.dart';
import '../services/privacy/privacy_export_policy.dart';
import '../services/privacy/privacy_own_identity.dart';
import '../services/export_bundle.dart';
import '../services/privacy/privacy_projection.dart';
import '../services/image_usage.dart';
import '../services/quality_export_policy.dart';
import '../services/recovery_service.dart';
import 'mermaid_render_host.dart';
import '../models/git_settings.dart';
import '../services/git/asset_index.dart';
import '../services/git/asset_rights_index.dart';
import '../services/git/deck_merge.dart';
import '../services/git/deck_search.dart';
import '../services/git/git_cli.dart';
import '../services/git/git_forge.dart';
import '../services/git/version_diff.dart';
import '../services/git/native_git_mirror_api.dart';
import '../services/s3/s3_service.dart';
import '../services/webdav_service.dart';
import '../state/collab_session_provider.dart';
import '../state/deck_provider.dart';
import '../state/deck_quality_provider.dart';
import '../state/document_provider.dart';
import 'document_editor_screen.dart';
import '../state/image_contrast_provider.dart';
import '../state/image_privacy_provider.dart';
import '../state/improvement_provider.dart';
import '../state/collaboration_provider.dart';
import '../state/matrix_client_provider.dart';
import '../state/secret_store_provider.dart';
import '../state/theme_logo_provider.dart';
import '../collab/collab_device_store.dart';
import '../services/provenance_service.dart';
import '../state/privacy_provider.dart';
import '../state/provider_warmup.dart';
import '../state/save_progress_provider.dart';
import '../state/info_safety_provider.dart';
import '../state/import_module_provider.dart';
import '../state/openkat_provider.dart';
import '../state/asset_rights_module_provider.dart';
import '../state/procesverbetering_provider.dart';
import '../state/editor_provider.dart';
import '../state/settings_provider.dart';
import '../state/tabs_provider.dart';
import '../state/git_provider.dart';
import '../state/s3_provider.dart';
import '../state/webdav_provider.dart';
import '../utils/project_path.dart';
import '../utils/error_snackbar.dart';
import '../utils/url_launcher_util.dart';
import '../utils/user_facing_error.dart';
import '../theme/app_theme.dart';
import '../theme/brand_logo.dart';
import '../l10n/app_localizations.dart';
import '../l10n/slide_quality_localization.dart';
import 'dialogs/asset_usage_dialog.dart';
import 'dialogs/asset_rights_dialog.dart';
import 'dialogs/command_palette.dart';
import 'editors/markdown_editor_field.dart';
import 'dialogs/duplicate_cleanup_dialog.dart';
import 'dialogs/management_summary_dialog.dart';
import 'dialogs/miauw_compliance_panel.dart';
import 'dialogs/scope_coverage_dialog.dart';
import 'dialogs/slide_diff_dialog.dart';
import 'dialogs/convert_to_document_dialog.dart';
import 'dialogs/export_dialog.dart';
import 'dialogs/export_failure_text.dart';
import 'dialogs/finalize_seal_dialog.dart';
import 'dialogs/git_search_dialog.dart';
import 'dialogs/find_replace_dialog.dart';
import 'dialogs/image_carousel_picker.dart';
import 'dialogs/import_security_alarm_dialog.dart';
import 'dialogs/new_deck_dialog.dart';
import 'dialogs/improvement_project_setup_dialog.dart';
import 'dialogs/open_kind_chrome.dart';
import 'dialogs/open_presentation_dialog.dart';
import 'dialogs/matrix_collab_dialogs.dart';
import 'dialogs/package_encrypt_dialog.dart';
import 'dialogs/package_password_dialog.dart';
import 'dialogs/proxy_fallback_dialog.dart';
import 'dialogs/presentation_info_dialog.dart';
import 'reader/document_reader_screen.dart';
import 'shell/app_menu_bar.dart';
import 'shell/shell_deck_commands.dart';
import 'dialogs/save_destination_dialog.dart';
import 'dialogs/scan_library_dialog.dart';
import 'dialogs/seal_timestamp_dialog.dart';
import 'dialogs/settings_dialog.dart';
import 'dialogs/git_browser_dialog.dart';
import 'dialogs/storage_connection_picker.dart';
import 'dialogs/s3_browser_dialog.dart';
import 'dialogs/webdav_browser_dialog.dart';
import '../services/trash_service.dart';
import 'shell/document_save_actions.dart';
import 'shell/openkat_import_action.dart';
import 'shell/presentation_import_action.dart';
import 'panels/editor_panel.dart';
import 'panels/preview_panel.dart';
import 'panels/collab_chat_panel.dart';
import 'panels/call_panel.dart';
import 'panels/slide_list_panel.dart';
import 'privacy_badge.dart';
import 'collab_verify_banner.dart';
import 'presentation/fullscreen_presenter.dart';
import 'presentation/session_export.dart';
import 'slides/slide_preview.dart';

part 'app_shell_main_layout.dart';
part 'app_shell_menu.dart';

// ── Shared helpers ──────────────────────────────────────────────────────────

// Shell sub-widgets and helpers, split into part files for navigability; the parts share this library's imports and private scope.
part 'shell/provenance_actions.dart';
part 'shell/shell_actions.dart';
part 'shell/shell_actions_present.dart';
part 'shell/shell_actions_export.dart';
part 'shell/shell_actions_connections.dart';
part 'shell/shell_actions_s3.dart';
part 'shell/shell_actions_git.dart';
part 'shell/shell_actions_git_dialogs.dart';
part 'shell/ai_actions.dart';
part 'shell/command_palette_actions.dart';
part 'shell/main_layout_shortcuts.dart';
part 'shell/menu_commands.dart';
part 'shell/module_prompts.dart';
part 'shell/tab_bar.dart';
part 'shell/welcome_screen.dart';
part 'shell/welcome_screen_chrome.dart';
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

class _AppShellState extends ConsumerState<AppShell> {
  late final OpenFileChannel _openFileChannel;
  late final NativeShortcutChannel _nativeShortcuts;

  /// Het tabblad waar de zichtbare Informatieveiligheid-melding bij hoort, of
  /// null als er geen staat. De melding is niet zomaar een mededeling maar een
  /// uitspraak over déze presentatie, dus hij mag een tabwissel of het sluiten
  /// van het deck niet overleven — dan gaat hij namelijk over iets anders dan
  /// wat de gebruiker ziet. Zie [_syncSecurityBannerWithTabs].
  int? _securityPromptTabId;

  /// Same role as [_securityPromptTabId] for the Procesverbetering discovery
  /// banner (PROCESS_IMPROVEMENT.md Phase 0).
  int? _improvementPromptTabId;

  @override
  void initState() {
    super.initState();
    setWillCloseCallback(_onWillClose);
    _nativeShortcuts = NativeShortcutChannel(
      () => _requestDocumentFind(showReplace: true),
    )..start();
    // Warm up the Informatieveiligheid-module state at shell startup so that by
    // the time a deck is opened its `loading` flag has cleared. Without this the
    // very first security-deck open would read the still-loading module and skip
    // the discovery prompt (which only ever appears when the module is known
    // off). See the [securityModulePromptProvider] listener in [build].
    ref.read(infoSafetyProvider);
    ref.read(procesverbeteringProvider);
    _openFileChannel = OpenFileChannel(_onFilesDropped);
    // De TabsNotifier kent geen BuildContext; de shell levert de dialoog die
    // om het wachtwoord van een versleuteld pakket vraagt (met retry-melding).
    ref
        .read(tabsProvider.notifier)
        .packagePasswordResolver = ({required bool retry}) async {
      if (!mounted) return null;
      return PackagePasswordDialog.show(context, retry: retry);
    };
    // Idem voor de vraag of de web-import de URL aan het eigen fetch-hulppunt
    // mag doorgeven. Zonder deze registratie vervalt die terugval.
    ref
        .read(tabsProvider.notifier)
        .proxyFallbackConfirm = ({required String host}) async {
      if (!mounted) return false;
      return ProxyFallbackDialog.show(context, host: host);
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
                // Enkelvoud noemt de soort (presentatie of document); meervoud
                // is neutraal ("bestanden") omdat er beide soorten in kunnen
                // zitten. Eén string met een plaatshouder, niet drie stukken
                // met het getal ertussen — dat legde de Nederlandse woordvolgorde
                // op aan 31 talen (#1614).
                snapshots.length == 1
                    ? (snapshots.single.kind.isDocument
                          ? l10n.d(
                              'Er is een document met niet-opgeslagen wijzigingen gevonden van een vorige sessie:',
                            )
                          : l10n.d(
                              'Er is een presentatie met niet-opgeslagen wijzigingen gevonden van een vorige sessie:',
                            ))
                    : l10n
                          .d(
                            'Er zijn {n} bestanden met niet-opgeslagen wijzigingen gevonden van een vorige sessie:',
                          )
                          .replaceAll('{n}', snapshots.length.toString()),
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
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                markdownKindIcon(s.kind),
                                size: 14,
                                color: AppTheme.slate600,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${s.label}  ·  ${_formatWhen(s.savedAt)}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppTheme.slate600,
                                ),
                              ),
                            ],
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
      final unreadable = ref
          .read(tabsProvider.notifier)
          .restoreRecovered(snapshots);
      // Zwijgen bij een mislukking is hier het ergst denkbare: de gebruiker
      // klikt "Herstellen", ziet een leeg tabblad, en concludeert dat het werk
      // weg is. Het staat er nog — dat hoort hij te horen.
      if (unreadable > 0 && mounted) {
        final l10n = context.l10n;
        showErrorSnackBar(
          ScaffoldMessenger.of(context),
          l10n,
          l10n.d(
            'Niet alles kon worden hersteld. Wat onleesbaar was, is bewaard gebleven.',
          ),
        );
      }
    } else {
      // Alleen wat zojuist is getoond en geweigerd — niet de map leegvegen, waar
      // ook de herstelbestanden van een tweede venster in kunnen liggen.
      await recovery.discardEach(snapshots.map((s) => s.id));
    }
  }

  String _formatWhen(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}-${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  void dispose() {
    setWillCloseCallback(() {});
    _nativeShortcuts.dispose();
    super.dispose();
  }

  void _onWillClose() {
    // De willClose-hook is synchroon, maar het bewaken van onopgeslagen werk
    // vraagt om dialogen en opslaan — dus start het in een fire-and-forget
    // Future. Wil de bewaking doorgaan, dan roept ze [quitApp]; wil ze
    // afbreken, dan doet ze niets en het venster blijft open.
    _handleClose();
  }

  Future<void> _handleClose() async {
    if (ref.read(tabsProvider).anyDirty) {
      final choice = await _confirmSaveBeforeClose(
        context.l10n.d(
          'Er zijn bestanden met niet-opgeslagen wijzigingen. Sla ze op voordat de app sluit.',
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
    // Alleen de tabbladen van dít venster. Zie [RecoveryService.discardEach].
    await ref
        .read(recoveryServiceProvider)
        .discardEach(ref.read(tabsProvider).tabs.map((t) => t.recoveryId));
    await quitApp();
  }

  Future<_CloseChoice> _confirmSaveBeforeClose(String message) =>
      _confirmSaveBeforeCloseDialog(context, message);

  Future<bool> _saveAllDirtyTabs() async {
    for (final tab in ref.read(tabsProvider).tabs) {
      if (!tab.isDirty) continue;
      // saveTabWithDestination routes a document through its own byte-faithful /
      // "Save as…" path — a dirty document would otherwise block quit forever.
      if (!await saveTabWithDestination(context, ref, tab)) return false;
    }
    return true;
  }

  Future<void> _onCloseTab(int index) => requestCloseTab(context, ref, index);

  /// Sluit het actieve tabblad. App-breed zodat Cmd/Ctrl+W altijd werkt,
  /// ongeacht waar de focus zit — net als Cmd/Ctrl+S hierboven. De
  /// niet-opgeslagen-wijzigingen-check zit in [requestCloseTab].
  void _closeActive() => _onCloseTab(ref.read(tabsProvider).clampedIndex);

  /// Sla het actieve tabblad op. App-breed zodat Ctrl/Cmd+S altijd werkt,
  /// ongeacht waar de focus zit — én ongeacht de soort. Voor een documenttabblad
  /// was dit stuk: het riep de deck-opslag aan, die een document niet kent, dus
  /// in de visuele modus (waar de eigen sneltoets van de editor de toets niet
  /// krijgt) sloeg er niets op. Nu routeert het per soort.
  void _saveActive() {
    final tab = ref.read(tabsProvider).current;
    if (tab != null) unawaited(saveTabWithDestination(context, ref, tab));
  }

  /// Open een presentatie via de zoek-/kies-dialoog. App-breed zodat Ctrl/Cmd+O
  /// altijd werkt, ongeacht waar de focus zit.
  void _openActive() {
    _openWithSearch(context, ref);
  }

  /// Wikkelt een app-brede sneltoets zodat hij niets doet zolang er iets boven
  /// de shell staat — een dialoog, de documentlezer, het presentatiescherm.
  ///
  /// Zonder deze poort stapelde twee keer Ctrl/Cmd+O twee openen-dialogen
  /// (#1927). `showDialog` duwt zijn route synchroon, maar de focusboom
  /// verwerkt die wissel pas in de volgende frame; twee aanslagen binnen
  /// dezelfde frame komen dus allebei nog bij deze binding aan. Op macOS telt
  /// daar een tweede ingang bij op: de native menubalk draagt dezelfde
  /// Cmd-sneltoets. De navigatiegeschiedenis weet het meteen, dus die is hier
  /// de betrouwbare bron — en de poort geldt voor élke app-brede sneltoets,
  /// niet alleen voor openen.
  VoidCallback _onlyWhenShellIsOnTop(VoidCallback action) => () {
    if (Navigator.of(context, rootNavigator: true).canPop()) return;
    action();
  };

  /// De app-brede sneltoetsen, alle door [_onlyWhenShellIsOnTop]. Losse
  /// methode zodat [build] onder de methodelengte-ratchet blijft.
  Map<ShortcutActivator, VoidCallback> _appWideShortcuts() => {
    const SingleActivator(LogicalKeyboardKey.keyS, control: true):
        _onlyWhenShellIsOnTop(_saveActive),
    const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
        _onlyWhenShellIsOnTop(_saveActive),
    const SingleActivator(LogicalKeyboardKey.keyO, control: true):
        _onlyWhenShellIsOnTop(_openActive),
    const SingleActivator(LogicalKeyboardKey.keyO, meta: true):
        _onlyWhenShellIsOnTop(_openActive),
    const SingleActivator(LogicalKeyboardKey.keyF, control: true):
        _onlyWhenShellIsOnTop(() => _requestDocumentFind(showReplace: false)),
    const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
        _onlyWhenShellIsOnTop(() => _requestDocumentFind(showReplace: false)),
    const SingleActivator(LogicalKeyboardKey.keyH, control: true):
        _onlyWhenShellIsOnTop(() => _requestDocumentFind(showReplace: true)),
    const ControlHActivator(): _onlyWhenShellIsOnTop(
      () => _requestDocumentFind(showReplace: true),
    ),
    const SingleActivator(LogicalKeyboardKey.keyH, meta: true):
        _onlyWhenShellIsOnTop(() => _requestDocumentFind(showReplace: true)),
    const SingleActivator(LogicalKeyboardKey.keyW, control: true):
        _onlyWhenShellIsOnTop(_closeActive),
    const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
        _onlyWhenShellIsOnTop(_closeActive),
  };

  void _requestDocumentFind({required bool showReplace}) {
    ref
        .read(tabsProvider)
        .current
        ?.documentNotifier
        ?.requestFind(showReplace: showReplace);
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

  /// Verwerk gesleepte bestanden: presentaties/pakketten openen, afbeeldingen
  /// als nieuwe slide(s) toevoegen aan het actieve deck. Hetzelfde pad als
  /// Finder-"Open met" (via [OpenFileChannel]): een plat `.md` opent als
  /// document, geen stille weigering.
  Future<void> _onFilesDropped(List<String> paths) async {
    final homeDir = ref.read(settingsProvider).homeDirectory;
    final tabs = ref.read(tabsProvider.notifier);
    final images = <String>[];
    final presentations = <PickedPresentation>[];
    for (final path in paths) {
      final ext = p.extension(path).toLowerCase();
      // Vangnet per bestand: deze open-weg is fire-and-forget (Finder-"Open met",
      // sleep-neer, launch-arg), dus een onverwachte fout die geen gerichte
      // weiger-reden kreeg zou anders stil in runZonedGuarded verdwijnen — precies
      // het "opent niet, geen melding"-gedrag. Eén kapot bestand mag de rest ook
      // niet afbreken.
      try {
        if (ext == '.md') {
          final result = await tabs.openFileByPath(path);
          if (mounted) {
            _reportOpenFailure(
              ScaffoldMessenger.of(context),
              context.l10n,
              result,
              reason: ref.read(openFailureProvider),
            );
          }
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
        } else if (isImportablePresentationName(path)) {
          final bytes = await File(path).readAsBytes();
          presentations.add((bytes: bytes, name: p.basename(path)));
        }
      } catch (e, s) {
        logError('AppShell._onFilesDropped: openen van $path mislukt', e, s);
        if (mounted) {
          showErrorSnackBar(
            ScaffoldMessenger.of(context),
            context.l10n,
            context.l10n.d('Kon dit bestand niet openen.'),
          );
        }
      }
    }
    if (images.isNotEmpty) _addImagesToActiveDeck(images);
    if (presentations.isNotEmpty && mounted) {
      await importDroppedPresentations(context, ref, presentations);
    }
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
        ?.deckNotifierOrNull
        ?.currentState
        .deck
        ?.projectPath;
    return service.importIntoDeck(path, projectPath: projectPath);
  }

  void _addImagesToActiveDeck(List<String> paths) {
    final tab = ref.read(tabsProvider).current;
    if (tab == null || !tab.isOpen || tab.deckNotifierOrNull == null) {
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

  /// Een laag naast het deck is niet ingelezen omdat hij te groot was.
  ///
  /// Het bestand op schijf is niet aangeraakt en wordt bij opslaan ook niet
  /// vervangen, dus er is niets weg — maar zonder deze melding ziet de gebruiker
  /// alleen dat zijn strepen er niet zijn, en dat leest als "die zijn er nooit
  /// geweest". Foutkleur, want dit is werk van de gebruiker zelf (#564).
  void _listenSidecarSkipped(BuildContext context, WidgetRef ref) {
    ref.listen<SidecarSkippedWarning?>(sidecarSkippedProvider, (_, warning) {
      if (warning == null) return;
      ref.read(sidecarSkippedProvider.notifier).state = null;
      final l10n = context.l10n;
      showErrorSnackBar(
        ScaffoldMessenger.of(context),
        l10n,
        '${l10n.d('Een laag naast dit deck was te groot en is niet ingelezen; het bestand zelf is ongewijzigd:')} '
        '${warning.layers.join(', ')}',
      );
    });
  }

  /// Het zegel van een geopend deck klopt niet meer met de inhoud — het deck
  /// is bewerkt ná het verzegelen. Foutkleur: dit is precies de situatie die
  /// het zegel zou moeten vangen, en zonder deze melding merkt niemand het op.
  void _listenSealTamper(BuildContext context, WidgetRef ref) {
    ref.listen<SealTamperWarning?>(sealTamperWarningProvider, (_, warning) {
      if (warning == null) return;
      ref.read(sealTamperWarningProvider.notifier).state = null;
      final l10n = context.l10n;
      showErrorSnackBar(
        ScaffoldMessenger.of(context),
        l10n,
        l10n.d(
          'Het zegel van dit deck klopt niet meer met de inhoud — het is bewerkt na het verzegelen.',
        ),
      );
    });
  }

  /// Of de eenmalige web-mededeling over crashherstel al is getoond. Per
  /// sessie, niet per tabblad: hij gaat over de omgeving, niet over dit deck.
  bool _toldAboutNoWebRecovery = false;

  /// Er staat niet-opgeslagen werk open.
  ///
  /// Twee dingen tegelijk, allebei alleen op web nodig:
  ///
  ///   * de browser krijgt een rem op het sluiten van het tabblad
  ///     ([setUnsavedWorkGuard]) — op desktop doet de willClose-hook dat al;
  ///   * en de gebruiker hoort één keer dat crashherstel hier niet bestaat.
  ///     [RecoveryService.available] is op web onwaar (geen app-supportmap) en
  ///     de autosave-tik start er niet eens. Dat is een verdedigbare keuze, maar
  ///     stilzwijgend is het een valstrik: op desktop wérkt het wel, dus de
  ///     gebruiker heeft geen reden te vermoeden dat het hier anders is.
  ///
  /// Bewust bij de eerste bewerking en niet bij het opstarten: een waarschuwing
  /// over verlies van werk terwijl er nog geen werk is, leest als ruis. En
  /// bewust aan de dienst gevraagd in plaats van aan `kIsWeb`: als herstel er
  /// ooit tóch komt, verdwijnt deze mededeling vanzelf mee.
  void _listenUnsavedWork(BuildContext context, WidgetRef ref) {
    ref.listen<bool>(tabsProvider.select((s) => s.anyDirty), (_, dirty) {
      setUnsavedWorkGuard(dirty);
      if (!dirty ||
          ref.read(recoveryServiceProvider).available ||
          _toldAboutNoWebRecovery) {
        return;
      }
      _toldAboutNoWebRecovery = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          content: Text(
            context.l10n.d(
              'In de browser is er geen crashherstel: sluit je dit tabblad, dan is niet-opgeslagen werk weg. Sla je presentatie zelf op.',
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabsState = ref.watch(tabsProvider);
    ref.listen<TabsState>(tabsProvider, (_, next) {
      _syncSecurityBannerWithTabs(next);
      _syncImprovementBannerWithTabs(next);
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
    _listenImprovementModulePrompt(context);

    _listenChartDataWarning(context, ref);
    _listenSidecarSkipped(context, ref);
    _listenSealTamper(context, ref);
    _listenRecoveryWriteError(context, ref);

    _listenUnsavedWork(context, ref);

    // Twee post-open meldingen over wáár het bestand belandde — byte-identieke
    // kopie elders, of terugval op de documentenmap toen de ingestelde thuismap
    // onbereikbaar bleek. Ze delen het luister-patroon en wonen als top-level
    // helpers naast [_listenChartDataWarning] om app_shell.dart klein te houden.
    _listenDuplicateCopyNotice(context, ref);
    _listenImportHomeUnavailable(context, ref);

    return AppPlatformMenuBar(
      actions: _menuActions(context.l10n),
      deckActions: _deckMenuActions(),
      child: CallbackShortcuts(
        bindings: _appWideShortcuts(),
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
                          children: _tabScopes(tabsState),
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
      ),
    );
  }

  /// De menubalk-handelingen die geen open presentatie nodig hebben.
  AppMenuActions _menuActions(AppLocalizations l10n) => AppMenuActions(
    newDeck: () => ref.read(tabsProvider.notifier).newEmptyTab(),
    newDocument: () => ref.read(tabsProvider.notifier).newDocument(),
    open: _openActive,
    save: _saveActive,
    find: ref.watch(tabsProvider).current?.documentNotifier == null
        ? null
        : () => _requestDocumentFind(showReplace: false),
    findReplace: ref.watch(tabsProvider).current?.documentNotifier == null
        ? null
        : () => _requestDocumentFind(showReplace: true),
    settings: () => SettingsDialog.show(context),
    userGuide: () => DocumentReaderScreen.open(
      context,
      title: l10n.d('Gebruikershandleiding'),
      assetBase: 'docs/USER_GUIDE.md',
    ),
    shortcuts: () => DocumentReaderScreen.open(
      context,
      title: l10n.d('Sneltoetsen'),
      assetBase: 'docs/SHORTCUTS.md',
    ),
  );

  /// De menubalk-handelingen van de werkruimte, of null zolang er geen
  /// presentatie open is — dan staan ze uitgeschakeld in het menu in plaats van
  /// te verdwijnen.
  AppDeckMenuActions? _deckMenuActions() {
    // Documenttabblad: geen deck-menu. `shellDeckCommandsProvider` blijft na een
    // deck-tab 'stale', dus zonder poort routeert Cmd+S daarheen i.p.v. het document.
    if (ref.watch(tabsProvider).current?.documentNotifier != null) return null;
    // `deckProvider` is per tabblad overschreven en op dit niveau dus leeg; de
    // werkruimte publiceert zelf wat ze kan zodra ze er is.
    final commands = ref.watch(shellDeckCommandsProvider);
    if (commands == null) return null;

    return AppDeckMenuActions(
      save: commands.save,
      export: commands.export,
      present: commands.present,
      fullDeckPreview: commands.fullDeckPreview,
      properties: commands.properties,
      find: commands.find,
      findReplace: commands.findReplace,
      commandPalette: commands.commandPalette,
      undo: commands.undo,
      redo: commands.redo,
      canExport: commands.canExport,
      canUndo: commands.canUndo,
      canRedo: commands.canRedo,
    );
  }
}
