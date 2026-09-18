part of '../slide_preview.dart';

extension _TimelinePreviewDispatch on SlidePreviewWidget {
  /// Uit [_buildContent] gehaald zodat die methode onder het lengteplafond
  /// blijft; de constructie leunt op de widget-velden van [SlidePreviewWidget].
  Widget _timelineContent(Slide slide, double w) => _TimelinePreview(
    slide: slide,
    w: w,
    font: fontFamily,
    profile: themeProfile,
    presentationMode: presentationMode,
    scrollable: scrollableTimeline,
    viewController: timelineViewController,
    interactive: timelineInteractive,
    revealedCount: timelineRevealedCount,
  );
}

/// Eye-candy timeline renderer.
///
/// The graphics (glowing spine, nodes, connectors) are painted by
/// [_TimelineRailPainter]; the event cards are real widgets layered on top so
/// their text stays crisp. Cards size to their content. When a horizontal rail
/// gets crowded the cards are distributed across several *floors* (heights) so
/// they tile instead of colliding — full cards, just at varying distances from
/// the line.
///
/// Animation: the line is the starting point — it draws itself first, then the
/// events are placed onto it one after another (sequentially).
///
/// Reveal modes:
/// * [revealedCount] non-null → step mode: exactly that many events are shown
///   (driven by the presenter, click-by-click).
/// * else, in [presentationMode] with [TimelineReveal.onEnter] → the line draws,
///   then events appear in sequence, on a one-shot controller.
/// * otherwise everything is shown at once (editor, thumbnails, static mode).
///
/// The spine draw is a fixed, snappy [kTimelineLineDrawMs] regardless of the
/// activation duration; only the per-event reveal stretches with the duration.
const int kTimelineLineDrawMs = 450;

/// Aantal keren dat de kaartgeometrie inclusief tekstmetingen is berekend.
///
/// Alleen bedoeld voor de regressietest die bewaakt dat een tijdlijnanimatie
/// deze dure, inhoudsafhankelijke stap niet op ieder frame herhaalt.
@visibleForTesting
int timelineLayoutMeasurementPasses = 0;

@visibleForTesting
void resetTimelineLayoutMeasurementPasses() {
  timelineLayoutMeasurementPasses = 0;
}

/// Size-independent timeline viewport shared between presenter and audience.
/// Pixels differ per display, so only the 0..1 position along the rail crosses
/// the window boundary. Like reveal progress, this is session-only render state.
class TimelineViewController extends ChangeNotifier {
  double _fraction = 0;

  double get fraction => _fraction;

  void setFraction(double value) {
    final next = value.clamp(0.0, 1.0).toDouble();
    if ((next - _fraction).abs() < 0.0005) return;
    _fraction = next;
    notifyListeners();
  }
}

class _TimelinePreview extends StatefulWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;
  final bool presentationMode;
  final bool scrollable;
  final TimelineViewController? viewController;
  final bool interactive;
  final int? revealedCount;

  const _TimelinePreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
    required this.presentationMode,
    required this.scrollable,
    required this.viewController,
    required this.interactive,
    this.revealedCount,
  });

  @override
  State<_TimelinePreview> createState() => _TimelinePreviewState();
}

