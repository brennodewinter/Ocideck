part of '../slide_preview.dart';

class _CockpitPreview extends StatefulWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;
  final CockpitColorScheme scheme;
  final bool presentationMode;

  const _CockpitPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
    required this.scheme,
    required this.presentationMode,
  });

  @override
  State<_CockpitPreview> createState() => _CockpitPreviewState();
}

class _CockpitPreviewState extends State<_CockpitPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Parsed cockpit spec, cached so rebuilds (and the per-frame animation)
  /// don't re-parse the cockpit JSON. Re-parsed only when the slide's cockpit
  /// markdown changes.
  late CockpitSpec _spec;

  @override
  void initState() {
    super.initState();
    _spec = CockpitSpec.parse(widget.slide.customMarkdown);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: cockpitDefaultAnimationDurationMs),
      value: 1,
    );
    _maybeStart();
  }

  @override
  void didUpdateWidget(_CockpitPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slide.id != widget.slide.id ||
        oldWidget.slide.customMarkdown != widget.slide.customMarkdown ||
        oldWidget.profile.animationDurationMs !=
            widget.profile.animationDurationMs ||
        oldWidget.presentationMode != widget.presentationMode) {
      if (oldWidget.slide.customMarkdown != widget.slide.customMarkdown) {
        _spec = CockpitSpec.parse(widget.slide.customMarkdown);
      }
      _maybeStart();
    }
  }

  void _maybeStart() {
    final spec = _spec;
    // null override = inherit the theme's shared activation duration.
    final ms = (spec.animationDurationMs ?? widget.profile.animationDurationMs)
        .clamp(cockpitMinAnimationDurationMs, cockpitMaxAnimationDurationMs);
    _controller.duration = Duration(milliseconds: ms);
    if (widget.presentationMode && spec.animateOnEnter) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    final meters = spec.meters.isEmpty
        ? CockpitSpec.pentestPreset().meters
        : spec.meters.take(cockpitMaxMeters).toList();
    final bg = AppTheme.parseHexColor(widget.profile.slideBackgroundColor);
    final accent = AppTheme.parseHexColor(widget.profile.accentColor);
    final textColor = AppTheme.parseHexColor(widget.profile.textColor);
    final pad = widget.w * 0.04;
    final logoSafe = widget.slide.showLogo
        ? _logoSafeInsets(widget.w, widget.profile)
        : EdgeInsets.zero;
    final outerPadding = EdgeInsets.fromLTRB(
      pad + logoSafe.left,
      pad + logoSafe.top,
      pad + logoSafe.right,
      _logoAwareBottomPadding(pad, logoSafe.bottom),
    );
    return Container(
      color: bg,
      padding: outerPadding,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final boot = Curves.easeOutCubic.transform(_controller.value);
          final title = widget.slide.title.trim();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title.isNotEmpty) ...[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: widget.w * 0.036,
                    fontFamily: widget.font,
                    fontWeight: FontWeight.w800,
                    decoration: TextDecoration.none,
                    height: 1.08,
                  ),
                ),
                SizedBox(height: widget.w * 0.022),
              ],
              Expanded(
                child: _CockpitGrid(
                  meters: meters,
                  accent: accent,
                  surface: bg,
                  textColor: textColor,
                  mutedColor: textColor.withValues(alpha: 0.62),
                  scheme: widget.scheme,
                  bootProgress: boot,
                  font: widget.font,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CockpitGrid extends StatelessWidget {
  final List<CockpitMeterSpec> meters;
  final Color accent;
  final Color surface;
  final Color textColor;
  final Color mutedColor;
  final CockpitColorScheme scheme;
  final double bootProgress;
  final String font;

  const _CockpitGrid({
    required this.meters,
    required this.accent,
    required this.surface,
    required this.textColor,
    required this.mutedColor,
    required this.scheme,
    required this.bootProgress,
    required this.font,
  });

  @override
  Widget build(BuildContext context) {
    final count = meters.length.clamp(1, cockpitMaxMeters);
    final columns = count == 1
        ? 1
        : count == 2
        ? 2
        : count <= 4
        ? 2
        : 3;
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = constraints.maxWidth * 0.018;
        final rows = (count / columns).ceil();
        final cellW = (constraints.maxWidth - gap * (columns - 1)) / columns;
        final cellH = (constraints.maxHeight - gap * (rows - 1)) / rows;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < count; i++)
              SizedBox(
                width: cellW,
                height: cellH,
                child: _CockpitInstrument(
                  meter: meters[i],
                  progress: _stagger(bootProgress, i, count),
                  accent: accent,
                  surface: surface,
                  textColor: textColor,
                  mutedColor: mutedColor,
                  good: AppTheme.parseHexColor(scheme.good),
                  warning: AppTheme.parseHexColor(scheme.warning),
                  critical: AppTheme.parseHexColor(scheme.critical),
                  cold: AppTheme.parseHexColor(scheme.cold),
                  sky: AppTheme.parseHexColor(scheme.sky),
                  ground: AppTheme.parseHexColor(scheme.ground),
                  font: font,
                ),
              ),
          ],
        );
      },
    );
  }

  double _stagger(double t, int index, int count) {
    final delay = count <= 1 ? 0.0 : index * 0.055;
    final scaled = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
    return Curves.easeOutBack.transform(scaled);
  }
}

