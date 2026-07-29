// Part of the slide_preview library — see ../slide_preview.dart.
// Procesverbetering statistical chart painters (PROCESS_IMPROVEMENT.md Phase 2).
// Limits/Cpk are derived at paint time and never read from stored JSON.
part of '../slide_preview.dart';

extension _ChartPreviewImprovement on _ChartPreviewState {
  Widget _controlChart(ChartSpec spec, Color textColor) {
    final view = deriveIndividualsChart(spec);
    if (view == null) {
      return _placeholderText(
        context.l10n.d('Te weinig gegevens voor een regelkaart'),
      );
    }
    return _customGrow((t) {
      return CustomPaint(
        painter: _ControlChartPainter(
          view: view,
          textColor: textColor,
          accent: AppTheme.parseHexColor(profile.accentColor),
          grow: t,
          font: font,
        ),
        child: const SizedBox.expand(),
      );
    });
  }

  Widget _histogramChart(ChartSpec spec, Color textColor) {
    final limits = resolveChartSpecLimits(
      yRef: spec.yRef,
      localUsl: spec.usl,
      localLsl: spec.lsl,
      localProcessTarget: spec.processTarget,
      y01: widget.y01,
    );
    final view = deriveHistogram(spec, y01: widget.y01);
    if (view == null) {
      return _placeholderText(
        context.l10n.d('Te weinig gegevens voor een histogram'),
      );
    }
    return _customGrow((t) {
      return CustomPaint(
        painter: _HistogramPainter(
          view: view,
          usl: limits.usl,
          lsl: limits.lsl,
          textColor: textColor,
          accent: AppTheme.parseHexColor(profile.accentColor),
          grow: t,
          font: font,
        ),
        child: const SizedBox.expand(),
      );
    });
  }

  Widget _paretoChart(ChartSpec spec, Color textColor) {
    final view = derivePareto(spec);
    if (view == null) {
      return _placeholderText(context.l10n.d('Geen grafiekgegevens'));
    }
    return _customGrow((t) {
      return CustomPaint(
        painter: _ParetoPainter(
          view: view,
          textColor: textColor,
          accent: AppTheme.parseHexColor(profile.accentColor),
          grow: t,
          font: font,
        ),
        child: const SizedBox.expand(),
      );
    });
  }

  Widget _runChart(ChartSpec spec, Color textColor) {
    final values = chartPrimarySample(spec);
    if (values.length < 2) {
      return _placeholderText(context.l10n.d('Geen grafiekgegevens'));
    }
    final mean = values.reduce((a, b) => a + b) / values.length;
    return _customGrow((t) {
      return CustomPaint(
        painter: _RunChartPainter(
          values: values,
          mean: mean,
          textColor: textColor,
          accent: AppTheme.parseHexColor(profile.accentColor),
          grow: t,
          font: font,
        ),
        child: const SizedBox.expand(),
      );
    });
  }

  Widget _boxPlotChart(ChartSpec spec, Color textColor) {
    final view = deriveBoxPlot(spec);
    if (view == null) {
      return _placeholderText(
        context.l10n.d('Te weinig gegevens voor een boxplot'),
      );
    }
    return _customGrow((t) {
      return CustomPaint(
        painter: _BoxPlotPainter(
          view: view,
          textColor: textColor,
          accent: AppTheme.parseHexColor(profile.accentColor),
          grow: t,
          font: font,
        ),
        child: const SizedBox.expand(),
      );
    });
  }

  Widget _probabilityPlotChart(ChartSpec spec, Color textColor) {
    final view = deriveProbabilityPlot(spec);
    if (view == null) {
      return _placeholderText(
        context.l10n.d('Te weinig gegevens voor een probability plot'),
      );
    }
    return _customGrow((t) {
      return CustomPaint(
        painter: _ProbabilityPlotPainter(
          view: view,
          textColor: textColor,
          accent: AppTheme.parseHexColor(profile.accentColor),
          grow: t,
          font: font,
          normalityLabel: context.l10n.d('AD p='),
        ),
        child: const SizedBox.expand(),
      );
    });
  }

