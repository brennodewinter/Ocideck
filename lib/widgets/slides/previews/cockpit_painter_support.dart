part of '../slide_preview.dart';

/// Materiaal- en tekendetails van de cockpitmeter.
///
/// Deze helpers blijven onderdeel van dezelfde painter, maar staan los van de
/// metertype-geometrie zodat `cockpit_preview.dart` onder de bestandsgrens
/// blijft en de klassieke schildercode overzichtelijk blijft.
extension _CockpitInstrumentPainterSupport on _CockpitInstrumentPainter {
  bool get _authentic => visualStyle == CockpitVisualStyle.authentic;

  double get _power => !_authentic
      ? 1
      : Curves.easeOut.transform(((progress - 0.03) / 0.30).clamp(0.0, 1.0));

  /// Instrumentpalet voor de authentieke stand, gekozen op de helderheid van
  /// de dia-achtergrond zodat een lichte dia een licht instrument krijgt.
  CockpitPalette get _palette => AppTheme.cockpitPaletteFor(surface);

  Color get _instrumentInk => _authentic ? _palette.ink : textColor;

  Color get _instrumentMuted =>
      _authentic ? _palette.inkMuted.withValues(alpha: 0.72) : mutedColor;

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

  void _authenticFrame(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * kCockpitAuthenticBezelFactor;
    canvas.drawCircle(
      c + Offset(0, size.shortestSide * 0.025),
      radius * 1.03,
      Paint()..color = Colors.black.withValues(alpha: 0.60),
    );
    canvas.drawCircle(c, radius, Paint()..color = _palette.bezel);
    canvas.drawCircle(
      c,
      radius * 0.93,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, size.shortestSide * 0.025)
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

    final inset = size.shortestSide * 0.065;
    for (final screw in [
      Offset(inset, inset),
      Offset(size.width - inset, inset),
      Offset(inset, size.height - inset),
      Offset(size.width - inset, size.height - inset),
    ]) {
      final sr = math.max(2.2, size.shortestSide * 0.025);
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

  /// Tekent het authentieke kompas-uitleesvenster: een vlak in de face-kleur dat
  /// de roos-streepjes eronder afdekt, zodat de ACT/TGT/marker-regels leesbaar
  /// binnen de plaat staan i.p.v. over de streepjes en de bezel te lopen. Alleen
  /// authentiek; de klassieke stand heeft een vrije rechterkolom (#1110).
  void _drawReadoutWindow(Canvas canvas, Size size, Rect window) {
    final rr = RRect.fromRectAndRadius(
      window,
      Radius.circular(size.shortestSide * 0.03),
    );
    canvas
      ..drawRRect(rr, Paint()..color = _palette.face)
      ..drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, size.shortestSide * 0.006)
          ..color = _line(0.30),
      );
  }
}

/// Buitenstraal van de authentieke bezel (fractie van de kortste zijde), zoals
/// [_CockpitInstrumentPainterSupport._authenticFrame] hem tekent.
const double kCockpitAuthenticBezelFactor = 0.465;

/// Straal van de authentieke wijzerplaat (de crème/donkere face): de bezel maal
/// 0,88, gelijk aan de `radius * 0.88` in `_authenticFrame`. Het uitleesvenster
/// moet binnen deze cirkel blijven.
const double kCockpitAuthenticFaceFactor = kCockpitAuthenticBezelFactor * 0.88;

/// Middelpunt en straal van de kompas-wijzerplaat binnen een instrument van
/// [size]. De authentieke roos valt samen met het bezel-middelpunt (celmidden);
/// de klassieke variant zit iets links zodat de rechterkolom vrij komt.
@visibleForTesting
({Offset center, double radius}) cockpitHeadingDial(
  Size size, {
  required bool authentic,
}) {
  return (
    center: Offset(size.width * (authentic ? 0.50 : 0.42), size.height * 0.50),
    radius: math.min(size.width, size.height) * (authentic ? 0.34 : 0.35),
  );
}

/// Plaatsing én begrenzing van de drie kompas-uitleesregels (ACT/TGT/marker),
/// zodat ze niet buiten het instrument vallen (#1110).
///
/// De twee visuele stijlen hebben een andere vorm en dus een andere plek:
/// * **klassiek** — het instrument vult een rechthoekige kaart; de regels vormen
///   een rechterkolom naast de roos, rechts uitgelijnd ([anchorRight] = true).
/// * **authentiek** — een ronde bezel vult de cel, dus er ís geen vrije kolom
///   ernaast (een rechterkolom zou over de bezel en het buurinstrument lopen).
///   De regels zitten daarom in een uitleesvenster ([window]) laag op de plaat,
///   gecentreerd — zoals de andere authentieke instrumenten hun waarde binnen de
///   wijzerplaat tonen.
///
/// In beide gevallen begrenst [maxWidth] de regelbreedte, zodat een lange
/// (gelokaliseerde) markerregel met een ellipsis binnen de plaat blijft.
@immutable
class CockpitHeadingReadouts {
  const CockpitHeadingReadouts({
    required this.anchorRight,
    required this.align,
    required this.maxWidth,
    required this.actualCenter,
    required this.targetCenter,
    required this.markerCenter,
    required this.actualFont,
    required this.targetFont,
    required this.markerFont,
    this.window,
  });

