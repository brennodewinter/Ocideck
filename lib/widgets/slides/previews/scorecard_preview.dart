// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// Preview for a `scorecard` slide: a handful of headline figures, each with
/// the change since the previous report underneath it. Content comes from
/// [ScorecardSpec.fromSlide].
///
/// Colours follow the deck's [ThemeProfile] — a scorecard is an ordinary
/// house-style slide, not a security one. The *sentiment* colours are the
/// exception: good and bad news stay green and red regardless of the palette,
/// for the same reason the heatmap keeps its own ramp. They carry meaning
/// rather than styling, and a brand-tinted "improvement" is not readable as
/// one. They are fixed [AppTheme] tokens, so an export isolate rasterises the
/// same slide the editor shows.
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

  /// One figure: what it is, what it is now, and how it moved. The change line
  /// is omitted entirely when there is no previous figure — a first report
  /// shows the number without pretending to a trend.
  Widget _tile(ScorecardEntry entry, AppLocalizations l10n, Color text) {
    final direction = entry.direction;
    final delta = entry.delta;
    final changeColor = _sentimentColor(entry.sentiment, text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          entry.label,
          style: _applyFont(
            font,
            TextStyle(
              fontSize: w * 0.021,
              fontWeight: FontWeight.w600,
              color: text.withValues(alpha: 0.7),
            ),
          ),
        ),
        SizedBox(height: w * 0.008),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              entry.value == null ? '—' : formatScorecardNumber(entry.value!),
              style: _applyFont(
                font,
                TextStyle(
                  fontSize: w * 0.055,
                  fontWeight: FontWeight.w700,
                  color: text,
                  height: 1.05,
                ),
              ),
            ),
            if (entry.unit.isNotEmpty) ...[
              SizedBox(width: w * 0.006),
              Text(
                entry.unit,
                style: _applyFont(
                  font,
                  TextStyle(
                    fontSize: w * 0.022,
                    color: text.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (direction != null && delta != null) ...[
          SizedBox(height: w * 0.008),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _directionIcon(direction),
                size: w * 0.024,
                color: changeColor,
              ),
              SizedBox(width: w * 0.004),
              Text(
                direction == ScorecardDirection.flat
                    ? l10n.d('ongewijzigd')
                    : formatScorecardDelta(delta),
                style: _applyFont(
                  font,
                  TextStyle(
                    fontSize: w * 0.022,
                    fontWeight: FontWeight.w600,
                    color: changeColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pad = w * 0.07;
    final hPad = w * 0.045;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final spec = ScorecardSpec.fromSlide(slide.title, slide.tableRows);
    final text = _hexColor(profile.textColor);
    final entries = spec.entries.where((e) => !e.isBlank).toList();

    return Container(
      color: _hexColor(profile.slideBackgroundColor),
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: w,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                hPad,
                pad + safe.top,
                hPad,
                _logoAwareBottomPadding(pad, safe.bottom),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (spec.title.isNotEmpty) ...[
                    Text(
                      spec.title,
                      style: _applyFont(
                        font,
                        TextStyle(
                          fontSize: w * 0.04,
                          fontWeight: FontWeight.w700,
                          color: text,
                        ),
                      ),
                    ),
                    SizedBox(height: w * 0.05),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < entries.length; i++) ...[
                        Expanded(child: _tile(entries[i], l10n, text)),
                        if (i < entries.length - 1) SizedBox(width: w * 0.03),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