  Widget _mainEffectsChart(ChartSpec spec, Color textColor) {
    final view = deriveMainEffects(spec);
    if (view == null) {
      return _placeholderText(
        context.l10n.d('Te weinig gegevens voor een hoofdeffectenplot'),
      );
    }
    return _customGrow((t) {
      return CustomPaint(
        painter: _MainEffectsPainter(
          view: view,
          textColor: textColor,
          accent: AppTheme.parseHexColor(profile.accentColor),
          grow: t,
          font: font,
        ),
        child: const SizedBox.expand(),
      );
    });
  }

  Widget _interactionChart(ChartSpec spec, Color textColor) {
    final view = deriveInteraction(spec);
    if (view == null) {
      return _placeholderText(
        context.l10n.d('Te weinig gegevens voor een interactieplot'),
      );
    }
    return _customGrow((t) {
      return CustomPaint(
        painter: _InteractionPainter(
          view: view,
          textColor: textColor,
          accent: AppTheme.parseHexColor(profile.accentColor),
          grow: t,
          font: font,
        ),
        child: const SizedBox.expand(),
      );
    });
  }
}

class _ControlChartPainter extends CustomPainter {
  _ControlChartPainter({
    required this.view,
    required this.textColor,
    required this.accent,
    required this.grow,
    required this.font,
  });

  final ControlChartView view;
  final Color textColor;
  final Color accent;
  final double grow;
  final String font;

  @override
  void paint(Canvas canvas, Size size) {
    final pad = Offset(size.width * 0.08, size.height * 0.12);
    final plot = Rect.fromLTWH(
      pad.dx,
      pad.dy,
      size.width - pad.dx * 2,
      size.height - pad.dy * 2,
    );
    final minY = [view.lcl, ...view.values].reduce(math.min);
    final maxY = [view.ucl, ...view.values].reduce(math.max);
    final span = (maxY - minY).abs() < 1e-9 ? 1.0 : maxY - minY;
    double yOf(double v) =>
        plot.bottom - ((v - minY) / span) * plot.height * grow;
    double xOf(int i) =>
        plot.left +
        (view.values.length <= 1
            ? plot.width / 2
            : i * plot.width / (view.values.length - 1));

    final grid = Paint()
      ..color = textColor.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (final y in [view.lcl, view.center, view.ucl]) {
      canvas.drawLine(
        Offset(plot.left, yOf(y)),
        Offset(plot.right, yOf(y)),
        grid,
      );
    }
    final limitPaint = Paint()
      ..color = AppTheme.danger600
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(plot.left, yOf(view.ucl)),
      Offset(plot.right, yOf(view.ucl)),
      limitPaint,
    );
    canvas.drawLine(
      Offset(plot.left, yOf(view.lcl)),
      Offset(plot.right, yOf(view.lcl)),
      limitPaint,
    );
    final centrePaint = Paint()
      ..color = textColor.withValues(alpha: 0.55)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(plot.left, yOf(view.center)),
      Offset(plot.right, yOf(view.center)),
      centrePaint,
    );

    final line = Path();
    for (var i = 0; i < view.values.length; i++) {
      final p = Offset(xOf(i), yOf(view.values[i]));
      if (i == 0) {
        line.moveTo(p.dx, p.dy);
      } else {
        line.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = accent
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < view.values.length; i++) {
      final ooc = view.outOfControl.contains(i);
      canvas.drawCircle(
        Offset(xOf(i), yOf(view.values[i])),
        ooc ? 5 : 3.5,
        Paint()..color = ooc ? AppTheme.danger600 : accent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ControlChartPainter old) =>
      old.view != view || old.grow != grow || old.accent != accent;
}

class _HistogramPainter extends CustomPainter {
  _HistogramPainter({
    required this.view,
    required this.usl,
    required this.lsl,
    required this.textColor,
    required this.accent,
    required this.grow,
    required this.font,
  });

  final HistogramView view;
  final double? usl;
  final double? lsl;
  final Color textColor;
  final Color accent;
  final double grow;
  final String font;

  @override
  void paint(Canvas canvas, Size size) {
    final pad = Offset(size.width * 0.08, size.height * 0.12);
    final plot = Rect.fromLTWH(
      pad.dx,
      pad.dy,
      size.width - pad.dx * 2,
      size.height - pad.dy * 2,
    );
    final maxC = view.counts.fold<int>(0, math.max).clamp(1, 1 << 30);
    final n = view.counts.length;
    final barW = plot.width / n;
    for (var i = 0; i < n; i++) {
      final h = (view.counts[i] / maxC) * plot.height * grow;
      final r = Rect.fromLTWH(
        plot.left + i * barW + 1,
        plot.bottom - h,
        barW - 2,
        h,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(2)),
        Paint()..color = accent.withValues(alpha: 0.85),
      );
    }
    final limit = Paint()
      ..color = AppTheme.danger600
      // Thumbnails are ~180 px wide; a fixed 1.5 px stroke disappears under
      // rasterisation. Scale with the canvas so a strip/preview still shows
      // the line, without thickening the full-slide presentation.
      ..strokeWidth = (size.width * 0.004).clamp(2.0, 4.0);
    void specLine(double? v) {
      if (v == null || view.edges.length < 2) return;
      final minX = view.edges.first;
      final maxX = view.edges.last;
      final span = (maxX - minX).abs() < 1e-9 ? 1.0 : maxX - minX;
      // Keep the line visible when the limit sits just outside the data
      // range: clamp to the plot edge rather than skipping the draw. Cpk
      // already uses the limit; hiding the line made thumbnails look broken.
      final x = (plot.left + ((v - minX) / span) * plot.width).clamp(
        plot.left,
        plot.right,
      );
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), limit);
    }

    specLine(lsl);
    specLine(usl);
    if (view.cpk != null) {
      final tp = TextPainter(
        text: TextSpan(
          text:
              'Cpk ${view.cpk!.toStringAsFixed(2)}'
              '${view.normalityPValue != null ? ' · AD p=${view.normalityPValue!.toStringAsFixed(2)}' : ''}',
          style: TextStyle(
            color: textColor.withValues(alpha: 0.8),
            fontSize: 11,
            fontFamily: font.isEmpty ? null : font,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(plot.left, plot.top - 16));
    }
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter old) =>
      old.view != view || old.grow != grow;
}

