import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import '../models/deck.dart';
import '../models/slide.dart';
import '../models/slide_quality.dart';
import '../services/caption_service.dart';
import '../services/description_service.dart';
import '../services/classification_enforcement_policy.dart';
import '../services/export_metadata.dart';
import '../services/export_service.dart';
import '../services/quality_export_policy.dart';
import '../services/recovery_service.dart';
import '../services/mermaid_render_service.dart';
import '../services/slide_quality_analyzer.dart';
import '../state/deck_provider.dart';
import '../state/deck_quality_provider.dart';
import '../state/image_contrast_provider.dart';
import '../state/editor_provider.dart';
import '../state/settings_provider.dart';
import '../state/tabs_provider.dart';
import '../utils/project_path.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'dialogs/export_dialog.dart';
import 'dialogs/find_replace_dialog.dart';
import 'dialogs/image_carousel_picker.dart';
import 'dialogs/new_deck_dialog.dart';
import 'dialogs/open_presentation_dialog.dart';
import 'dialogs/presentation_info_dialog.dart';
import 'dialogs/settings_dialog.dart';
import 'panels/editor_panel.dart';
import 'panels/preview_panel.dart';
import 'panels/slide_list_panel.dart';
import 'presentation/fullscreen_presenter.dart';

// ── Shared helpers ──────────────────────────────────────────────────────────

