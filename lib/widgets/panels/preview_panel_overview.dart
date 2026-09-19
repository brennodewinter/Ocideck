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

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
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
    final editor = ref.read(editorProvider);
    if (editor.hasMultiSelection &&
        editor.selection.contains(oldIndex) &&
        editor.selection.contains(newIndex)) {
      return;
    }
    applySlideReorder(
      oldIndex,
      newIndex.clamp(0, deck.slides.length - 1),
      editor: editor,
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
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: AppTheme.panelBg,
        appBar: AppBar(
          title: Text(
            widget.editable
                ? '${deck.title} — ${l10n.d('Slide-overzicht')}'
                : '${deck.title} — ${l10n.d('volledig deck')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          backgroundColor: AppTheme.navy,
          leading: IconButton(
            tooltip: l10n.d('Sluiten'),
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          actions: widget.editable
              ? [
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
        _columns = (constraints.maxWidth / (timedPreset ? 280 : 320))
            .floor()
            .clamp(1, timedPreset ? 5 : 6);
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
                    onReorder: (oldIndex) => _reorder(oldIndex, index),
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
              style: TextStyle(color: AppTheme.slate500, fontSize: 11),
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
        ? PresenterPalette.laserGreen
        : validation.excessSlides > 0
        ? Theme.of(context).colorScheme.error
        : AppTheme.amber600;
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
                    style: const TextStyle(
                      color: PresenterPalette.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${validation.requiredSlides} ${l10n.d('dia\'s')} × '
                    '${timing.slideDuration.inSeconds} ${l10n.d('seconden')}  ·  '
                    '${_clock(validation.targetDuration!)}',
                    style: const TextStyle(
                      color: PresenterPalette.textMuted,
                      fontFeatures: [FontFeature.tabularFigures()],
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
    required this.onReorder,
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
  final ValueChanged<int> onReorder;
  final VoidCallback? onMovePrevious;
  final VoidCallback? onMoveNext;
  final bool outsideTimedFormat;

  Map<CustomSemanticsAction, VoidCallback> _semanticActions(
    AppLocalizations l10n,
  ) {
    final actions = <CustomSemanticsAction, VoidCallback>{};
    final previous = onMovePrevious;
    final next = onMoveNext;
    if (previous != null) {
      actions[CustomSemanticsAction(label: l10n.d('Vorige'))] = previous;
    }
    if (next != null) {
      actions[CustomSemanticsAction(label: l10n.d('Volgende'))] = next;
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
                  feedback: Material(
                    color: Colors.transparent,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppTheme.navy,
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
                          style: const TextStyle(
                            color: Colors.white,
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
      onWillAcceptWithDetails: (details) => !readOnly && details.data != index,
      onAcceptWithDetails: (details) => onReorder(details.data),
      builder: (context, candidates, rejected) {
        final targeted = candidates.isNotEmpty;
        final colorScheme = Theme.of(context).colorScheme;
        final borderColor = outsideTimedFormat
            ? Theme.of(context).colorScheme.error
            : targeted
            ? AppTheme.accent
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
                border: Border.all(color: borderColor, width: targeted ? 3 : 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: selected || targeted ? 0.34 : 0.18,
                    ),
                    blurRadius: selected || targeted ? 14 : 8,
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