class _ParetoPainter extends CustomPainter {
  _ParetoPainter({
    required this.view,
    required this.textColor,
    required this.accent,
    required this.grow,
    required this.font,
  });

  final ParetoView view;
  final Color textColor;
  final Color accent;
  final double grow;
  final String font;

  @override
  void paint(Canvas canvas, Size size) {
    final pad = Offset(size.width * 0.08, size.height * 0.14);
    final plot = Rect.fromLTWH(
      pad.dx,
      pad.dy,
      size.width - pad.dx * 2,
      size.height - pad.dy * 2,
    );
    final maxV = view.values
        .fold<double>(0, math.max)
        .clamp(1e-9, double.infinity);
    final n = view.values.length;
    final barW = plot.width / n;
    for (var i = 0; i < n; i++) {
      final h = (view.values[i] / maxV) * plot.height * grow;
      final vital = i < view.vitalFewCount;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(plot.left + i * barW + 2, plot.bottom - h, barW - 4, h),
          const Radius.circular(2),
        ),
        Paint()..color = vital ? accent : accent.withValues(alpha: 0.35),
      );
    }
    final cumPath = Path();
    for (var i = 0; i < n; i++) {
      final x = plot.left + (i + 0.5) * barW;
      final y =
          plot.bottom - (view.cumulativePct[i] / 100) * plot.height * grow;
      if (i == 0) {
        cumPath.moveTo(x, y);
      } else {
        cumPath.lineTo(x, y);
      }
    }
    canvas.drawPath(
      cumPath,
      Paint()
        ..color = AppTheme.teal
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    // 80% line — vital-few callout.
    final y80 = plot.bottom - 0.8 * plot.height;
    canvas.drawLine(
      Offset(plot.left, y80),
      Offset(plot.right, y80),
      Paint()
        ..color = AppTheme.teal.withValues(alpha: 0.45)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _ParetoPainter old) =>
      old.view != view || old.grow != grow;
}

