// Part of the slide_preview library — see ../slide_preview.dart.
// The shared chart legend (series chips and the pie/donut slice key). Lifted
// out of the _ChartPreviewState extension when the legend started reacting to
// plot hover too (#2286) — as its own widget it shares the emphasis index and
// one hover callback, and the class drops back under its size ceiling.
part of '../slide_preview.dart';

/// De legenda onder een grafiek: reeks-chips voor de cartesian typen, of een
/// slice-sleutel voor pie/donut ([pie]). [emphasised] is de te benadrukken
/// entry (chip-hover, plot-hover of de gespiegelde hover van het andere
/// scherm); die krijgt een getinte chip terwijl de rest vervaagt.
/// [onHoverEntry] meldt een chip-hover als reeks- of slice-index.
class _ChartLegend extends StatelessWidget {
  const _ChartLegend({
    required this.spec,
    required this.textColor,
    required this.w,
    required this.font,
    required this.labelScale,
    required this.presentationMode,
    required this.pie,
    required this.emphasised,
    required this.seriesColor,
    required this.onHoverEntry,
  });

  final ChartSpec spec;
  final Color textColor;
  final double w;
  final String font;
  final double labelScale;
  final bool presentationMode;
  final bool pie;
  final int? emphasised;
  final Color Function(ChartSeries series, int index) seriesColor;
  final ValueChanged<int?> onHoverEntry;

  /// True wanneer een andere entry benadrukt wordt, zodat [index] vervaagt.
  bool _dimmed(int index) => emphasised != null && emphasised != index;

  @override
  Widget build(BuildContext context) =>
      pie ? _buildPieKey(context) : _buildSeriesChips(context);

  Widget _buildSeriesChips(BuildContext context) {
    return SizedBox(
      height: w * 0.03,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < spec.series.length; i++) ...[
              if (i > 0) SizedBox(width: w * 0.01),
              MouseRegion(
                onEnter: (_) => onHoverEntry(i),
                onExit: (_) => onHoverEntry(null),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: _dimmed(i) ? 0.4 : 1,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: w * 0.01,
                      vertical: w * 0.004,
                    ),
                    decoration: BoxDecoration(
                      color: emphasised == i
                          ? seriesColor(
                              spec.series[i],
                              i,
                            ).withValues(alpha: 0.18)
                          : textColor.withValues(alpha: 0.045),
                      borderRadius: BorderRadius.circular(w),
                      border: Border.all(
                        color: emphasised == i
                            ? seriesColor(spec.series[i], i)
                            : Colors.transparent,
                        width: w * 0.0015,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: w * 0.012,
                          height: w * 0.012,
                          decoration: BoxDecoration(
                            color: seriesColor(spec.series[i], i),
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: w * 0.006),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: w * 0.16),
                          child: Text(
                            spec.series[i].name.isEmpty
                                ? '${context.l10n.d('Reeks')} ${i + 1}'
                                : decodeNamedHtmlEntities(spec.series[i].name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _applyFont(
                              font,
                              TextStyle(
                                fontSize: w * 0.013,
                                fontWeight: FontWeight.w600,
                                color: textColor.withValues(alpha: 0.82),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPieKey(BuildContext context) {
    final itemCount = math.min(spec.x.length, 18);
    final columns = math.min(itemCount, presentationMode ? 4 : 6);
    final rows = (itemCount / columns).ceil();
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = w * 0.006;
        final itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return SizedBox(
          height: rows * w * 0.03 * labelScale + (rows - 1) * gap,
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < itemCount; i++)
                MouseRegion(
                  onEnter: (_) => onHoverEntry(i),
                  onExit: (_) => onHoverEntry(null),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: _dimmed(i) ? 0.4 : 1,
                    child: Container(
                      width: itemWidth,
                      height: w * 0.03 * labelScale,
                      padding: EdgeInsets.symmetric(horizontal: w * 0.008),
                      decoration: BoxDecoration(
                        color: emphasised == i
                            ? AppTheme.parseHexColor(
                                chartRowColor(spec, i),
                              ).withValues(alpha: 0.18)
                            : textColor.withValues(alpha: 0.045),
                        borderRadius: BorderRadius.circular(w),
                        border: Border.all(
                          color: emphasised == i
                              ? AppTheme.parseHexColor(chartRowColor(spec, i))
                              : Colors.transparent,
                          width: w * 0.0015,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: w * 0.012,
                            height: w * 0.012,
                            decoration: BoxDecoration(
                              color: AppTheme.parseHexColor(
                                chartRowColor(spec, i),
                              ),
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: w * 0.006),
                          Expanded(
                            child: Text(
                              decodeNamedHtmlEntities(spec.x[i]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _applyFont(
                                font,
                                TextStyle(
                                  fontSize: w * 0.013 * labelScale,
                                  fontWeight: FontWeight.w600,
                                  color: textColor.withValues(alpha: 0.82),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
