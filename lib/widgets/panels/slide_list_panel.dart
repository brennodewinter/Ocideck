import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/deck.dart';
import '../../models/slide.dart';
import '../../state/deck_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/settings_provider.dart';
import '../../services/image_service.dart';
import '../../services/slide_rasterizer.dart';
import '../../state/slide_clipboard_provider.dart';
import '../../theme/app_theme.dart';
import '../dialogs/add_slide_dialog.dart';
import '../dialogs/import_slides_dialog.dart';
import '../dialogs/slide_finder_dialog.dart';
import '../slides/slide_thumbnail.dart';

class SlideListPanel extends ConsumerStatefulWidget {
  const SlideListPanel({super.key});

  @override
  ConsumerState<SlideListPanel> createState() => _SlideListPanelState();
}

class _SlideListPanelState extends ConsumerState<SlideListPanel> {
  String _query = '';
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode(debugLabel: 'SlideListPanel');
  final Map<String, GlobalKey> _slideKeys = {};

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
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

  void _scrollSlideToTop(int index) {
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
      if (target == null) return;

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
  Future<void> _copySlideAsImage(Slide slide) async {
    final deck = ref.read(deckProvider).deck;
    if (deck == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Slide renderen…'),
        duration: Duration(milliseconds: 700),
      ),
    );
    Uint8List? bytes;
    try {
      final images = await SlideRasterizer.rasterize(
        context: context,
        slides: [slide],
        themeProfile: deck.themeProfile,
        projectPath: deck.projectPath,
        tlp: deck.tlp,
      );
      if (images.isNotEmpty) bytes = images.first;
    } catch (_) {}
    if (!mounted) return;
    final ok =
        bytes != null && await ImageService().copyImageBytesToClipboard(bytes);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Slide gekopieerd naar klembord.' : 'Kopiëren mislukt.',
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
        final at = ref.read(deckProvider.notifier).insertSlides([slide]);
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
    if (firstIndex >= 0) editorNotifier.select(firstIndex);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          slides.length == 1
              ? '1 slide geïmporteerd.'
              : '${slides.length} slides geïmporteerd.',
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      height: 30,
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _query = v),
        style: const TextStyle(color: Colors.white, fontSize: 12),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Zoek in slides…',
          hintStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          prefixIcon: const Icon(
            Icons.search,
            size: 15,
            color: Color(0xFF6B7280),
          ),
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
                  icon: const Icon(Icons.clear, color: Color(0xFF6B7280)),
                  onPressed: () => setState(() {
                    _searchController.clear();
                    _query = '';
                  }),
                ),
          filled: true,
          fillColor: const Color(0xFF1B1E25),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFF3A3F4B)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFF3A3F4B)),
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
                color: Color(0xFF4A4F5B),
              ),
              const SizedBox(height: 10),
              Text(
                'Geen slides met "$query"',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
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
          projectPath: deck.projectPath,
          themeProfile: deck.themeProfile,
          slideCount: deck.slides.length,
          tlp: deck.tlp,
          onTap: () => _onSlideTap(index),
          onToggleSkip: () => notifier.toggleSkip(index),
          onCopyImage: () => _copySlideAsImage(slide),
          onDuplicate: () {
            notifier.duplicateSlide(index);
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

  @override
  Widget build(BuildContext context) {
    final deckState = ref.watch(deckProvider);
    final deck = deckState.deck!;
    _pruneSlideKeys(deck);
    final editor = ref.watch(editorProvider);
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
          color: AppTheme.panelBg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──────────────────────────────────────────────────────
              Container(
                color: const Color(0xFF252830),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'SLIDES',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
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
                          style: const TextStyle(
                            color: Color(0xFF64748B),
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
                child: searching
                    ? _buildFilteredList(
                        deck,
                        query,
                        editor,
                        notifier,
                        editorNotifier,
                      )
                    : ReorderableListView.builder(
                        scrollController: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        buildDefaultDragHandles: false,
                        itemCount: deck.slides.length,
                        onReorderItem: (old, nw) {
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
                          editorNotifier.select(
                            newSel.clamp(0, deck.slides.length - 1),
                          );
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
                            projectPath: deck.projectPath,
                            themeProfile: deck.themeProfile,
                            slideCount: deck.slides.length,
                            tlp: deck.tlp,
                            onTap: () => _onSlideTap(i),
                            onToggleSkip: () => notifier.toggleSkip(i),
                            onCopyImage: () => _copySlideAsImage(slide),
                            onDuplicate: () {
                              notifier.duplicateSlide(i);
                              editorNotifier.select(i + 1);
                            },
                            onDelete: () {
                              if (deck.slides.length <= 1) return;
                              notifier.removeSlide(i);
                              editorNotifier.clampIndex(deck.slides.length - 2);
                            },
                          );
                        },
                      ),
              ),

              // ── Add / Paste slide buttons ─────────────────────────────────
              Container(
                color: const Color(0xFF252830),
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
                              .pasteImage();
                          if (path == null) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Geen afbeelding op het klembord gevonden.',
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
                            Slide.create(
                              SlideType.image,
                            ).copyWith(imagePath: path),
                          );
                          editorNotifier.select(newIdx);
                        },
                        icon: const Icon(Icons.image_outlined, size: 14),
                        label: const Text('Afbeelding plakken'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Color(0xFF4A4F5B)),
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
                        label: const Text('Slide toevoegen'),
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
                        icon: const Icon(
                          Icons.travel_explore_outlined,
                          size: 14,
                        ),
                        label: const Text('Slide zoeken'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Color(0xFF4A4F5B)),
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
                        label: const Text('Slides importeren'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Color(0xFF4A4F5B)),
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
                            notifier.updateSlide(
                              newIdx,
                              Slide.duplicate(clipboard),
                            );
                            editorNotifier.select(newIdx);
                          },
                          icon: const Icon(Icons.content_paste, size: 14),
                          label: const Text('Slide plakken'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Color(0xFF4A4F5B)),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Smalle balk bovenin de slidelijst die toont hoeveel slides overgeslagen
/// worden, met één knop om alle markeringen ineens te wissen.
class _SkipBanner extends StatelessWidget {
  final int count;
  final VoidCallback onClearAll;

  const _SkipBanner({required this.count, required this.onClearAll});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
      decoration: BoxDecoration(
        color: const Color(0x33B8860B),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF8A6D3B)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.visibility_off_outlined,
            size: 13,
            color: Color(0xFFD4A24E),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              count == 1
                  ? '1 slide overgeslagen'
                  : '$count slides overgeslagen',
              style: const TextStyle(
                color: Color(0xFFE3C281),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: onClearAll,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFD4A24E),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              minimumSize: const Size(0, 26),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Alles tonen'),
          ),
        ],
      ),
    );
  }
}

