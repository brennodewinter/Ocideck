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
  static const _gridPad = 24.0;
  static const _gridSpacing = 20.0;
  static const _cardAspect = 1.52;
  // Randscroll tijdens slepen (#2361): de buitenste paar pixels van het
  // raster zijn de actieve zone, met snelheid evenredig aan de diepte erin.
  static const _autoScrollZone = 64.0;
  static const _autoScrollMaxStep = 20.0;
  static const _autoScrollInterval = Duration(milliseconds: 16);

  final FocusNode _focusNode = FocusNode(debugLabel: 'SlideOverview');
  final ScrollController _scrollController = ScrollController();
  int _columns = 1;
  // De gesleepte dia en het invoegslot (0..N) dat de pointer nu boven hangt;
  // beide null buiten een sleep om (#2362).
  int? _draggingIndex;
  int? _hoveredSlot;
  // Globale positie van de sleepaanwijzer; de randscroll-tick plant zichzelf
  // steeds opnieuw zodat hij vanzelf stopt zodra er niets meer te scrollen is.
  Offset? _dragPointer;
  Timer? _autoScrollTimer;

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
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

  void _dragChanged(int? index) {
    _dragPointer = null;
    _stopAutoScroll();
    // De sleep-avatar kan over een pop heen leven (Escape tijdens een
    // gesleepte dia): dan is deze state al weg en is er niets bij te werken.
    if (!mounted) return;
    setState(() {
      _draggingIndex = index;
      _hoveredSlot = null;
    });
  }

  /// Volgt de sleepaanwijzer voor randscroll (#2361) via `Draggable`'s
  /// `onDragUpdate`. Een DragTarget-omhulling kan niet: de framework-
  /// hittest stopt bij de eerste accepterende kaart en meldt voorouders
  /// nooit.
  void _trackDragPointer(Offset globalOffset) {
    _dragPointer = globalOffset;
    // Net als _dragChanged kan dit post-dispose vuren via een nog levende
    // sleep-avatar; de controller is dan al weg.
    if (!mounted) return;
    _autoScrollTick();
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  RenderBox? _gridBox() {
    if (!_scrollController.hasClients) return null;
    final box = _scrollController.position.context.notificationContext
        ?.findRenderObject();
    return box is RenderBox && box.hasSize ? box : null;
  }

  /// Scrollsnelheid op dit moment: 0 buiten de randzone, toenemend richting
  /// `_autoScrollMaxStep` naarmate de aanwijzer dichter bij de rand komt.
  double _edgeVelocity() {
    final pointer = _dragPointer;
    final box = _gridBox();
    if (pointer == null || box == null) return 0;
    final dy = box.globalToLocal(pointer).dy;
    final height = box.size.height;
    final zone = math.min(_autoScrollZone, height / 2);
    if (dy < 0 || dy > height) return 0;
    if (dy < zone) return -_autoScrollMaxStep * (1 - dy / zone);
    if (dy > height - zone) {
      return _autoScrollMaxStep * (1 - (height - dy) / zone);
    }
    return 0;
  }

  /// Eén scrollstap. De tick herplant zichzelf alleen als er ook echt
  /// gescrold werd — bij de lijstgrenzen, een drop, annuleren of het verlaten
  /// van de randzone houdt hij vanzelf op (#2361). Omdat het Flutter-framework
  /// tijdens het scrollen geen nieuwe `onMove` stuurt, herberekent de tick de
  /// invoegmarkering uit de rastergeometrie.
  void _autoScrollTick() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    final velocity = _edgeVelocity();
    if (velocity == 0 || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (position.pixels + velocity).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    position.jumpTo(target);
    _hoverSlot(_slotFromPointer());
    _autoScrollTimer = Timer(_autoScrollInterval, _autoScrollTick);
  }

  /// Het invoegslot onder `_dragPointer`, afgeleid uit dezelfde rastermaten
  /// als `GridView` — leesvolgorde, linkerhelft van een kaart is het slot
  /// ervoor, rechterhelft het slot erna.
  int? _slotFromPointer() {
    final pointer = _dragPointer;
    final box = _gridBox();
    final count = ref.read(deckProvider).deck?.slides.length;
    if (pointer == null || box == null || count == null) {
      return null;
    }
    final local = box.globalToLocal(pointer);
    final cellW =
        (box.size.width - _gridPad * 2 - _gridSpacing * (_columns - 1)) /
        _columns;
    final col = ((local.dx - _gridPad) / (cellW + _gridSpacing)).floor().clamp(
      0,
      _columns - 1,
    );
    final inCardX = (local.dx - _gridPad - col * (cellW + _gridSpacing)).clamp(
      0.0,
      cellW,
    );
    final contentY = local.dy + _scrollController.position.pixels - _gridPad;
    final row = (contentY / (cellW / _cardAspect + _gridSpacing)).floor().clamp(
      0,
      count,
    );
    return (row * _columns + col + (inCardX > cellW / 2 ? 1 : 0)).clamp(
      0,
      count,
    );
  }

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
                  controller: _scrollController,
                  padding: const EdgeInsets.all(_gridPad),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _columns,
                    mainAxisSpacing: _gridSpacing,
                    crossAxisSpacing: _gridSpacing,
                    childAspectRatio: _cardAspect,
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
                      onDragPointer: _trackDragPointer,
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
