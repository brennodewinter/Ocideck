// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// Preview for a `scorecard` slide: a handful of headline figures, each on its
/// own card, with the change since the previous report beneath it. Content comes
/// from [ScorecardSpec.fromSlide].
///
/// The cards fill the slide rather than sitting in a single thin band at the
/// top: a scorecard is the one slide in a report that is *meant* to be read from
/// the back of the room, so the figures claim the height they need. How they are
/// arranged follows from how many there are — see [_ScorecardLayout] — and one
/// lone figure becomes a hero, at a size no grid could give it.
///
/// Colours follow the deck's [ThemeProfile]: the card tint and rule are the
/// profile's accent, so a scorecard picks up the house style instead of
/// introducing a second one. The *sentiment* colours are the exception: good and
/// bad news stay green and red regardless of the palette, for the same reason
/// the heatmap keeps its own ramp. They carry meaning rather than styling, and a
/// brand-tinted "improvement" is not readable as one. They are fixed [AppTheme]
/// tokens, so an export isolate rasterises the same slide the editor shows.
class _ScorecardPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _ScorecardPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  /// The colour a change is drawn in. Neutral movement borrows the body text
  /// colour at reduced weight rather than a grey of its own, so it sits in the
  /// deck's palette instead of beside it.
  Color _sentimentColor(ScorecardSentiment sentiment, Color text) =>
      switch (sentiment) {
        ScorecardSentiment.good => AppTheme.success700,
        ScorecardSentiment.bad => AppTheme.danger700,
        ScorecardSentiment.neutral => text.withValues(alpha: 0.55),
      };

  IconData _directionIcon(ScorecardDirection direction) => switch (direction) {
    ScorecardDirection.up => Icons.arrow_upward_rounded,
    ScorecardDirection.down => Icons.arrow_downward_rounded,
    ScorecardDirection.flat => Icons.remove_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final pad = w * 0.055;
    final hPad = w * 0.045;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final spec = ScorecardSpec.fromSlide(slide.title, slide.tableRows);
    final text = _hexColor(profile.textColor);
    final accent = _hexColor(profile.accentColor);
    final entries = spec.entries.where((e) => !e.isBlank).toList();
    final layout = _ScorecardLayout.of(entries.length);

    return Container(
      color: _hexColor(profile.slideBackgroundColor),
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox(
            // A fixed slide-shaped box rather than a min-height column: the
            // cards below claim the leftover height with Expanded, which is
            // what lets one figure grow into a hero instead of floating in a
            // strip at the top.
            width: w,
            height: w * 9 / 16,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                hPad,
                pad + safe.top,
                hPad,
                _logoAwareBottomPadding(pad, safe.bottom),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (spec.title.isNotEmpty) ...[
                    Text(
                      spec.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _applyFont(
                        font,
                        TextStyle(
                          fontSize: w * 0.04,
                          fontWeight: FontWeight.w700,
                          color: text,
                        ),
                      ),
                    ),
                    SizedBox(height: w * 0.03),
                  ],
                  Expanded(
                    child: _grid(context, entries, layout, text, accent),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The cards, arranged in the rows [_ScorecardLayout] prescribes. A row that
  /// is short of the widest row's card count is padded with empty flex, so five
  /// figures read as three above two of the same width, rather than two
  /// stretched cards under three narrow ones.
  Widget _grid(
    BuildContext context,
    List<ScorecardEntry> entries,
    _ScorecardLayout layout,
    Color text,
    Color accent,
  ) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final gap = w * 0.02;
    final rows = layout.rows;
    final widest = rows.reduce((a, b) => a > b ? a : b);

    var index = 0;
    final children = <Widget>[];
    for (var r = 0; r < rows.length; r++) {
      final cells = <Widget>[];
      for (var c = 0; c < rows[r] && index < entries.length; c++) {
        if (cells.isNotEmpty) cells.add(SizedBox(width: gap));
        cells.add(
          Expanded(
            child: _card(context, entries[index++], layout, text, accent),
          ),
        );
      }
      // Keep the cards the same width across rows: the leftover columns of a
      // short last row stay empty rather than being shared out.
      for (var c = rows[r]; c < widest; c++) {
        cells
          ..add(SizedBox(width: gap))
          ..add(const Expanded(child: SizedBox.shrink()));
      }
      if (children.isNotEmpty) children.add(SizedBox(height: gap));
      children.add(Expanded(child: Row(children: cells)));
    }
    return Column(children: children);
  }

  /// One figure: what it is, what it is now, how it moved, and what it replaced.
  ///
  /// The change line is omitted entirely when there is no previous figure — a
  /// first report shows the number without pretending to a trend — and so is the
  /// "was …" line that would otherwise name a value that does not exist.
  ///
  /// The type is sized from the card the figure actually got, not from the slide
  /// width: the same card is three times as tall with one figure on the slide as
  /// with five, and a fixed fraction of the width would either overflow the
  /// crowded case or waste the roomy one. [_CardMetrics] does the arithmetic.
  Widget _card(
    BuildContext context,
    ScorecardEntry entry,
    _ScorecardLayout layout,
    Color text,
    Color accent,
  ) {
    final l10n = context.l10n;
    final hero = layout.isHero;
    final direction = entry.direction;
    final delta = entry.delta;
    final changeColor = _sentimentColor(entry.sentiment, text);

    return LayoutBuilder(
      builder: (context, constraints) {
        final m = _CardMetrics.measure(
          height: constraints.maxHeight,
          width: constraints.maxWidth,
          slideWidth: w,
          hero: hero,
          label: entry.label,
          font: font,
          hasChange: direction != null && delta != null,
          hasPrevious: entry.previous != null,
        );
        final align = hero
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start;

        return Container(
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(w * 0.014),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A solid accent rule along the top edge: the one piece of
              // full-strength brand colour on the slide, which is enough to tie
              // the card to the deck without colouring the figure itself.
              Container(height: m.barHeight, color: accent),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: m.hPad,
                    vertical: m.vPad,
                  ),
                  child: Column(
                    crossAxisAlignment: align,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (entry.label.isNotEmpty) ...[
                        Text(
                          entry.label,
                          // A label is a few words, not a sentence: let it wrap
                          // onto a second line and cut it there, rather than
                          // pushing the figure out of its card.
                          maxLines: _CardMetrics.labelMaxLines,
                          overflow: TextOverflow.ellipsis,
                          textAlign: hero ? TextAlign.center : TextAlign.start,
                          style: m.labelStyle(font, text),
                        ),
                        SizedBox(height: m.gap),
                      ],
                      _figure(entry, m, text, hero),
                      if (direction != null && delta != null) ...[
                        SizedBox(height: m.gap),
                        _changePill(l10n, direction, delta, changeColor, m),
                      ],
                      if (m.showPrevious) ...[
                        SizedBox(height: m.gap * 0.6),
                        Text(
                          '${l10n.d('was')} ${formatScorecardNumber(entry.previous!)}'
                          '${entry.unit.isEmpty ? '' : ' ${entry.unit}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _applyFont(
                            font,
                            TextStyle(
                              fontSize: m.footnoteSize,
                              color: text.withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The figure itself with its unit beside it. A long figure with a unit can
  /// outgrow its card; shrink it to fit instead of overflowing.
  Widget _figure(ScorecardEntry entry, _CardMetrics m, Color text, bool hero) =>
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: hero ? Alignment.center : Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              entry.value == null ? '—' : formatScorecardNumber(entry.value!),
              style: _applyFont(
                font,
                TextStyle(
                  fontSize: m.figureSize,
                  fontWeight: FontWeight.w700,
                  color: text,
                  height: 1.0,
                  letterSpacing: -m.figureSize * 0.02,
                ),
              ),
            ),
            if (entry.unit.isNotEmpty) ...[
              SizedBox(width: m.figureSize * 0.12),
              Text(
                entry.unit,
                style: _applyFont(
                  font,
                  TextStyle(
                    fontSize: m.unitSize,
                    fontWeight: FontWeight.w600,
                    color: text.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ],
        ),
      );

  /// The change since the previous report, as a tinted pill. The tint is what
  /// makes a rise or a fall legible at a glance; the arrow and the sign keep it
  /// legible once the slide is printed in greyscale and the tint is gone.
  Widget _changePill(
    AppLocalizations l10n,
    ScorecardDirection direction,
    double delta,
    Color color,
    _CardMetrics m,
  ) {
    final size = m.changeSize;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: size * 0.55,
          vertical: size * 0.2,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(size * 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_directionIcon(direction), size: size * 1.05, color: color),
            SizedBox(width: size * 0.2),
            Text(
              direction == ScorecardDirection.flat
                  ? l10n.d('ongewijzigd')
                  : formatScorecardDelta(delta),
              style: _applyFont(
                font,
                TextStyle(
                  fontSize: size,
                  fontWeight: FontWeight.w700,
                  color: color,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How a given number of figures is arranged.
///
/// The row shapes keep the cards square-ish — four figures as 2×2 rather than a
/// single row of four thin columns — because a figure reads better in a block
/// than in a strip, and a squarer card leaves the figure more height to grow
/// into. Sizes are not decided here: they follow from the card each figure ends
/// up with ([_CardMetrics]).
class _ScorecardLayout {
  const _ScorecardLayout._(this.rows);

  /// How many cards each row holds, top to bottom.
  final List<int> rows;

  /// A single figure gets the whole slide and is centred in it.
  bool get isHero => rows.length == 1 && rows.first == 1;

  static _ScorecardLayout of(int count) => switch (count) {
    <= 1 => const _ScorecardLayout._([1]),
    2 => const _ScorecardLayout._([2]),
    3 => const _ScorecardLayout._([3]),
    4 => const _ScorecardLayout._([2, 2]),
    _ => const _ScorecardLayout._([3, 2]),
  };
}

/// The type sizes for one card, derived from the space that card actually got.
///
/// The figure takes whatever the label, the change pill and the "was …" line
/// leave over, which is what makes the same code produce a hero number on a
/// one-figure slide and a legible tile on a five-figure one. The label is
/// *measured* rather than assumed to wrap, so a short label hands its second
/// line to the figure instead of reserving it unused.
///
/// Everything is computed up front rather than left to the layout to sort out:
/// a card that overflows draws Flutter's warning stripes across a slide that is
/// on its way into a client report.
class _CardMetrics {
  const _CardMetrics._({
    required this.barHeight,
    required this.hPad,
    required this.vPad,
    required this.gap,
    required this.labelSize,
    required this.figureSize,
    required this.changeSize,
    required this.footnoteSize,
    required this.showPrevious,
  });

  /// Two lines is where a label stops being a label.
  static const int labelMaxLines = 2;

  final double barHeight;
  final double hPad;
  final double vPad;
  final double gap;
  final double labelSize;
  final double figureSize;
  final double changeSize;
  final double footnoteSize;

  /// Whether the "was …" line fits. It is the first thing dropped when the card
  /// is crowded: the change pill above it already says what moved, so losing it
  /// costs a detail rather than the point.
  final bool showPrevious;

  double get unitSize => changeSize * 1.15;

  TextStyle labelStyle(String font, Color text) => _applyFont(
    font,
    TextStyle(
      fontSize: labelSize,
      fontWeight: FontWeight.w600,
      color: text.withValues(alpha: 0.65),
      height: _labelHeightFactor,
    ),
  );

  static const double _labelHeightFactor = 1.25;

  static _CardMetrics measure({
    required double height,
    required double width,
    required double slideWidth,
    required bool hero,
    required String label,
    required String font,
    required bool hasChange,
    required bool hasPrevious,
  }) {
    // An unbounded card (an intrinsic-size pass) has no budget to divide; fall
    // back to the slide width so the figures stay sane rather than infinite.
    final h = height.isFinite ? height : slideWidth * 0.3;
    final barHeight = slideWidth * 0.005;
    final hPad = width * (hero ? 0.06 : 0.08);
    final vPad = h * 0.08;
    final gap = h * 0.04;

    // Cap every size against the slide width too: on a one-figure slide the
    // card is so tall that a purely height-derived label would outgrow the
    // slide title.
    double cap(double fromHeight, double fraction) =>
        fromHeight < slideWidth * fraction ? fromHeight : slideWidth * fraction;
    final labelSize = cap(h * 0.105, 0.032);
    final changeSize = cap(h * 0.095, 0.026);
    final footnoteSize = cap(h * 0.075, 0.021);

    final labelHeight = label.isEmpty
        ? 0.0
        : _measureLabel(
            label: label,
            font: font,
            fontSize: labelSize,
            maxWidth: width - 2 * hPad,
          );
    final changeHeight = hasChange ? changeSize * 1.6 : 0.0;
    final footnoteHeight = footnoteSize * 1.3;

    double leftover(bool withPrevious) =>
        h -
        barHeight -
        2 * vPad -
        (label.isEmpty ? 0 : labelHeight + gap) -
        (hasChange ? changeHeight + gap : 0) -
        (withPrevious ? footnoteHeight + gap * 0.6 : 0);

    // Try to keep the "was …" line, but not at the price of a figure that is no
    // longer the biggest thing on its own card.
    var showPrevious = hasPrevious;
    var available = leftover(showPrevious);
    if (showPrevious && available < h * 0.22) {
      showPrevious = false;
      available = leftover(false);
    }

    final minimum = h * 0.14;
    final figure = available * 0.94;
    return _CardMetrics._(
      barHeight: barHeight,
      hPad: hPad,
      vPad: vPad,
      gap: gap,
      labelSize: labelSize,
      figureSize: figure < minimum ? minimum : figure,
      changeSize: changeSize,
      footnoteSize: footnoteSize,
      showPrevious: showPrevious,
    );
  }

  /// The height the label will really take, at up to [labelMaxLines] lines.
  static double _measureLabel({
    required String label,
    required String font,
    required double fontSize,
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: _applyFont(
          font,
          TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            height: _labelHeightFactor,
          ),
        ),
      ),
      maxLines: labelMaxLines,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth < 0 ? 0 : maxWidth);
    final height = painter.height;
    painter.dispose();
    return height;
  }
}
