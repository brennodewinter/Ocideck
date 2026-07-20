part of '../slide_preview.dart';

/// Meetwerk voor de tijdlijnkaarten.
///
/// Staat los van [_TimelinePreview] omdat het een ander soort code is: geen
/// widgets, maar de vraag "past deze tekst, en zo nee, wat dan wel". Het
/// antwoord bepaalt de lettergrootte en het regelbudget van elke kaart, en de
/// typografie hieronder is dezelfde die de kaart rendert — vandaar dat beide in
/// dit bestand staan en niet uit elkaar kunnen lopen.

/// Lays out [text] in [maxWidth] and reports both the height it takes and
/// whether it had to be cut off at [maxLines]. This is the same measurement the
/// rest of the deck uses (see `slide_layout_metrics.dart`) rather than an
/// estimate from the character count, which cannot know the actual glyph widths
/// of the profile font and so mis-sizes exactly the cards that are tightest.
({double height, double width, bool clipped}) _measureText(
  String text,
  TextStyle style,
  double maxWidth,
  int maxLines,
) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: maxLines,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: math.max(1.0, maxWidth));
  final result = (
    height: tp.height,
    width: tp.width,
    clipped: tp.didExceedMaxLines,
  );
  tp.dispose();
  return result;
}

/// Typography of a card at a given [scale] — kept next to [_TimelineCard] so the
/// measurement below and the widget that renders it cannot drift apart.
TextStyle _badgeStyle(double w, double scale, String font) => TextStyle(
  fontSize: w * 0.0135 * scale,
  fontFamily: font,
  fontWeight: FontWeight.w700,
  height: 1.0,
);

TextStyle _titleStyle(double w, double scale, String font) => TextStyle(
  fontSize: w * 0.0168 * scale,
  fontFamily: font,
  fontWeight: FontWeight.w700,
  height: 1.15,
);

TextStyle _descStyle(double w, double scale, String font) => TextStyle(
  fontSize: w * 0.0135 * scale,
  fontFamily: font,
  fontWeight: FontWeight.w400,
  height: 1.25,
);

/// How wide the marker badge may become. It is laid out at its natural width —
/// the title takes whatever is left — but never past this bound, so a freakishly
/// long marker ellipsises instead of pushing the title out of the card.
double _badgeMaxWidth(double inner, bool hasTitle) =>
    hasTitle ? inner * 0.6 : inner;

/// Height of the tallest card at this scale and line budget, plus whether any
/// text had to be truncated to reach it.
({double height, bool clipped}) _measureCards(
  List<TimelineEvent> events,
  double cardW,
  double w,
  double scale,
  bool showDesc,
  int titleLines,
  int descLines,
  String font,
) {
  final hPad = w * 0.012;
  final vPad = w * 0.009 * scale;
  final badgeHPad = w * 0.008;
  final badgeVPad = w * 0.0028 * scale;
  final badgeGap = w * 0.01;
  final descGap = w * 0.006 * scale;
  final inner = cardW - 2 * hPad;

  var tallest = 0.0;
  var clipped = false;
  for (final e in events) {
    final marker = e.marker.trim();
    final title = e.title.trim();
    final desc = e.description.trim();

    var rowH = 0.0;
    var titleRoom = inner;
    if (marker.isNotEmpty) {
      final m = _measureText(
        marker,
        _badgeStyle(w, scale, font),
        _badgeMaxWidth(inner, title.isNotEmpty),
        1,
      );
      clipped = clipped || m.clipped;
      rowH = m.height + 2 * badgeVPad;
      titleRoom = inner - (m.width + 2 * badgeHPad) - badgeGap;
    }
    if (title.isNotEmpty) {
      final t = _measureText(
        title,
        _titleStyle(w, scale, font),
        titleRoom,
        titleLines,
      );
      clipped = clipped || t.clipped;
      rowH = math.max(rowH, t.height);
    }

    var h = 2 * vPad + rowH;
    if (showDesc && desc.isNotEmpty) {
      final d = _measureText(
        desc,
        _descStyle(w, scale, font),
        inner,
        descLines,
      );
      clipped = clipped || d.clipped;
      h += descGap + d.height;
    }
    tallest = math.max(tallest, h);
  }
  return (height: tallest, clipped: clipped);
}

/// Picks the font [scale] and the title/description line budget for the cards.
///
/// The card has a fixed width and a fixed vertical slot ([room], the pitch to
/// the next card), so the only free variables are the type size and how many
/// lines each field may wrap to. This walks the scale down from its natural size
/// and returns the *first* combination in which every card fits its slot **and**
/// no text is truncated — text staying whole is what we optimise for, since a
/// half-sentence on a timeline destroys the message it exists to carry.
///
/// If no combination shows everything (genuinely too much text for the slide),
/// it falls back to the largest budget that still fits the slot. Overflowing the
/// slot is never an option: cards would collide with the row above.
({double scale, int descLines, int titleLines}) _fitCards(
  List<TimelineEvent> events,
  double cardW,
  double room,
  double w,
  bool showDesc,
  String font,
) {
  const scaleSteps = [1.0, 0.94, 0.88, 0.82, 0.76, 0.70, 0.66, 0.62];
  const maxTitleLines = 2;
  const maxDescLines = 3;

  for (final scale in scaleSteps) {
    for (var titleLines = 1; titleLines <= maxTitleLines; titleLines++) {
      for (var descLines = 1; descLines <= maxDescLines; descLines++) {
        final m = _measureCards(
          events,
          cardW,
          w,
          scale,
          showDesc,
          titleLines,
          descLines,
          font,
        );
        if (!m.clipped && m.height <= room) {
          return (scale: scale, descLines: descLines, titleLines: titleLines);
        }
      }
    }
  }

  // Nothing fits whole. Degrade predictably: smallest type, and the most lines
  // that still stay inside the slot.
  const scale = 0.62;
  var best = (scale: scale, descLines: 1, titleLines: 1);
  for (var titleLines = 1; titleLines <= maxTitleLines; titleLines++) {
    for (var descLines = 1; descLines <= maxDescLines; descLines++) {
      final m = _measureCards(
        events,
        cardW,
        w,
        scale,
        showDesc,
        titleLines,
        descLines,
        font,
      );
      if (m.height <= room) {
        best = (scale: scale, descLines: descLines, titleLines: titleLines);
      }
    }
  }
  return best;
}