class _TimelinePreviewState extends State<_TimelinePreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final ScrollController _scrollController;
  bool _reduceMotion = false;

  bool get _animatesOnEnter =>
      widget.presentationMode &&
      !_reduceMotion &&
      widget.revealedCount == null &&
      widget.slide.timelineReveal == TimelineReveal.onEnter;

  /// Effective draw-in duration: the slide's override, or the theme's shared
  /// activation duration when the slide inherits (null), clamped to range.
  int get _durationMs => clampTimelineDuration(
    widget.slide.timelineAnimationMs ?? widget.profile.animationDurationMs,
  );

  /// A thumbnail cannot give six cards the same reading room as a full slide.
  /// Keep the rail model identical, but shorten its viewport responsively so a
  /// date stays a date instead of an ellipsis with a connector attached.
  int get _viewportEvents {
    if (widget.w < 320) return 4;
    if (widget.w < 560) return 5;
    return timelineViewportEvents;
  }

  /// Share of the controller spent drawing the spine. Derived from a fixed
  /// wall-clock budget so the line stays snappy (~[kTimelineLineDrawMs]) even
  /// when the overall duration is long; capped at 0.45 so a very short duration
  /// still leaves the events more than half the time.
  double get _lineFraction =>
      (kTimelineLineDrawMs / _durationMs).clamp(0.02, 0.45);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _durationMs),
      value: 1,
    )..addListener(_followDrawIn);
    _scrollController = ScrollController()..addListener(_publishView);
    widget.viewController?.addListener(_applySharedView);
    _maybeStart();
    _afterLayout(_applySharedView);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion == _reduceMotion) return;
    _reduceMotion = reduceMotion;
    _maybeStart();
  }

  @override
  void didUpdateWidget(_TimelinePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewController != widget.viewController) {
      oldWidget.viewController?.removeListener(_applySharedView);
      widget.viewController?.addListener(_applySharedView);
      _afterLayout(_applySharedView);
    }
    if (oldWidget.slide.id != widget.slide.id ||
        !listEquals(oldWidget.slide.bullets, widget.slide.bullets) ||
        oldWidget.slide.timelineReveal != widget.slide.timelineReveal ||
        oldWidget.slide.timelineAnimationMs !=
            widget.slide.timelineAnimationMs ||
        oldWidget.profile.animationDurationMs !=
            widget.profile.animationDurationMs ||
        oldWidget.presentationMode != widget.presentationMode ||
        oldWidget.revealedCount != widget.revealedCount) {
      final newSlide = oldWidget.slide.id != widget.slide.id;
      final newContent = !listEquals(
        oldWidget.slide.bullets,
        widget.slide.bullets,
      );
      _maybeStart();
      if (newSlide || newContent) {
        _afterLayout(() => _scrollTo(0, animate: false));
      } else if (oldWidget.revealedCount != widget.revealedCount &&
          widget.revealedCount != null) {
        _afterLayout(_followRevealedEvent);
      }
    }
  }

  void _maybeStart() {
    _controller.duration = Duration(milliseconds: _durationMs);
    if (_animatesOnEnter) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 1;
    }
  }

  void _afterLayout(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback();
    });
  }

  /// Keeps the newest event in view while the on-enter animation advances.
  /// The controller is the clock for both reveal and scrolling, so the rail
  /// never drifts out of sync with the cards or the audience window.
  void _followDrawIn() {
    if (!_animatesOnEnter || !_scrollController.hasClients) return;
    final progress = ((_controller.value - _lineFraction) / (1 - _lineFraction))
        .clamp(0.0, 1.0);
    _scrollTo(
      _scrollController.position.maxScrollExtent *
          Curves.easeInOutCubic.transform(progress),
      animate: false,
    );
  }

  /// Step mode uses the same viewport, but lets the presenter's click be the
  /// clock. A short glide makes the spatial move clear without delaying the
  /// next event reveal.
  void _followRevealedEvent() {
    if (!_scrollController.hasClients) return;
    final total = parseTimelineEvents(widget.slide.bullets).length;
    if (total <= 1) return;
    final lastRevealed = ((widget.revealedCount ?? 1) - 1).clamp(0, total - 1);
    final fraction = lastRevealed / (total - 1);
    _scrollTo(
      _scrollController.position.maxScrollExtent * fraction,
      animate: !_reduceMotion,
    );
  }

  void _scrollTo(double offset, {required bool animate}) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = offset.clamp(0.0, position.maxScrollExtent).toDouble();
    if (animate) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    } else if ((position.pixels - target).abs() > 0.25) {
      _scrollController.jumpTo(target);
    }
  }

  void _publishView() {
    if (!widget.interactive || widget.viewController == null) return;
    final position = _scrollController.position;
    final max = position.maxScrollExtent;
    widget.viewController!.setFraction(max <= 0 ? 0 : position.pixels / max);
  }

  void _applySharedView() {
    final controller = widget.viewController;
    if (controller == null || !_scrollController.hasClients) return;
    _scrollTo(
      _scrollController.position.maxScrollExtent * controller.fraction,
      animate: false,
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_followDrawIn);
    _controller.dispose();
    widget.viewController?.removeListener(_applySharedView);
    _scrollController.removeListener(_publishView);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final events = parseTimelineEvents(widget.slide.bullets);
    final bg = AppTheme.parseHexColor(widget.profile.slideBackgroundColor);
    final accent = AppTheme.parseHexColor(widget.profile.accentColor);
    final textColor = AppTheme.parseHexColor(widget.profile.textColor);
    // Secondary text is the configured text colour, only slightly softened so it
    // still reads as the same colour as the rest of the slides.
    final muted = textColor.withValues(alpha: 0.74);
    // Text on the accent badge prefers the profile's title-text colour (what the
    // theme uses for text on accent/dark bars), but falls back to black/white
    // when that colour doesn't contrast with the accent — so the marker can
    // never become unreadable on an unlucky palette.
    final onAccent = _readableOn(
      accent,
      AppTheme.parseHexColor(widget.profile.titleTextColor),
    );

    final pad = widget.w * 0.045;
    final logoSafe = widget.slide.showLogo
        ? _logoSafeInsets(widget.w, widget.profile, corner: true)
        : EdgeInsets.zero;
    final outerPadding = EdgeInsets.fromLTRB(
      pad + logoSafe.left,
      pad + logoSafe.top,
      pad + logoSafe.right,
      _logoAwareBottomPadding(pad, logoSafe.bottom),
    );

    final title = widget.slide.title.trim();

    return Container(
      color: bg,
      padding: outerPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty) ...[
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: widget.w * 0.036,
                fontFamily: widget.font,
                fontWeight: FontWeight.w800,
                decoration: TextDecoration.none,
                height: 1.08,
              ),
            ),
            SizedBox(height: widget.w * 0.025),
          ],
          Expanded(
            child: events.isEmpty
                ? const SizedBox.expand()
                : _timelineSurface(
                    events: events,
                    accent: accent,
                    onAccent: onAccent,
                    bg: bg,
                    textColor: textColor,
                    muted: muted,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _timelineSurface({
    required List<TimelineEvent> events,
    required Color accent,
    required Color onAccent,
    required Color bg,
    required Color textColor,
    required Color muted,
  }) {
    final horizontal = _effectiveHorizontal(events.length);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final intervals = math.max(1, events.length - 1);
        final visibleIntervals = math.max(1, _viewportEvents - 1);
        final extentFactor = widget.scrollable
            ? math.max(1.0, intervals / visibleIntervals)
            : 1.0;
        final contentSize = horizontal
            ? Size(viewport.width * extentFactor, viewport.height)
            : Size(viewport.width, viewport.height * extentFactor);

        Widget canvas() => AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _TimelineCanvas(
            events: events,
            w: widget.w,
            viewportSize: viewport,
            horizontal: horizontal,
            staticLayout: !widget.scrollable,
            drawT: _controller.value,
            lineFraction: _lineFraction,
            revealedCount: widget.revealedCount,
            currentIndex: _validCurrentIndex(events.length),
            animating: _animatesOnEnter,
            accent: accent,
            onAccent: onAccent,
            bg: bg,
            textColor: textColor,
            muted: muted,
            font: widget.font,
          ),
        );

        if (!widget.scrollable || extentFactor == 1) return canvas();
        return RawScrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          interactive: true,
          thickness: math.max(3.0, widget.w * 0.0045),
          radius: Radius.circular(widget.w * 0.01),
          thumbColor: accent.withValues(alpha: 0.72),
          padding: EdgeInsets.all(widget.w * 0.004),
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
            physics: const ClampingScrollPhysics(),
            child: SizedBox(
              width: contentSize.width,
              height: contentSize.height,
              child: canvas(),
            ),
          ),
        );
      },
    );
  }

  /// The slide's current-point index, but only when it actually points at one
  /// of the parsed events — a stale (hand-edited) index highlights nothing.
  int? _validCurrentIndex(int count) {
    final i = widget.slide.timelineCurrentIndex;
    return (i != null && i >= 0 && i < count) ? i : null;
  }

  /// Auto uses the horizontal multi-floor rail (it tiles cards across heights,
  /// so it stays elegant well into the teens) and only switches to a vertical
  /// spine for very long timelines; an explicit choice always wins.
  bool _effectiveHorizontal(int count) {
    switch (widget.slide.timelineLayout) {
      case TimelineLayout.horizontal:
        return true;
      case TimelineLayout.vertical:
        return false;
      case TimelineLayout.auto:
        return count <= 14;
    }
  }
}