class _RunChartPainter extends CustomPainter {
  _RunChartPainter({
    required this.values,
    required this.mean,
    required this.textColor,
    required this.accent,
    required this.grow,
    required this.font,
  });

  final List<double> values;
  final double mean;
  final Color textColor;
  final Color accent;
  final double grow;
  final String font;

  @override
  void paint(Canvas canvas, Size size) {
    final pad = Offset(size.width * 0.08, size.height * 0.12);
    final plot = Rect.fromLTWH(
      pad.dx,
      pad.dy,
      size.width - pad.dx * 2,
      size.height - pad.dy * 2,
    );
    final minY = values.reduce(math.min);
    final maxY = values.reduce(math.max);
    final span = (maxY - minY).abs() < 1e-9 ? 1.0 : maxY - minY;
    double yOf(double v) =>
        plot.bottom - ((v - minY) / span) * plot.height * grow;
    double xOf(int i) =>
        plot.left +
        (values.length <= 1
            ? plot.width / 2
            : i * plot.width / (values.length - 1));
    canvas.drawLine(
      Offset(plot.left, yOf(mean)),
      Offset(plot.right, yOf(mean)),
      Paint()
        ..color = textColor.withValues(alpha: 0.4)
        ..strokeWidth = 1.2,
    );
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final p = Offset(xOf(i), yOf(values[i]));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(
        Offset(xOf(i), yOf(values[i])),
        3.5,
        Paint()..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RunChartPainter old) =>
      old.values != values || old.grow != grow;
}

class _BoxPlotPainter extends CustomPainter {
  _BoxPlotPainter({
    required this.view,
    required this.textColor,
    required this.accent,
    required this.grow,
    required this.font,
  });

  final BoxPlotView view;
  final Color textColor;
  final Color accent;
  final double grow;
  final String font;

  @override
  void paint(Canvas canvas, Size size) {
    final pad = Offset(size.width * 0.1, size.height * 0.12);
    final plot = Rect.fromLTWH(
      pad.dx,
      pad.dy,
      size.width - pad.dx * 2,
      size.height - pad.dy * 2,
    );
    var minY = view.boxes.first.whiskerLow;
    var maxY = view.boxes.first.whiskerHigh;
    for (final b in view.boxes) {
      minY = math.min(minY, b.whiskerLow);
      maxY = math.max(maxY, b.whiskerHigh);
      for (final o in b.outliers) {
        minY = math.min(minY, o);
        maxY = math.max(maxY, o);
      }
    }
    final span = (maxY - minY).abs() < 1e-9 ? 1.0 : maxY - minY;
    double yOf(double v) =>
        plot.bottom - ((v - minY) / span) * plot.height * grow;
    final slot = plot.width / view.boxes.length;
    for (var i = 0; i < view.boxes.length; i++) {
      final b = view.boxes[i];
      final cx = plot.left + (i + 0.5) * slot;
      final boxW = slot * 0.45;
      final stroke = Paint()
        ..color = accent
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(cx, yOf(b.whiskerLow)),
        Offset(cx, yOf(b.q1)),
        stroke,
      );
      canvas.drawLine(
        Offset(cx, yOf(b.q3)),
        Offset(cx, yOf(b.whiskerHigh)),
        stroke,
      );
      canvas.drawLine(
        Offset(cx - boxW * 0.25, yOf(b.whiskerLow)),
        Offset(cx + boxW * 0.25, yOf(b.whiskerLow)),
        stroke,
      );
      canvas.drawLine(
        Offset(cx - boxW * 0.25, yOf(b.whiskerHigh)),
        Offset(cx + boxW * 0.25, yOf(b.whiskerHigh)),
        stroke,
      );
      final box = Rect.fromLTWH(
        cx - boxW / 2,
        yOf(b.q3),
        boxW,
        (yOf(b.q1) - yOf(b.q3)).abs(),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(2)),
        Paint()..color = accent.withValues(alpha: 0.2),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(2)),
        stroke,
      );
      canvas.drawLine(
        Offset(cx - boxW / 2, yOf(b.median)),
        Offset(cx + boxW / 2, yOf(b.median)),
        Paint()
          ..color = textColor
          ..strokeWidth = 2,
      );
      for (final o in b.outliers) {
        canvas.drawCircle(
          Offset(cx, yOf(o)),
          3,
          Paint()..color = AppTheme.danger600,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoxPlotPainter old) =>
      old.view != view || old.grow != grow;
}

class _MainEffectsPainter extends CustomPainter {
  _MainEffectsPainter({
    required this.view,
    required this.textColor,
    required this.accent,
    required this.grow,
    required this.font,
  });

