part of '../slide_preview.dart';

/// Materiaal- en tekendetails van de cockpitmeter.
///
/// Deze helpers blijven onderdeel van dezelfde painter, maar staan los van de
/// metertype-geometrie zodat `cockpit_instrument_painter.dart` onder de
/// bestandsgrens blijft. Alle geometrie is een fractie van de zijde `s` van het
/// instrumentvierkant uit `CockpitCellPlan`, met het bezelmiddelpunt `c` als
/// oorsprong — niet van de celmaat, want de cel is breder dan de wijzerplaat en
/// draagt ernaast het uitleesvenster.
extension _CockpitInstrumentPainterSupport on _CockpitInstrumentPainter {
  bool get _authentic => visualStyle == CockpitVisualStyle.authentic;

  double get _power => !_authentic
      ? 1
      : Curves.easeOut.transform(((progress - 0.03) / 0.30).clamp(0.0, 1.0));

  /// Instrumentpalet voor de authentieke stand, gekozen op de helderheid van
  /// de dia-achtergrond zodat een lichte dia een licht instrument krijgt.
  CockpitPalette get _palette => AppTheme.cockpitPaletteFor(surface);

  Color get _instrumentInk => _authentic ? _palette.ink : textColor;

  /// Gedempte inkt op volle dekking: op de crème plaat haalt #585D64 zo
  /// 5,2:1, met 0,85 alfa bleef hij op 3,96:1 onder AA.
  Color get _instrumentMuted => _authentic ? _palette.inkMuted : mutedColor;

  /// Structural lines (gauge tracks, ticks, glass) derive from the instrument
  /// ink at low opacity so they read on any slide background.
  Color _line(double alpha) => _instrumentInk.withValues(alpha: alpha * _power);

  Offset _arcScaleLabel(
    Offset center,
    double radius,
    double sweep, {
    required bool right,
  }) {
    // A 250°/300° dial ends in the lower corners. Pull those labels inward so
    // they do not cross the colour bands; the clear lower row of the 180°
    // voltmeter keeps its existing positions.
    final wideSweep = sweep > 220;
    final x = radius * (wideSweep ? 0.62 : 0.78) * (right ? 1 : -1);
    final y = radius * (wideSweep ? 0.40 : 0.54);
    return center + Offset(x, y);
  }

  /// Schroeven in de hoeken van de instrumentband (bezel én venster), zodat
  /// de labelstrook eronder vrij blijft.
  void _screws(Canvas canvas, CockpitRect band) {
    final short = math.min(band.w, band.h);
    final inset = short * 0.065;
    for (final screw in [
      Offset(band.x + inset, band.y + inset),
      Offset(band.right - inset, band.y + inset),
      Offset(band.x + inset, band.bottom - inset),
      Offset(band.right - inset, band.bottom - inset),
    ]) {
      final sr = math.max(2.2, short * 0.025);
      canvas.drawCircle(screw, sr, Paint()..color = _palette.screw);
      canvas.drawCircle(screw, sr * 0.72, Paint()..color = _palette.screwMetal);
      canvas.drawLine(
        screw + Offset(-sr * 0.45, -sr * 0.45),
        screw + Offset(sr * 0.45, sr * 0.45),
        Paint()
          ..color = _palette.screwSlot
          ..strokeWidth = math.max(1, sr * 0.25),
      );
    }
  }

  void _authenticFrame(Canvas canvas, Offset c, double s) {
    final radius = s * 0.465;
    canvas.drawCircle(
      c + Offset(0, s * 0.025),
      radius * 1.03,
      Paint()..color = Colors.black.withValues(alpha: 0.60),
    );
    canvas.drawCircle(c, radius, Paint()..color = _palette.bezel);
    canvas.drawCircle(
      c,
      radius * 0.93,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, s * 0.025)
        ..color = _palette.bezelDark,
    );
    canvas.drawCircle(c, radius * 0.88, Paint()..color = _palette.face);
    canvas.drawCircle(
      c,
      radius * 0.86,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _line(0.22),
    );

