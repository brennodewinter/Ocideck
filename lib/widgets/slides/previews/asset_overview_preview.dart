// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// Preview for an `assets` slide: the attack surface broken into kinds of
/// object, each drawn as a bar whose filled head is the share needing work,
/// with the four counts aligned in columns. Content comes from
/// [AssetOverviewSpec.fromSlide].
///
/// The counts are **columns with one header**, not labelled figures repeated on
/// every row. Repeating "no owner" eight times spends ink on the label rather
/// than the number, and columns let the reader run an eye down one figure —
/// which is how a table earns its place over a list.
///
/// Every bar is scaled to the **largest group on the slide**, not to its own
/// row. A category of three and a category of three hundred must not draw the
/// same width, or the picture says the opposite of the numbers.
///
/// Colours follow the deck's [ThemeProfile], except the at-risk fill and the
/// unowned count, which stay red because they carry meaning rather than
/// styling — the same exception the scorecard and actions slides make.
class _AssetOverviewPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _AssetOverviewPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  /// Width of each numeric column. Shared by the header, the rows and the
  /// totals so the three always line up.
  double get _colWidth => w * 0.095;

  double get _nameWidth => w * 0.18;

  double get _gap => w * 0.012;

  /// A column heading: small, muted, and truncated rather than allowed to push
  /// the table out of shape when a font runs wide.
  Widget _head(String label, Color text) => SizedBox(
    width: _colWidth,
    child: Text(
      label,
      textAlign: TextAlign.right,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _applyFont(
        font,
        TextStyle(
          fontSize: w * 0.015,
          fontWeight: FontWeight.w600,
          color: text.withValues(alpha: 0.5),
        ),
      ),
    ),
  );

  Widget _num(int value, Color color, {bool emphasised = false}) => SizedBox(
    width: _colWidth,
    child: Text(
      '$value',
      textAlign: TextAlign.right,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _applyFont(
        font,
        TextStyle(
          fontSize: emphasised ? w * 0.026 : w * 0.023,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    ),
  );

  /// A count that means nothing when it is nought: shown, but not shouted.
  Color _tone(int value, Color loud, Color text) =>
      value > 0 ? loud : text.withValues(alpha: 0.3);

  Widget _headerRow(AppLocalizations l10n, Color text) => Padding(
    padding: EdgeInsets.only(bottom: w * 0.012),
    child: Row(
      children: [
        SizedBox(width: _nameWidth + _gap),
        const Expanded(child: SizedBox.shrink()),
        SizedBox(width: _gap),
        _head(l10n.d('gevonden'), text),
        _head(l10n.d('werk'), text),
        _head(l10n.d('nieuw'), text),
        _head(l10n.d('geen eigenaar'), text),
      ],
    ),
  );

  Widget _groupRow(AssetGroup group, Color text, int largest) {
    final share = largest <= 0 ? 0.0 : (group.total / largest).clamp(0.0, 1.0);
    final barHeight = w * 0.016;

    return Padding(
      padding: EdgeInsets.only(bottom: w * 0.014),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _nameWidth,
            child: Text(
              group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _applyFont(
                font,
                TextStyle(
                  fontSize: w * 0.021,
                  fontWeight: FontWeight.w600,
                  color: text,
                ),
              ),
            ),
          ),
          SizedBox(width: _gap),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final full = constraints.maxWidth * share;
                return Stack(
                  children: [
                    Container(
                      width: full,
                      height: barHeight,
                      decoration: BoxDecoration(
                        color: text.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(barHeight / 2),
                      ),
                    ),
                    // The at-risk head sits inside the group's own bar, so the
                    // eye reads it as a share of that group rather than of the
                    // whole estate.
                    Container(
                      width: full * group.atRiskFraction,
                      height: barHeight,
                      decoration: BoxDecoration(
                        color: AppTheme.danger700,
                        borderRadius: BorderRadius.circular(barHeight / 2),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          SizedBox(width: _gap),
          _num(group.total, text),
          _num(group.atRisk, _tone(group.atRisk, AppTheme.danger700, text)),
          _num(
            group.newlyFound,
            _tone(group.newlyFound, _hexColor(profile.accentColor), text),
          ),
          _num(group.unowned, _tone(group.unowned, AppTheme.danger700, text)),
        ],
      ),
    );
  }

  /// The bottom line, aligned to the same columns: how big the surface is and
  /// how much of it needs something. Derived from the rows, never stored, so it
  /// cannot disagree with the figures above it.
  Widget _totalsRow(
    AssetOverviewSpec spec,
    AppLocalizations l10n,
    Color text,
  ) => Column(
    children: [
      Container(
        height: 1,
        margin: EdgeInsets.only(bottom: w * 0.012),
        color: text.withValues(alpha: 0.15),
      ),
      Row(
        children: [
          SizedBox(
            width: _nameWidth,
            child: Text(
              l10n.d('objecten in beeld'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _applyFont(
                font,
                TextStyle(
                  fontSize: w * 0.018,
                  fontWeight: FontWeight.w600,
                  color: text.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          SizedBox(width: _gap),
          const Expanded(child: SizedBox.shrink()),
          SizedBox(width: _gap),
          _num(spec.totalAssets, text, emphasised: true),
          _num(
            spec.totalAtRisk,
            _tone(spec.totalAtRisk, AppTheme.danger700, text),
            emphasised: true,
          ),
          _num(
            spec.totalNew,
            _tone(spec.totalNew, _hexColor(profile.accentColor), text),
            emphasised: true,
          ),
          _num(
            spec.totalUnowned,
            _tone(spec.totalUnowned, AppTheme.danger700, text),
            emphasised: true,
          ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pad = w * 0.07;
    final hPad = w * 0.045;
    final spec = AssetOverviewSpec.fromSlide(slide.title, slide.tableRows);
    final text = _hexColor(profile.textColor);
    final groups = spec.groups.where((g) => !g.isBlank).toList();
    final largest = spec.largestGroup;

    return _PreviewScaffold(
      width: w,
      slide: slide,
      profile: profile,
      horizontalPadding: hPad,
      verticalPadding: pad,
      background: _hexColor(profile.slideBackgroundColor),
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
          SizedBox(height: w * 0.03),
        ],
        if (groups.isNotEmpty) _headerRow(l10n, text),
        for (final group in groups) _groupRow(group, text, largest),
        if (groups.isNotEmpty) _totalsRow(spec, l10n, text),
      ],
    );
  }
}