/// One node's geometry: the dot on the spine, where its card sits, and the point
/// on the card edge the connector should reach.
class _TlNode {
  final Offset pos;
  final double cardLeft;
  final double cardWidth;
  final double anchorTop; // Positioned `top` for the card
  final double
  vertAnchor; // FractionalTranslation y: 0 below, -1 above, -.5 centre
  final Offset connector; // point on the card edge

  const _TlNode({
    required this.pos,
    required this.cardLeft,
    required this.cardWidth,
    required this.anchorTop,
    required this.vertAnchor,
    required this.connector,
  });
}

/// The result of laying out a timeline for the available area: the nodes plus
/// the shared content settings (font scale, whether descriptions fit, how many
/// description lines the room allows, node size).
class _TlLayout {
  final List<_TlNode> nodes;
  final double scale;
  final bool showDesc;
  final int descLines;
  final int titleLines;
  final double nodeRadius;
  final List<_TlSpine> spines;

  _TlLayout(
    this.nodes,
    this.scale,
    this.showDesc,
    this.descLines,
    this.titleLines,
    this.nodeRadius,
  ) : spines = [_TlSpine(nodes.first.pos, nodes.last.pos)];

  _TlLayout.withSpines(
    this.nodes,
    this.scale,
    this.showDesc,
    this.descLines,
    this.titleLines,
    this.nodeRadius,
    this.spines,
  );
}

