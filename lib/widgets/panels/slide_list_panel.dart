import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/deck.dart';
import '../../models/slide.dart';
import '../../state/deck_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/tabs_provider.dart';
import '../../services/classification_enforcement_policy.dart';
import '../../services/image_service.dart';
import '../../services/slide_rasterizer.dart';
import '../../state/slide_clipboard_provider.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/log.dart';
import '../../utils/page_scoped_notes.dart';
import '../dialogs/add_slide_dialog.dart';
import '../dialogs/import_slides_dialog.dart';
import '../dialogs/slide_finder_dialog.dart';
import '../../services/slide_layout_metrics.dart';
import '../slides/slide_preview.dart';
import '../slides/slide_thumbnail.dart';

part 'slide_list_panel_bars.dart';

class SlideListPanel extends ConsumerStatefulWidget {
  /// Current width of the slide rail. When it changes (dragging the divider),
  /// the slide being edited is scrolled back into view once the resize
  /// settles. Passed in by the shell rather than measured with a
  /// LayoutBuilder: rebuilding a ReorderableListView during layout trips its
  /// overlay bookkeeping ("_RenderLayoutBuilder was mutated…").
  final double? railWidth;

  const SlideListPanel({super.key, this.railWidth});

  @override
  ConsumerState<SlideListPanel> createState() => _SlideListPanelState();
}

class _SlideListPanelState extends ConsumerState<SlideListPanel> {
  String _query = '';
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode(debugLabel: 'SlideListPanel');
  final Map<String, GlobalKey> _slideKeys = {};
  Timer? _resizeSettleTimer;

