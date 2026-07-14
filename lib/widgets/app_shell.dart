import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../platform/launch_files.dart';
import '../platform/platform_features.dart';
import '../utils/display_path.dart';
import '../utils/log.dart';
import '../models/deck.dart';
import '../models/recent_file.dart';
import '../models/settings.dart' show AppSettings;
import '../models/slide.dart';
import '../models/slide_quality.dart';
import '../models/webdav_settings.dart';
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
import '../services/privacy/privacy_projection.dart';
import '../services/privacy/redaction_manifest_service.dart';
import '../services/web_asset_store.dart';
import '../services/quality_export_policy.dart';
import '../services/recovery_service.dart';
import '../services/mermaid_render_service.dart';
import '../services/webdav_service.dart';
import '../state/deck_provider.dart';
import '../state/deck_quality_provider.dart';
import '../state/image_contrast_provider.dart';
import '../state/privacy_provider.dart';
import '../state/sec_module_provider.dart';
import '../state/editor_provider.dart';
import '../state/settings_provider.dart';
import '../state/tabs_provider.dart';
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
import 'dialogs/webdav_browser_dialog.dart';
import '../services/trash_service.dart';
import 'panels/editor_panel.dart';
import 'panels/preview_panel.dart';
import 'panels/slide_list_panel.dart';
import 'presentation/fullscreen_presenter.dart';
import 'slides/slide_preview.dart';

part 'app_shell_main_layout.dart';

// ── Shared helpers ──────────────────────────────────────────────────────────

// Shell sub-widgets and helpers, split into part files for navigability.
// These parts share this library's imports and private scope.
part 'shell/shell_actions.dart';
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

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
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
        images.add(path);
      }
    }
    if (images.isNotEmpty) _addImagesToActiveDeck(images);
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

  @override
  Widget build(BuildContext context) {
    final tabsState = ref.watch(tabsProvider);

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
                          for (final tab in tabsState.tabs)
                            ProviderScope(
                              key: ValueKey(tab.id),
                              overrides: [
                                deckProvider.overrideWith(
                                  (ref) => tab.deckNotifier,
                                ),
                                editorProvider.overrideWith(
                                  (ref) => tab.editorNotifier,
                                ),
                                deckQualityProvider.overrideWith((ref) {
                                  final deck = ref.watch(
                                    deckProvider.select((state) => state.deck),
                                  );
                                  if (deck == null) {
                                    return const SlideQualityResult([]);
                                  }
                                  return ref
                                      .watch(slideQualityAnalyzerProvider)
                                      .analyze(deck);
                                }),
                                imageContrastIssuesProvider.overrideWith(
                                  computeImageContrastIssues,
                                ),
                                // De privacyscan leest het deck, dus hij moet
                                // per tab gescoped worden — anders lost hij op
                                // in de root-container en scant hij een leeg
                                // deck, stilletjes.
                                privacyScanProvider.overrideWith(
                                  computePrivacyScan,
                                ),
                                privacyQualityIssuesProvider.overrideWith(
                                  computePrivacyQualityIssues,
                                ),
                              ],
                              child: const _TabContent(),
                            ),
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