class _TlSpine {
  final Offset start;
  final Offset end;

  const _TlSpine(this.start, this.end);
}

/// Returns [preferred] when it has enough contrast against [bg] to stay legible,
/// otherwise black or white — whichever reads on [bg]. Used for the marker badge
/// text, which sits on the accent colour.
Color _readableOn(Color bg, Color preferred) {
  double rel(Color c) => c.computeLuminance();
  double contrast(Color a, Color b) {
    final hi = math.max(rel(a), rel(b)) + 0.05;
    final lo = math.min(rel(a), rel(b)) + 0.05;
    return hi / lo;
  }

  if (contrast(bg, preferred) >= 3.0) return preferred;
  return rel(bg) > 0.5 ? AppTheme.forestDark : Colors.white;
}

/// Lays out the spine, nodes and cards for the available area, then stacks the
/// painted graphics under the (content-hugging) card widgets.
class _TimelineCanvas extends StatefulWidget {
  final List<TimelineEvent> events;
  final double w; // full slide width, for uniform typography
  final Size viewportSize;
  final bool horizontal;
  final bool staticLayout;
  final double drawT;
  final int? revealedCount;

  /// Index of the event marked as the current point (validated by the caller);
  /// null = none. When set, it takes over the highlight the last event gets by
  /// default, so the deck shows exactly one "you are here".
  final int? currentIndex;
  final bool animating;
  final Color accent;
  final Color onAccent;
  final Color bg;
  final Color textColor;
  final Color muted;
  final String font;

  /// Fraction of the animation spent drawing the line before events appear.
  /// Computed from a fixed wall-clock budget (see [kTimelineLineDrawMs]) so the
  /// spine always snaps in quickly regardless of the overall activation
  /// duration — only the event reveal stretches with a longer duration.
  final double lineFraction;

