import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import '../models/deck.dart';
import '../models/slide.dart';
import '../services/caption_service.dart';
import '../services/description_service.dart';
import '../services/export_service.dart';
import '../services/recovery_service.dart';
import '../state/deck_provider.dart';
import '../state/editor_provider.dart';
import '../state/settings_provider.dart';
import '../state/tabs_provider.dart';
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

/// Open the search-based presentation picker and load the chosen file
/// (optionally jumping to a matched slide).
Future<void> _openWithSearch(
  BuildContext context,
  WidgetRef ref,
  String? initialDirectory,
) async {
  final settings = ref.read(settingsProvider);
  final result = await OpenPresentationDialog.show(
    context,
    fileService: ref.read(fileServiceProvider),
    initialDirectory: initialDirectory ?? settings.homeDirectory,
  );
  if (result == null) return;
  await ref
      .read(tabsProvider.notifier)
      .openFileByPath(result.path, selectIndex: result.slideIndex);
}

/// Vraag een URL op om een presentatie (pakket of markdown) op te halen.
Future<String?> _showUrlDialog(BuildContext context) {
  final l10n = context.l10n;
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.d('Importeren via URL')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Plak de link naar een .ocideck-pakket of een Marp-markdownbestand.',
              ),
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'https://…',
                prefixIcon: Icon(Icons.link, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.t('cancel')),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(ctx, controller.text),
          icon: const Icon(Icons.download, size: 16),
          label: Text(l10n.d('Ophalen')),
        ),
      ],
    ),
  );
}

List<String> _imageSearchPaths(String? projectPath, String? homeDirectory) {
  final projectImagesPath = projectPath == null
      ? null
      : p.join(projectPath, 'images');
  return [?projectImagesPath, ?projectPath, ?homeDirectory];
}

String? _resolveImagePath(String path, String? projectPath) {
  if (path.isEmpty) return null;
  if (p.isAbsolute(path) || projectPath == null) return path;
  return p.join(projectPath, path);
}

List<String> _imageUsages(WidgetRef ref, String absolutePath) {
  final target = p.normalize(absolutePath);
  final usages = <String>[];
  for (final tab in ref.read(tabsProvider).tabs) {
    final deck = tab.deckNotifier.currentState.deck;
    if (deck == null) continue;
    for (var i = 0; i < deck.slides.length; i++) {
      final slide = deck.slides[i];
      for (final candidate in [slide.imagePath, slide.imagePath2]) {
        if (candidate.isEmpty) continue;
        final resolved = p.normalize(
          p.isAbsolute(candidate)
              ? candidate
              : p.join(deck.projectPath ?? '', candidate),
        );
        if (resolved == target) {
          usages.add('${tab.label} · slide ${i + 1}');
          break;
        }
      }
    }
  }
  return usages;
}

/// Wijs in alle open decks elke slideverwijzing naar [fromAbsolute] om naar
/// [toAbsolute]. Gebruikt door de afbeeldingenbibliotheek wanneer een md5-
/// duplicaat wordt opgeruimd, zodat slides het behouden bestand blijven tonen.
Future<void> _replaceImageUsages(
  WidgetRef ref,
  String fromAbsolute,
  String toAbsolute,
) async {
  final target = p.normalize(fromAbsolute);
  for (final tab in ref.read(tabsProvider).tabs) {
    final notifier = tab.deckNotifier;
    final deck = notifier.currentState.deck;
    if (deck == null) continue;
    final projectPath = deck.projectPath ?? '';

    String resolve(String candidate) => p.normalize(
      p.isAbsolute(candidate) ? candidate : p.join(projectPath, candidate),
    );
    // Blijf relatief opslaan als de slide dat al deed en het nieuwe pad
    // binnen het project ligt; anders absoluut.
    String replacement(String candidate) {
      if (p.isAbsolute(candidate) || projectPath.isEmpty) return toAbsolute;
      return p.isWithin(projectPath, toAbsolute)
          ? p.relative(toAbsolute, from: projectPath)
          : toAbsolute;
    }

    for (var i = 0; i < deck.slides.length; i++) {
      final slide = deck.slides[i];
      var updated = slide;
      if (slide.imagePath.isNotEmpty && resolve(slide.imagePath) == target) {
        updated = updated.copyWith(imagePath: replacement(slide.imagePath));
      }
      if (slide.imagePath2.isNotEmpty && resolve(slide.imagePath2) == target) {
        updated = updated.copyWith(imagePath2: replacement(slide.imagePath2));
      }
      if (!identical(updated, slide)) notifier.updateSlide(i, updated);
    }
  }
}

