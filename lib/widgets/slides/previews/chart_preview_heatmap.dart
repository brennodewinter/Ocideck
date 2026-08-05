// Part of the slide_preview library — see ../slide_preview.dart.
// The heatmap / risk-matrix chart builder, split out of
// chart_preview_extra.dart to stay under the file-size ratchet. This
// _ChartPreviewState builder is an extension in the same library.
part of '../slide_preview.dart';

extension _ChartPreviewHeatmap on _ChartPreviewState {
  // ── Heatmap (doubles as a risk matrix) ───────────────────────────────────

  /// A grid coloured by value: every series is a row, every label a column, the
  /// cell colour a light→accent ramp over the data range. Label the axes
  /// likelihood and impact and it reads as a risk matrix. A colour-scale strip
  /// sits under the grid.
  Widget _heatmapChart(ChartSpec spec, Color textColor) {
    final rows = spec.series;
    final cols = spec.x;
    if (rows.isEmpty || cols.isEmpty) {
      return _placeholderText(context.l10n.d('Geen grafiekgegevens'));
    }
    double? lo, hi;
    for (final s in rows) {
      for (final v in s.data) {
        lo = lo == null ? v : math.min(lo, v);
        hi = hi == null ? v : math.max(hi, v);
      }
    }
    final low = lo ?? 0;
    var high = hi ?? 1;
    if (high <= low) high = low + 1;
    // Magnitude → a fixed heat ramp, not the deck theme (see chart.dart), picked
    // for the slide background so low always recedes and high always intensifies.
    final ramp = heatmapRamp(
      darkBackground: isDarkHex(profile.slideBackgroundColor),
    );
    final labelStyle = _applyFont(
      font,
      TextStyle(
        fontSize: w * 0.0115 * _labelScale,
        color: textColor.withValues(alpha: 0.88),
        fontWeight: presentationMode ? FontWeight.w600 : FontWeight.normal,
      ),
    );

    return _customGrow((t) {
      return LayoutBuilder(
        builder: (context, c) {
          final labelW = math.max(w * 0.1, c.maxWidth * 0.2);
          return Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: labelW,
                      child: Column(
                        children: [
                          for (var r = 0; r < rows.length; r++)
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(right: w * 0.008),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    rows[r].name.isEmpty
                                        ? '${context.l10n.d('Reeks')} ${r + 1}'
                                        : rows[r].name,
                                    textAlign: TextAlign.right,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: labelStyle,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          for (var r = 0; r < rows.length; r++)
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var cc = 0; cc < cols.length; cc++)
                                    Expanded(
                                      child: _heatCell(
                                        cc < rows[r].data.length
                                            ? rows[r].data[cc]
                                            : 0.0,
                                        cc < rows[r].data.length,
                                        low,
                                        high,
                                        ramp,
                                        t,
                                        textColor,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: w * 0.03 * _labelScale,
                child: Row(
                  children: [
                    SizedBox(width: labelW),
                    Expanded(
                      child: Row(
                        children: [
                          for (var cc = 0; cc < cols.length; cc++)
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: w * 0.002,
                                ),
                                child: Text(
                                  cols[cc],
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: labelStyle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: w * 0.008),
              _heatScale(ramp, low, high, textColor, labelW),
            ],
          );
        },
      );
    });
  }

  Widget _heatCell(
    double v,
    bool present,
    double low,
    double high,
    List<String> ramp,
    double t,
    Color textColor,
  ) {
    final norm = (high - low) <= 0
        ? 0.0
        : ((v - low) / (high - low)).clamp(0.0, 1.0);
    final fillHex = heatmapColorAt(ramp, norm);
    final color = present
        ? AppTheme.parseHexColor(fillHex)
        : textColor.withValues(alpha: 0.04);
    // The cell colour is fixed (not the theme), so the label colour is too:
    // white on the hot/dark cells, dark ink on the pale ones.
    final onColor = AppTheme.parseHexColor(heatmapInk(fillHex));
    return Padding(
      padding: EdgeInsets.all(w * 0.0025),
      child: Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(w * 0.004),
          ),
          child: present
              ? Text(
                  _fmtNum(v),
                  maxLines: 1,
                  style: _applyFont(
                    font,
                    TextStyle(
                      fontSize: w * 0.012 * _labelScale,
                      color: onColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _heatScale(
    List<String> ramp,
    double lo,
    double hi,
    Color textColor,
    double labelW,
  ) {
    final style = _applyFont(
      font,
      TextStyle(
        fontSize: w * 0.011 * _labelScale,
        color: textColor.withValues(alpha: 0.7),
        fontWeight: FontWeight.w600,
      ),
    );
    return SizedBox(
      height: w * 0.02 * _labelScale,
      child: Row(
        children: [
          SizedBox(width: labelW),
          Expanded(
            child: Row(
              children: [
                Text(_fmtNum(lo), style: style),
                SizedBox(width: w * 0.006),
                Expanded(
                  child: Container(
                    height: w * 0.012,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          for (final s in ramp) AppTheme.parseHexColor(s),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(w * 0.008),
                    ),
                  ),
                ),
                SizedBox(width: w * 0.006),
                Text(_fmtNum(hi), style: style),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
