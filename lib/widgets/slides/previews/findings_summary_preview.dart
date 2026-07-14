// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// Preview for a `findingsSummary` slide (PENTEST_MIAUW §4.3.4 / §11): the title,
/// the total finding count, and a bar chart of findings per CVSS severity band
/// (via `fl_chart`), with a legend carrying the exact per-band counts. Content
/// comes from [FindingsSummarySpec.fromSlide]; the bar colours are the
/// deterministic [FindingSeverityPalette] tokens so it renders identically in an
/// export isolate. The chart is drawn without animation so a rasterised export
/// captures the settled bars.
class _FindingsSummaryPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _FindingsSummaryPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pad = w * 0.07; // vertical margin
    final hPad = w * 0.045; // narrower side margin — use the width (feedback)
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final spec = FindingsSummarySpec.fromSlide(slide.title, slide.tableRows);

    return Container(
      color: Colors.white,
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
                  if (spec.title.isNotEmpty)
                    Text(
                      spec.title,
                      style: _applyFont(
                        font,
                        TextStyle(
                          fontSize: w * 0.04,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.navy,
                        ),
                      ),
                    ),
                  SizedBox(height: w * 0.015),
                  Text(
                    '${l10n.d('Totaal')}: ${spec.total}',
                    style: _applyFont(
                      font,
                      TextStyle(fontSize: w * 0.026, color: AppTheme.slate600),
                    ),
                  ),
                  SizedBox(height: w * 0.008),
                  // Retest is always named — also when nothing was resolved.
                  Text(
                    '${l10n.d('Opgelost na hertest')}: ${spec.resolved}',
                    style: _applyFont(
                      font,
                      TextStyle(
                        fontSize: w * 0.024,
                        color: AppTheme.success700,
                      ),
                    ),
                  ),
                  SizedBox(height: w * 0.03),
                  SizedBox(height: w * 0.42, child: _chart(spec)),
                  SizedBox(height: w * 0.03),
                  _legend(context, spec),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chart(FindingsSummarySpec spec) {
    final maxCount = FindingsSummarySpec.order
        .map(spec.countOf)
        .fold(0, (a, b) => a > b ? a : b);
    // fl_chart needs a positive axis; give a little headroom above the tallest
    // bar so it never touches the top edge.
    final maxY = (maxCount <= 0 ? 1 : maxCount) * 1.25;
    return BarChart(
      BarChartData(
        maxY: maxY,
        minY: 0,
        alignment: BarChartAlignment.spaceEvenly,
        barGroups: [
          for (var i = 0; i < FindingsSummarySpec.order.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: spec.countOf(FindingsSummarySpec.order[i]).toDouble(),
                  color: FindingSeverityPalette.of(
                    FindingsSummarySpec.order[i],
                    profile: profile,
                  ),
                  width: w * 0.06,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(w * 0.004),
                  ),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY,
                    color: AppTheme.navy.withValues(alpha: 0.04),
                  ),
                ),
              ],
            ),
        ],
        titlesData: const FlTitlesData(show: false),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
      ),
      duration: Duration.zero,
    );
  }

  Widget _legend(BuildContext context, FindingsSummarySpec spec) {
    final l10n = context.l10n;
    return Wrap(
      spacing: w * 0.03,
      runSpacing: w * 0.015,
      children: [
        for (final band in FindingsSummarySpec.order)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: w * 0.02,
                height: w * 0.02,
                decoration: BoxDecoration(
                  color: FindingSeverityPalette.of(band, profile: profile),
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: w * 0.012),
              Text(
                '${l10n.d(findingsSeverityDutchLabel(band))}: ${spec.countOf(band)}',
                style: _applyFont(
                  font,
                  TextStyle(
                    fontSize: w * 0.022,
                    color: AppTheme.slate700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
