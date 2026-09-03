part of '../slide_preview.dart';

/// Tekent één cockpitcel: het instrument op de wijzerplaat, het uitleesvenster
/// in de flank en, authentiek, de schroeven en het glas. Waar alles staat komt
/// uit [plan] (services/cockpit_layout.dart); de painter meet niets zelf, zodat
/// de SVG-export met dezelfde rekenkern hetzelfde beeld geeft.
class _CockpitInstrumentPainter extends CustomPainter {
  final CockpitMeterSpec meter;
  final CockpitCellPlan plan;

  /// Rasterbrede krimpfactor voor de vensterregels ([cockpitReadoutScale]).
  final double readoutScale;
  final double progress;
  final CockpitVisualStyle visualStyle;
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

  /// De teksten in het uitleesvenster, al vertaald, met plaatshouders voor de
  /// meterwaarden. Een painter heeft geen BuildContext, dus ze komen van
  /// buiten; een record omdat dat waarde-gelijkheid heeft en [shouldRepaint]
  /// er dus in één vergelijking op kan afgaan.
  final ({String attitude, String actual, String target}) faceText;

  _CockpitInstrumentPainter({
    required this.meter,
    required this.plan,
    required this.readoutScale,
    required this.progress,
    required this.visualStyle,
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

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(plan.dialCenterX, plan.dialCenterY);
    final s = plan.dialSide;
    if (_authentic) {
      _screws(canvas, plan.instrumentBand);
      _authenticFrame(canvas, c, s);
    } else {
      _classicFrame(canvas, plan.instrumentBand);
    }
    switch (meter.type) {
      case CockpitMeterType.speedometer:
        _arcGauge(canvas, c, s, sweep: 250, startDeg: 145);
        break;
      case CockpitMeterType.voltmeter:
        _arcGauge(canvas, c, s, sweep: 180, startDeg: 180);
        break;
      case CockpitMeterType.thermometer:
        _thermometer(canvas, c, s);
        break;
      case CockpitMeterType.altimeter:
        _arcGauge(canvas, c, s, sweep: 300, startDeg: 120);
        break;
      case CockpitMeterType.climbDescent:
        _climb(canvas, c, s);
        break;
      case CockpitMeterType.horizon:
        _horizon(canvas, c, s);
        break;
      case CockpitMeterType.heading:
        _heading(canvas, c, s);
        break;
    }
    if (_authentic) _authenticGlass(canvas, c, s);
    _readout(canvas);
  }

  void _classicFrame(Canvas canvas, CockpitRect band) {
    final rect = Rect.fromLTWH(band.x, band.y, band.w, band.h);
    final r = math.min(band.w, band.h) * 0.07;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(r)),
      Paint()..color = surface,
    );
    final borderW = math.max(1.0, rect.shortestSide * 0.008);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(borderW / 2), Radius.circular(r)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderW
        ..color = accent.withValues(alpha: 0.42 + progress * 0.22),
    );
    // Thin inner hairline for a machined "bezel" depth, derived from the slide
    // text colour so it works on any background.
    //
    // The corner radius is floored at zero, which `RRect` requires: the outer
    // radius follows the meter's size while the border width has a fixed pixel
    // as its floor, so on a meter shorter than some fifteen pixels — a preview
    // being *measured* at zero width, or simply a great many meters side by
    // side — that floor wins and the difference goes negative. A sharp corner
    // is the right answer there (#782).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(borderW + 1.5),
        Radius.circular(math.max(0, r - borderW)),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _line(0.06 + progress * 0.04),
    );
  }

  /// Schaalcijfer op de wijzerplaat; in de miniatuur (een paar pixels) blijft
  /// hij weg — een streepje dat een cijfer voorstelt helpt niemand.
  void _scaleLabel(
    Canvas canvas,
    String text,
    Offset at, {
    _Anchor anchor = _Anchor.center,
    TextAlign align = TextAlign.center,
  }) {
    if (plan.scaleSize < cockpitMinTextPx) return;
    _text(
      canvas,
      text,
      at,
      plan.scaleSize,
      _instrumentMuted,
      anchor: anchor,
      align: align,
    );
  }

  void _arcGauge(
    Canvas canvas,
    Offset c,
    double s, {
    required double sweep,
    required double startDeg,
  }) {
    final radius = s * 0.335;
    final stroke = math.max(3.0, s * 0.035);
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
          ..color = color.withValues(alpha: 0.86 * _power),
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
            ? math.max(1.5, s * 0.009)
            : math.max(1, s * 0.005);
      canvas.drawLine(inner, outer, tickPaint);
    }

    // Minimum en maximum in de boogvrije opening onderaan — de plek waar
    // vroeger de waarde-regel doorheen liep; die staat nu in het venster.
    _scaleLabel(
      canvas,
      cockpitFormatNumber(meter.min),
      _arcScaleLabel(c, radius, sweep, right: false),
    );
    _scaleLabel(
      canvas,
      cockpitFormatNumber(meter.max),
      _arcScaleLabel(c, radius, sweep, right: true),
    );

    final shown = _animatedValue(meter.value);
    final angle = _rad(_angleFor(shown, startDeg, sweep));
    _needle(canvas, c, angle, radius - stroke * 1.35, s);
    _hub(canvas, c, s);
  }

  void _thermometer(Canvas canvas, Offset c, double s) {
    // De buis staat op de bezel-as; het getal staat niet meer onder de bol
    // maar in het venster, dus de plaat is helemaal voor de buis.
    // De buis begint onder de lampjes (op −0,307·s) en de bol zakt mee, zodat
    // de testlampen en het maximum-cijfer vrij blijven.
    final cx = c.dx;
    final tubeWidth = s * 0.11;
    final bulbRadius = tubeWidth * 0.82;
    final topY = c.dy - s * 0.25;
    final bulbCenter = Offset(cx, c.dy + s * 0.14);
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

    final t = _norm(_animatedValue(meter.value));
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
        ..strokeWidth = math.max(1.5, s * 0.006)
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
      ..color = _instrumentInk
      ..strokeWidth = math.max(2.0, s * 0.008)
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
    canvas.drawPath(tri, Paint()..color = _instrumentInk);

    // Het bereik was nergens af te lezen: maximum naast de kanaaltop, minimum
    // naast de bol, rechts uitgelijnd links van de buis.
    _scaleLabel(
      canvas,
      cockpitFormatNumber(meter.max),
      Offset(cx - s * 0.10, channelTop),
      anchor: _Anchor.centerRight,
      align: TextAlign.right,
    );
    _scaleLabel(
      canvas,
      cockpitFormatNumber(meter.min),
      Offset(cx - s * 0.10, channelBottom),
      anchor: _Anchor.centerRight,
      align: TextAlign.right,
    );
  }

  void _climb(Canvas canvas, Offset c, double s) {
    final r = s * 0.33;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.016
        ..color = _line(0.30),
    );
    final tickPaint = Paint()
      ..color = _line(0.44)
      ..strokeWidth = math.max(1, s * 0.007);
    for (var i = 0; i <= 10; i++) {
      final a = _rad(90 - 180 * i / 10);
      final long = i % 5 == 0;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * (r * (long ? 0.72 : 0.82)),
        c + Offset(math.cos(a), math.sin(a)) * (r * 0.95),
        tickPaint..strokeWidth = long ? 2 : 1,
      );
    }
    // Het bereik met teken in plaats van een kaal + en −: dezelfde inkt, meer
    // informatie, geen vertaling nodig. In de linkerhelft, want de naald
    // bestrijkt de rechter: op de 0°-lijn liep hij dwars door de "0".
    _scaleLabel(
      canvas,
      '+${cockpitFormatNumber(meter.max)}',
      c + Offset(-r * 0.50, -r * 0.52),
    );
    _scaleLabel(canvas, '0', c + Offset(-r * 0.62, 0));
    _scaleLabel(
      canvas,
      cockpitFormatNumber(meter.min),
      c + Offset(-r * 0.50, r * 0.52),
    );
    final shown = _animatedValue(meter.value);
    final angle = _rad(90 - 180 * _norm(shown));
    _needle(canvas, c, angle, r * 0.76, s);
    _hub(canvas, c, s);
  }

  void _horizon(Canvas canvas, Offset c, double s) {
    final r = s * 0.34;
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
        ..strokeWidth = s * 0.018
        ..color = _line(0.55),
    );
    // Het vliegtuigsymbool: wit met een donkere rand, zoals de horizonlijn.
    // In accentkleur was het op de lucht (EU-blauw op #2563EB) onzichtbaar.
    canvas.drawLine(
      Offset(c.dx - r * 0.38, c.dy),
      Offset(c.dx + r * 0.38, c.dy),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..strokeWidth = s * 0.028
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset(c.dx - r * 0.38, c.dy),
      Offset(c.dx + r * 0.38, c.dy),
      Paint()
        ..color = Colors.white
        ..strokeWidth = s * 0.016
        ..strokeCap = StrokeCap.round,
    );
    // Pitch en bank staan in het venster (inkt op plaat) en niet meer
    // donkerblauw op de bruine grond.
  }

  void _heading(Canvas canvas, Offset c, double s) {
    final r = s * 0.34;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.017
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
      _scaleLabel(
        canvas,
        entry.key,
        c + Offset(math.cos(a), math.sin(a)) * (r * 0.66),
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

    final angle = _rad(_animatedHeading(meter.value) - 90);
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
    canvas.drawPath(
      needle,
      Paint()..color = _authentic ? _instrumentInk : accent,
    );
    _hub(canvas, c, s);
    // ACT/TGT/marker staan in het venster naast de roos (#1110 verhuisd): de
    // roos blijft heel, en de markerregel is daar begrensd zoals elk label.
  }

  /// Het uitleesvenster: authentiek een plaat in face-kleur, en daarop de
  /// regels uit de rekenkern, verticaal gecentreerd.
  void _readout(Canvas canvas) {
    final win = plan.window;
    final rect = Rect.fromLTWH(win.x, win.y, win.w, win.h);
    if (_authentic) _readoutPlate(canvas, rect, plan.dialSide);
    if (plan.numberSize < cockpitMinTextPx) return;
    final lines = cockpitReadoutLines(
      meter,
      plan,
      attitudeTemplate: faceText.attitude,
      actualTemplate: faceText.actual,
      targetTemplate: faceText.target,
      shownValue: _animatedValue(meter.value),
      shownHeading: _animatedHeading(meter.value),
      scale: readoutScale,
    );
    var y = rect.center.dy - cockpitReadoutHeight(lines) / 2;
    for (final line in lines) {
      // Een eenheidregel van vier pixels is in de miniatuur alleen een vlek.
      if (line.size >= cockpitMinTextPx) {
        _readoutLine(canvas, Offset(rect.center.dx, y + line.height / 2), line);
      }
      y += line.height + line.gapAfter;
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

  @override
  bool shouldRepaint(_CockpitInstrumentPainter oldDelegate) =>
      oldDelegate.meter != meter ||
      oldDelegate.plan.width != plan.width ||
      oldDelegate.plan.height != plan.height ||
      oldDelegate.plan.numberSize != plan.numberSize ||
      oldDelegate.readoutScale != readoutScale ||
      oldDelegate.progress != progress ||
      oldDelegate.visualStyle != visualStyle ||
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

enum _Anchor { topLeft, topCenter, center, centerRight }