// ── Bulk-actiebalk (meervoudige selectie) ─────────────────────────────────────

class _BulkActionBar extends StatelessWidget {
  final int count;
  final VoidCallback onDelete;
  final VoidCallback onSkip;
  final VoidCallback onShow;
  final VoidCallback onDeselect;

  const _BulkActionBar({
    required this.count,
    required this.onDelete,
    required this.onSkip,
    required this.onShow,
    required this.onDeselect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      decoration: BoxDecoration(
        color: const Color(0x332E7D64),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count geselecteerd',
              style: const TextStyle(
                color: Color(0xFFE2E8F0),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _BulkIcon(
            icon: Icons.visibility_off_outlined,
            tooltip: 'Overslaan bij presenteren/exporteren',
            onTap: onSkip,
          ),
          _BulkIcon(
            icon: Icons.visibility_outlined,
            tooltip: 'Weer tonen',
            onTap: onShow,
          ),
          _BulkIcon(
            icon: Icons.delete_outline,
            tooltip: 'Verwijderen',
            color: const Color(0xFFE5746E),
            onTap: onDelete,
          ),
          _BulkIcon(
            icon: Icons.close,
            tooltip: 'Selectie opheffen',
            onTap: onDeselect,
          ),
        ],
      ),
    );
  }
}

class _BulkIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _BulkIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 16),
        onPressed: onTap,
        color: color ?? const Color(0xFFCBD5E1),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
