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

class _TimelinePreview extends StatefulWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;
  final bool presentationMode;
  final int? revealedCount;

  const _TimelinePreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
    required this.presentationMode,
    this.revealedCount,
  });

  @override
  State<_TimelinePreview> createState() => _TimelinePreviewState();
}

class _TimelinePreviewState extends State<_TimelinePreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool get _animatesOnEnter =>
      widget.presentationMode &&
      widget.revealedCount == null &&
      widget.slide.timelineReveal == TimelineReveal.onEnter;

  /// Effective draw-in duration: the slide's override, or the theme's shared
  /// activation duration when the slide inherits (null), clamped to range.
  int get _durationMs => clampTimelineDuration(
    widget.slide.timelineAnimationMs ?? widget.profile.animationDurationMs,
  );

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
    );
    _maybeStart();
  }

  @override
  void didUpdateWidget(_TimelinePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slide.id != widget.slide.id ||
        !listEquals(oldWidget.slide.bullets, widget.slide.bullets) ||
        oldWidget.slide.timelineReveal != widget.slide.timelineReveal ||
        oldWidget.slide.timelineAnimationMs !=
            widget.slide.timelineAnimationMs ||
        oldWidget.profile.animationDurationMs !=
            widget.profile.animationDurationMs ||
        oldWidget.presentationMode != widget.presentationMode ||
        oldWidget.revealedCount != widget.revealedCount) {
      _maybeStart();
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

  @override
  void dispose() {
    _controller.dispose();
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
                : AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => _TimelineCanvas(
                      events: events,
                      w: widget.w,
                      horizontal: _effectiveHorizontal(events.length),
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
                  ),
          ),
        ],
      ),
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

  const _TlLayout(
    this.nodes,
    this.scale,
    this.showDesc,
    this.descLines,
    this.titleLines,
    this.nodeRadius,
  );
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
class _TimelineCanvas extends StatelessWidget {
  final List<TimelineEvent> events;
  final double w; // full slide width, for uniform typography
  final bool horizontal;
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
    required this.horizontal,
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
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final n = events.length;
        final layout = horizontal
            ? _horizontalLayout(size, n)
            : _verticalLayout(size, n);
        final nodes = layout.nodes;
        final reveal = _revealFactors(n);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _TimelineRailPainter(
                  nodes: nodes,
                  reveal: reveal,
                  spineStart: nodes.first.pos,
                  spineEnd: nodes.last.pos,
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
  _TlLayout _horizontalLayout(Size size, int n) {
    final aw = size.width;
    final ah = size.height;
    final railY = ah * 0.5;
    final startX = aw * 0.06;
    final endX = aw * 0.94;
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
    final baseCardW = (spacing * 1.7).clamp(aw * 0.17, aw * 0.27).toDouble();
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
        .clamp(aw * 0.18, aw * 0.42)
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
  _TlLayout _verticalLayout(Size size, int n) {
    final aw = size.width;
    final ah = size.height;
    final spineX = aw * 0.5;
    final top = ah * 0.06;
    final bottom = ah * 0.965;
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
}

/// A single event card: marker badge, title, optional description. Sizes to its
/// content; typography scales from the slide width [w] times [scale] so all
/// cards match while dense timelines shrink. When [showDescription] is false the
/// card collapses to a compact one-line `badge + title` entry.
class _TimelineCard extends StatelessWidget {
  final TimelineEvent event;
  final bool emphasized;

  /// Marks the explicit current point ("you are here"): a stronger tint, a
  /// solid accent border and a soft glow, one visual step above [emphasized].
  final bool isCurrent;
  final double w;
  final double scale;
  final bool showDescription;
  final int descLines;
  final int titleLines;
  final double cardWidth;
  final Color accent;
  final Color onAccent;
  final Color textColor;
  final Color muted;
  final String font;

  const _TimelineCard({
    super.key,
    required this.event,
    required this.emphasized,
    required this.isCurrent,
    required this.w,
    required this.scale,
    required this.showDescription,
    required this.descLines,
    required this.titleLines,
    required this.cardWidth,
    required this.accent,
    required this.onAccent,
    required this.textColor,
    required this.muted,
    required this.font,
  });

  @override
  Widget build(BuildContext context) {
    final hasMarker = event.marker.trim().isNotEmpty;
    final hasTitle = event.title.trim().isNotEmpty;
    final badge = hasMarker ? _badge() : null;
    // Both fields get the line budget the fit search proved they can have: a
    // headline that needs two lines gets two rather than losing half its words.
    final title = hasTitle ? _title(maxLines: titleLines) : null;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.012,
        vertical: w * 0.009 * scale,
      ),
      // Surfaces are tinted with the profile accent so the timeline visibly
      // belongs to the presentation's colour scheme rather than a neutral grey.
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isCurrent ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(w * 0.009),
        border: Border.all(
          color: isCurrent
              ? accent
              : emphasized
              ? accent.withValues(alpha: 0.7)
              : accent.withValues(alpha: 0.22),
          width: isCurrent
              ? 2.0
              : emphasized
              ? 1.6
              : 1.0,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.30),
                  blurRadius: w * 0.014,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Marker and title share one line, so the description gets the row
          // that a stacked badge would otherwise take.
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Bounded rather than flexible: two Flexible children would split
              // the row evenly and starve the title of the space the badge does
              // not need. This keeps the badge at its natural width (capped, so
              // it can never overflow) and hands the remainder to the title —
              // exactly what the fit measurement assumes.
              if (badge != null) ...[
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: _badgeMaxWidth(
                      cardWidth - 2 * (w * 0.012),
                      hasTitle,
                    ),
                  ),
                  child: badge,
                ),
                SizedBox(width: w * 0.01),
              ],
              if (title != null) Expanded(child: title),
            ],
          ),
          if (showDescription) ...[
            SizedBox(height: w * 0.006 * scale),
            Text(
              decodeNamedHtmlEntities(event.description.trim()),
              maxLines: descLines,
              overflow: TextOverflow.ellipsis,
              style: _descStyle(
                w,
                scale,
                font,
              ).copyWith(color: muted, decoration: TextDecoration.none),
            ),
          ],
        ],
      ),
    );
  }

  Widget _badge() => Container(
    padding: EdgeInsets.symmetric(
      horizontal: w * 0.008,
      vertical: w * 0.0028 * scale,
    ),
    decoration: BoxDecoration(
      color: accent,
      borderRadius: BorderRadius.circular(w * 0.02),
    ),
    child: Text(
      decodeNamedHtmlEntities(event.marker.trim()),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _badgeStyle(
        w,
        scale,
        font,
      ).copyWith(color: onAccent, decoration: TextDecoration.none),
    ),
  );

  // Bold but deliberately not oversized — the weight already sets it apart, and
  // keeping it modest leaves room for the description.
  Widget _title({required int maxLines}) => Text(
    decodeNamedHtmlEntities(event.title.trim()),
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    style: _titleStyle(
      w,
      scale,
      font,
    ).copyWith(color: textColor, decoration: TextDecoration.none),
  );
}

