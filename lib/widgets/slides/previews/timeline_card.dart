part of '../slide_preview.dart';

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
