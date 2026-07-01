// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability (bar/stacked/scatter/line/pie chart builders); all imports live in the main
// library file. These _ChartPreviewState chart builders relocate verbatim
// into an extension — same library, same members, no behaviour change.
part of '../slide_preview.dart';

extension _ChartPreviewCartesian on _ChartPreviewState {
  Widget _barChart(ChartSpec spec, Color textColor) {
    final groups = <BarChartGroupData>[];
    for (var xi = 0; xi < spec.x.length; xi++) {
      groups.add(
        BarChartGroupData(
          x: xi,
          barRods: [
            for (var si = 0; si < spec.series.length; si++)
              if (xi < spec.series[si].data.length)
                BarChartRodData(
                  toY: spec.series[si].data[xi] * _grow,
                  color: _seriesDisplayColor(spec.series[si], si),
                  width: _barRodWidth(spec),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(w * 0.006),
                  ),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: _maxY(spec),
                    color: textColor.withValues(alpha: 0.025),
                  ),
                ),
          ],
        ),
      );
    }
    return BarChart(
      BarChartData(
        minY: _minY(spec),
        maxY: _maxY(spec),
        // The axis-label spacing in _titles assumes this layout; keep it
        // explicit rather than relying on fl_chart's default.
        alignment: BarChartAlignment.spaceEvenly,
        barGroups: groups,
        titlesData: _titles(spec, textColor, bars: true),
        gridData: _grid(textColor),
        borderData: FlBorderData(show: false),
        extraLinesData: _boundLines(spec),
        barTouchData: BarTouchData(
          enabled: true,
          mouseCursorResolver: (event, response) => response?.spot == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          touchTooltipData: BarTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => const Color(0xFF0F172A),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final label = group.x >= 0 && group.x < spec.x.length
                  ? spec.x[group.x]
                  : '';
              final series = rodIndex < spec.series.length
                  ? spec.series[rodIndex].name
                  : '';
              return BarTooltipItem(
                '$label\n${series.isEmpty ? 'Reeks ${rodIndex + 1}' : series}: ${_fmtNum(rod.toY)}',
                _tooltipStyle(),
              );
            },
          ),
        ),
      ),
      duration: _chartAnimDuration,
    );
  }

  Widget _stackedBarChart(ChartSpec spec, Color textColor) {
    final groups = <BarChartGroupData>[];
    for (var xi = 0; xi < spec.x.length; xi++) {
      // A stacked bar is ONE rod per group whose segments are stacked vertically
      // via rodStackItems. (Multiple rods in a group render side-by-side, which
      // is grouping, not stacking.)
      var top = 0.0;
      final stackItems = <BarChartRodStackItem>[];
      for (var si = 0; si < spec.series.length; si++) {
        if (xi >= spec.series[si].data.length) continue;
        final value = spec.series[si].data[xi] * _grow;
        stackItems.add(
          BarChartRodStackItem(
            top,
            top + value,
            _seriesDisplayColor(spec.series[si], si),
          ),
        );
        top += value;
      }
      groups.add(
        BarChartGroupData(
          x: xi,
          barRods: [
            BarChartRodData(
              fromY: 0,
              toY: top,
              width: _barRodWidth(spec),
              rodStackItems: stackItems,
              // The segments carry the colours; the rod body stays clear.
              color: Colors.transparent,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(w * 0.006),
              ),
            ),
          ],
        ),
      );
    }
    return BarChart(
      BarChartData(
        minY: _minY(spec),
        maxY: _maxY(spec),
        alignment: BarChartAlignment.spaceEvenly,
        barGroups: groups,
        titlesData: _titles(spec, textColor, bars: true),
        gridData: _grid(textColor),
        borderData: FlBorderData(show: false),
        extraLinesData: _boundLines(spec),
        barTouchData: BarTouchData(enabled: false),
      ),
      duration: _chartAnimDuration,
    );
  }

  Widget _scatterChart(ChartSpec spec, Color textColor) {
    final spots = <ScatterSpot>[];
    for (var si = 0; si < spec.series.length; si++) {
      for (var xi = 0; xi < spec.series[si].data.length; xi++) {
        spots.add(
          ScatterSpot(
            xi.toDouble(),
            spec.series[si].data[xi] * _grow,
            dotPainter: FlDotCirclePainter(
              radius: w * 0.007,
              color: _seriesDisplayColor(spec.series[si], si),
              strokeWidth: w * 0.002,
              strokeColor: _hexColor(profile.slideBackgroundColor),
            ),
          ),
        );
      }
    }
    return ScatterChart(
      ScatterChartData(
        minY: _minY(spec),
        maxY: _maxY(spec),
        scatterSpots: spots,
        titlesData: _titles(spec, textColor),
        gridData: _grid(textColor),
        borderData: FlBorderData(show: false),
        scatterTouchData: ScatterTouchData(enabled: false),
      ),
      duration: _chartAnimDuration,
    );
  }

  Widget _lineChart(ChartSpec spec, Color textColor) {
    final bars = <LineChartBarData>[];
    for (var si = 0; si < spec.series.length; si++) {
      bars.add(
        LineChartBarData(
          spots: [
            for (var xi = 0; xi < spec.series[si].data.length; xi++)
              FlSpot(xi.toDouble(), spec.series[si].data[xi] * _grow),
          ],
          color: _seriesDisplayColor(spec.series[si], si),
          barWidth: w * (_hovered == si ? 0.0065 : 0.0045),
          isCurved: true,
          curveSmoothness: 0.22,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: w * 0.005,
              color: _seriesDisplayColor(spec.series[si], si),
              strokeWidth: w * 0.0025,
              strokeColor: _hexColor(profile.slideBackgroundColor),
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            color: _seriesDisplayColor(
              spec.series[si],
              si,
            ).withValues(alpha: spec.series.length == 1 ? 0.14 : 0.05),
          ),
        ),
      );
    }
    return LineChart(
      LineChartData(
        minY: _minY(spec),
        maxY: _maxY(spec),
        lineBarsData: bars,
        titlesData: _titles(spec, textColor),
        gridData: _grid(textColor),
        borderData: FlBorderData(show: false),
        extraLinesData: _boundLines(spec),
        lineTouchData: LineTouchData(
          enabled: true,
          // Measure proximity to the actual dot (x *and* y), not just the
          // column, so the tooltip belongs to the point under the cursor.
          distanceCalculator: (touch, spot) => (touch - spot).distance,
          touchSpotThreshold: (w * 0.02).clamp(8.0, 24.0).toDouble(),
          mouseCursorResolver: (event, response) =>
              response?.lineBarSpots?.isEmpty ?? true
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => const Color(0xFF0F172A),
            // Show every dot near the cursor. When several dots sit on (almost)
            // the same spot they all appear; the font shrinks to keep them
            // readable when stacked.
            getTooltipItems: (spots) {
              final style = _lineTooltipStyle(spots.length);
              return [
                for (final spot in spots)
                  LineTooltipItem(
                    '${spot.spotIndex < spec.x.length ? spec.x[spot.spotIndex] : ''}\n'
                    '${spot.barIndex < spec.series.length && spec.series[spot.barIndex].name.isNotEmpty ? spec.series[spot.barIndex].name : 'Reeks ${spot.barIndex + 1}'}: ${_fmtNum(spot.y)}',
                    style,
                  ),
              ];
            },
          ),
        ),
      ),
      duration: _chartAnimDuration,
    );
  }

  Widget _pieChart(ChartSpec spec, Color textColor) {
    if (spec.series.isEmpty || spec.x.isEmpty) {
      return _placeholderText('—');
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final visibleSeries = math.min(spec.series.length, 2);
        final columns = visibleSeries;
        const rows = 1;
        final tileHeight = constraints.maxHeight / rows;
        final tileWidth = constraints.maxWidth / columns;
        return GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: tileWidth / tileHeight,
            crossAxisSpacing: w * 0.012,
            mainAxisSpacing: w * 0.008,
          ),
          itemCount: visibleSeries,
          itemBuilder: (context, si) {
            final series = spec.series[si];
            final values = [
              for (var xi = 0; xi < spec.x.length; xi++)
                xi < series.data.length && series.data[xi] > 0
                    ? series.data[xi]
                    : 0.0,
            ];
            final total = values.fold<double>(0, (a, b) => a + b);
            return Row(
              children: [
                Expanded(
                  flex: 4,
                  child: total <= 0
                      ? Center(
                          child: Text(
                            '0',
                            style: _applyFont(
                              font,
                              TextStyle(
                                fontSize: w * 0.025,
                                color: textColor.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, pieConstraints) {
                            final available =
                                pieConstraints.biggest.shortestSide;
                            final radius = (available * 0.42).clamp(
                              w * 0.018,
                              w * 0.075,
                            );
                            return ClipRect(
                              child: _HoverPieChart(
                                externalHover: _hovered,
                                values: values,
                                labels: spec.x,
                                colors: [
                                  for (var xi = 0; xi < values.length; xi++)
                                    _hexColor(chartRowColor(spec, xi)),
                                ],
                                radius: radius,
                                centerSpaceRadius: radius * 0.42,
                                sectionSpace: w * 0.002,
                                titleStyle: _applyFont(
                                  font,
                                  TextStyle(
                                    fontSize: (radius * 0.18).clamp(
                                      w * 0.009,
                                      w * 0.013,
                                    ),
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                tooltipStyle: _tooltipStyle(),
                              ),
                            );
                          },
                        ),
                ),
                SizedBox(width: w * 0.008),
                Expanded(
                  flex: 2,
                  child: Text(
                    series.name.isEmpty ? 'Reeks ${si + 1}' : series.name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: _applyFont(
                      font,
                      TextStyle(
                        fontSize: w * 0.015,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
