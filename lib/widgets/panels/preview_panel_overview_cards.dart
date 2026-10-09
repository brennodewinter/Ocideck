part of 'preview_panel.dart';

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
    required this.onDragPointer,
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
  final ValueChanged<Offset> onDragPointer;
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
                  onDragUpdate: (details) =>
                      onDragPointer(details.globalPosition),
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