    final lampsOn = progress > 0.10 && progress < 0.48;
    final lampY = c.dy - radius * 0.66;
    final lampColors = [critical, warning, good];
    for (var i = 0; i < lampColors.length; i++) {
      final lamp = Offset(c.dx + (i - 1) * radius * 0.19, lampY);
      canvas.drawCircle(lamp, radius * 0.027, Paint()..color = Colors.black);
      canvas.drawCircle(
        lamp,
        radius * 0.019,
        Paint()
          ..color = lampColors[i].withValues(
            alpha: lampsOn ? 0.95 : 0.18 * _power,
          ),
      );
    }
  }

  void _authenticGlass(Canvas canvas, Offset c, double s) {
    final radius = s * 0.40;
    final glass = Rect.fromCircle(center: c, radius: radius);
    canvas.save();
    canvas.clipPath(Path()..addOval(glass));
    canvas.drawArc(
      glass.shift(Offset(-radius * 0.17, -radius * 0.20)),
      _rad(205),
      _rad(88),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, radius * 0.055)
        ..color = Colors.white.withValues(alpha: 0.07 * _power),
    );
    canvas.restore();
  }

  double _animatedValue(double target) {
    if (!_authentic) return target * progress + meter.min * (1 - progress);
    if (progress <= 0.16) return meter.min;
    if (progress < 0.52) {
      final t = Curves.easeOutCubic.transform((progress - 0.16) / 0.36);
      return meter.min + (meter.max - meter.min) * t;
    }
    final t = Curves.easeOutBack.transform((progress - 0.52) / 0.48);
    return (meter.max + (target - meter.max) * t)
        .clamp(meter.min, meter.max)
        .toDouble();
  }

  double _animatedHeading(double target) {
    if (!_authentic) return target * progress;
    if (progress <= 0.16) return 0;
    if (progress < 0.52) {
      return 360 * Curves.easeOutCubic.transform((progress - 0.16) / 0.36);
    }
    final t = Curves.easeOutBack.transform((progress - 0.52) / 0.48);
    return 360 + (target - 360) * t;
  }

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
    canvas.drawPath(
      path,
      Paint()..color = _authentic ? _instrumentInk : accent,
    );
  }

  void _hub(Canvas canvas, Offset c, double s) {
    if (_authentic) {
      canvas.drawCircle(c, s * 0.052, Paint()..color = _palette.hub);
      canvas.drawCircle(c, s * 0.038, Paint()..color = _palette.hubMetal);
      canvas.drawCircle(c, s * 0.022, Paint()..color = _palette.hubInner);
      canvas.drawCircle(c, s * 0.009, Paint()..color = _palette.hubHighlight);
      return;
    }
    canvas.drawCircle(c, s * 0.05, Paint()..color = accent);
    canvas.drawCircle(c, s * 0.026, Paint()..color = surface);
    canvas.drawCircle(c, s * 0.013, Paint()..color = accent);
  }

  /// De plaat van het uitleesvenster: face-kleur met een hairline, dezelfde
  /// tekenroutine als het kompasvenster van #1110, nu voor elk instrument.
  void _readoutPlate(Canvas canvas, Rect window, double s) {
    final rr = RRect.fromRectAndRadius(window, Radius.circular(s * 0.03));
    canvas
      ..drawRRect(rr, Paint()..color = _palette.face)
      ..drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, s * 0.006)
          ..color = _line(0.30),
      );
  }

  /// Eén vensterregel, gecentreerd op [center]: het getal vet in inkt met de
  /// korte eenheid er kleiner achter, de overige regels gedempt. Tabellaire
  /// cijfers zodat de rollende uitlezing niet wiebelt.
  void _readoutLine(Canvas canvas, Offset center, CockpitReadoutLine line) {
    final ink = _instrumentInk.withValues(alpha: _power);
    final muted = _instrumentMuted.withValues(
      alpha: _instrumentMuted.a * _power,
    );
    // Een inline-eenheid van vier pixels is in de miniatuur alleen een vlek.
    final unit = line.inlineUnitSize >= cockpitMinTextPx
        ? line.inlineUnit
        : null;
    final painter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: line.text,
            style: TextStyle(
              color: line.strong ? ink : muted,
              fontSize: line.size,
              fontWeight: line.strong ? FontWeight.w800 : FontWeight.w600,
              fontFamily: font,
              fontFeatures: const [FontFeature.tabularFigures()],
              decoration: TextDecoration.none,
              height: 1.0,
            ),
          ),
          if (unit != null) ...[
            TextSpan(
              text: ' ',
              style: TextStyle(fontSize: line.inlineGap, height: 1.0),
            ),
            TextSpan(
              text: unit,
              style: TextStyle(
                color: muted,
                fontSize: line.inlineUnitSize,
                fontWeight: FontWeight.w600,
                fontFamily: font,
                decoration: TextDecoration.none,
                height: 1.0,
              ),
            ),
          ],
        ],
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(1, plan.window.w));
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
    double? maxWidth,
  }) {
    final effectiveColor = _authentic
        ? (color == accent
              ? accent.withValues(alpha: _power)
              : color.withValues(alpha: color.a * _power))
        : color;
    final painter =
        TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: effectiveColor,
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
        )..layout(
          maxWidth: maxWidth == null
              ? math.max(12, size * 12)
              : math.max(1, maxWidth),
        );
    final dx = switch (anchor) {
      _Anchor.topCenter || _Anchor.center => offset.dx - painter.width / 2,
      _Anchor.centerRight => offset.dx - painter.width,
      _ => offset.dx,
    };
    final dy = switch (anchor) {
      _Anchor.center || _Anchor.centerRight => offset.dy - painter.height / 2,
      _ => offset.dy,
    };
    painter.paint(canvas, Offset(dx, dy));
  }
}