  const _TimelineCanvas({
    required this.events,
    required this.w,
    required this.viewportSize,
    required this.horizontal,
    required this.staticLayout,
    required this.drawT,
    required this.revealedCount,
    required this.currentIndex,
    required this.animating,
    required this.accent,
    required this.onAccent,
    required this.bg,
    required this.textColor,
    required this.muted,
    required this.font,
    required this.lineFraction,
  });

  @override
  State<_TimelineCanvas> createState() => _TimelineCanvasState();
}

class _TimelineCanvasState extends State<_TimelineCanvas> {
  _TlLayout? _cachedLayout;
  Size? _cachedSize;

  List<TimelineEvent> get events => widget.events;
  double get w => widget.w;
  Size get viewportSize => widget.viewportSize;
  bool get horizontal => widget.horizontal;
  double get drawT => widget.drawT;
  int? get revealedCount => widget.revealedCount;
  int? get currentIndex => widget.currentIndex;
  bool get animating => widget.animating;
  Color get accent => widget.accent;
  Color get onAccent => widget.onAccent;
  Color get bg => widget.bg;
  Color get textColor => widget.textColor;
  Color get muted => widget.muted;
  String get font => widget.font;
  double get lineFraction => widget.lineFraction;

  @override
  void didUpdateWidget(_TimelineCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameTimelineEvents(oldWidget.events, widget.events) ||
        oldWidget.w != widget.w ||
        oldWidget.viewportSize != widget.viewportSize ||
        oldWidget.horizontal != widget.horizontal ||
        oldWidget.staticLayout != widget.staticLayout ||
        oldWidget.font != widget.font) {
      _cachedLayout = null;
      _cachedSize = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final n = events.length;
        if (_cachedLayout == null || _cachedSize != size) {
          _cachedSize = size;
          _cachedLayout = widget.staticLayout && n > timelineViewportEvents
              ? _staticLayout(size, n)
              : horizontal
              ? _horizontalLayout(size, viewportSize, n)
              : _verticalLayout(size, viewportSize, n);
        }
        final layout = _cachedLayout!;
        final nodes = layout.nodes;
        final reveal = _revealFactors(n);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _TimelineRailPainter(
                  nodes: nodes,
                  spines: layout.spines,
                  reveal: reveal,
                  spineProgress: _spineProgress(n),
                  nodeRadius: layout.nodeRadius,
                  currentIndex: currentIndex,
                  accent: accent,
                  bg: bg,
                ),
              ),
            ),
            for (var i = 0; i < n; i++)
              _card(
                i,
                nodes[i],
                reveal[i],
                layout.scale,
                layout.showDesc,
                layout.descLines,
                layout.titleLines,
              ),
          ],
        );
      },
    );
  }

  Widget _card(
    int i,
    _TlNode node,
    double r,
    double scale,
    bool showDesc,
    int descLines,
    int titleLines,
  ) {
    return Positioned(
      left: node.cardLeft,
      top: node.anchorTop,
      width: node.cardWidth,
      child: FractionalTranslation(
        translation: Offset(0, node.vertAnchor),
        child: IgnorePointer(
          child: Opacity(
            opacity: r.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, (1 - r) * 10),
              child: _TimelineCard(
                key: ValueKey('timeline-card-$i'),
                event: events[i],
                // With an explicit current point that card carries the (strong)
                // highlight; otherwise the last event keeps its subtle default.
                emphasized: currentIndex == null && i == events.length - 1,
                isCurrent: i == currentIndex,
                w: w,
                scale: scale,
                showDescription:
                    showDesc && events[i].description.trim().isNotEmpty,
                descLines: descLines,
                titleLines: titleLines,
                cardWidth: node.cardWidth,
                accent: accent,
                onAccent: onAccent,
                textColor: textColor,
                muted: muted,
                font: font,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Per-event reveal 0..1. Step mode is binary; on-enter places events in
  /// sequence *after* the line has drawn; otherwise everything is fully shown.
  List<double> _revealFactors(int n) {
    if (revealedCount != null) {
      final shown = revealedCount!.clamp(0, n);
      return [for (var i = 0; i < n; i++) i < shown ? 1.0 : 0.0];
    }
    if (!animating) return List<double>.filled(n, 1.0);
    final eventsT = ((drawT - lineFraction) / (1 - lineFraction)).clamp(
      0.0,
      1.0,
    );
    return [
      for (var i = 0; i < n; i++)
        Curves.easeOutBack.transform(_sequence(eventsT, i, n)).clamp(0.0, 1.0),
    ];
  }

  double _sequence(double eventsT, int i, int n) {
    if (n <= 1) return eventsT;
    final start = (i / n) * 0.9;
    final window = 0.9 / n + 0.12;
    return ((eventsT - start) / window).clamp(0.0, 1.0);
  }

  /// The line draws over the first [lineFraction] of the animation, then stays.
  double _spineProgress(int n) {
    if (revealedCount != null) {
      if (n <= 1) return revealedCount! > 0 ? 1.0 : 0.0;
      final shown = revealedCount!.clamp(0, n);
      if (shown <= 0) return 0.0;
      return ((shown - 1) / (n - 1)).clamp(0.0, 1.0);
    }
    if (!animating) return 1.0;
    return (drawT / lineFraction).clamp(0.0, 1.0);
  }

  /// Horizontal rail. Cards alternate above/below and, when crowded, climb to
  /// further *floors* so they never overlap. Card size adapts to the room each
  /// floor gets, dropping the description only when a floor is genuinely tight.
  _TlLayout _horizontalLayout(Size size, Size viewport, int n) {
    timelineLayoutMeasurementPasses++;
    final aw = size.width;
    final ah = size.height;
    final railY = ah * 0.5;
    final startX = viewport.width * 0.06;
    final endX = aw - viewport.width * 0.06;
    final span = endX - startX;
    final spacing = n > 1 ? span / (n - 1) : span;

    // Vertical room on the smaller side of the rail; reserve a little margin.
    final half = math.min(railY, ah - railY) - ah * 0.02;
    final nearGap = ah * 0.05;
    // De twee verdiepingstellingen hieronder delen allebei door een maat die
    // van de breedte is afgeleid, en een preview wordt vaker *gemeten* dan
    // getekend: een inklappend paneel of een animatie die bij nul begint levert
    // breedte nul, en dan zijn `minPitch` en `spacing` exact nul. `x / 0` is
    // Infinity — of NaN als `x` ook nul is — en `.floor()`/`.ceil()` daarop
    // gooit `Unsupported operation: Infinity or NaN toInt`, een melding die de
    // tijdlijn niet noemt en de deling al helemaal niet. Bij die breedte valt
    // er niets te verdelen, dus is één verdieping het antwoord (#782).
    final minPitch = w * 0.07;
    final maxFloors = minPitch > 0
        ? math.max(1, ((half - nearGap) / minPitch).floor())
        : 1;
    // Decide floors from a comfortable base width: same-side cards sit 2·spacing
    // apart, and a floor holds them only if a card plus a clear gap (the 1.25
    // breathing factor) fits in that span; otherwise climb to another floor.
    final baseCardW = (spacing * 1.7)
        .clamp(viewport.width * 0.17, viewport.width * 0.27)
        .toDouble();
    final widthFloors = spacing > 0
        ? math.max(1, (baseCardW * 1.25 / (2 * spacing)).ceil())
        : 1;
    // The first and last cards are clamped inward to stay on the slide, which
    // shoves them toward their nearest same-side neighbour. With a single floor
    // that neighbour is only 2·spacing away and they collide; a second floor
    // puts it at a different height instead. So as soon as there are two cards
    // per side (n >= 4) prefer two floors — when there is vertical room for it.
    final neededFloors = math.max(n >= 4 ? 2 : 1, widthFloors);
    final floors = math.min(maxFloors, neededFloors);
    final pitch = (half - nearGap) / floors;
    // Widen the cards to use the horizontal room the floors afford
    // (same-side-same-floor nodes are 2·floors·spacing apart), but never so wide
    // that an interior — or inward-clamped edge — card overlaps that neighbour.
    // The edge term accounts for the clamp of the first/last card: it solves
    // `span - cardW >= cardW/2 - startX`, with a little extra breathing room.
    final sameFloorSpan = 2 * floors * spacing;
    final edgeSafeW = (sameFloorSpan + startX) / 1.7;
    // The ceiling used to sit at 0.30·aw, which on a six-event timeline left the
    // cards far narrower than the rail could actually afford — the neighbouring
    // card on the same floor is `sameFloorSpan` away, and the 0.8 factor already
    // guarantees the gap. Raising it lets sentence-length descriptions wrap in
    // two comfortable lines instead of being cut off; `edgeSafeW` still protects
    // the inward-clamped first and last card.
    final cardW = (sameFloorSpan * 0.8)
        .clamp(viewport.width * 0.18, viewport.width * 0.42)
        .toDouble()
        .clamp(0.0, edgeSafeW)
        .toDouble();
    final showDesc = pitch > w * 0.052;
    final fit = _fitCards(events, cardW, pitch, w, showDesc, font);
    final scale = fit.scale;
    final descLines = fit.descLines;
    // Node size scales with the slide width (not the pixel size of this view),
    // so the editor preview and the full-screen presentation match exactly.
    final nodeRadius = math.max(2.5, w * 0.0095);

    final nodes = <_TlNode>[
      for (var i = 0; i < n; i++)
        () {
          final x = n > 1 ? startX + spacing * i : startX + span / 2;
          final above = i.isEven;
          final floor = (i ~/ 2) % floors;
          final cardLeft = (x - cardW / 2)
              .clamp(0.0, math.max(0.0, aw - cardW))
              .toDouble();
          final nearY = above
              ? railY - nearGap - floor * pitch
              : railY + nearGap + floor * pitch;
          // De verbindingslijn zet zich tien pixels binnen de kaartrand, maar
          // een kaart die smaller is dan twintig pixels heeft die ruimte niet:
          // de bovengrens van de clamp zakt dan onder de ondergrens en dat is
          // een `ArgumentError` — dezelfde foutklasse als #714. De marge is
          // daarom hoogstens de halve kaart, en de bovengrens wordt tegen de
          // ondergrens aan gehouden: bij zulke breedtes liggen ze rekenkundig
          // op hetzelfde punt, maar `(cardLeft + cardW) - marge` en
          // `cardLeft + marge` verschillen dan nog in de laatste bit, en dat is
          // genoeg om ze te laten kruisen (#782).
          final connInset = math.min(10.0, cardW / 2);
          final connMin = cardLeft + connInset;
          final connMax = math.max(connMin, cardLeft + cardW - connInset);
          final connX = x.clamp(connMin, connMax).toDouble();
          return _TlNode(
            pos: Offset(x, railY),
            cardLeft: cardLeft,
            cardWidth: cardW,
            anchorTop: nearY,
            vertAnchor: above ? -1.0 : 0.0,
            connector: Offset(connX, nearY),
          );
        }(),
    ];
    return _TlLayout(
      nodes,
      scale,
      showDesc,
      descLines,
      fit.titleLines,
      nodeRadius,
    );
  }

  /// Vertical spine with cards alternating left/right. Used for very long
  /// timelines; cards shrink (and drop the description) as events pack in.
  _TlLayout _verticalLayout(Size size, Size viewport, int n) {
    timelineLayoutMeasurementPasses++;
    final aw = size.width;
    final ah = size.height;
    final spineX = aw * 0.5;
    final top = viewport.height * 0.06;
    final bottom = ah - viewport.height * 0.08;
    final span = bottom - top;
    final spacing = n > 1 ? span / (n - 1) : span;
    final cardW = aw * 0.36;
    final gap = aw * 0.05;

    final nodes = <_TlNode>[
      for (var i = 0; i < n; i++)
        () {
          final y = n > 1 ? top + spacing * i : top + span / 2;
          final leftSide = i.isEven;
          final cardLeft = leftSide ? spineX - gap - cardW : spineX + gap;
          return _TlNode(
            pos: Offset(spineX, y),
            cardLeft: cardLeft,
            cardWidth: cardW,
            anchorTop: y,
            vertAnchor: -0.5,
            connector: Offset(leftSide ? spineX - gap : spineX + gap, y),
          );
        }(),
    ];

    final vSlot = n > 1 ? nodes[1].pos.dy - nodes[0].pos.dy : double.infinity;
    final showDesc = vSlot.isFinite ? vSlot > w * 0.052 : true;
    // A centred card can use the whole slot (half above + half below its node).
    final room = vSlot.isFinite ? vSlot : w * 0.30;
    final fit = _fitCards(events, cardW, room, w, showDesc, font);
    final scale = fit.scale;
    final descLines = fit.descLines;
    // Width-relative node size (matches preview ↔ presentation), capped so dense
    // spines keep the dots from touching.
    var nodeRadius = math.max(2.5, w * 0.0095);
    if (vSlot.isFinite) nodeRadius = math.min(nodeRadius, vSlot * 0.34);
    return _TlLayout(
      nodes,
      scale,
      showDesc,
      descLines,
      fit.titleLines,
      nodeRadius,
    );
  }

  /// Een stilstaand exportbeeld kan niet scrollen. Lange reeksen worden daarom
  /// over meerdere leesbanen verdeeld: iedere gebeurtenis houdt een eigen
  /// rij en de kaarttypografie mag verder schalen dan in de interactieve
  /// kijkstand. Zo blijven alle 64 punten op één pagina zonder overlap staan.
  _TlLayout _staticLayout(Size size, int n) {
    timelineLayoutMeasurementPasses++;
    // Veertien is een bovengrens, geen doel: bij 64 gebeurtenissen worden dit
    // vijf banen van dertien rijen. Dat geeft iedere kaart ook op de smalle
    // editorpreview voldoende hoogte voor marker, titel én toelichting.
    const maxRows = 14;
    final columns = (n / maxRows).ceil();
    final rows = (n / columns).ceil();
    final columnWidth = size.width / columns;
    final top = size.height * 0.035;
    final bottom = size.height * 0.965;
    final rowPitch = rows > 1 ? (bottom - top) / (rows - 1) : bottom - top;
    final spineInset = columnWidth * 0.07;
    final gap = columnWidth * 0.045;
    final cardWidth = columnWidth * 0.84;
    final fit = _fitCards(
      events,
      cardWidth,
      rowPitch * 0.94,
      w,
      true,
      font,
      scaleSteps: const [0.62, 0.56, 0.50, 0.44, 0.40],
    );
    final nodes = <_TlNode>[];
    final spines = <_TlSpine>[];
    for (var column = 0; column < columns; column++) {
      final first = column * rows;
      final count = math.min(rows, n - first);
      final spineX = column * columnWidth + spineInset;
      for (var row = 0; row < count; row++) {
        final y = rows > 1 ? top + row * rowPitch : (top + bottom) / 2;
        nodes.add(
          _TlNode(
            pos: Offset(spineX, y),
            cardLeft: spineX + gap,
            cardWidth: cardWidth,
            anchorTop: y,
            vertAnchor: -0.5,
            connector: Offset(spineX + gap, y),
          ),
        );
      }
      spines.add(_TlSpine(nodes[first].pos, nodes[first + count - 1].pos));
    }
    return _TlLayout.withSpines(
      nodes,
      fit.scale,
      true,
      fit.descLines,
      fit.titleLines,
      math.max(2.0, w * 0.004),
      spines,
    );
  }
}

bool _sameTimelineEvents(List<TimelineEvent> a, List<TimelineEvent> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].marker != b[i].marker ||
        a[i].title != b[i].title ||
        a[i].description != b[i].description) {
      return false;
    }
  }
  return true;
}