  final MainEffectsView view;
  final Color textColor;
  final Color accent;
  final double grow;
  final String font;

  @override
  void paint(Canvas canvas, Size size) {
    final pad = Offset(size.width * 0.08, size.height * 0.14);
    final plot = Rect.fromLTWH(
      pad.dx,
      pad.dy,
      size.width - pad.dx * 2,
      size.height - pad.dy * 2,
    );
    var minY = view.grandMean;
    var maxY = view.grandMean;
    for (final line in view.lines) {
      minY = math.min(minY, math.min(line.low, line.high));
      maxY = math.max(maxY, math.max(line.low, line.high));
    }
    final span = (maxY - minY).abs() < 1e-9 ? 1.0 : maxY - minY;
    final padY = span * 0.1;
    minY -= padY;
    maxY += padY;
    final ySpan = maxY - minY;
    double yOf(double v) =>
        plot.bottom - ((v - minY) / ySpan) * plot.height * grow;

    canvas.drawLine(
      Offset(plot.left, yOf(view.grandMean)),
      Offset(plot.right, yOf(view.grandMean)),
      Paint()
        ..color = textColor.withValues(alpha: 0.25)
        ..strokeWidth = 1,
    );

    final slot = plot.width / view.lines.length;
    for (var i = 0; i < view.lines.length; i++) {
      final line = view.lines[i];
      final cx = plot.left + (i + 0.5) * slot;
      final xLow = cx - slot * 0.18;
      final xHigh = cx + slot * 0.18;
      final color = AppTheme.parseHexColor(
        chartColorPalette[i % chartColorPalette.length],
      );
      canvas.drawLine(
        Offset(xLow, yOf(line.low)),
        Offset(xHigh, yOf(line.high)),
        Paint()
          ..color = color
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
      for (final (x, y) in [(xLow, line.low), (xHigh, line.high)]) {
        canvas.drawCircle(Offset(x, yOf(y)), 4, Paint()..color = color);
      }
      final tp = TextPainter(
        text: TextSpan(
          text: line.label,
          style: TextStyle(
            color: textColor.withValues(alpha: 0.85),
            fontSize: 10,
            fontFamily: font.isEmpty ? null : font,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: slot - 4);
      tp.paint(canvas, Offset(cx - tp.width / 2, plot.bottom + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _MainEffectsPainter old) =>
      old.view != view || old.grow != grow;
}

class _InteractionPainter extends CustomPainter {
  _InteractionPainter({
    required this.view,
    required this.textColor,
    required this.accent,
    required this.grow,
    required this.font,
  });

  final InteractionView view;
  final Color textColor;
  final Color accent;
  final double grow;
  final String font;

  @override
  void paint(Canvas canvas, Size size) {
    final pad = Offset(size.width * 0.08, size.height * 0.14);
    final plot = Rect.fromLTWH(
      pad.dx,
      pad.dy,
      size.width - pad.dx * 2,
      size.height - pad.dy * 2,
    );
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    for (final panel in view.panels) {
      for (final line in panel.lines) {
        minY = math.min(minY, math.min(line.atFactorLow, line.atFactorHigh));
        maxY = math.max(maxY, math.max(line.atFactorLow, line.atFactorHigh));
      }
    }
    if (!minY.isFinite) return;
    final span = (maxY - minY).abs() < 1e-9 ? 1.0 : maxY - minY;
    final padY = span * 0.1;
    minY -= padY;
    maxY += padY;
    final ySpan = maxY - minY;
    double yOf(double v) =>
        plot.bottom - ((v - minY) / ySpan) * plot.height * grow;

    final slot = plot.width / view.panels.length;
    for (var pi = 0; pi < view.panels.length; pi++) {
      final panel = view.panels[pi];
      final cx = plot.left + (pi + 0.5) * slot;
      final xLow = cx - slot * 0.18;
      final xHigh = cx + slot * 0.18;
      for (var li = 0; li < panel.lines.length; li++) {
        final line = panel.lines[li];
        final color = li == 0
            ? accent
            : AppTheme.parseHexColor(
                chartColorPalette[(li + 1) % chartColorPalette.length],
              );
        canvas.drawLine(
          Offset(xLow, yOf(line.atFactorLow)),
          Offset(xHigh, yOf(line.atFactorHigh)),
          Paint()
            ..color = color
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
        for (final (x, y) in [
          (xLow, line.atFactorLow),
          (xHigh, line.atFactorHigh),
        ]) {
          canvas.drawCircle(Offset(x, yOf(y)), 3.5, Paint()..color = color);
        }
      }
      final tp = TextPainter(
        text: TextSpan(
          text: panel.label,
          style: TextStyle(
            color: textColor.withValues(alpha: 0.85),
            fontSize: 9,
            fontFamily: font.isEmpty ? null : font,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: slot - 2);
      tp.paint(canvas, Offset(cx - tp.width / 2, plot.bottom + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _InteractionPainter old) =>
      old.view != view || old.grow != grow;
}

class _ProbabilityPlotPainter extends CustomPainter {
  _ProbabilityPlotPainter({
    required this.view,
    required this.textColor,
    required this.accent,
    required this.grow,
    required this.font,
    required this.normalityLabel,
  });

  final ProbabilityPlotView view;
  final Color textColor;
  final Color accent;
  final double grow;
  final String font;
  final String normalityLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final pad = Offset(size.width * 0.08, size.height * 0.12);
    final plot = Rect.fromLTWH(
      pad.dx,
      pad.dy,
      size.width - pad.dx * 2,
      size.height - pad.dy * 2,
    );
    final xs = view.theoreticalQuantiles;
    final ys = view.sortedValues;
    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);
    final spanX = (maxX - minX).abs() < 1e-9 ? 1.0 : maxX - minX;
    final spanY = (maxY - minY).abs() < 1e-9 ? 1.0 : maxY - minY;
    double xOf(double v) => plot.left + ((v - minX) / spanX) * plot.width;
    double yOf(double v) =>
        plot.bottom - ((v - minY) / spanY) * plot.height * grow;

    final meanY = ys.reduce((a, b) => a + b) / ys.length;
    final sdY = math.sqrt(
      ys.fold<double>(0, (s, v) {
            final d = v - meanY;
            return s + d * d;
          }) /
          (ys.length - 1),
    );
    final refPaint = Paint()
      ..color = textColor.withValues(alpha: 0.35)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(xOf(minX), yOf(meanY + sdY * minX)),
      Offset(xOf(maxX), yOf(meanY + sdY * maxX)),
      refPaint,
    );

    for (var i = 0; i < xs.length; i++) {
      canvas.drawCircle(
        Offset(xOf(xs[i]), yOf(ys[i])),
        4,
        Paint()..color = accent,
      );
    }

    if (view.normalityPValue != null) {
      final tp = TextPainter(
        text: TextSpan(
          text: '$normalityLabel${view.normalityPValue!.toStringAsFixed(2)}',
          style: TextStyle(color: textColor, fontSize: 11, fontFamily: font),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(plot.left, plot.top - 4));
    }
  }

  @override
  bool shouldRepaint(covariant _ProbabilityPlotPainter old) =>
      old.view != view ||
      old.grow != grow ||
      old.normalityLabel != normalityLabel;
}
