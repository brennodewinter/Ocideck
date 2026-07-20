// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// Preview for a `discoveries` slide: the objects this scan turned up that
/// nobody knew existed, each drawn as a bar of how long it sat there unnoticed.
/// Content comes from [DiscoveriesSpec.fromSlide].
///
/// The slide leads with the **longest exposure**, not with the count. "Twaalf
/// nieuwe objecten" is a scan result and reads as housekeeping; "één stond
/// veertien maanden open" is the sentence the room remembers. The count and the
/// unowned tally follow underneath, where they belong.
///
/// Every bar is scaled to the longest exposure on the slide, exactly as the
/// asset overview scales to its largest group: per-row scaling would draw three
/// days the width of four hundred and the picture would contradict the figures.
///
/// Exposure and ownership are two separate axes and get two separate channels —
/// the bar says how long, the right-hand column says whose. Colouring the bar by
/// ownership would fuse two facts into one mark and neither would survive a
/// greyscale print. Only "geen eigenaar" is red, and it stays red across themes
/// because it carries meaning rather than styling — the same exception the
/// scorecard and asset slides make.
class _DiscoveriesPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _DiscoveriesPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  double get _nameWidth => w * 0.26;

  double get _daysWidth => w * 0.13;

  double get _ownerWidth => w * 0.19;

  double get _gap => w * 0.014;

  /// An exposure written out for a reader: the figure from
  /// [scaleDaysUnnoticed] with the matching word.
  String _exposureLabel(AppLocalizations l10n, int days) {
    final scaled = scaleDaysUnnoticed(days);
    if (scaled.inMonths) {
      return '${scaled.value} '
          '${scaled.value == 1 ? l10n.d('maand') : l10n.d('maanden')}';
    }
    return '${scaled.value} '
        '${scaled.value == 1 ? l10n.d('dag') : l10n.d('dagen')}';
  }

  Widget _head(String label, Color text, double width, TextAlign align) =>
      SizedBox(
        width: width,
        child: Text(
          label,
          textAlign: align,
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

  /// The headline: the worst exposure on the slide, stated in words before any
  /// row is read. Absent entirely when no row carries a figure — a first scan
  /// has no history to measure against and must not imply one.
  Widget _headline(DiscoveriesSpec spec, AppLocalizations l10n, Color text) {
    final longest = spec.longestUnnoticed;
    if (longest == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: w * 0.028),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            _exposureLabel(l10n, longest),
            style: _applyFont(
              font,
              TextStyle(
                fontSize: w * 0.055,
                fontWeight: FontWeight.w800,
                color: AppTheme.danger700,
              ),
            ),
          ),
          SizedBox(width: _gap),
          Flexible(
            child: Text(
              l10n.d('langst onopgemerkt bereikbaar'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _applyFont(
                font,
                TextStyle(
                  fontSize: w * 0.019,
                  fontWeight: FontWeight.w600,
                  color: text.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerRow(AppLocalizations l10n, Color text) => Padding(
    padding: EdgeInsets.only(bottom: w * 0.012),
    child: Row(
      children: [
        SizedBox(width: _nameWidth + _gap),
        Expanded(child: _head(l10n.d('onopgemerkt'), text, w, TextAlign.left)),
        SizedBox(width: _gap),
        _head('', text, _daysWidth, TextAlign.right),
        SizedBox(width: _gap),
        _head(l10n.d('eigenaar'), text, _ownerWidth, TextAlign.left),
      ],
    ),
  );

  /// The name of the find, with the kind of object underneath it in smaller
  /// muted type. Two lines rather than one wide column: a hostname is long and
  /// the kind is short, so stacking them keeps the bars their full width.
  Widget _nameCell(Discovery discovery, Color text) => SizedBox(
    width: _nameWidth,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          discovery.name,
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
        if (discovery.kind.isNotEmpty)
          Text(
            discovery.kind,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _applyFont(
              font,
              TextStyle(
                fontSize: w * 0.016,
                color: text.withValues(alpha: 0.55),
              ),
            ),
          ),
      ],
    ),
  );

  /// The exposure bar. An unknown exposure draws no bar at all rather than a
  /// zero-length one: "we do not know" and "found immediately" are different
  /// statements and the slide must not turn the first into the second.
  /// [index] only names the bar for the widget test that checks the shared
  /// scale — the one claim of this layout that cannot be read off the text.
  Widget _bar(DiscoveriesSpec spec, Discovery discovery, int index) {
    final barHeight = w * 0.016;
    return LayoutBuilder(
      // The Align matters: this sits in an [Expanded], which hands its child a
      // *tight* width. Without a loose parent the Container would be stretched
      // to the full row and every bar would draw the same length whatever the
      // exposure — the picture silently contradicting the figures beside it.
      builder: (context, constraints) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          key: ValueKey('discoveries-bar-$index'),
          width: constraints.maxWidth * spec.barFraction(discovery),
          height: barHeight,
          decoration: BoxDecoration(
            color: _hexColor(profile.accentColor),
            borderRadius: BorderRadius.circular(barHeight / 2),
          ),
        ),
      ),
    );
  }

  Widget _daysCell(Discovery discovery, AppLocalizations l10n, Color text) {
    final days = discovery.daysUnnoticed;
    return SizedBox(
      width: _daysWidth,
      child: Text(
        days == null ? l10n.d('onbekend') : _exposureLabel(l10n, days),
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _applyFont(
          font,
          TextStyle(
            fontSize: w * 0.019,
            fontWeight: days == null ? FontWeight.w400 : FontWeight.w700,
            color: days == null ? text.withValues(alpha: 0.4) : text,
          ),
        ),
      ),
    );
  }

  Widget _ownerCell(Discovery discovery, AppLocalizations l10n, Color text) =>
      SizedBox(
        width: _ownerWidth,
        child: Text(
          discovery.hasOwner ? discovery.owner : l10n.d('geen eigenaar'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _applyFont(
            font,
            TextStyle(
              fontSize: w * 0.018,
              fontWeight: discovery.hasOwner
                  ? FontWeight.w500
                  : FontWeight.w700,
              color: discovery.hasOwner
                  ? text.withValues(alpha: 0.75)
                  : AppTheme.danger700,
            ),
          ),
        ),
      );

  Widget _discoveryRow(
    DiscoveriesSpec spec,
    Discovery discovery,
    int index,
    AppLocalizations l10n,
    Color text,
  ) => Padding(
    padding: EdgeInsets.only(bottom: w * 0.016),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _nameCell(discovery, text),
        SizedBox(width: _gap),
        Expanded(child: _bar(spec, discovery, index)),
        SizedBox(width: _gap),
        _daysCell(discovery, l10n, text),
        SizedBox(width: _gap),
        _ownerCell(discovery, l10n, text),
      ],
    ),
  );

  /// The bottom line: how many finds and how many of them nobody owns. Derived
  /// from the rows, never stored, so it cannot disagree with them.
  Widget _totalsRow(DiscoveriesSpec spec, AppLocalizations l10n, Color text) {
    final parts = [
      '${spec.count} '
          '${spec.count == 1 ? l10n.d('ontdekking') : l10n.d('ontdekkingen')}',
      // Same wording as the asset overview's banner, so the two reporting
      // slides name the governance problem identically.
      if (spec.unownedCount > 0)
        '${spec.unownedCount} ${l10n.d('geen eigenaar')}',
    ];
    return Column(
      children: [
        Container(
          height: 1,
          margin: EdgeInsets.only(bottom: w * 0.012),
          color: text.withValues(alpha: 0.15),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            parts.join('  ·  '),
            maxLines: 1,
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
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pad = w * 0.07;
    final hPad = w * 0.045;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final spec = DiscoveriesSpec.fromSlide(slide.title, slide.tableRows);
    final text = _hexColor(profile.textColor);
    final discoveries = spec.discoveries.where((d) => !d.isBlank).toList();

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
                    SizedBox(height: w * 0.025),
                  ],
                  if (discoveries.isNotEmpty) ...[
                    _headline(spec, l10n, text),
                    _headerRow(l10n, text),
                    for (var i = 0; i < discoveries.length; i++)
                      _discoveryRow(spec, discoveries[i], i, l10n, text),
                    _totalsRow(spec, l10n, text),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
