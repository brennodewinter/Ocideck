// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// Preview for an `actions` slide: what has to happen, who carries it, by when,
/// and what is being asked of the room. Content comes from
/// [ActionsSpec.fromSlide].
///
/// Colours follow the deck's [ThemeProfile], except the two that carry meaning
/// rather than styling: an **escalation** and an **overdue** deadline stay red
/// whatever the palette, for the same reason the scorecard keeps its green and
/// red. A brand-tinted "this is late" does not read as late.
///
/// Overdue is judged against the **current date**, not a stored flag, so a deck
/// shown two months after it was written stops claiming everything is on
/// schedule. Reading the clock while rendering follows the footer's `{date}`
/// token, which does the same.
class _ActionsPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _ActionsPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  /// The marker colour for what is being asked. `info` borrows the body text
  /// colour at low opacity so the labelled rows are the ones that catch the eye.
  Color _kindColor(ActionKind kind, Color text) => switch (kind) {
    ActionKind.escalation => AppTheme.danger700,
    ActionKind.decision => _hexColor(profile.accentColor),
    ActionKind.info => text.withValues(alpha: 0.25),
  };

  /// A date as the footer writes it, so the deck has one date format.
  String _date(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year}';
  }

  Widget _chip(String label, Color color) => Container(
    padding: EdgeInsets.symmetric(horizontal: w * 0.008, vertical: w * 0.002),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(w * 0.004),
    ),
    child: Text(
      label,
      style: _applyFont(
        font,
        TextStyle(
          fontSize: w * 0.016,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    ),
  );

  /// The right-hand tail: the deadline, and whether it has passed.
  Widget _deadline(
    ActionItem item,
    AppLocalizations l10n,
    Color text,
    DateTime asOf,
  ) {
    final overdue = item.isOverdue(asOf);
    final color = overdue ? AppTheme.danger700 : text.withValues(alpha: 0.75);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (overdue) ...[
          Icon(
            Icons.warning_amber_rounded,
            size: w * 0.019,
            color: AppTheme.danger700,
          ),
          SizedBox(width: w * 0.004),
        ],
        Text(
          item.due == null ? l10n.d('geen datum') : _date(item.due!),
          style: _applyFont(
            font,
            TextStyle(
              fontSize: w * 0.018,
              fontWeight: overdue ? FontWeight.w700 : FontWeight.w500,
              color: item.due == null ? text.withValues(alpha: 0.4) : color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(
    ActionItem item,
    AppLocalizations l10n,
    Color text,
    DateTime asOf,
  ) {
    final kindColor = _kindColor(item.kind, text);
    final done = item.status == ActionStatus.done;
    final owner = item.owner.trim().isEmpty ? '—' : item.owner.trim();

    return Padding(
      padding: EdgeInsets.only(bottom: w * 0.018),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The marker rides the full row so an escalation is visible before a
          // word of it is read.
          Container(
            width: w * 0.005,
            height: w * 0.042,
            decoration: BoxDecoration(
              color: kindColor,
              borderRadius: BorderRadius.circular(w * 0.003),
            ),
          ),
          SizedBox(width: w * 0.012),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.action,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _applyFont(
                    font,
                    TextStyle(
                      fontSize: w * 0.023,
                      fontWeight: FontWeight.w600,
                      color: done ? text.withValues(alpha: 0.5) : text,
                      // A finished action stays on the slide — that it is done
                      // is the news — but it stops competing for attention.
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                SizedBox(height: w * 0.004),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        owner,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _applyFont(
                          font,
                          TextStyle(
                            fontSize: w * 0.017,
                            color: text.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: w * 0.008),
                    Text(
                      l10n.d(actionStatusDutchLabel(item.status)),
                      style: _applyFont(
                        font,
                        TextStyle(
                          fontSize: w * 0.017,
                          color: text.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: w * 0.012),
          // Only an ask is labelled. An "info" chip on every other row would
          // spend ink saying nothing is required.
          if (item.kind != ActionKind.info) ...[
            _chip(l10n.d(actionKindDutchLabel(item.kind)), kindColor),
            SizedBox(width: w * 0.012),
          ],
          _deadline(item, l10n, text, asOf),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pad = w * 0.07;
    final hPad = w * 0.045;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final spec = ActionsSpec.fromSlide(slide.title, slide.tableRows);
    final text = _hexColor(profile.textColor);
    final items = spec.items.where((i) => !i.isBlank).toList();
    final asOf = DateTime.now();

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
                    SizedBox(height: w * 0.035),
                  ],
                  for (final item in items) _row(item, l10n, text, asOf),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
