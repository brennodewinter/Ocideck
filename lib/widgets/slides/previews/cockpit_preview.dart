part of '../slide_preview.dart';

class _CockpitPreview extends StatefulWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;
  final bool presentationMode;

  const _CockpitPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
    required this.presentationMode,
  });

  @override
  State<_CockpitPreview> createState() => _CockpitPreviewState();
}

class _CockpitPreviewState extends State<_CockpitPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
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
        oldWidget.presentationMode != widget.presentationMode) {
      _maybeStart();
    }
  }

  void _maybeStart() {
    final spec = CockpitSpec.parse(widget.slide.customMarkdown);
    _controller.duration = Duration(milliseconds: spec.animationDurationMs);
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
    final spec = CockpitSpec.parse(widget.slide.customMarkdown);
    final meters = spec.meters.isEmpty
        ? CockpitSpec.pentestPreset().meters
        : spec.meters.take(cockpitMaxMeters).toList();
    final bg = _hexColor(widget.profile.slideBackgroundColor);
    final accent = _hexColor(widget.profile.accentColor);
    final textColor = _hexColor(widget.profile.textColor);
    final pad = widget.w * 0.04;
    final logoSafe = widget.slide.showLogo
        ? _logoSafeInsets(widget.w, widget.profile)
        : EdgeInsets.zero;
    final outerPadding = EdgeInsets.fromLTRB(
      pad + logoSafe.left,
      pad + logoSafe.top,
      pad + logoSafe.right,
      pad + logoSafe.bottom,
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
  final double bootProgress;
  final String font;

  const _CockpitGrid({
    required this.meters,
    required this.accent,
    required this.surface,
    required this.textColor,
    required this.mutedColor,
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
  final String font;

  const _CockpitInstrument({
    required this.meter,
    required this.progress,
    required this.accent,
    required this.surface,
    required this.textColor,
    required this.mutedColor,
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
                  font: font,
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
  final String font;

  _CockpitInstrumentPainter({
    required this.meter,
    required this.progress,
    required this.accent,
    required this.surface,
    required this.textColor,
    required this.mutedColor,
    required this.font,
  });

  static const _green = Color(0xFF22C55E);
  static const _amber = Color(0xFFF59E0B);
  static const _red = Color(0xFFEF4444);

  /// Structural lines (gauge tracks, ticks, glass) derive from the slide text
  /// colour at low opacity so the instruments read on any slide background.
  Color _line(double alpha) => textColor.withValues(alpha: alpha);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = math.min(size.width, size.height) * 0.06;
    final bg = Paint()..color = surface;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)), bg);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(1), Radius.circular(r)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, size.shortestSide * 0.008)
        ..color = accent.withValues(alpha: 0.42 + progress * 0.22),
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
    final c = Offset(size.width * 0.43, size.height * (compact ? 0.52 : 0.50));
    final radius = math.min(size.width, size.height) * (compact ? 0.33 : 0.35);
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
      arc(meter.min, greenStart, _amber);
      arc(greenStart, greenEnd, _green);
      arc(greenEnd, meter.redFrom, _amber);
      arc(meter.redFrom, meter.max, _red);
    } else {
      arc(meter.min, meter.redFrom, _red);
      arc(meter.redFrom, greenStart, _amber);
      arc(greenStart, greenEnd, _green);
      arc(greenEnd, meter.max, _amber);
    }

    final tickPaint = Paint()
      ..color = _line(0.50)
      ..strokeWidth = math.max(1, size.shortestSide * 0.006);
    for (var i = 0; i <= 10; i++) {
      final angle = _rad(startDeg + sweep * i / 10);
      final outer = c + Offset(math.cos(angle), math.sin(angle)) * (radius + 2);
      final inner =
          c +
          Offset(math.cos(angle), math.sin(angle)) * (radius - stroke * 1.2);
      canvas.drawLine(inner, outer, tickPaint);
    }

    final shown = meter.value * progress + meter.min * (1 - progress);
    final angle = _rad(_angleFor(shown, startDeg, sweep));
    final needleEnd =
        c + Offset(math.cos(angle), math.sin(angle)) * (radius - stroke * 1.35);
    canvas.drawLine(
      c,
      needleEnd,
      Paint()
        ..color = accent
        ..strokeWidth = math.max(2, size.shortestSide * 0.018)
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(c, size.shortestSide * 0.035, Paint()..color = accent);
    _text(
      canvas,
      '${_fmt(meter.value)}${meter.unit}',
      Offset(size.width * 0.78, size.height * 0.52),
      size.width * 0.058,
      textColor,
      align: TextAlign.center,
      anchor: _Anchor.center,
      weight: FontWeight.w700,
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
      Path()
        ..addRRect(
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
      final g = n(greenEnd);
      final rr = math.max(g, n(meter.redFrom));
      paletteColors = const [_green, _green, _amber, _red, _red];
      paletteStops = [0.0, g, (g + rr) / 2, rr, 1.0];
    } else {
      final rr = n(meter.redFrom);
      final g = math.max(rr, n(greenStart));
      paletteColors = const [_red, _red, _amber, _green, _green];
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

    _text(
      canvas,
      '${_fmt(meter.value)}${meter.unit}',
      Offset(w * 0.76, h * 0.5),
      w * 0.066,
      textColor,
      anchor: _Anchor.center,
      align: TextAlign.center,
      weight: FontWeight.w800,
    );
  }

  void _climb(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.44, size.height * 0.50);
    final r = math.min(size.width, size.height) * 0.34;
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
    final needleEnd = c + Offset(math.cos(angle), math.sin(angle)) * (r * 0.76);
    canvas.drawLine(
      c,
      needleEnd,
      Paint()
        ..color = accent
        ..strokeWidth = math.max(2, size.shortestSide * 0.018)
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(c, size.shortestSide * 0.034, Paint()..color = accent);
    _text(
      canvas,
      '${meter.value > 0 ? '+' : ''}${_fmt(meter.value)}${meter.unit}',
      Offset(size.width * 0.78, size.height * 0.53),
      size.width * 0.058,
      textColor,
      anchor: _Anchor.center,
      align: TextAlign.center,
      weight: FontWeight.w700,
    );
  }

  void _horizon(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.45, size.height * 0.50);
    final r = math.min(size.width, size.height) * 0.34;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    canvas.translate(c.dx, c.dy);
    canvas.rotate(_rad(meter.bank * progress));
    final pitch = meter.pitch * progress * r / 45;
    canvas.drawRect(
      Rect.fromLTWH(-r * 1.6, -r * 1.6 + pitch, r * 3.2, r * 1.6),
      Paint()..color = const Color(0xFF2563EB),
    );
    canvas.drawRect(
      Rect.fromLTWH(-r * 1.6, pitch, r * 3.2, r * 1.6),
      Paint()..color = const Color(0xFF9A5A22),
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
      'P ${_fmt(meter.pitch)}  B ${_fmt(meter.bank)}',
      Offset(size.width * 0.77, size.height * 0.53),
      size.width * 0.042,
      mutedColor,
      align: TextAlign.center,
      anchor: _Anchor.center,
    );
  }

  void _heading(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.44, size.height * 0.50);
    final r = math.min(size.width, size.height) * 0.34;
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
    canvas.drawPath(marker, Paint()..color = _amber.withValues(alpha: 0.95));

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
    canvas.drawCircle(c, size.shortestSide * 0.034, Paint()..color = accent);
    _text(
      canvas,
      'ACT ${_fmt(meter.value).padLeft(3, '0')}°',
      Offset(size.width * 0.78, size.height * 0.44),
      size.width * 0.042,
      textColor,
      align: TextAlign.center,
      anchor: _Anchor.center,
      weight: FontWeight.w700,
    );
    _text(
      canvas,
      'TGT ${_fmt(meter.heading).padLeft(3, '0')}°',
      Offset(size.width * 0.78, size.height * 0.60),
      size.width * 0.034,
      mutedColor,
      align: TextAlign.center,
      anchor: _Anchor.center,
      weight: FontWeight.w600,
    );
    if (meter.markerLabel.isNotEmpty) {
      _text(
        canvas,
        meter.markerLabel,
        Offset(size.width * 0.78, size.height * 0.72),
        size.width * 0.030,
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
      oldDelegate.font != font;
}

enum _Anchor { topLeft, topCenter, center }