/// Paints the glowing spine, the connector stubs and the nodes. Text lives in
/// the overlaid card widgets, so this painter is purely the line-art.
class _TimelineRailPainter extends CustomPainter {
  final List<_TlNode> nodes;
  final List<double> reveal;
  final Offset spineStart;
  final Offset spineEnd;
  final double spineProgress;
  final double nodeRadius;

  /// Node of the explicit current point; null = none. That node grows and gets
  /// a halo ring, replacing the size bump the last node gets by default.
  final int? currentIndex;
  final Color accent;
  final Color bg;

  _TimelineRailPainter({
    required this.nodes,
    required this.reveal,
    required this.spineStart,
    required this.spineEnd,
    required this.spineProgress,
    required this.nodeRadius,
    required this.currentIndex,
    required this.accent,
    required this.bg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;
    final drawnEnd = Offset.lerp(spineStart, spineEnd, spineProgress)!;
    final trackW = math.max(2.0, nodeRadius * 0.42);

    // Faint full-length track so you can see where the timeline is going.
    canvas.drawLine(
      spineStart,
      spineEnd,
      Paint()
        ..color = accent.withValues(alpha: 0.16)
        ..strokeWidth = trackW
        ..strokeCap = StrokeCap.round,
    );
    // Soft glow under the drawn portion.
    canvas.drawLine(
      spineStart,
      drawnEnd,
      Paint()
        ..color = accent.withValues(alpha: 0.14)
        ..strokeWidth = nodeRadius * 1.5
        ..strokeCap = StrokeCap.round,
    );
    // Bright drawn spine.
    canvas.drawLine(
      spineStart,
      drawnEnd,
      Paint()
        ..color = accent
        ..strokeWidth = trackW * 1.4
        ..strokeCap = StrokeCap.round,
    );

    // Connectors from each revealed node to its card.
    for (var i = 0; i < nodes.length; i++) {
      final r = reveal[i];
      if (r <= 0.01) continue;
      final node = nodes[i];
      canvas.drawLine(
        node.pos,
        Offset.lerp(node.pos, node.connector, r)!,
        Paint()
          ..color = accent.withValues(alpha: 0.35 * r)
          ..strokeWidth = math.max(1.0, nodeRadius * 0.16),
      );
    }

    // Nodes on top.
    for (var i = 0; i < nodes.length; i++) {
      final r = reveal[i];
      if (r <= 0.01) continue;
      final node = nodes[i];
      final current = i == currentIndex;
      // Without an explicit current point the last node keeps its subtle bump.
      final last = currentIndex == null && i == nodes.length - 1;
      final rad =
          nodeRadius *
          (0.55 + 0.45 * r) *
          (current
              ? 1.35
              : last
              ? 1.18
              : 1.0);
      canvas.drawCircle(
        node.pos,
        rad * 2.1,
        Paint()
          ..color = accent.withValues(
            alpha:
                (current
                    ? 0.24
                    : last
                    ? 0.18
                    : 0.12) *
                r,
          ),
      );
      if (current) {
        // Halo ring: the "you are here" marker around the current node.
        canvas.drawCircle(
          node.pos,
          rad * 1.9,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.2, rad * 0.28)
            ..color = accent.withValues(alpha: 0.55 * r),
        );
      }
      canvas.drawCircle(node.pos, rad, Paint()..color = accent);
      canvas.drawCircle(
        node.pos,
        rad,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, rad * 0.34)
          ..color = bg,
      );
      canvas.drawCircle(node.pos, rad * 0.32, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(_TimelineRailPainter old) =>
      old.spineProgress != spineProgress ||
      !listEquals(old.reveal, reveal) ||
      old.nodeRadius != nodeRadius ||
      old.currentIndex != currentIndex ||
      old.accent != accent ||
      old.bg != bg ||
      old.nodes.length != nodes.length;
}