  @override
  void dispose() {
    _resizeSettleTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Thumbnails are 16:9, so when the rail is resized their heights change and
  /// the scroll offset no longer points at the slide being edited. Once the
  /// resize settles, bring the selected slide back to the top of the list.
  @override
  void didUpdateWidget(covariant SlideListPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final width = widget.railWidth;
    final previous = oldWidget.railWidth;
    if (width == null || previous == null || (width - previous).abs() < 0.5) {
      return;
    }
    _resizeSettleTimer?.cancel();
    _resizeSettleTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _scrollSlideToTop(ref.read(editorProvider).selectedIndex);
    });
  }

  /// Lower-cased, concatenated text of a slide for searching. Kept broad on
  /// purpose: everything you typed into the slide should make it findable.
  String _slideText(Slide slide) {
    return [
      slide.title,
      slide.subtitle,
      ...slide.bullets,
      ...slide.bullets2,
      slide.quote,
      slide.quoteAuthor,
      slide.customMarkdown,
      slide.imageCaption,
      slide.imageCaption2,
      slide.notes,
      slide.imagePath,
      slide.imagePath2,
      slide.videoPath,
      slide.audioPath,
      slide.type.label,
    ].join(' ').toLowerCase();
  }

  /// Multi-word AND match: every term must appear somewhere in the slide.
  bool _matches(Slide slide, String query) {
    final text = _slideText(slide);
    return query
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .every(text.contains);
  }

  bool get _textInputHasFocus {
    final context = FocusManager.instance.primaryFocus?.context;
    return context?.widget is EditableText;
  }

  GlobalKey _keyForSlide(Slide slide) {
    return _slideKeys.putIfAbsent(
      slide.id,
      () => GlobalKey(debugLabel: 'slide-${slide.id}'),
    );
  }

  void _pruneSlideKeys(Deck deck) {
    final ids = deck.slides.map((slide) => slide.id).toSet();
    _slideKeys.removeWhere((id, _) => !ids.contains(id));
  }

  void _scrollSlideToTop(int index, {int attempts = 2}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final deck = ref.read(deckProvider).deck;
      if (deck == null ||
          index < 0 ||
          index >= deck.slides.length ||
          !_scrollController.hasClients) {
        return;
      }

      final keyContext = _slideKeys[deck.slides[index].id]?.currentContext;
      final target = keyContext?.findRenderObject();
      if (target == null) {
        // The thumbnail hasn't been built (it sits outside the viewport and
        // cache). Jump close to it based on the average item height, then try
        // again now that the surrounding items exist.
        if (attempts <= 0) return;
        final position = _scrollController.position;
        final avgItem =
            (position.maxScrollExtent + position.viewportDimension) /
            deck.slides.length;
        _scrollController.jumpTo(
          (avgItem * index).clamp(0.0, position.maxScrollExtent),
        );
        _scrollSlideToTop(index, attempts: attempts - 1);
        return;
      }

      final viewport = RenderAbstractViewport.maybeOf(target);
      if (viewport == null) return;

      final offset = viewport
          .getOffsetToReveal(target, 0)
          .offset
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
      );
    });
  }

  void _selectSlide(int index) {
    final deck = ref.read(deckProvider).deck;
    if (deck == null || deck.slides.isEmpty) return;
    final clamped = index.clamp(0, deck.slides.length - 1);
    ref.read(editorProvider.notifier).select(clamped);
    _focusNode.requestFocus();
    _scrollSlideToTop(clamped);
  }

  void _moveSelection(int delta) {
    final deck = ref.read(deckProvider).deck;
    if (deck == null || deck.slides.isEmpty) return;
    final current = ref.read(editorProvider).selectedIndex;
    _selectSlide((current + delta).clamp(0, deck.slides.length - 1));
  }

  /// Klik met modifier: Shift = bereik, Ctrl/Cmd = toevoegen/verwijderen,
  /// anders enkelvoudige selectie.
  void _onSlideTap(int index) {
    final keys = HardwareKeyboard.instance;
    final editorN = ref.read(editorProvider.notifier);
    if (keys.isShiftPressed) {
      editorN.selectRange(index);
      _focusNode.requestFocus();
      _scrollSlideToTop(index);
    } else if (keys.isControlPressed || keys.isMetaPressed) {
      editorN.toggleSelect(index);
      _focusNode.requestFocus();
      _scrollSlideToTop(index);
    } else {
      _selectSlide(index);
    }
  }

  /// Render de hele slide naar een afbeelding en kopieer 'm naar het klembord,
  /// zodat je 'm elders kunt plakken.
  /// Fail-closed classificatie-gate voor egress-paden buiten [ExportService].
  /// Rasteren-naar-klembord is functioneel een export: het levert een volledige
  /// render van (mogelijk geclassificeerde) slide-inhoud af op het systeem-
  /// klembord. Zonder deze check zou het vrijgaveplafond omzeild kunnen worden.
  /// Retourneert true als de actie door mag; toont anders de weigerreden.
  bool _classificationAllowsEgress(
    Deck deck,
    ScaffoldMessengerState messenger,
  ) {
    final policy = ClassificationEnforcementPolicy.fromAppSettings(
      ref.read(settingsProvider),
    );
    final decision = policy.evaluate(deck.tlp);
    if (!decision.allowed) {
      messenger.showSnackBar(SnackBar(content: Text(decision.reason!)));
      return false;
    }
    return true;
  }

  Future<void> _copySlideAsImage(Slide slide) async {
    final deck = ref.read(deckProvider).deck;
    if (deck == null) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!_classificationAllowsEgress(deck, messenger)) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(context.l10n.d('Slide renderen…')),
        duration: const Duration(milliseconds: 700),
      ),
    );
    Uint8List? bytes;
    try {
      final images = await SlideRasterizer.rasterize(
        context: context,
        slides: [slide],
        themeProfile: deck.themeProfile,
        cockpitColorScheme: ref.read(settingsProvider).cockpitColorScheme,
        projectPath: deck.projectPath,
        tlp: deck.tlp,
        organization: deck.organization,
        showClassificationWatermark: ref
            .read(settingsProvider)
            .classificationWatermarkEnabled,
      );
      if (images.isNotEmpty) bytes = images.first;
    } catch (e) {
      logWarning('_SlideListPanelState._copySlideAsImage: rasterize slide', e);
    }
    if (!mounted) return;
    final ok =
        bytes != null && await ImageService().copyImageBytesToClipboard(bytes);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? context.l10n.d('Slide gekopieerd naar klembord.')
              : context.l10n.d('Kopiëren mislukt.'),
        ),
      ),
    );
  }

  /// De geselecteerde slides, op volgorde van positie in het deck.
  List<Slide> _selectedSlides(Deck deck) {
    final indices = ref.read(editorProvider).selection.toList()..sort();
    return [
      for (final i in indices)
        if (i >= 0 && i < deck.slides.length) deck.slides[i],
    ];
  }

  /// Kopieer de geselecteerde slides (bulk) naar een ander open deck. Toont een
  /// keuzelijst van de overige open tabbladen; de slides worden achteraan dat
  /// deck toegevoegd (met nieuwe id's, zodat het kopieën zijn).
  Future<void> _copySelectionToOtherDeck() async {
    final deck = ref.read(deckProvider).deck;
    if (deck == null) return;
    final slides = _selectedSlides(deck);
    if (slides.isEmpty) return;

    final tabs = ref.read(tabsProvider);
    final currentId = tabs.current?.id;
    final targets = tabs.tabs
        .where((t) => t.id != currentId && t.isOpen)
        .toList();

    final messenger = ScaffoldMessenger.of(context);
    if (targets.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.d(
              'Geen ander deck open. Open eerst een ander tabblad.',
            ),
          ),
        ),
      );
      return;
    }

    final target = await showDialog<TabInfo>(
      context: context,
      builder: (ctx) {
        final l10n = ctx.l10n;
        return SimpleDialog(
          title: Text(
            slides.length == 1
                ? l10n.d('1 slide kopiëren naar…')
                : '${slides.length} ${l10n.d('slides kopiëren naar…')}',
          ),
          children: [
            for (final t in targets)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, t),
                child: Row(
                  children: [
                    const Icon(Icons.slideshow_outlined, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t.label)),
                  ],
                ),
              ),
          ],
        );
      },
    );
    if (target == null || !mounted) return;

    final at = target.deckNotifier.insertSlides(slides);
    if (at >= 0) target.editorNotifier.select(at);

    final targetIndex = tabs.tabs.indexWhere((t) => t.id == target.id);
    if (targetIndex >= 0) {
      ref.read(tabsProvider.notifier).selectTab(targetIndex);
    }

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          at >= 0
              ? '${slides.length} ${context.l10n.d('slide(s) gekopieerd naar')} “${target.label}”.'
              : context.l10n.d('Kopiëren mislukt.'),
        ),
      ),
    );
  }

  /// Verwijder alle geselecteerde slides (bulk). Houdt minstens één over.
  void _deleteSelection() {
    final deck = ref.read(deckProvider).deck;
    if (deck == null) return;
    final selection = ref.read(editorProvider).selection;
    final remaining = deck.slides.length - selection.length;
    if (remaining < 1) return;
    ref.read(deckProvider.notifier).removeSlides(selection);
    final target = selection
        .reduce((a, b) => a < b ? a : b)
        .clamp(0, remaining - 1);
    ref.read(editorProvider.notifier).select(target);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _textInputHasFocus) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.arrowLeft:
        _moveSelection(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.arrowRight:
        _moveSelection(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.pageUp:
        _moveSelection(-5);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.pageDown:
        _moveSelection(5);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _selectSlide(0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        final deck = ref.read(deckProvider).deck;
        if (deck != null) _selectSlide(deck.slides.length - 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyA
          when HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed:
        final deck = ref.read(deckProvider).deck;
        if (deck != null) {
          ref.read(editorProvider.notifier).selectAll(deck.slides.length);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        _deleteSelection();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  Future<void> _findSlides(
    BuildContext context,
    WidgetRef ref,
    DeckState deckState,
  ) async {
    final settings = ref.read(settingsProvider);
    final deck = deckState.deck;
    final initialDir = deck?.projectPath ?? settings.homeDirectory;

    await SlideFinderDialog.show(
      context,
      fileService: ref.read(fileServiceProvider),
      initialDirectory: initialDir,
      excludePath: deckState.filePath,
      onAdd: (slide) {
        // Voeg in ná de huidige slide (niet achteraan). Doordat we de nieuwe
        // slide selecteren, ketenen opeenvolgende keuzes netjes achter elkaar.
        final idx = ref.read(editorProvider).selectedIndex;
        final at = ref.read(deckProvider.notifier).insertSlides([
          slide,
        ], afterIndex: idx);
        if (at >= 0) ref.read(editorProvider.notifier).select(at);
      },
    );
  }

  Future<void> _importSlides(
    BuildContext context,
    WidgetRef ref,
    DeckState deckState,
  ) async {
    final settings = ref.read(settingsProvider);
    final deck = deckState.deck;
    final initialDir = deck?.projectPath ?? settings.homeDirectory;

    final slides = await ImportSlidesDialog.show(
      context,
      fileService: ref.read(fileServiceProvider),
      initialDirectory: initialDir,
      excludePath: deckState.filePath,
    );
    if (slides == null || slides.isEmpty) return;

    final notifier = ref.read(deckProvider.notifier);
    final editorNotifier = ref.read(editorProvider.notifier);
    final at = ref.read(editorProvider).selectedIndex;
    final firstIndex = notifier.insertSlides(slides, afterIndex: at);
    if (firstIndex >= 0) {
      editorNotifier.select(firstIndex);
      _scrollSlideToTop(firstIndex);
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          slides.length == 1
              ? context.l10n.d('1 slide geïmporteerd.')
              : '${slides.length} ${context.l10n.d('slides geïmporteerd.')}',
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    final l10n = context.l10n;
    return SizedBox(
      height: 30,
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _query = v),
        style: const TextStyle(color: Colors.white, fontSize: 12),
        decoration: InputDecoration(
          isDense: true,
          hintText: l10n.d('Zoek in slides…'),
          hintStyle: TextStyle(color: AppTheme.gray500, fontSize: 12),
          prefixIcon: Icon(Icons.search, size: 15, color: AppTheme.gray500),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 30,
            minHeight: 30,
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 14,
                  splashRadius: 14,
                  tooltip: l10n.d('Zoekopdracht wissen'),
                  icon: Icon(Icons.clear, color: AppTheme.gray500),
                  onPressed: () => setState(() {
                    _searchController.clear();
                    _query = '';
                  }),
                ),
          filled: true,
          fillColor: AppTheme.darkSlate900,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppTheme.darkSlate600),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppTheme.darkSlate600),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppTheme.accent),
          ),
        ),
      ),
    );
  }

  Widget _buildFilteredList(
    Deck deck,
    String query,
    EditorState editor,
    DeckNotifier notifier,
    EditorNotifier editorNotifier,
  ) {
    final l10n = context.l10n;
    final matches = <int>[
      for (var i = 0; i < deck.slides.length; i++)
        if (_matches(deck.slides[i], query)) i,
    ];

    if (matches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.search_off_outlined,
                size: 32,
                color: AppTheme.darkSlate500,
              ),
              const SizedBox(height: 10),
              Text(
                '${l10n.d('Geen slides met')} "$query"',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.slate400, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: matches.length,
      itemBuilder: (_, i) {
        final index = matches[i];
        final slide = deck.slides[index];
        return SlideThumbnail(
          key: _keyForSlide(slide),
          slide: slide,
          index: index,
          isSelected: editor.selection.contains(index),
          isPrimary: editor.selectedIndex == index,
          hasUserNotes: slideHasUserNotes(deck.userNotes, slide.id),
          projectPath: deck.projectPath,
          themeProfile: deck.themeProfile,
          slideCount: deck.slides.length,
          tlp: deck.tlp,
          organization: deck.organization,
          fitScaleOverride: sharedSplitFitScale(
            deck.slides,
            index,
            deck.themeProfile,
            deck.themeProfile.fontFamily,
          ),
          numberStart: numberedListStartFor(deck.slides, index),
          onTap: () => _onSlideTap(index),
          onToggleSkip: () => notifier.toggleSkip(index),
          onCopyImage: () => _copySlideAsImage(slide),
          onDuplicate: () {
            notifier.duplicateSlide(index);
            editorNotifier.select(index + 1);
          },
          onSplit: () {
            notifier.splitSlide(index);
            editorNotifier.select(index + 1);
          },
          onDelete: () {
            if (deck.slides.length <= 1) return;
            notifier.removeSlide(index);
            editorNotifier.clampIndex(deck.slides.length - 2);
          },
        );
      },
    );
  }

  Widget _buildSlideList(
    Deck deck,
    bool searching,
    String query,
    EditorState editor,
    DeckNotifier notifier,
    EditorNotifier editorNotifier,
  ) {
    if (searching) {
      return _buildFilteredList(deck, query, editor, notifier, editorNotifier);
    }
    return ReorderableListView.builder(
      // Rebuild when slides are bulk-added/removed — the list's internal
      // bookkeeping can otherwise keep showing the old item count until restart.
      key: ValueKey(
        'slide-list-${deck.slides.length}-${deck.slides.isEmpty ? 'empty' : deck.slides.last.id}',
      ),
      scrollController: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 4),
      buildDefaultDragHandles: false,
      itemCount: deck.slides.length,
      onReorderItem: (old, nw) {
        // Sleep je één slide uit een multiselectie, dan verhuist het hele blok
        // in één keer; de selectie volgt het blok naar de nieuwe plek.
        if (editor.hasMultiSelection && editor.selection.contains(old)) {
          final start = notifier.moveSlides(editor.selection, old, nw);
          if (start >= 0) {
            final count = editor.selection.length;
            final primaryOffset = editor.selection
                .where((i) => i < editor.selectedIndex)
                .length;
            editorNotifier.selectBlock(
              start,
              count,
              primary: start + primaryOffset,
            );
          }
          return;
        }
        notifier.reorderSlides(old, nw);
        // Adjust selection when active slide moved
        final selIdx = editor.selectedIndex;
        int newSel = selIdx;
        if (old == selIdx) {
          newSel = nw;
        } else if (old < selIdx && nw >= selIdx) {
          newSel = selIdx - 1;
        } else if (old > selIdx && nw <= selIdx) {
          newSel = selIdx + 1;
        }
        editorNotifier.select(newSel.clamp(0, deck.slides.length - 1));
      },
      proxyDecorator: (child, index, animation) =>
          Material(color: Colors.transparent, child: child),
      itemBuilder: (_, i) {
        final slide = deck.slides[i];
        return SlideThumbnail(
          key: _keyForSlide(slide),
          slide: slide,
          index: i,
          isSelected: editor.selection.contains(i),
          isPrimary: editor.selectedIndex == i,
          hasUserNotes: slideHasUserNotes(deck.userNotes, slide.id),
          projectPath: deck.projectPath,
          themeProfile: deck.themeProfile,
          slideCount: deck.slides.length,
          tlp: deck.tlp,
          organization: deck.organization,
          fitScaleOverride: sharedSplitFitScale(
            deck.slides,
            i,
            deck.themeProfile,
            deck.themeProfile.fontFamily,
          ),
          numberStart: numberedListStartFor(deck.slides, i),
          onTap: () => _onSlideTap(i),
          onToggleSkip: () => notifier.toggleSkip(i),
          onCopyImage: () => _copySlideAsImage(slide),
          onDuplicate: () {
            notifier.duplicateSlide(i);
            editorNotifier.select(i + 1);
          },
          onSplit: () {
            notifier.splitSlide(i);
            editorNotifier.select(i + 1);
          },
          onDelete: () {
            if (deck.slides.length <= 1) return;
            notifier.removeSlide(i);
            editorNotifier.clampIndex(deck.slides.length - 2);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final deckState = ref.watch(deckProvider);
    final deck = deckState.deck!;
    _pruneSlideKeys(deck);
    final editor = ref.watch(editorProvider);

    ref.listen<int>(editorProvider.select((s) => s.selectedIndex), (
      previous,
      next,
    ) {
      if (previous != next) _scrollSlideToTop(next);
    });
    ref.listen<int?>(deckProvider.select((s) => s.deck?.slides.length), (
      previous,
      next,
    ) {
      if (previous != null && next != null && next > previous) {
        _scrollSlideToTop(ref.read(editorProvider).selectedIndex);
      }
    });
    final notifier = ref.read(deckProvider.notifier);
    final editorNotifier = ref.read(editorProvider.notifier);

    final clipboard = ref.watch(slideClipboardProvider);

    final query = _query.trim().toLowerCase();
    final searching = query.isNotEmpty;
    final matchCount = searching
        ? deck.slides.where((s) => _matches(s, query)).length
        : deck.slides.length;
    final skippedCount = deck.slides.where((s) => s.skipped).length;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _focusNode.requestFocus,
        child: Container(
          color: Theme.of(context).extension<AppPalette>()!.panel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──────────────────────────────────────────────────────
              Container(
                color: Theme.of(
                  context,
                ).extension<AppPalette>()!.panelText.withValues(alpha: 0.05),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          l10n.d('SLIDES'),
                          style: TextStyle(
                            color: AppTheme.slate400,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          searching
                              ? '$matchCount / ${deck.slides.length}'
                              : '${deck.slides.length}',
                          style: TextStyle(
                            color: AppTheme.slate500,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildSearchField(),
                    // "Overslaan"-balk: alleen zichtbaar als er slides overgeslagen
                    // worden. Eén klik zet alle markeringen weer uit.
                    if (skippedCount > 0) ...[
                      const SizedBox(height: 6),
                      _SkipBanner(
                        count: skippedCount,
                        onClearAll: notifier.clearAllSkips,
                      ),
                    ],
                    // Bulk-actiebalk bij een meervoudige selectie.
                    if (editor.hasMultiSelection) ...[
                      const SizedBox(height: 6),
                      _BulkActionBar(
                        count: editor.selection.length,
                        onCopyToDeck: _copySelectionToOtherDeck,
                        onDelete: _deleteSelection,
                        onSkip: () => notifier.setSkippedForSlides(
                          editor.selection,
                          true,
                        ),
                        onShow: () => notifier.setSkippedForSlides(
                          editor.selection,
                          false,
                        ),
                        onDeselect: () =>
                            editorNotifier.select(editor.selectedIndex),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Slide list ───────────────────────────────────────────────────
              Expanded(
                child: _buildSlideList(
                  deck,
                  searching,
                  query,
                  editor,
                  notifier,
                  editorNotifier,
                ),
              ),

              // ── Add / Paste slide buttons ─────────────────────────────────
              _addPasteButtons(
                context,
                deck,
                deckState,
                editor,
                clipboard,
                l10n,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addPasteButtons(
    BuildContext context,
    Deck deck,
    DeckState deckState,
    EditorState editor,
    Slide? clipboard,
    AppLocalizations l10n,
  ) {
    final notifier = ref.read(deckProvider.notifier);
    final editorNotifier = ref.read(editorProvider.notifier);
    return Container(
      color: AppTheme.darkSlate800,
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          SizedBox(
            height: 32,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final path = await ref
                    .read(imageServiceProvider)
                    .pasteImage(projectPath: deck.projectPath);
                if (path == null) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        l10n.d('Geen afbeelding op het klembord gevonden.'),
                      ),
                    ),
                  );
                  return;
                }
                final idx = editor.selectedIndex;
                notifier.addSlide(SlideType.image, afterIndex: idx);
                final newIdx = idx + 1;
                notifier.updateSlide(
                  newIdx,
                  Slide.create(SlideType.image).copyWith(imagePath: path),
                );
                editorNotifier.select(newIdx);
              },
              icon: const Icon(Icons.image_outlined, size: 14),
              label: Text(l10n.d('Afbeelding plakken')),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: AppTheme.darkSlate500),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(fontSize: 11),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final type = await AddSlideDialog.show(context);
                if (type != null) {
                  final idx = editor.selectedIndex;
                  notifier.addSlide(type, afterIndex: idx);
                  editorNotifier.select(idx + 1);
                }
              },
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.d('Slide toevoegen')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _findSlides(context, ref, deckState),
              icon: const Icon(Icons.travel_explore_outlined, size: 14),
              label: Text(l10n.d('Slide zoeken')),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: AppTheme.darkSlate500),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(fontSize: 11),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _importSlides(context, ref, deckState),
              icon: const Icon(Icons.library_add_outlined, size: 14),
              label: Text(l10n.d('Slides importeren')),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: AppTheme.darkSlate500),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(fontSize: 11),
              ),
            ),
          ),
          if (clipboard != null) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final idx = editor.selectedIndex;
                  notifier.addSlide(clipboard.type, afterIndex: idx);
                  // Replace the newly created blank slide with the copied one
                  final newIdx = idx + 1;
                  notifier.updateSlide(newIdx, Slide.duplicate(clipboard));
                  editorNotifier.select(newIdx);
                },
                icon: const Icon(Icons.content_paste, size: 14),
                label: Text(l10n.d('Slide plakken')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: AppTheme.darkSlate500),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