class _CockpitInstrument extends StatelessWidget {
  final CockpitMeterSpec meter;
  final double progress;
  final Color accent;
  final Color surface;
  final Color textColor;
  final Color mutedColor;
  final Color good;
  final Color warning;
  final Color critical;
  final Color cold;
  final Color sky;
  final Color ground;
  final String font;

  const _CockpitInstrument({
    required this.meter,
    required this.progress,
    required this.accent,
    required this.surface,
    required this.textColor,
    required this.mutedColor,
    required this.good,
    required this.warning,
    required this.critical,
    required this.cold,
    required this.sky,
    required this.ground,
    required this.font,
  });

  @override
  Widget build(BuildContext context) {
    final label = meter.label.isEmpty
        ? cockpitMeterTypeLabel(meter.type).toUpperCase()
        : meter.label;
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelSize = (constraints.maxWidth * 0.058).clamp(13.0, 18.0);
        return Column(
          children: [
            Expanded(
              child: CustomPaint(
                painter: _CockpitInstrumentPainter(
                  meter: meter,
                  progress: progress.clamp(0, 1).toDouble(),
                  accent: accent,
                  surface: surface,
                  textColor: textColor,
                  mutedColor: mutedColor,
                  good: good,
                  warning: warning,
                  critical: critical,
                  cold: cold,
                  sky: sky,
                  ground: ground,
                  font: font,
                  faceText: (
                    attitude: context.l10n.d('P {pitch}  B {bank}'),
                    actual: context.l10n.d('ACT {value}°'),
                    target: context.l10n.d('TGT {heading}°'),
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
            SizedBox(height: math.max(3, 6 * progress)),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: mutedColor,
                fontSize: labelSize,
                fontFamily: font,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
                height: 1.12,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CockpitInstrumentPainter extends CustomPainter {
  final CockpitMeterSpec meter;
  final double progress;
  final Color accent;
  final Color surface;
  final Color textColor;
  final Color mutedColor;

  /// Status zone colours from the active cockpit colour scheme.
  final Color good;
  final Color warning;
  final Color critical;
  final Color cold;

  /// Artificial-horizon sky and ground colours.
  final Color sky;
  final Color ground;
  final String font;

  /// De teksten op de instrumentglazen, al vertaald, met plaatshouders voor de
  /// meterwaarden. Een painter heeft geen BuildContext, dus ze komen van
  /// buiten; een record omdat dat waarde-gelijkheid heeft en [shouldRepaint]
  /// er dus in één vergelijking op kan afgaan.
  final ({String attitude, String actual, String target}) faceText;

  _CockpitInstrumentPainter({
    required this.meter,
    required this.progress,
    required this.accent,
    required this.surface,
    required this.textColor,
    required this.mutedColor,
    required this.good,
    required this.warning,
    required this.critical,
    required this.cold,
    required this.sky,
    required this.ground,
    required this.font,
    required this.faceText,
  });

  /// Structural lines (gauge tracks, ticks, glass) derive from the slide text
  /// colour at low opacity so the instruments read on any slide background.
  Color _line(double alpha) => textColor.withValues(alpha: alpha);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = math.min(size.width, size.height) * 0.07;
    final bg = Paint()..color = surface;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)), bg);
    final borderW = math.max(1.0, size.shortestSide * 0.008);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(borderW / 2), Radius.circular(r)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderW
        ..color = accent.withValues(alpha: 0.42 + progress * 0.22),
    );
    // Thin inner hairline for a machined "bezel" depth, derived from the slide
    // text colour so it works on any background.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(borderW + 1.5),
        Radius.circular(r - borderW),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _line(0.06 + progress * 0.04),
    );
    switch (meter.type) {
      case CockpitMeterType.speedometer:
        _arcGauge(canvas, size, sweep: 250, startDeg: 145);
        break;
      case CockpitMeterType.voltmeter:
        _arcGauge(canvas, size, sweep: 180, startDeg: 180, compact: true);
        break;
      case CockpitMeterType.thermometer:
        _thermometer(canvas, size);
        break;
      case CockpitMeterType.altimeter:
        _arcGauge(canvas, size, sweep: 300, startDeg: 120, altimeter: true);
        break;
      case CockpitMeterType.climbDescent:
        _climb(canvas, size);
        break;
      case CockpitMeterType.horizon:
        _horizon(canvas, size);
        break;
      case CockpitMeterType.heading:
        _heading(canvas, size);
        break;
    }
  }

  void _arcGauge(
    Canvas canvas,
    Size size, {
    required double sweep,
    required double startDeg,
    bool compact = false,
    bool altimeter = false,
  }) {
    final c = Offset(size.width * 0.40, size.height * (compact ? 0.52 : 0.50));
    final radius = math.min(size.width, size.height) * (compact ? 0.34 : 0.37);
    final stroke = math.max(3.0, size.shortestSide * 0.035);
    final rect = Rect.fromCircle(center: c, radius: radius);
    void arc(double from, double to, Color color) {
      final a0 = _angleFor(from, startDeg, sweep);
      final a1 = _angleFor(to, startDeg, sweep);
      canvas.drawArc(
        rect,
        _rad(a0),
        _rad(a1 - a0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke
          ..color = color.withValues(alpha: 0.86),
      );
    }

    canvas.drawArc(
      rect,
      _rad(startDeg),
      _rad(sweep),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = _line(0.16),
    );
    final greenStart = math.min(meter.greenFrom, meter.greenTo);
    final greenEnd = math.max(meter.greenFrom, meter.greenTo);
    if (meter.redFrom > greenEnd) {
      arc(meter.min, greenStart, warning);
      arc(greenStart, greenEnd, good);
      arc(greenEnd, meter.redFrom, warning);
      arc(meter.redFrom, meter.max, critical);
    } else {
      arc(meter.min, meter.redFrom, critical);
      arc(meter.redFrom, greenStart, warning);
      arc(greenStart, greenEnd, good);
      arc(greenEnd, meter.max, warning);
    }

    final tickPaint = Paint();
    for (var i = 0; i <= 10; i++) {
      final major = i % 5 == 0;
      final angle = _rad(startDeg + sweep * i / 10);
      final dir = Offset(math.cos(angle), math.sin(angle));
      final outer = c + dir * (radius + 2);
      final inner = c + dir * (radius - stroke * (major ? 1.45 : 0.75));
      tickPaint
        ..color = _line(major ? 0.62 : 0.30)
        ..strokeWidth = major
            ? math.max(1.5, size.shortestSide * 0.009)
            : math.max(1, size.shortestSide * 0.005);
      canvas.drawLine(inner, outer, tickPaint);
    }

    final shown = meter.value * progress + meter.min * (1 - progress);
    final angle = _rad(_angleFor(shown, startDeg, sweep));
    _needle(canvas, c, angle, radius - stroke * 1.35, size.shortestSide);
    _hub(canvas, c, size.shortestSide);
    _valueText(
      canvas,
      Offset(size.width * 0.75, size.height * 0.50),
      size.width * 0.092,
      number: _fmt(meter.value),
      unit: meter.unit,
    );
  }

  void _thermometer(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.30;
    final tubeWidth = math.min(w, h) * 0.14;
    final bulbRadius = tubeWidth * 0.95;
    final topY = h * 0.16;
    final bulbCenter = Offset(cx, h * 0.82);
    final channelTop = topY + tubeWidth * 0.5;
    final channelBottom = bulbCenter.dy;
    final span = channelBottom - channelTop;

    // Glass body: a capsule tube (rounded top) fused with the bulb so the
    // junction reads as a single piece of glass instead of two overlapping
    // outlines.
    final tubeRect = Rect.fromLTRB(
      cx - tubeWidth / 2,
      topY,
      cx + tubeWidth / 2,
      bulbCenter.dy + bulbRadius * 0.25,
    );
    final body = Path.combine(
      PathOperation.union,
      Path()..addRRect(
        RRect.fromRectAndCorners(
          tubeRect,
          topLeft: Radius.circular(tubeWidth / 2),
          topRight: Radius.circular(tubeWidth / 2),
        ),
      ),
      Path()..addOval(Rect.fromCircle(center: bulbCenter, radius: bulbRadius)),
    );
    canvas.drawPath(body, Paint()..color = _line(0.08));

    final t = _norm(meter.value) * progress;
    final levelY = channelBottom - span * t;

    // Fill the fluid with the full palette (green → amber → red across the
    // scale, aligned to the meter's zones) so the colour itself is the legend;
    // the marker further down shows where the current value sits.
    final greenStart = math.min(meter.greenFrom, meter.greenTo);
    final greenEnd = math.max(meter.greenFrom, meter.greenTo);
    final redHigh = meter.redFrom > greenEnd;
    double n(double v) => _norm(v).clamp(0.0, 1.0).toDouble();
    final List<Color> paletteColors;
    final List<double> paletteStops;
    if (redHigh) {
      final gs = n(greenStart);
      final ge = math.max(gs, n(greenEnd));
      final rf = math.max(ge, n(meter.redFrom));
      // Below the green zone's lower bound reads as "too cold" → blue, then
      // green in range, warming through amber to red at the top.
      paletteColors = [cold, cold, good, good, warning, critical, critical];
      paletteStops = [0.0, gs * 0.55, gs, ge, (ge + rf) / 2, rf, 1.0];
    } else {
      final rr = n(meter.redFrom);
      final g = math.max(rr, n(greenStart));
      paletteColors = [critical, critical, warning, good, good];
      paletteStops = [0.0, rr, (rr + g) / 2, g, 1.0];
    }
    final bounds = body.getBounds();
    canvas.save();
    canvas.clipPath(body);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: paletteColors,
          stops: paletteStops,
        ).createShader(bounds),
    );
    canvas.restore();

    // Glass outline and a slim gloss highlight for depth.
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, w * 0.006)
        ..color = _line(0.42),
    );
    final glossW = tubeWidth * 0.13;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          cx - tubeWidth * 0.30,
          topY + tubeWidth * 0.55,
          glossW,
          span * 0.5,
        ),
        Radius.circular(glossW),
      ),
      Paint()..color = _line(0.20),
    );

    // Marker ("streepje") indicating where the current value sits.
    final markLeft = cx - tubeWidth / 2;
    final markRight = cx + tubeWidth / 2;
    final markPaint = Paint()
      ..color = textColor
      ..strokeWidth = math.max(2.0, w * 0.008)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(markLeft - tubeWidth * 0.24, levelY),
      Offset(markRight + tubeWidth * 0.24, levelY),
      markPaint,
    );
    final tri = Path()
      ..moveTo(markRight + tubeWidth * 0.24, levelY)
      ..lineTo(markRight + tubeWidth * 0.62, levelY - tubeWidth * 0.30)
      ..lineTo(markRight + tubeWidth * 0.62, levelY + tubeWidth * 0.30)
      ..close();
    canvas.drawPath(tri, Paint()..color = textColor);

    _valueText(
      canvas,
      Offset(w * 0.72, h * 0.5),
      w * 0.092,
      number: _fmt(meter.value),
      unit: meter.unit,
    );
  }

  void _climb(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.42, size.height * 0.50);
    final r = math.min(size.width, size.height) * 0.36;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.016
        ..color = _line(0.30),
    );
    final tickPaint = Paint()
      ..color = _line(0.44)
      ..strokeWidth = math.max(1, size.shortestSide * 0.007);
    for (var i = 0; i <= 10; i++) {
      final a = _rad(90 - 180 * i / 10);
      final long = i % 5 == 0;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * (r * (long ? 0.72 : 0.82)),
        c + Offset(math.cos(a), math.sin(a)) * (r * 0.95),
        tickPaint..strokeWidth = long ? 2 : 1,
      );
    }
    _text(
      canvas,
      '+',
      c + Offset(0, -r * 0.58),
      size.width * 0.065,
      mutedColor,
      anchor: _Anchor.center,
      align: TextAlign.center,
      weight: FontWeight.w800,
    );
    _text(
      canvas,
      '0',
      c + Offset(r * 0.60, 0),
      size.width * 0.052,
      mutedColor,
      anchor: _Anchor.center,
      align: TextAlign.center,
    );
    _text(
      canvas,
      '-',
      c + Offset(0, r * 0.66),
      size.width * 0.075,
      mutedColor,
      anchor: _Anchor.center,
      align: TextAlign.center,
      weight: FontWeight.w800,
    );
    final shown = meter.value * progress;
    final angle = _rad(90 - 180 * _norm(shown));
    _needle(canvas, c, angle, r * 0.76, size.shortestSide);
    _hub(canvas, c, size.shortestSide);
    _valueText(
      canvas,
      Offset(size.width * 0.77, size.height * 0.50),
      size.width * 0.092,
      number: '${meter.value > 0 ? '+' : ''}${_fmt(meter.value)}',
      unit: meter.unit,
    );
  }

  void _horizon(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.42, size.height * 0.50);
    final r = math.min(size.width, size.height) * 0.35;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    canvas.translate(c.dx, c.dy);
    canvas.rotate(_rad(meter.bank * progress));
    final pitch = meter.pitch * progress * r / 45;
    canvas.drawRect(
      Rect.fromLTWH(-r * 1.6, -r * 1.6 + pitch, r * 3.2, r * 1.6),
      Paint()..color = sky,
    );
    canvas.drawRect(
      Rect.fromLTWH(-r * 1.6, pitch, r * 3.2, r * 1.6),
      Paint()..color = ground,
    );
    canvas.drawLine(
      Offset(-r * 1.4, pitch),
      Offset(r * 1.4, pitch),
      Paint()
        ..color = Colors.white
        ..strokeWidth = r * 0.035,
    );
    canvas.restore();
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.018
        ..color = _line(0.55),
    );
    canvas.drawLine(
      Offset(c.dx - r * 0.38, c.dy),
      Offset(c.dx + r * 0.38, c.dy),
      Paint()
        ..color = accent
        ..strokeWidth = size.width * 0.018
        ..strokeCap = StrokeCap.round,
    );
    _text(
      canvas,
      faceText.attitude
          .replaceAll('{pitch}', _fmt(meter.pitch))
          .replaceAll('{bank}', _fmt(meter.bank)),
      Offset(size.width * 0.80, size.height * 0.50),
      size.width * 0.04,
      textColor,
      align: TextAlign.center,
      anchor: _Anchor.center,
      weight: FontWeight.w700,
    );
  }

  void _heading(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.42, size.height * 0.50);
    final r = math.min(size.width, size.height) * 0.35;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.017
        ..color = _line(0.30),
    );
    for (var i = 0; i < 36; i++) {
      final a = _rad(i * 10 - 90);
      final long = i % 3 == 0;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * (r * (long ? 0.82 : 0.90)),
        c + Offset(math.cos(a), math.sin(a)) * r,
        Paint()
          ..color = _line(long ? 0.62 : 0.32)
          ..strokeWidth = long ? 2 : 1,
      );
    }
    const labels = {'N': -90.0, 'E': 0.0, 'S': 90.0, 'W': 180.0};
    for (final entry in labels.entries) {
      final a = _rad(entry.value);
      _text(
        canvas,
        entry.key,
        c + Offset(math.cos(a), math.sin(a)) * (r * 0.66),
        size.width * 0.038,
        mutedColor,
        anchor: _Anchor.center,
        align: TextAlign.center,
        weight: FontWeight.w600,
      );
    }
    final targetAngle = _rad(meter.heading - 90);
    final markerOuter =
        c + Offset(math.cos(targetAngle), math.sin(targetAngle)) * (r * 1.02);
    final markerLeft =
        c +
        Offset(math.cos(targetAngle + 0.12), math.sin(targetAngle + 0.12)) *
            (r * 0.83);
    final markerRight =
        c +
        Offset(math.cos(targetAngle - 0.12), math.sin(targetAngle - 0.12)) *
            (r * 0.83);
    final marker = Path()
      ..moveTo(markerOuter.dx, markerOuter.dy)
      ..lineTo(markerLeft.dx, markerLeft.dy)
      ..lineTo(markerRight.dx, markerRight.dy)
      ..close();
    canvas.drawPath(marker, Paint()..color = accent.withValues(alpha: 0.95));

    final angle = _rad((meter.value * progress) - 90);
    final needle = Path()
      ..moveTo(
        c.dx + math.cos(angle) * r * 0.72,
        c.dy + math.sin(angle) * r * 0.72,
      )
      ..lineTo(
        c.dx + math.cos(angle + 2.6) * r * 0.18,
        c.dy + math.sin(angle + 2.6) * r * 0.18,
      )
      ..lineTo(
        c.dx + math.cos(angle - 2.6) * r * 0.18,
        c.dy + math.sin(angle - 2.6) * r * 0.18,
      )
      ..close();
    canvas.drawPath(needle, Paint()..color = accent);
    _hub(canvas, c, size.shortestSide);
    _text(
      canvas,
      faceText.actual.replaceAll('{value}', _fmt(meter.value).padLeft(3, '0')),
      Offset(size.width * 0.76, size.height * 0.43),
      size.width * 0.05,
      textColor,
      align: TextAlign.center,
      anchor: _Anchor.center,
      weight: FontWeight.w800,
    );
    _text(
      canvas,
      faceText.target.replaceAll(
        '{heading}',
        _fmt(meter.heading).padLeft(3, '0'),
      ),
      Offset(size.width * 0.76, size.height * 0.59),
      size.width * 0.038,
      mutedColor,
      align: TextAlign.center,
      anchor: _Anchor.center,
      weight: FontWeight.w600,
    );
    if (meter.markerLabel.isNotEmpty) {
      _text(
        canvas,
        meter.markerLabel,
        Offset(size.width * 0.76, size.height * 0.72),
        size.width * 0.032,
        mutedColor,
        align: TextAlign.center,
        anchor: _Anchor.center,
      );
    }
  }

  double _angleFor(double value, double startDeg, double sweep) =>
      startDeg + sweep * _norm(value).clamp(0, 1);

  double _norm(double value) {
    final span = meter.max - meter.min;
    if (span <= 0) return 0;
    return ((value - meter.min) / span).clamp(0, 1).toDouble();
  }

  double _rad(double deg) => deg * math.pi / 180;

  String _fmt(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  /// A tapered instrument needle (wide at the hub, pointed at the tip, with a
  /// short counterweight tail) — reads far more like a real gauge than a plain
  /// line. [s] is the instrument's shortest side.
  void _needle(
    Canvas canvas,
    Offset c,
    double angleRad,
    double length,
    double s,
  ) {
    final dir = Offset(math.cos(angleRad), math.sin(angleRad));
    final perp = Offset(-dir.dy, dir.dx);
    final halfW = math.max(2.0, s * 0.016);
    final tip = c + dir * length;
    final tail = c - dir * (length * 0.20);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(c.dx + perp.dx * halfW, c.dy + perp.dy * halfW)
      ..lineTo(tail.dx, tail.dy)
      ..lineTo(c.dx - perp.dx * halfW, c.dy - perp.dy * halfW)
      ..close();
    canvas.drawPath(path, Paint()..color = accent);
  }

  /// A machined two-tone hub: accent disc, a ring punched out in the surface
  /// colour, and an accent centre dot.
  void _hub(Canvas canvas, Offset c, double s) {
    canvas.drawCircle(c, s * 0.05, Paint()..color = accent);
    canvas.drawCircle(c, s * 0.026, Paint()..color = surface);
    canvas.drawCircle(c, s * 0.013, Paint()..color = accent);
  }

  /// Renders a reading as a large number with a smaller, muted unit so the
  /// value carries weight without the unit shouting.
  void _valueText(
    Canvas canvas,
    Offset center,
    double numberSize, {
    required String number,
    String unit = '',
  }) {
    final painter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: number,
            style: TextStyle(
              color: textColor,
              fontSize: numberSize,
              fontWeight: FontWeight.w800,
              fontFamily: font,
              decoration: TextDecoration.none,
              height: 1.0,
            ),
          ),
          if (unit.isNotEmpty)
            TextSpan(
              text: unit,
              style: TextStyle(
                color: mutedColor,
                fontSize: numberSize * 0.6,
                fontWeight: FontWeight.w600,
                fontFamily: font,
                decoration: TextDecoration.none,
                height: 1.0,
              ),
            ),
        ],
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
    )..layout(maxWidth: numberSize * 16);
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  void _text(
    Canvas canvas,
    String text,
    Offset offset,
    double size,
    Color color, {
    FontWeight weight = FontWeight.w600,
    TextAlign align = TextAlign.left,
    _Anchor anchor = _Anchor.topLeft,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          fontFamily: font,
          decoration: TextDecoration.none,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(12, size * 12));
    final dx = switch (anchor) {
      _Anchor.topCenter || _Anchor.center => offset.dx - painter.width / 2,
      _ => offset.dx,
    };
    final dy = switch (anchor) {
      _Anchor.center => offset.dy - painter.height / 2,
      _ => offset.dy,
    };
    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_CockpitInstrumentPainter oldDelegate) =>
      oldDelegate.meter != meter ||
      oldDelegate.progress != progress ||
      oldDelegate.accent != accent ||
      oldDelegate.surface != surface ||
      oldDelegate.textColor != textColor ||
      oldDelegate.mutedColor != mutedColor ||
      oldDelegate.good != good ||
      oldDelegate.warning != warning ||
      oldDelegate.critical != critical ||
      oldDelegate.cold != cold ||
      oldDelegate.sky != sky ||
      oldDelegate.ground != ground ||
      oldDelegate.font != font ||
      oldDelegate.faceText != faceText;
}

enum _Anchor { topLeft, topCenter, center }