// Shell sub-widgets and helpers, split into part files for navigability.
// These parts share this library's imports and private scope.
part 'shell/shell_actions.dart';
part 'shell/tab_bar.dart';
part 'shell/welcome_screen.dart';
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
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRestore());
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
              for (final s in snapshots)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '•  ${s.label}  ·  ${_formatWhen(s.savedAt)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF475569),
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

  Future<_CloseChoice> _confirmSaveBeforeClose(String message) async {
    if (!mounted) return _CloseChoice.cancel;
    return await showDialog<_CloseChoice>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            final l10n = ctx.l10n;
            return AlertDialog(
              title: Text(l10n.d('Niet-opgeslagen wijzigingen')),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, _CloseChoice.cancel),
                  child: Text(l10n.t('cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, _CloseChoice.discard),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(ctx).colorScheme.error,
                  ),
                  child: Text(l10n.d('Niet opslaan')),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, _CloseChoice.save),
                  child: Text(l10n.d('Opslaan en sluiten')),
                ),
              ],
            );
          },
        ) ??
        _CloseChoice.cancel;
  }

  Future<bool> _saveAllDirtyTabs() async {
    final homeDir = ref.read(settingsProvider).homeDirectory;
    for (final tab in ref.read(tabsProvider).tabs) {
      if (!tab.isDirty) continue;
      final saved = await tab.deckNotifier.save(initialDirectory: homeDir);
      if (!saved) return false;
    }
    return true;
  }

  Future<void> _onCloseTab(int index) async {
    final tab = ref.read(tabsProvider).tabs[index];
    if (tab.isDirty) {
      final choice = await _confirmSaveBeforeClose(
        context.l10n.d(
          'Deze presentatie heeft niet-opgeslagen wijzigingen. Sla de presentatie op voordat het tabblad sluit.',
        ),
      );
      switch (choice) {
        case _CloseChoice.cancel:
          return;
        case _CloseChoice.discard:
          // Wijzigingen verwerpen: closeTab() ruimt ook het herstelbestand op.
          break;
        case _CloseChoice.save:
          final saved = await tab.deckNotifier.save(
            initialDirectory: ref.read(settingsProvider).homeDirectory,
          );
          if (!saved) return;
      }
    }
    ref.read(tabsProvider.notifier).closeTab(index);
  }

  /// Sla het actieve tabblad op. App-breed zodat Ctrl/Cmd+S altijd werkt,
  /// ongeacht waar de focus zit.
  void _saveActive() {
    final tab = ref.read(tabsProvider).current;
    tab?.deckNotifier.save(
      initialDirectory: ref.read(settingsProvider).homeDirectory,
    );
  }

  /// Open een presentatie via de zoek-/kies-dialoog. App-breed zodat Ctrl/Cmd+O
  /// altijd werkt, ongeacht waar de focus zit.
  void _openActive() {
    _openWithSearch(context, ref, ref.read(settingsProvider).homeDirectory);
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
        await tabs.importPackageFile(path, homeDir: homeDir);
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
            _onFilesDropped(detail.files.map((f) => f.path).toList());
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

class _MainLayout extends ConsumerStatefulWidget {
  final ExportService exportService;

  const _MainLayout({required this.exportService});

  @override
  ConsumerState<_MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<_MainLayout> {
  static const _minSlideRailWidth = 210.0;
  static const _defaultSlideRailWidth = 320.0;
  static const _minEditorWidth = 420.0;

  double _slideRailWidth = _defaultSlideRailWidth;

  @override
  Widget build(BuildContext context) {
    final deckState = ref.watch(deckProvider);
    final deck = deckState.deck!;
    final editor = ref.watch(editorProvider);
    final settings = ref.watch(settingsProvider);
    final l10n = context.l10n;
    final deckNotifier = ref.read(deckProvider.notifier);
    final editorNotifier = ref.read(editorProvider.notifier);

    final isMarkdownMode = editor.mode == EditorMode.markdown;

    Future<void> saveDeck() async {
      await deckNotifier.save(initialDirectory: settings.homeDirectory);
    }

    void openFind() {
      if (isMarkdownMode) {
        editorNotifier.requestMarkdownFind(showReplace: false);
      }
    }

    void openFindReplace() {
      if (isMarkdownMode) {
        editorNotifier.requestMarkdownFind(showReplace: true);
        return;
      }
      FindReplaceDialog.show(
        context,
        countMatches: (q, cs) =>
            deckNotifier.countMatches(q, caseSensitive: cs),
        replaceAll: (q, r, cs) =>
            deckNotifier.replaceAll(q, r, caseSensitive: cs),
      );
    }

    Future<void> clearAllChecklists() async {
      final count = deckNotifier.checkedChecklistCount;
      if (count == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.d('Er zijn geen aangevinkte checklist-items om te legen.'),
            ),
          ),
        );
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final l10n = ctx.l10n;
          return AlertDialog(
            title: Text(l10n.d('Alle checkboxen legen?')),
            content: Text(
              '${l10n.d('Hiermee worden alle')} $count '
              '${l10n.d('aangevinkte checklist-items in de hele presentatie uitgevinkt. Dit kun je ongedaan maken met Ctrl/Cmd+Z.')}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.t('cancel')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.d('Alles legen')),
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;
      deckNotifier.clearAllChecklists();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count ${l10n.d('checklist-items uitgevinkt.')}'),
        ),
      );
    }

    Future<void> openImageCarousel() async {
      final idx = editor.selectedIndex.clamp(0, deck.slides.length - 1);
      final slide = deck.slides[idx];
      final initialPath = _resolveImagePath(slide.imagePath, deck.projectPath);
      final result = await ImageCarouselPicker.show(
        context,
        searchPaths: _imageSearchPaths(
          deck.projectPath,
          settings.homeDirectory,
        ),
        initialPath: initialPath,
        captionService: ref.read(captionServiceProvider),
        descriptionService: ref.read(descriptionServiceProvider),
        usageOf: (absolutePath) => _imageUsages(ref, absolutePath),
        onReplaceUsages: (from, to) => _replaceImageUsages(ref, from, to),
        openDeckFiles: [
          for (final tab in ref.read(tabsProvider).tabs)
            ?tab.deckNotifier.currentState.filePath,
        ],
      );
      if (result == null) return;

      final updated = switch (slide.type) {
        SlideType.title ||
        SlideType.image ||
        SlideType.quote ||
        SlideType.question ||
        SlideType.bulletsImage => slide.copyWith(
          imagePath: result.path,
          imageCaption: result.caption,
        ),
        SlideType.twoImages => slide.copyWith(
          imagePath: slide.imagePath.isEmpty ? result.path : slide.imagePath,
          imagePath2: slide.imagePath.isEmpty ? slide.imagePath2 : result.path,
          imageCaption: slide.imagePath.isEmpty
              ? result.caption
              : slide.imageCaption,
          imageCaption2: slide.imagePath.isEmpty
              ? slide.imageCaption2
              : result.caption,
        ),
        SlideType.bullets => slide.copyWith(
          type: SlideType.bulletsImage,
          imagePath: result.path,
          imageCaption: result.caption,
          imageSize: slide.imageSize > 0 ? slide.imageSize : 40,
        ),
        _ => null,
      };

      if (updated == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.d(
                'Deze slide kan geen afbeelding ontvangen. Kies eerst een afbeeldingsslide.',
              ),
            ),
          ),
        );
        return;
      }

      deckNotifier.updateSlide(idx, updated);
    }

    void presentDeck() {
      // Overgeslagen slides weglaten en de selectie naar de eerstvolgende
      // zichtbare slide vertalen.
      final visible = <int>[
        for (var i = 0; i < deck.slides.length; i++)
          if (!deck.slides[i].skipped &&
              slideVisibleAtTlp(deck.slides[i], deck.tlp))
            i,
      ];
      final slides = _slidesForPresentationOrExport(deck);
      if (slides.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.d('Alle slides zijn overgeslagen — niets om te tonen.'),
            ),
          ),
        );
        return;
      }
      var initial = visible.indexWhere((i) => i >= editor.selectedIndex);
      if (initial < 0) initial = visible.length - 1;
      if (initial < 0) initial = 0;
      FullscreenPresenter.present(
        context,
        slides: slides,
        projectPath: deck.projectPath,
        themeProfile: deck.themeProfile,
        cockpitColorScheme: ref.read(settingsProvider).cockpitColorScheme,
        initialIndex: initial,
        tlp: deck.tlp,
        organization: deck.organization,
        showClassificationWatermark: ref
            .read(settingsProvider)
            .classificationWatermarkEnabled,
        targetDuration: () {
          final secs = deck.presentationTargetSeconds;
          return secs > 0 ? Duration(seconds: secs) : null;
        }(),
        annotations: deck.annotations,
        onAnnotationsChanged: deckNotifier.setAnnotations,
        initialUserNotes: deck.userNotes,
        onUserNotesChanged: deckNotifier.setUserNotes,
        onSlideChanged: (updated) {
          final index = deckNotifier.currentState.deck?.slides.indexWhere(
            (slide) => slide.id == updated.id,
          );
          if (index != null && index >= 0) {
            deckNotifier.updateSlide(index, updated);
          }
        },
      );
    }

    void exportDeck() {
      final slides = _slidesForPresentationOrExport(deck);
      if (slides.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.d('Alle slides zijn overgeslagen — niets om te exporteren.'),
            ),
          ),
        );
        return;
      }
      ExportDialog.show(
        context,
        deckPath: deckState.filePath!,
        slides: slides,
        themeProfile: deck.themeProfile,
        cockpitColorScheme: ref.read(settingsProvider).cockpitColorScheme,
        projectPath: deck.projectPath,
        exportService: widget.exportService,
        tlp: deck.tlp,
        enforcementPolicy: ClassificationEnforcementPolicy.fromAppSettings(
          ref.read(settingsProvider),
        ),
        qualityResult: const SlideQualityAnalyzer().analyze(deck),
        qualityPolicy: QualityExportPolicy.fromAppSettings(
          warningsEnabled: ref.read(settingsProvider).qualityWarningsOnExport,
          blockOnErrors: ref.read(settingsProvider).qualityBlockExportOnErrors,
        ),
        exportDirectory: ref.read(settingsProvider).exportDirectory,
        // Inline chart data so the HTML export can render charts standalone,
        // even when a chart links an external CSV.
        markdown: ref
            .read(markdownServiceProvider)
            .generateDeck(deck.copyWith(slides: slides), inlineChartData: true),
        organization: deck.organization,
        showClassificationWatermark: ref
            .read(settingsProvider)
            .classificationWatermarkEnabled,
        documentMetadata: ExportDocumentMetadata(
          title: deck.title,
          author: deck.author,
          organization: deck.organization,
          description: deck.description,
          keywords: deck.keywords,
          tlp: deck.tlp,
        ),
      );
    }

    final canExport = deckState.filePath != null && !deckState.isDirty;
    final enforcement = ClassificationEnforcementPolicy.fromAppSettings(
      ref.watch(settingsProvider),
    );
    final classificationDecision = enforcement.evaluate(deck.tlp);
    final exportTooltip = deckState.filePath == null
        ? l10n.t('exportNeedsSave')
        : deckState.isDirty
        ? l10n.t('exportNeedsClean')
        : !classificationDecision.allowed
        ? classificationDecision.reason!
        : l10n.t('exportReady');

    void toggleMarkdownMode() {
      if (isMarkdownMode) {
        editorNotifier.setMode(EditorMode.visual);
      } else {
        editorNotifier.setMode(
          EditorMode.markdown,
          initialMarkdown: deckNotifier.generateMarkdown(),
        );
      }
    }

    void openFullDeckPreview() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              FullDeckPreview(deck: deck, themeProfile: deck.themeProfile),
        ),
      );
    }

    Future<void> newInTab() async {
      final title = await NewDeckDialog.show(context);
      if (title != null) {
        ref.read(tabsProvider.notifier).newDeckInNewTab(title);
      }
    }

    Future<void> openProperties() async {
      final info = await PresentationInfoDialog.show(context, deck);
      if (info == null) return;
      deckNotifier.updateInfo(
        title: info.title,
        author: info.author,
        organization: info.organization,
        version: info.version,
        date: info.date,
        description: info.description,
        keywords: info.keywords,
        presentationTargetSeconds: info.presentationTargetSeconds,
      );
    }

    Future<void> exportPackage() async {
      final fileService = ref.read(fileServiceProvider);
      final dest = await fileService.pickPackageDestination(deck);
      if (dest == null) return;
      try {
        await fileService.exportPackage(deck, dest);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.d('Pakket geëxporteerd naar:')}\n$dest'),
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.d('Export mislukt:')} $e')),
        );
      }
    }

    Future<void> importPackage() async {
      final fileService = ref.read(fileServiceProvider);
      final path = await fileService.pickPackageFile(
        initialDirectory: settings.homeDirectory,
      );
      if (path == null) return;
      final ok = await ref
          .read(tabsProvider.notifier)
          .importPackageFile(path, homeDir: settings.homeDirectory);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.d('Kon dit pakket niet importeren.'))),
        );
      }
    }

    Future<void> importUrl() async {
      final url = await _showUrlDialog(context);
      if (url == null || url.trim().isEmpty) return;
      final ok = await ref
          .read(tabsProvider.notifier)
          .importFromUrl(url, homeDir: settings.homeDirectory);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.d('Kon van deze URL geen presentatie ophalen.')),
          ),
        );
      }
    }

    PopupMenuItem<String> menuItem(String value, IconData icon, String label) {
      return PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF475569)),
            const SizedBox(width: 10),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
    }

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyS &&
            (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed)) {
          saveDeck();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true):
              saveDeck,
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): saveDeck,
          // Ongedaan maken / opnieuw. Vuren alleen wanneer de focus niet in een
          // tekstveld zit (dat handelt z'n eigen undo af), dus geen conflict.
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
              deckNotifier.undo,
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
              deckNotifier.undo,
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            control: true,
            shift: true,
          ): deckNotifier.redo,
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
            shift: true,
          ): deckNotifier.redo,
          const SingleActivator(LogicalKeyboardKey.keyY, control: true):
              deckNotifier.redo,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              openFind,
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true): openFind,
          const SingleActivator(LogicalKeyboardKey.keyH, control: true):
              openFindReplace,
          const SingleActivator(LogicalKeyboardKey.keyH, meta: true):
              openFindReplace,
        },
        child: Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Icon(Icons.slideshow_outlined, size: 22),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(deck.title, overflow: TextOverflow.ellipsis),
                ),
                if (deckState.isDirty) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.orangeAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
                const SizedBox(width: 16),
                _TlpChip(
                  tlp: deck.tlp,
                  warnUnset:
                      !classificationDecision.allowed &&
                      deck.tlp == TlpLevel.none,
                  onSelected: (level) => deckNotifier.updateInfo(tlp: level),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: l10n.t('presentationProperties'),
                  child: IconButton(
                    icon: const Icon(Icons.info_outline, size: 18),
                    onPressed: openProperties,
                  ),
                ),
              ],
            ),
            actions: [
              // ── Bewerken ────────────────────────────────────────────────
              Tooltip(
                message: l10n.t('undo'),
                child: IconButton(
                  icon: const Icon(Icons.undo, size: 18),
                  onPressed: deckState.canUndo ? deckNotifier.undo : null,
                ),
              ),
              Tooltip(
                message: l10n.t('redo'),
                child: IconButton(
                  icon: const Icon(Icons.redo, size: 18),
                  onPressed: deckState.canRedo ? deckNotifier.redo : null,
                ),
              ),
              const _ActionsDivider(),
              // ── Inhoud ──────────────────────────────────────────────────
              Tooltip(
                message: l10n.t('imageLibrary'),
                child: IconButton(
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  onPressed: openImageCarousel,
                ),
              ),
              const _ActionsDivider(),
              // ── Presenteren & uitvoer ───────────────────────────────────
              Tooltip(
                message: l10n.t('presentFullscreen'),
                child: IconButton(
                  icon: const Icon(Icons.play_circle_outline, size: 20),
                  onPressed: presentDeck,
                ),
              ),
              Tooltip(
                message: isMarkdownMode
                    ? l10n.t('visualMode')
                    : l10n.t('markdownMode'),
                child: IconButton(
                  icon: Icon(
                    isMarkdownMode ? Icons.view_quilt : Icons.code,
                    size: 18,
                  ),
                  onPressed: toggleMarkdownMode,
                ),
              ),
              Tooltip(
                message: l10n.t('saveShortcut'),
                child: IconButton(
                  icon: const Icon(Icons.save_outlined, size: 18),
                  onPressed: saveDeck,
                ),
              ),
              const _ActionsDivider(),
              // ── Overig (minder vaak gebruikt) ───────────────────────────
              PopupMenuButton<String>(
                tooltip: l10n.t('more'),
                icon: const Icon(Icons.more_vert, size: 20),
                position: PopupMenuPosition.under,
                onSelected: (v) {
                  switch (v) {
                    case 'new_tab':
                      newInTab();
                    case 'open':
                      _openWithSearch(context, ref, settings.homeDirectory);
                    case 'export_package':
                      exportPackage();
                    case 'import_package':
                      importPackage();
                    case 'import_url':
                      importUrl();
                    case 'find':
                      openFindReplace();
                    case 'clear_checklists':
                      clearAllChecklists();
                    case 'full_preview':
                      openFullDeckPreview();
                    case 'properties':
                      openProperties();
                    case 'settings':
                      SettingsDialog.show(context);
                  }
                },
                itemBuilder: (_) => [
                  menuItem(
                    'new_tab',
                    Icons.add_circle_outline,
                    l10n.t('newPresentationTab'),
                  ),
                  menuItem(
                    'open',
                    Icons.folder_open_outlined,
                    l10n.t('openEllipsis'),
                  ),
                  const PopupMenuDivider(),
                  menuItem(
                    'export_package',
                    Icons.inventory_2_outlined,
                    l10n.t('exportPackage'),
                  ),
                  menuItem(
                    'import_package',
                    Icons.unarchive_outlined,
                    l10n.t('importPackage'),
                  ),
                  menuItem('import_url', Icons.link, l10n.t('importUrl')),
                  const PopupMenuDivider(),
                  menuItem('find', Icons.find_replace, l10n.t('findReplace')),
                  menuItem(
                    'clear_checklists',
                    Icons.check_box_outline_blank,
                    l10n.d('Alle checkboxen legen'),
                  ),
                  menuItem(
                    'full_preview',
                    Icons.preview_outlined,
                    l10n.t('fullDeckPreview'),
                  ),
                  const PopupMenuDivider(),
                  // Style profiles are chosen via the "STIJL" pulldown in the
                  // editor toolbar; no need to duplicate them here.
                  menuItem(
                    'settings',
                    Icons.settings_outlined,
                    l10n.t('settings'),
                  ),
                ],
              ),
              const SizedBox(width: 8),
            ],
          ),
          bottomNavigationBar: _DeckStatusBar(
            deck: deck,
            deckState: deckState,
            exportDirectory: settings.exportDirectory,
            onSave: saveDeck,
            onExport: canExport ? exportDeck : null,
            exportTooltip: exportTooltip,
          ),
          body: Builder(
            builder: (ctx) {
              if (deckState.error != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(deckState.error!),
                      backgroundColor: Colors.red[700],
                      action: SnackBarAction(
                        label: 'OK',
                        textColor: Colors.white,
                        onPressed: () =>
                            ref.read(deckProvider.notifier).clearError(),
                      ),
                    ),
                  );
                  ref.read(deckProvider.notifier).clearError();
                });
              }

              // The available width comes from MediaQuery, NOT a
              // LayoutBuilder: a LayoutBuilder rebuilds this subtree during
              // the layout phase, and when the slide list's keyed
              // ReorderableListView items get reparented in that pass their
              // overlay children are activated outside an active layout —
              // "A _RenderLayoutBuilder was mutated in performLayout". The
              // body row spans the window, so the window width is equivalent.
              final bodyWidth = MediaQuery.sizeOf(ctx).width;
              final maxRailWidth = (bodyWidth - _minEditorWidth)
                  .clamp(_minSlideRailWidth, bodyWidth)
                  .toDouble();
              final railWidth = _slideRailWidth
                  .clamp(_minSlideRailWidth, maxRailWidth)
                  .toDouble();
              if (railWidth != _slideRailWidth) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _slideRailWidth = railWidth);
                });
              }

              return Row(
                children: [
                  SizedBox(
                    width: railWidth,
                    child: SlideListPanel(railWidth: railWidth),
                  ),
                  _ResizableDivider(
                    onDrag: (delta) {
                      setState(() {
                        _slideRailWidth = (_slideRailWidth + delta)
                            .clamp(_minSlideRailWidth, maxRailWidth)
                            .toDouble();
                      });
                    },
                  ),
                  const Expanded(child: EditorPanel()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── AppBar helpers ────────────────────────────────────────────────────────────