  /// True: regels rechts uitgelijnd op hun anker (klassieke rechterkolom).
  /// False: regels gecentreerd op hun anker (authentiek venster).
  final bool anchorRight;

  /// Tekstuitlijning per regel (rechts in de klassieke kolom, gecentreerd in
  /// het authentieke venster). Het bijpassende `_Anchor` leidt de tekenkant zelf
  /// af uit [anchorRight]; dat is een privé-type en hoort niet in deze API.
  final TextAlign align;

  /// Breedtegrens per regel; langere tekst krijgt een ellipsis.
  final double maxWidth;

  /// Ankerpunten van de drie regels — de rechterrand bij [anchorRight], anders
  /// het midden; verticaal gecentreerd.
  final Offset actualCenter;
  final Offset targetCenter;
  final Offset markerCenter;

  /// Lettergroottes van de drie regels, afgestemd op stijl en instrumentmaat
  /// (klassiek breedte-, authentiek kortste-zijde-gebaseerd).
  final double actualFont;
  final double targetFont;
  final double markerFont;

  /// Alleen authentiek: het uitleesvenster dat de roos-streepjes eronder afdekt.
  /// Null in de klassieke stand.
  final Rect? window;
}

/// Berekent de plaatsing van de kompas-uitleesregels uit de instrument-[size] en
/// de roos-geometrie ([center]/[radius]).
///
/// Puur en zonder neveneffect, zodat een test kan bewijzen dat de regels binnen
/// het instrument blijven — de begrenzing die issue #1110 vroeg. Authentiek: het
/// venster valt binnen de face-cirkel (straal [kCockpitAuthenticFaceFactor]·
/// kortste-zijde rond het celmidden). Klassiek: de kolom valt naast de roos en
/// binnen de rand; de marge [_headingReadoutGap] vangt ook de markerpunt op die
/// tot r·1,02 buiten de cirkel steekt.
@visibleForTesting
CockpitHeadingReadouts cockpitHeadingReadouts(
  Size size,
  Offset center,
  double radius, {
  required bool authentic,
}) {
  if (authentic) {
    final faceCenter = Offset(size.width / 2, size.height / 2);
    final faceR = size.shortestSide * kCockpitAuthenticFaceFactor;
    final winW = faceR * 1.20;
    final winH = faceR * 0.64;
    // Onder de naaf (het celmidden), zodat het venster de hub/naald-basis vrij
    // laat en met marge binnen de face-cirkel valt.
    final winCenter = Offset(faceCenter.dx, faceCenter.dy + faceR * 0.40);
    final window = Rect.fromCenter(
      center: winCenter,
      width: winW,
      height: winH,
    );
    return CockpitHeadingReadouts(
      anchorRight: false,
      align: TextAlign.center,
      maxWidth: winW - faceR * 0.14,
      actualCenter: Offset(winCenter.dx, window.top + winH * 0.26),
      targetCenter: Offset(winCenter.dx, winCenter.dy),
      markerCenter: Offset(winCenter.dx, window.bottom - winH * 0.24),
      actualFont: size.shortestSide * 0.058,
      targetFont: size.shortestSide * 0.045,
      markerFont: size.shortestSide * 0.047,
      window: window,
    );
  }
  // Net binnen de rand van de rechthoekige kaart zodat de tekst niet op de rand
  // valt.
  final rightEdge = size.width * 0.965;
  final freeLeft = center.dx + radius + size.width * _headingReadoutGap;
  return CockpitHeadingReadouts(
    anchorRight: true,
    align: TextAlign.right,
    maxWidth: rightEdge - freeLeft,
    actualCenter: Offset(rightEdge, size.height * 0.43),
    targetCenter: Offset(rightEdge, size.height * 0.59),
    markerCenter: Offset(rightEdge, size.height * 0.72),
    actualFont: size.width * 0.05,
    targetFont: size.width * 0.038,
    markerFont: size.width * 0.032,
  );
}

/// Tussenruimte (fractie van de breedte) tussen de roos en de klassieke
/// uitleeskolom. Groter dan de r·0,02 waarmee de markerpunt buiten de cirkel
/// steekt.
const double _headingReadoutGap = 0.02;