List<Slide> _slidesForPresentationOrExport(Deck deck) {
  // Drop skipped slides and slides whose TLP classification is stricter than
  // the level chosen for this presentation/export.
  final slides = deck.slides
      .where((s) => !s.skipped && slideVisibleAtTlp(s, deck.tlp))
      .toList();
  final closingMarkdown = deck.themeProfile.closingSlideMarkdown.trim();
  if (deck.themeProfile.closingSlideEnabled && closingMarkdown.isNotEmpty) {
    slides.add(
      Slide.create(
        SlideType.freeMarkdown,
      ).copyWith(customMarkdown: closingMarkdown),
    );
  }
  return slides;
}

// ── App shell ─────────────────────────────────────────────────────────────────

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
      final shouldSave = await _confirmSaveBeforeClose(
        context.l10n.d(
          'Er zijn presentaties met niet-opgeslagen wijzigingen. Sla ze op voordat de app sluit.',
        ),
      );
      if (!shouldSave) return;
      final saved = await _saveAllDirtyTabs();
      if (saved) await _destroy();
    } else {
      await _destroy();
    }
  }

  /// Nette afsluiting: herstelbestanden opruimen (alles is opgeslagen) en sluiten.
  Future<void> _destroy() async {
    await ref.read(recoveryServiceProvider).clearAll();
    await windowManager.destroy();
  }

  Future<bool> _confirmSaveBeforeClose(String message) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            final l10n = ctx.l10n;
            return AlertDialog(
              title: Text(l10n.d('Niet-opgeslagen wijzigingen')),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(l10n.t('cancel')),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(l10n.d('Opslaan en sluiten')),
                ),
              ],
            );
          },
        ) ??
        false;
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
      final shouldSave = await _confirmSaveBeforeClose(
        context.l10n.d(
          'Deze presentatie heeft niet-opgeslagen wijzigingen. Sla de presentatie op voordat het tabblad sluit.',
        ),
      );
      if (!shouldSave) return;
      final saved = await tab.deckNotifier.save(
        initialDirectory: ref.read(settingsProvider).homeDirectory,
      );
      if (!saved) return;
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
                              ],
                              child: const _TabContent(),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_dragging) const _DropOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Visuele hint terwijl bestanden boven het venster zweven.
