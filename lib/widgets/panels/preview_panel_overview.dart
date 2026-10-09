part of 'preview_panel.dart';

/// Schermvullende deckweergave. Vanuit de editor is dit een visuele
/// slide-organizer; losse aanroepers kunnen de bestaande alleen-lezen
/// presentatieweergave blijven gebruiken.
class FullDeckPreview extends ConsumerStatefulWidget {
  final Deck deck;
  final ThemeProfile themeProfile;
  final bool editable;

  const FullDeckPreview({
    super.key,
    required this.deck,
    required this.themeProfile,
    this.editable = false,
  });

  @override
  ConsumerState<FullDeckPreview> createState() => _FullDeckPreviewState();
}

class _FullDeckPreviewState extends ConsumerState<FullDeckPreview> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'SlideOverview');
  int _columns = 1;
  // De gesleepte dia en het invoegslot (0..N) dat de pointer nu boven hangt;
  // beide null buiten een sleep om (#2362).
  int? _draggingIndex;
  int? _hoveredSlot;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  double get _zoom => ref.read(settingsProvider).slideOverviewZoom;

  void _zoomTo(double zoom) {
    unawaited(ref.read(settingsProvider.notifier).setSlideOverviewZoom(zoom));
    _focusNode.requestFocus();
  }

  void _zoomBy(double delta) => _zoomTo(_zoom + delta);

  /// Ctrl + muiswiel zoomt, zoals in elke slide-sorter. Zonder Ctrl is het
  /// gewoon scrollen en doet deze listener niets.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !HardwareKeyboard.instance.isControlPressed) {
      return;
    }
    _zoomBy(
      event.scrollDelta.dy < 0
          ? kSlideOverviewZoomStep
          : -kSlideOverviewZoomStep,
    );
  }

  void _select(int index) {
    final keys = HardwareKeyboard.instance;
    final notifier = ref.read(editorProvider.notifier);
    if (keys.isShiftPressed) {
      notifier.selectRange(index);
    } else if (keys.isControlPressed || keys.isMetaPressed) {
      notifier.toggleSelect(index);
    } else {
      notifier.select(index);
    }
    _focusNode.requestFocus();
  }

  void _stepSelection(int delta) {
    final deck = ref.read(deckProvider).deck;
    if (deck == null || deck.slides.isEmpty) return;
    final current = ref.read(editorProvider).selectedIndex;
    _select((current + delta).clamp(0, deck.slides.length - 1));
  }

  void _reorder(int oldIndex, int newIndex) {
    final deck = ref.read(deckProvider).deck;
    if (deck == null || deck.finalized || deck.playOnly) return;
    applySlideReorder(
      oldIndex,
      newIndex.clamp(0, deck.slides.length - 1),
      editor: ref.read(editorProvider),
      notifier: ref.read(deckProvider.notifier),
      editorNotifier: ref.read(editorProvider.notifier),
      slideCount: deck.slides.length,
    );
    _focusNode.requestFocus();
  }

  /// Het blok dat meereist: de multiselectie als de gesleepte dia daarin zit,
  /// anders alleen de gesleepte dia.
  Set<int> _draggedSet() {
    final dragged = _draggingIndex;
    if (dragged == null) return const {};
    final selection = ref.read(editorProvider).selection;
    return selection.contains(dragged) ? selection : {dragged};
  }

  /// Registreert het invoegslot onder de pointer. Slots die niets verplaatsen
  /// (in of direct langs het eigen blok) tonen geen markering.
  void _hoverSlot(int? slot) {
    final deck = ref.read(deckProvider).deck;
    if (slot != null &&
        deck != null &&
        isNoOpInsertSlot(_draggedSet(), slot, deck.slides.length)) {
      slot = null;
    }
    if (slot != _hoveredSlot) setState(() => _hoveredSlot = slot);
  }

  void _dragChanged(int? index) => setState(() {
    _draggingIndex = index;
    _hoveredSlot = null;
  });

  void _dropSlide(int draggedIndex, int slot) {
    final deck = ref.read(deckProvider).deck;
    if (deck == null || deck.finalized || deck.playOnly) return;
    applySlideInsertion(
      draggedIndex,
      slot,
      editor: ref.read(editorProvider),
      notifier: ref.read(deckProvider.notifier),
      editorNotifier: ref.read(editorProvider.notifier),
      slideCount: deck.slides.length,
    );
    _focusNode.requestFocus();
  }

  void _moveSelection(int delta) {
    final deck = ref.read(deckProvider).deck;
    if (deck == null || deck.finalized || deck.playOnly) return;
    final editor = ref.read(editorProvider);
    final selected = editor.selection.toList()..sort();
    if (selected.isEmpty) return;
    final edge = delta < 0 ? selected.first : selected.last;
    final target = edge + delta;
    if (target < 0 || target >= deck.slides.length) return;
    _reorder(edge, target);
  }

  void _undo(bool redo) {
    final notifier = ref.read(deckProvider.notifier);
    redo ? notifier.redo() : notifier.undo();
    final count = notifier.currentState.deck?.slides.length ?? 0;
    ref.read(editorProvider.notifier).clampIndex(count - 1);
    _focusNode.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final modifier = keys.isControlPressed || keys.isMetaPressed;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        Navigator.pop(context);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        modifier ? _moveSelection(-1) : _stepSelection(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        modifier ? _moveSelection(1) : _stepSelection(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        modifier ? _moveSelection(-_columns) : _stepSelection(-_columns);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        modifier ? _moveSelection(_columns) : _stepSelection(_columns);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _select(0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        final count = ref.read(deckProvider).deck?.slides.length ?? 0;
        if (count > 0) _select(count - 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyA when modifier:
        final count = ref.read(deckProvider).deck?.slides.length ?? 0;
        ref.read(editorProvider.notifier).selectAll(count);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyZ when modifier:
        _undo(keys.isShiftPressed);
        return KeyEventResult.handled;
      // Zoomen zoals overal: Cmd/Ctrl met + of −, en 0 terug naar 100%. Beide
      // plustoetsen, want + zit op de meeste indelingen op shift-= en levert
      // dan `equal` in plaats van `add`.
      case LogicalKeyboardKey.equal ||
              LogicalKeyboardKey.add ||
              LogicalKeyboardKey.numpadAdd
          when modifier && widget.editable:
        _zoomBy(kSlideOverviewZoomStep);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.minus || LogicalKeyboardKey.numpadSubtract
          when modifier && widget.editable:
        _zoomBy(-kSlideOverviewZoomStep);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.digit0 || LogicalKeyboardKey.numpad0
          when modifier && widget.editable:
        _zoomTo(1);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final liveState = widget.editable ? ref.watch(deckProvider) : null;
    final deck = liveState?.deck ?? widget.deck;
    final l10n = context.l10n;
    final readOnly = deck.finalized || deck.playOnly;
    final zoom = ref.watch(settingsProvider.select((s) => s.slideOverviewZoom));
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.editable
                ? '${deck.title} — ${l10n.d('Slide-overzicht')}'
                : '${deck.title} — ${l10n.d('volledig deck')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          leading: IconButton(
            tooltip: l10n.d('Sluiten'),
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          actions: widget.editable
              ? [
                  // Zoomen is een kijkvoorkeur, geen bewerking — de knoppen
                  // blijven daarom ook bruikbaar op een verzegeld deck.
                  IconButton(
                    key: const Key('overview-zoom-out'),
                    tooltip: l10n.d('Uitzoomen'),
                    onPressed: zoom > kSlideOverviewZoomMin + 1e-6
                        ? () => _zoomBy(-kSlideOverviewZoomStep)
                        : null,
                    icon: const Icon(Icons.zoom_out, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (zoom != 1)
                    Tooltip(
                      message: l10n.d('Ware grootte'),
                      child: TextButton(
                        onPressed: () => _zoomTo(1),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 32),
                          padding: EdgeInsets.zero,
                        ),
                        child: Text(
                          '${(zoom * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 12,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  IconButton(
                    key: const Key('overview-zoom-in'),
                    tooltip: l10n.d('Inzoomen'),
                    onPressed: zoom < kSlideOverviewZoomMax - 1e-6
                        ? () => _zoomBy(kSlideOverviewZoomStep)
                        : null,
                    icon: const Icon(Icons.zoom_in, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  if (readOnly)
                    Tooltip(
                      message: l10n.d(
                        'Deze presentatie is afgerond en verzegeld en kan niet worden bewerkt.',
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.lock_outline),
                      ),
                    ),
                  IconButton(
                    key: const Key('overview-undo'),
                    tooltip: l10n.d('Ongedaan maken'),
                    onPressed: liveState?.canUndo == true && !readOnly
                        ? () => _undo(false)
                        : null,
                    icon: const Icon(Icons.undo),
                  ),
                  IconButton(
                    key: const Key('overview-redo'),
                    tooltip: l10n.d('Opnieuw'),
                    onPressed: liveState?.canRedo == true && !readOnly
                        ? () => _undo(true)
                        : null,
                    icon: const Icon(Icons.redo),
                  ),
                  const SizedBox(width: 8),
                ]
              : null,
        ),
        body: widget.editable
            ? _organizer(deck, readOnly)
            : _presentedDeck(deck),
      ),
    );
  }

  Widget _organizer(Deck deck, bool readOnly) {
    final editor = ref.watch(editorProvider);
    final settings = ref.watch(settingsProvider);
    final scopeCia = deckScopeCiaIndex(deck.slides);
    final numberStarts = numberedListStarts(deck.slides);
    return LayoutBuilder(
      builder: (context, constraints) {
        final timedPreset = deck.presentationTiming.isTimedPreset;
        final zoom = settings.slideOverviewZoom;
        // De zoom vergroot de streefteel; het kolomplafond schaalt mee, zodat
        // uitzoomen ook echt méér kolommen geeft en inzoomen er minder.
        _columns = (constraints.maxWidth / ((timedPreset ? 280 : 320) * zoom))
            .floor()
            .clamp(1, ((timedPreset ? 5 : 6) / zoom).ceil());
        final itemCount = timedPreset
            ? math.max(
                deck.slides.length,
                deck.presentationTiming.requiredSlides!,
              )
            : deck.slides.length;
        return Column(
          children: [
            if (timedPreset) _TimedPresentationOverviewHeader(deck: deck),
            Expanded(
              child: Listener(
                onPointerSignal: _onPointerSignal,
                child: GridView.builder(
                  key: const Key('slide-overview-grid'),
                  padding: const EdgeInsets.all(24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _columns,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 20,
                    childAspectRatio: 1.52,
                  ),
                  itemCount: itemCount,
                  itemBuilder: (context, index) {
                    if (index >= deck.slides.length) {
                      return _MissingTimedPresentationSlide(index: index);
                    }
                    return _OverviewSlideCard(
                      key: ValueKey('overview-${deck.slides[index].id}'),
                      deck: deck,
                      index: index,
                      selected: editor.selection.contains(index),
                      readOnly: readOnly,
                      settings: settings,
                      scopeCia: scopeCia,
                      numberStart: numberStarts[index],
                      outsideTimedFormat:
                          timedPreset &&
                          index >= (deck.presentationTiming.maxSlides ?? 20),
                      onSelect: () => _select(index),
                      onOpen: () {
                        _select(index);
                        Navigator.pop(context);
                      },
                      onSlotHover: _hoverSlot,
                      onDropSlot: _dropSlide,
                      onDragChanged: _dragChanged,
                      markerBefore: _hoveredSlot == index,
                      slotHints: _draggingIndex != null,
                      onMovePrevious: index == 0
                          ? null
                          : () => _reorder(index, index - 1),
                      onMoveNext: index == deck.slides.length - 1
                          ? null
                          : () => _reorder(index, index + 1),
                    );
                  },
                ),
              ),
            ),
            // Invoegslot N is geen kaart: de doelzone onder het raster biedt
            // "achteraan" als expliciete, altijd bereikbare bestemming.
            if (_draggingIndex != null)
              _OverviewEndSlot(
                active: _hoveredSlot == deck.slides.length,
                onHover: (hover) =>
                    _hoverSlot(hover ? deck.slides.length : null),
                onAccept: (dragged) => _dropSlide(dragged, deck.slides.length),
              ),
          ],
        );
      },
    );
  }

  Widget _presentedDeck(Deck deck) {
    final settings = ref.watch(settingsProvider);
    final renderSlides = expandFindingsForRender(
      deck.slides,
      profile: widget.themeProfile,
    );
    final scopeCia = deckScopeCiaIndex(deck.slides);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 40),
      itemCount: renderSlides.length,
      itemBuilder: (_, index) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${context.l10n.d('Slide')} ${index + 1}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              decoration: const BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 12,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: SlidePreviewWidget(
                slide: renderSlides[index],
                projectPath: deck.projectPath,
                themeProfile: widget.themeProfile,
                deckMarpStyle: deck.marpStyle,
                cockpitColorScheme: settings.cockpitColorScheme,
                allowRemoteMedia: settings.allowRemoteMedia,
                onLinkTap: openExternalUrl,
                slideNumber: index + 1,
                slideCount: renderSlides.length,
                splitRunPosition: splitRunPositionFor(renderSlides, index),
                scopeCia: scopeCia,
                reportLanguage: deck.language,
                improvementY01: deck.improvementY01Metric,
                tlp: deck.tlp,
                organization: deck.organization,
                deckSignature: deck.signature,
                sealedAt: deck.finalized ? deck.sealAt : '',
                showClassificationWatermark:
                    settings.classificationWatermarkEnabled,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimedPresentationOverviewHeader extends StatelessWidget {
  const _TimedPresentationOverviewHeader({required this.deck});

  final Deck deck;

  String _clock(Duration duration) {
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${duration.inMinutes}:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final timing = deck.presentationTiming;
    final validation = timing.validate(deck.slides.length);
    final formatName = timing.isIgnite
        ? l10n.d('Ignite-storyboard')
        : l10n.d('PechaKucha-storyboard');
    final color = validation.isValid
        ? AppTheme.successFg
        : validation.excessSlides > 0
        ? AppTheme.dangerFg
        : AppTheme.warningFg;
    return Material(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(Icons.auto_awesome_motion, color: color, size: 22),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatName,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${validation.requiredSlides} ${l10n.d('dia\'s')} × '
                    '${timing.slideDuration.inSeconds} ${l10n.d('seconden')}  ·  '
                    '${_clock(validation.targetDuration!)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${deck.slides.length} / ${validation.requiredSlides}',
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingTimedPresentationSlide extends StatelessWidget {
  const _MissingTimedPresentationSlide({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '${l10n.d('Slide')} ${index + 1}, ${l10n.d('ontbreekt')}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outlineVariant,
            width: 2,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_photo_alternate_outlined,
                color: colorScheme.onSurfaceVariant,
                size: 30,
              ),
              const SizedBox(height: 8),
              Text(
                '${(index + 1).toString().padLeft(2, '0')}  ·  ${l10n.d('ontbreekt')}',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewSlideCard extends StatelessWidget {
  const _OverviewSlideCard({
    super.key,
    required this.deck,
    required this.index,
    required this.selected,
    required this.readOnly,
    required this.settings,
    required this.scopeCia,
    required this.numberStart,
    required this.onSelect,
    required this.onOpen,
    required this.onSlotHover,
    required this.onDropSlot,
    required this.onDragChanged,
    required this.markerBefore,
    required this.slotHints,
    required this.onMovePrevious,
    required this.onMoveNext,
    this.outsideTimedFormat = false,
  });

  final Deck deck;
  final int index;
  final bool selected;
  final bool readOnly;
  final AppSettings settings;
  final Map<String, CiaRating> scopeCia;
  final int numberStart;
  final VoidCallback onSelect;
  final VoidCallback onOpen;
  final ValueChanged<int?> onSlotHover;
  final void Function(int draggedIndex, int slot) onDropSlot;
  final ValueChanged<int?> onDragChanged;
  final bool markerBefore;
  final bool slotHints;
  final VoidCallback? onMovePrevious;
  final VoidCallback? onMoveNext;
  final bool outsideTimedFormat;

  /// Linkerhelft van de kaart = slot vóór deze dia, rechterhelft = slot erna
  /// (leesvolgorde). Zo dekt elke kaart twee invoegslots zonder eigen tegel.
  int? _slotFor(DragTargetDetails<int> details, BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final dx = box.globalToLocal(details.offset).dx;
    return dx < box.size.width / 2 ? index : index + 1;
  }

  /// Invoegmarkering (#2362): tijdens een sleep een subtiele streep op elke
  /// slotrand; het actieve slot krijgt een volle accentlijn aan de kaartrand.
  List<Widget> _insertMarkers(ColorScheme colorScheme) {
    if (markerBefore) {
      return [
        Positioned(
          key: const Key('insert-marker'),
          left: 0,
          top: 6,
          bottom: 6,
          width: 5,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ];
    }
    if (!slotHints) return const [];
    return [
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
            child: const SizedBox(width: 4, height: 26),
          ),
        ),
      ),
    ];
  }

  Map<CustomSemanticsAction, VoidCallback> _semanticActions(
    AppLocalizations l10n,
  ) {
    final actions = <CustomSemanticsAction, VoidCallback>{};
    final previous = onMovePrevious;
    final next = onMoveNext;
    if (previous != null) {
      actions[CustomSemanticsAction(label: l10n.d('Verplaats vóór'))] =
          previous;
    }
    if (next != null) {
      actions[CustomSemanticsAction(label: l10n.d('Verplaats na'))] = next;
    }
    return actions;
  }

  Widget _footer(BuildContext context, String title, ColorScheme colorScheme) =>
      Container(
        height: 42,
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Row(
          children: [
            if (selected) ...[
              Icon(Icons.check_circle, size: 17, color: colorScheme.primary),
              const SizedBox(width: 7),
            ],
            Expanded(
              child: Text(
                '${index + 1}. $title',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (!readOnly)
              Tooltip(
                message: context.l10n.d('Sorteren'),
                child: Draggable<int>(
                  data: index,
                  onDragStarted: () => onDragChanged(index),
                  onDragEnd: (_) => onDragChanged(null),
                  feedback: Material(
                    color: Colors.transparent,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(color: Colors.black38, blurRadius: 10),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Text(
                          '${index + 1}. $title',
                          style: TextStyle(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  childWhenDragging: const Opacity(
                    opacity: 0.35,
                    child: Icon(Icons.drag_indicator),
                  ),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Icon(
                      Icons.drag_indicator,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final slide = deck.slides[index];
    final l10n = context.l10n;
    final title = slide.title.trim().isEmpty
        ? l10n.d(slide.type.label)
        : slide.title.trim();
    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => !readOnly,
      onMove: (details) {
        final slot = _slotFor(details, context);
        if (slot != null) onSlotHover(slot);
      },
      onLeave: (_) => onSlotHover(null),
      onAcceptWithDetails: (details) {
        final slot = _slotFor(details, context);
        if (slot != null) onDropSlot(details.data, slot);
      },
      builder: (context, candidates, rejected) {
        final colorScheme = Theme.of(context).colorScheme;
        final borderColor = outsideTimedFormat
            ? Theme.of(context).colorScheme.error
            : selected
            ? colorScheme.primary
            : colorScheme.outlineVariant;
        return Semantics(
          button: true,
          selected: selected,
          label:
              '${l10n.d('Slide')} ${index + 1}/${deck.slides.length}: $title',
          customSemanticsActions: readOnly ? const {} : _semanticActions(l10n),
          onTap: onSelect,
          child: GestureDetector(
            onTap: onSelect,
            onDoubleTap: onOpen,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: selected ? 0.34 : 0.18,
                    ),
                    blurRadius: selected ? 14 : 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: ExcludeSemantics(
                          child: RepaintBoundary(
                            child: SlidePreviewWidget(
                              slide: slide,
                              projectPath: deck.projectPath,
                              themeProfile: deck.themeProfile,
                              deckMarpStyle: deck.marpStyle,
                              cockpitColorScheme: settings.cockpitColorScheme,
                              allowRemoteMedia: settings.allowRemoteMedia,
                              slideNumber: index + 1,
                              slideCount: deck.slides.length,
                              fitScaleOverride: sharedSplitFitScale(
                                deck.slides,
                                index,
                                deck.themeProfile,
                                deck.themeProfile.fontFamily,
                              ),
                              splitRunPosition: splitRunPositionFor(
                                deck.slides,
                                index,
                              ),
                              numberStart: numberStart,
                              scopeCia: scopeCia,
                              reportLanguage: deck.language,
                              improvementY01: deck.improvementY01Metric,
                              tlp: deck.tlp,
                              organization: deck.organization,
                              deckSignature: deck.signature,
                              sealedAt: deck.finalized ? deck.sealAt : '',
                              showClassificationWatermark:
                                  settings.classificationWatermarkEnabled,
                              decodeMaxEdge: 512,
                            ),
                          ),
                        ),
                      ),
                      _footer(context, title, colorScheme),
                    ],
                  ),
                  if (outsideTimedFormat)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text(
                            l10n.d('Buiten het format'),
                            style: TextStyle(
                              color: colorScheme.onErrorContainer,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // De markering hangt aan de kaartrand — de kaart zelf is
                  // geen dropdoel meer.
                  ..._insertMarkers(colorScheme),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Dropdoel voor invoegslot N ("achteraan"). Alleen zichtbaar tijdens een
/// sleep: het slot na de laatste dia hangt niet aan een kaart en heeft dus een
/// eigen doelzone nodig (#2362).
class _OverviewEndSlot extends StatelessWidget {
  const _OverviewEndSlot({
    required this.active,
    required this.onHover,
    required this.onAccept,
  });

  final bool active;
  final ValueChanged<bool> onHover;
  final ValueChanged<int> onAccept;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => true,
      onMove: (_) => onHover(true),
      onLeave: (_) => onHover(false),
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidates, rejected) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 32,
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 10),
        decoration: BoxDecoration(
          color: active
              ? colorScheme.primary.withValues(alpha: 0.14)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? colorScheme.primary : colorScheme.outlineVariant,
            width: active ? 2.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            context.l10n.d('Achteraan plaatsen'),
            style: TextStyle(
              color: active
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
