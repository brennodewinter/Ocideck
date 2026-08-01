part of '../slide_preview.dart';

/// Materiaal- en tekendetails van de cockpitmeter.
///
/// Deze helpers blijven onderdeel van dezelfde painter, maar staan los van de
/// metertype-geometrie zodat `cockpit_preview.dart` onder de bestandsgrens
/// blijft en de klassieke schildercode overzichtelijk blijft.
extension _CockpitInstrumentPainterSupport on _CockpitInstrumentPainter {
  void _authenticFrame(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.465;
    canvas.drawCircle(
      c + Offset(0, size.shortestSide * 0.025),
      radius * 1.03,
      Paint()..color = Colors.black.withValues(alpha: 0.60),
    );
    canvas.drawCircle(c, radius, Paint()..color = AppTheme.cockpitBezel);
    canvas.drawCircle(
      c,
      radius * 0.93,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, size.shortestSide * 0.025)
        ..color = AppTheme.cockpitBezelDark,
    );
    canvas.drawCircle(c, radius * 0.88, Paint()..color = AppTheme.cockpitFace);
    canvas.drawCircle(
      c,
      radius * 0.86,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _line(0.22),
    );

    final inset = size.shortestSide * 0.065;
    for (final screw in [
      Offset(inset, inset),
      Offset(size.width - inset, inset),
      Offset(inset, size.height - inset),
      Offset(size.width - inset, size.height - inset),
    ]) {
      final sr = math.max(2.2, size.shortestSide * 0.025);
      canvas.drawCircle(screw, sr, Paint()..color = AppTheme.cockpitScrew);
      canvas.drawCircle(
        screw,
        sr * 0.72,
        Paint()..color = AppTheme.cockpitScrewMetal,
      );
      canvas.drawLine(
        screw + Offset(-sr * 0.45, -sr * 0.45),
        screw + Offset(sr * 0.45, sr * 0.45),
        Paint()
          ..color = AppTheme.cockpitScrewSlot
          ..strokeWidth = math.max(1, sr * 0.25),
      );
    }

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

  void _authenticGlass(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.40;
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
      canvas.drawCircle(c, s * 0.052, Paint()..color = AppTheme.cockpitHub);
      canvas.drawCircle(
        c,
        s * 0.038,
        Paint()..color = AppTheme.cockpitHubMetal,
      );
      canvas.drawCircle(
        c,
        s * 0.022,
        Paint()..color = AppTheme.cockpitHubInner,
      );
      canvas.drawCircle(
        c,
        s * 0.009,
        Paint()..color = AppTheme.cockpitHubHighlight,
      );
      return;
    }
    canvas.drawCircle(c, s * 0.05, Paint()..color = accent);
    canvas.drawCircle(c, s * 0.026, Paint()..color = surface);
    canvas.drawCircle(c, s * 0.013, Paint()..color = accent);
  }

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
              color: _instrumentInk.withValues(alpha: _power),
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
                color: _instrumentMuted.withValues(alpha: _power),
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
    final effectiveColor = _authentic
        ? (color == accent
              ? accent.withValues(alpha: _power)
              : color.withValues(alpha: color.a * _power))
        : color;
    final painter = TextPainter(
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
}