class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: const Color(0xFF1C2B47).withValues(alpha: 0.55),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF60A5FA), width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.file_download_outlined,
                  size: 40,
                  color: Color(0xFF2563EB),
                ),
                const SizedBox(height: 10),
                Text(
                  context.l10n.d('Laat los om toe te voegen'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.d(
                    'Afbeeldingen → nieuwe slides · .md / .ocideck → openen',
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tab bar ───────────────────────────────────────────────────────────────────

class _AppTabBar extends StatelessWidget {
  final TabsState tabsState;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final VoidCallback onAdd;

  const _AppTabBar({
    required this.tabsState,
    required this.onSelect,
    required this.onClose,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Container(
      height: 36,
      color: palette.panel,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < tabsState.tabs.length; i++)
                    _TabChip(
                      tab: tabsState.tabs[i],
                      isActive: i == tabsState.clampedIndex,
                      showClose:
                          tabsState.tabs.length > 1 || tabsState.tabs[i].isOpen,
                      panelText: palette.panelText,
                      accent: Theme.of(context).colorScheme.secondary,
                      onTap: () => onSelect(i),
                      onClose: () => onClose(i),
                    ),
                ],
              ),
            ),
          ),
          Tooltip(
            message: l10n.t('newTab'),
            child: InkWell(
              onTap: onAdd,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  Icons.add,
                  size: 16,
                  color: palette.panelText.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final TabInfo tab;
  final bool isActive;
  final bool showClose;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final Color panelText;
  final Color accent;

  const _TabChip({
    required this.tab,
    required this.isActive,
    required this.showClose,
    required this.onTap,
    required this.onClose,
    required this.panelText,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 80, maxWidth: 200),
        height: 36,
        decoration: BoxDecoration(
          color: isActive
              ? panelText.withValues(alpha: 0.12)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive ? accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tab.isDirty)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 5),
                decoration: const BoxDecoration(
                  color: Colors.orangeAccent,
                  shape: BoxShape.circle,
                ),
              ),
            Flexible(
              child: Text(
                tab.label,
                style: TextStyle(
                  fontSize: 12,
                  color: isActive
                      ? panelText
                      : panelText.withValues(alpha: 0.72),
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showClose) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: onClose,
                borderRadius: BorderRadius.circular(3),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close,
                    size: 12,
                    color: panelText.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Per-tab content ───────────────────────────────────────────────────────────

class _TabContent extends ConsumerWidget {
  const _TabContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOpen = ref.watch(deckProvider.select((s) => s.isOpen));
    if (!isOpen) return const _WelcomeScreen();
    return _MainLayout(exportService: ExportService());
  }
}

// ── Welcome screen ────────────────────────────────────────────────────────────

class _WelcomeScreen extends ConsumerWidget {
  const _WelcomeScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final palette = theme.extension<AppPalette>()!;
    final homeDir = ref.watch(settingsProvider.select((s) => s.homeDirectory));
    final recentFiles = ref.watch(
      settingsProvider.select((s) => s.recentFiles),
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Row(
        children: [
          // ── Midden: logo + knoppen ─────────────────────────────────────
          Expanded(
            child: Align(
              alignment: const Alignment(-0.15, 0.12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    label: 'De Winter Information Solutions',
                    image: true,
                    child: Image.asset(
                      'assets/images/de-winter-wittegeheel.png',
                      width: 320,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    width: 220,
                    child: ElevatedButton.icon(
                      onPressed: () => _newDeck(context, ref),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(l10n.t('newPresentation')),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 220,
                    child: OutlinedButton.icon(
                      onPressed: () => _openWithSearch(context, ref, homeDir),
                      icon: const Icon(Icons.folder_open_outlined, size: 18),
                      label: Text(l10n.t('open')),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => SettingsDialog.show(context),
                    icon: const Icon(Icons.settings_outlined, size: 17),
                    label: Text(l10n.t('settings')),
                  ),
                ],
              ),
            ),
          ),
          // ── Rechts: recente bestanden ──────────────────────────────────
          if (recentFiles.isNotEmpty)
            Container(
              width: 280,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  left: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                    child: Text(
                      l10n.t('recentPresentations'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: palette.mutedText,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: recentFiles.length,
                      itemBuilder: (_, i) {
                        final path = recentFiles[i];
                        final name = path.split('/').last.replaceAll('.md', '');
                        return InkWell(
                          onTap: () => ref
                              .read(tabsProvider.notifier)
                              .openFileByPath(path),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.slideshow_outlined,
                                  size: 16,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        path,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: palette.mutedText,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _newDeck(BuildContext context, WidgetRef ref) async {
    final title = await NewDeckDialog.show(context);
    if (title != null) {
      ref.read(tabsProvider.notifier).newDeckInCurrentTab(title);
    }
  }
}

// ── Main 2-panel layout ───────────────────────────────────────────────────────

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

    void openFindReplace() {
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
        initialIndex: initial,
        tlp: deck.tlp,
        annotations: deck.annotations,
        onAnnotationsChanged: deckNotifier.setAnnotations,
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
        projectPath: deck.projectPath,
        exportService: widget.exportService,
        tlp: deck.tlp,
        exportDirectory: ref.read(settingsProvider).exportDirectory,
        // Inline chart data so the HTML export can render charts standalone,
        // even when a chart links an external CSV.
        markdown: ref
            .read(markdownServiceProvider)
            .generateDeck(deck.copyWith(slides: slides), inlineChartData: true),
      );
    }

    final canExport = deckState.filePath != null && !deckState.isDirty;
    final exportTooltip = deckState.filePath == null
        ? l10n.t('exportNeedsSave')
        : deckState.isDirty
        ? l10n.t('exportNeedsClean')
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
                    default:
                      if (v.startsWith('style:')) {
                        final name = v.substring(6);
                        final profile = settings.themeProfiles.firstWhere(
                          (p) => p.name == name,
                          orElse: () => settings.themeProfile,
                        );
                        deckNotifier.updateThemeProfile(profile);
                      }
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
                  for (final profile in settings.themeProfiles)
                    PopupMenuItem<String>(
                      value: 'style:${profile.name}',
                      child: Row(
                        children: [
                          Icon(
                            profile.name == deck.themeProfile.name
                                ? Icons.check
                                : Icons.palette_outlined,
                            size: 16,
                            color: const Color(0xFF475569),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              '${l10n.t('styleProfile')}: ${profile.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const PopupMenuDivider(),
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

class _DeckStatusBar extends StatelessWidget {
  final Deck deck;
  final DeckState deckState;
  final String? exportDirectory;
  final Future<void> Function() onSave;
  final VoidCallback? onExport;
  final String exportTooltip;

  const _DeckStatusBar({
    required this.deck,
    required this.deckState,
    required this.exportDirectory,
    required this.onSave,
    required this.onExport,
    required this.exportTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final skipped = deck.slides.where((s) => s.skipped).length;
    final fileLabel = deckState.filePath == null
        ? l10n.t('notSavedYet')
        : p.basename(deckState.filePath!);
    final saveLabel = deckState.isDirty ? l10n.t('unsaved') : l10n.t('saved');
    final exportLabel = exportDirectory == null
        ? l10n.t('exportNextToDeck')
        : '${l10n.t('exportFolder')}: ${p.basename(exportDirectory!)}';

    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            _StatusAction(
              icon: deckState.isDirty
                  ? Icons.radio_button_checked
                  : Icons.check_circle_outline,
              label: saveLabel,
              tooltip: deckState.isDirty
                  ? l10n.t('unsavedChanges')
                  : l10n.t('noUnsavedChanges'),
              color: deckState.isDirty
                  ? const Color(0xFFD97706)
                  : const Color(0xFF15803D),
              onTap: () => onSave(),
            ),
            const _StatusDivider(),
            _StatusItem(
              icon: Icons.description_outlined,
              label: fileLabel,
              tooltip: deckState.filePath ?? l10n.t('noFileYet'),
            ),
            const _StatusDivider(),
            _StatusItem(
              icon: Icons.slideshow_outlined,
              label: skipped == 0
                  ? '${deck.slides.length} ${l10n.t('slides')}'
                  : '${deck.slides.length} ${l10n.t('slides')} · $skipped ${l10n.t('skipped')}',
              tooltip: skipped == 0
                  ? l10n.t('allSlidesIncluded')
                  : '$skipped ${l10n.t('skippedSlidesExcluded')}',
              color: skipped == 0 ? null : const Color(0xFF8A6D3B),
            ),
            const _StatusDivider(),
            _StatusItem(
              icon: Icons.palette_outlined,
              label: deck.themeProfile.name,
              tooltip: '${l10n.t('styleProfile')}: ${deck.themeProfile.name}',
            ),
            if (deck.tlp != TlpLevel.none) ...[
              const _StatusDivider(),
              _StatusItem(
                icon: Icons.shield_outlined,
                label: deck.tlp.label,
                tooltip: '${l10n.t('classification')}: ${deck.tlp.label}',
                color: Color(deck.tlp.foreground),
              ),
            ],
            const Spacer(),
            _StatusItem(
              icon: Icons.folder_outlined,
              label: exportLabel,
              tooltip: exportDirectory ?? l10n.t('exportsNextToDeck'),
            ),
            const SizedBox(width: 6),
            _StatusAction(
              icon: Icons.upload_file_outlined,
              label: l10n.t('export'),
              tooltip: exportTooltip,
              onTap: onExport,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final Color? color;

  const _StatusItem({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: fg,
                fontWeight: color == null ? FontWeight.normal : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final Color? color;
  final VoidCallback? onTap;

  const _StatusAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = enabled
        ? (color ?? Theme.of(context).colorScheme.secondary)
        : Theme.of(context).disabledColor;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: fg,
                  fontWeight: enabled ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusDivider extends StatelessWidget {
  const _StatusDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

/// Dunne verticale scheiding tussen groepen AppBar-knoppen.
class _ActionsDivider extends StatelessWidget {
  const _ActionsDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.white24,
    );
  }
}

class _ResizableDivider extends StatefulWidget {
  final ValueChanged<double> onDrag;

  const _ResizableDivider({required this.onDrag});

  @override
  State<_ResizableDivider> createState() => _ResizableDividerState();
}

class _ResizableDividerState extends State<_ResizableDivider> {
  static const double _keyboardStep = 24;

  bool _hovered = false;
  bool _dragging = false;
  bool _focused = false;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.onDrag(-_keyboardStep);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      widget.onDrag(_keyboardStep);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final active = _hovered || _dragging || _focused;
    // Keyboard-operable (WCAG 2.1.1): the divider is focusable, arrow keys
    // move it, and focus is shown with the same highlight as hovering
    // (WCAG 2.4.7). Screen readers see it as an adjustable element.
    return Focus(
      onKeyEvent: _onKeyEvent,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Semantics(
        slider: true,
        label: l10n.d('Breedte van het slidepaneel'),
        hint: l10n.d('Pijltjestoetsen passen de breedte aan'),
        onIncrease: () => widget.onDrag(_keyboardStep),
        onDecrease: () => widget.onDrag(-_keyboardStep),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => setState(() => _dragging = true),
            onHorizontalDragEnd: (_) => setState(() => _dragging = false),
            onHorizontalDragCancel: () => setState(() => _dragging = false),
            onHorizontalDragUpdate: (details) =>
                widget.onDrag(details.delta.dx),
            child: Tooltip(
              message: l10n.d(
                'Sleep om de slide-preview breder of smaller te maken',
              ),
              child: SizedBox(
                width: 9,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 90),
                    width: active ? 3 : 1,
                    color: active
                        ? Theme.of(context).colorScheme.secondary
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// TLP-classificatie als altijd zichtbare, direct instelbare chip in de
/// AppBar-titel. Toont de huidige status in de officiële TLP-kleur en opent
/// bij klikken een keuzelijst met alle niveaus (incl. "Geen").
class _TlpChip extends StatelessWidget {
  final TlpLevel tlp;
  final ValueChanged<TlpLevel> onSelected;

  const _TlpChip({required this.tlp, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isSet = tlp != TlpLevel.none;
    final fg = Color(tlp.foreground);

    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isSet ? Colors.black : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSet ? fg.withValues(alpha: 0.7) : Colors.white24,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isSet)
            const Icon(Icons.shield_outlined, size: 14, color: Colors.white70),
          if (!isSet) const SizedBox(width: 5),
          Text(
            isSet ? tlp.label : 'TLP',
            style: TextStyle(
              color: isSet ? fg : Colors.white70,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
              letterSpacing: 0.3,
            ),
          ),
          Icon(
            Icons.arrow_drop_down,
            size: 16,
            color: isSet ? fg : Colors.white54,
          ),
        ],
      ),
    );

    return PopupMenuButton<TlpLevel>(
      tooltip: l10n.d('TLP-classificatie (Traffic Light Protocol)'),
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final level in TlpLevel.values)
          PopupMenuItem<TlpLevel>(
            value: level,
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: level == TlpLevel.none
                        ? Colors.transparent
                        : Color(level.foreground),
                    border: Border.all(color: const Color(0xFF94A3B8)),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Text(level == TlpLevel.none ? l10n.d('Geen') : level.label),
                if (level == tlp) ...[
                  const SizedBox(width: 12),
                  const Spacer(),
                  const Icon(Icons.check, size: 16, color: Color(0xFF475569)),
                ],
              ],
            ),
          ),
      ],
      child: child,
    );
  }
}
