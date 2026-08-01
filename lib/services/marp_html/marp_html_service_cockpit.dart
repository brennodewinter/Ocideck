// Part of the marp_html_service library — see ../marp_html_service.dart.
// Split out for navigability (cockpit instrument SVG rendering); all imports live in the main
// library file. These were private `static` MarpHtmlService helpers; as
// top-level private functions they share the library and are called by
// bare name from the service's public render methods.
part of '../marp_html_service.dart';

/// Instrument- en structuurkleuren voor de cockpit-SVG-export, als één set die
/// op de helderheid van de dia-achtergrond schakelt — zodat de export het
/// dia-thema volgt, net als de app-render (`AppTheme.cockpitPaletteFor`). Alles
/// is hex, want dit is een string-genererende service zonder `Color`.
typedef _CockpitSvgPalette = ({
  String card,
  String cardStroke,
  String bezel,
  String bezelStroke,
  String face,
  String faceStroke,
  String screwHole,
  String screwMetal,
  String track,
  String dialFill,
  String dialStroke,
  String tick,
  String ink,
  String inkMuted,
  String label,
  String needle,
  String accent,
  String glass,
  String tubeFill,
  String bulbFill,
});

/// Relatieve luminantie van een `#rrggbb`, zelfde formule als
/// `Color.computeLuminance`, zodat de export dezelfde licht/donker-grens hanteert
/// als de app.
double _cockpitHexLuminance(String hex) {
  final h = hex.replaceAll('#', '').trim();
  if (h.length < 6) return 0;
  double lin(int c) {
    final s = c / 255.0;
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = int.tryParse(h.substring(0, 2), radix: 16) ?? 0;
  final g = int.tryParse(h.substring(2, 4), radix: 16) ?? 0;
  final b = int.tryParse(h.substring(4, 6), radix: 16) ?? 0;
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}

/// Een lichte dia krijgt het lichte instrument, een donkere (of geen thema) het
/// zwarte — dezelfde grens als de app-render.
bool _cockpitLightBg(ThemeProfile? theme) =>
    theme != null && _cockpitHexLuminance(theme.slideBackgroundColor) > 0.5;

/// Bouwt het instrumentpalet voor de export: authentiek/klassiek × licht/donker.
/// De donkere waarden zijn de bestaande; de lichte spiegelen de app
/// (crème wijzerplaat, donkere markeringen, zilveren bezel).
_CockpitSvgPalette _cockpitSvgPalette(
  bool light,
  bool authentic,
  String accent,
) {
  return (
    card: authentic
        ? (light ? '#CED2D6' : '#202223')
        : (light ? '#E7EAEE' : '#111827'),
    cardStroke: authentic
        ? (light ? '#AAB0B5' : '#45484A')
        : (light ? '#CBD2DA' : '#334155'),
    bezel: light ? '#B9BDC1' : '#343739',
    bezelStroke: light ? '#888D91' : '#08090A',
    face: light ? '#EDE8DA' : '#101314',
    faceStroke: light ? '#B0AEA4' : '#6A6D6E',
    screwHole: light ? '#888D91' : '#090A0B',
    screwMetal: light ? '#C0C4C7' : '#66696A',
    track: light ? '#C4CBD3' : '#1E293B',
    dialFill: light ? '#EDE8DA' : '#0B1120',
    dialStroke: light ? '#9AA1AA' : '#475569',
    tick: light ? '#5B6570' : '#CBD5E1',
    ink: light ? '#1F2937' : '#F8FAFC',
    inkMuted: light ? '#5B6570' : '#94A3B8',
    label: authentic
        ? (light ? '#40454B' : '#D9D1BD')
        : (light ? '#475569' : '#94A3B8'),
    needle: authentic ? (light ? '#23262B' : '#E8E0CA') : accent,
    accent: accent,
    glass: light ? '#9AA1AA' : '#CBD5E1',
    tubeFill: light ? '#C4CBD3' : '#1E293B',
    bulbFill: light ? '#D8D4C8' : '#0B1120',
  );
}

String _cockpitSvg(
  CockpitSpec spec,
  ThemeProfile? theme,
  CockpitColorScheme scheme,
) {
  final meters =
      (spec.meters.isEmpty ? CockpitSpec.samplePreset().meters : spec.meters)
          .take(cockpitMaxMeters)
          .toList();
  final accent = theme?.accentColor ?? '#38BDF8';
  final light = _cockpitLightBg(theme);
  final cols = meters.length <= 1
      ? 1
      : meters.length <= 4
      ? 2
      : 3;
  final rows = (meters.length / cols).ceil().clamp(1, 2);
  final cellW = 800.0 / cols;
  final cellH = 360.0 / rows;
  final b = StringBuffer()
    ..write(
      '<svg viewBox="0 0 900 500" xmlns="http://www.w3.org/2000/svg" '
      'font-family="inherit" width="100%" class="cockpit-svg '
      '${scheme.visualStyle.name}">',
    )
    ..write(
      '<rect width="900" height="500" rx="26" '
      'fill="${light ? '#E9EBEE' : '#07111F'}"/>',
    )
    ..write(
      '<rect x="22" y="22" width="856" height="456" rx="22" '
      'fill="${light ? '#DDE1E6' : '#0F172A'}" stroke="$accent" '
      'stroke-opacity=".35" stroke-width="2"/>',
    );
  for (var i = 0; i < meters.length; i++) {
    final row = i ~/ cols;
    final col = i % cols;
    final x = 50 + col * cellW;
    final y = 82 + row * cellH;
    b.write('<g class="cockpit-meter" style="--meter-index:$i">');
    _cockpitInstrumentSvg(
      b,
      meters[i],
      i,
      x,
      y,
      cellW - 20,
      cellH - 20,
      accent,
      scheme,
      light,
    );
    b.write('</g>');
  }
  b.write('</svg>');
  return b.toString();
}

void _cockpitInstrumentSvg(
  StringBuffer b,
  CockpitMeterSpec meter,
  int index,
  double x,
  double y,
  double w,
  double h,
  String accent,
  CockpitColorScheme scheme,
  bool light,
) {
  final colors = scheme;
  final cardH = math.max(80.0, h - 24);
  final authentic = scheme.visualStyle == CockpitVisualStyle.authentic;
  final p = _cockpitSvgPalette(light, authentic, accent);
  final gaugeCx = x + w * .43;
  final gaugeCy = y + cardH * .50;
  final gaugeR = math.min(w, cardH) * .36;
  b
    ..write(
      '<rect x="$x" y="$y" width="$w" height="$cardH" rx="18" '
      'fill="${p.card}" stroke="${p.cardStroke}" stroke-width="1.5"/>',
    )
    ..write(
      authentic
          ? '<circle cx="$gaugeCx" cy="$gaugeCy" r="${gaugeR + 8}" '
                'fill="${p.bezel}" stroke="${p.bezelStroke}" stroke-width="9"/>'
                '<circle cx="$gaugeCx" cy="$gaugeCy" r="$gaugeR" '
                'fill="${p.face}" stroke="${p.faceStroke}" stroke-opacity=".35"/>'
          : '',
    )
    ..write(authentic ? _instrumentScrews(x, y, w, cardH, p) : '')
    ..write(
      '<text x="${x + w / 2}" y="${y + h - 6}" text-anchor="middle" '
      'font-size="13" font-weight="700" fill="${p.label}">'
      '${_esc(meter.label.isEmpty ? 'Meter ${index + 1}' : meter.label)}</text>',
    );
  switch (meter.type) {
    case CockpitMeterType.thermometer:
      _thermometerSvg(b, meter, x, y, w, cardH, colors, p);
      break;
    case CockpitMeterType.climbDescent:
      _climbDescentSvg(b, meter, x, y, w, cardH, p);
      break;
    case CockpitMeterType.horizon:
      _horizonSvg(b, meter, index, x, y, w, cardH, colors, p);
      break;
    case CockpitMeterType.heading:
      _headingSvg(b, meter, x, y, w, cardH, colors, p);
      break;
    case CockpitMeterType.speedometer:
    case CockpitMeterType.voltmeter:
    case CockpitMeterType.altimeter:
      _arcGaugeSvg(b, meter, x, y, w, cardH, colors, p);
      break;
  }
}

String _instrumentScrews(
  double x,
  double y,
  double w,
  double h,
  _CockpitSvgPalette p,
) {
  final inset = math.min(w, h) * .065;
  final points = [
    (x + inset, y + inset),
    (x + w - inset, y + inset),
    (x + inset, y + h - inset),
    (x + w - inset, y + h - inset),
  ];
  return points
      .map(
        (point) =>
            '<circle cx="${point.$1}" cy="${point.$2}" r="4.5" '
            'fill="${p.screwHole}"/><circle cx="${point.$1}" cy="${point.$2}" '
            'r="2.6" fill="${p.screwMetal}"/>',
      )
      .join();
}

void _arcGaugeSvg(
  StringBuffer b,
  CockpitMeterSpec meter,
  double x,
  double y,
  double w,
  double h,
  CockpitColorScheme scheme,
  _CockpitSvgPalette p,
) {
  final cx = x + w * .43;
  final cy = y + h * 0.52;
  final r = math.min(w * 0.34, h * 0.36);
  double angleFor(double value) {
    final span = meter.max - meter.min == 0 ? 1.0 : meter.max - meter.min;
    final n = ((value - meter.min) / span).clamp(0.0, 1.0);
    return -210 + 240 * n;
  }

  void arc(double from, double to, String color) {
    final a0 = angleFor(from);
    final a1 = angleFor(to);
    if ((a1 - a0).abs() < .5) return;
    b.write(
      '<path d="${_arcPath(cx, cy, r, a0, a1)}" fill="none" '
      'stroke="$color" stroke-width="10" stroke-linecap="round"/>',
    );
  }

  b.write(
    '<path d="${_arcPath(cx, cy, r, -210, 30)}" fill="none" '
    'stroke="${p.track}" stroke-width="12" stroke-linecap="round"/>',
  );
  if (meter.redFrom < meter.greenFrom) {
    arc(meter.min, meter.redFrom, scheme.critical);
    arc(meter.redFrom, meter.greenFrom, scheme.warning);
    arc(meter.greenFrom, meter.greenTo, scheme.good);
    arc(meter.greenTo, meter.max, scheme.warning);
  } else {
    arc(meter.min, meter.greenFrom, scheme.warning);
    arc(meter.greenFrom, meter.greenTo, scheme.good);
    arc(meter.greenTo, meter.redFrom, scheme.warning);
    arc(meter.redFrom, meter.max, scheme.critical);
  }

  final needle = angleFor(meter.value) * math.pi / 180;
  final nx = cx + math.cos(needle) * r * .82;
  final ny = cy + math.sin(needle) * r * .82;
  b
    ..write(
      '<line x1="$cx" y1="$cy" x2="$nx" y2="$ny" stroke="${p.needle}" '
      'stroke-width="4" stroke-linecap="round"/>',
    )
    ..write('<circle cx="$cx" cy="$cy" r="8" fill="${p.needle}"/>')
    ..write(
      '<text x="${x + w * .78}" y="${y + h * .56}" text-anchor="middle" '
      'font-size="18" font-weight="800" fill="${p.ink}">'
      '${_esc(_num(meter.value))}${_esc(meter.unit)}</text>',
    )
    // Min/max radiaal net buiten de boogtippen, zodat de getallen niet door de
    // schaal lopen.
    ..write(
      '<text x="${cx - (r + 16) * 0.87}" y="${cy + (r + 16) * 0.5 + 4}" '
      'text-anchor="middle" font-size="11" fill="${p.inkMuted}">'
      '${_esc(_num(meter.min))}</text>',
    )
    ..write(
      '<text x="${cx + (r + 16) * 0.87}" y="${cy + (r + 16) * 0.5 + 4}" '
      'text-anchor="middle" font-size="11" fill="${p.inkMuted}">'
      '${_esc(_num(meter.max))}</text>',
    );
}

void _thermometerSvg(
  StringBuffer b,
  CockpitMeterSpec meter,
  double x,
  double y,
  double w,
  double h,
  CockpitColorScheme scheme,
  _CockpitSvgPalette p,
) {
  // Centreer de buis op het bezel-middelpunt en houd buis + bulb binnen de
  // bezelradius, zodat de thermometer niet door de onderrand van de cirkel zakt.
  final cx = x + w * .43;
  final cy = y + h * .50;
  final rr = math.min(w, h) * .36;
  const tubeWidth = 12.0;
  final tubeX = cx - tubeWidth / 2;
  final top = cy - rr * .64;
  final bottom = cy + rr * .22;
  final bulbR = rr * .20;
  final bulbCy = bottom + bulbR * .7;
  final span = meter.max - meter.min == 0 ? 1.0 : meter.max - meter.min;
  final n = ((meter.value - meter.min) / span).clamp(0.0, 1.0);
  final fillTop = bottom - (bottom - top) * n;
  final greenStart = math.min(meter.greenFrom, meter.greenTo);
  final color = meter.value >= meter.redFrom
      ? scheme.critical
      : meter.value >= meter.greenTo
      ? scheme.warning
      : meter.value < greenStart
      ? scheme.cold
      : scheme.good;
  b
    ..write(
      '<rect x="${tubeX - 9}" y="${top - 7}" width="${tubeWidth + 18}" '
      'height="${bulbCy + bulbR - top + 14}" rx="14" fill="${p.glass}" '
      'fill-opacity=".10"/>',
    )
    ..write(
      '<rect x="$tubeX" y="$top" width="$tubeWidth" height="${bottom - top}" '
      'rx="8" fill="${p.tubeFill}" stroke="${p.glass}" stroke-opacity=".48" stroke-width="3"/>',
    )
    ..write(
      '<rect x="${tubeX + 3}" y="$fillTop" width="6" '
      'height="${bottom - fillTop + bulbR * .5}" rx="3" fill="$color"/>',
    )
    ..write(
      '<circle cx="$cx" cy="$bulbCy" r="$bulbR" fill="${p.bulbFill}" '
      'stroke="${p.glass}" stroke-opacity=".48" stroke-width="3"/>',
    )
    ..write('<circle cx="$cx" cy="$bulbCy" r="${bulbR * .56}" fill="$color"/>');
  b.write(
    '<text x="${x + w * .80}" y="${cy + 6}" text-anchor="middle" '
    'font-size="18" font-weight="800" fill="${p.ink}">'
    '${_esc(_num(meter.value))}${_esc(meter.unit)}</text>',
  );
}

void _climbDescentSvg(
  StringBuffer b,
  CockpitMeterSpec meter,
  double x,
  double y,
  double w,
  double h,
  _CockpitSvgPalette p,
) {
  // Centreer op het bezel-middelpunt (x+0.43w, y+0.5h) zodat de wijzerplaat
  // recht in de cirkel staat.
  final cx = x + w * .43;
  final cy = y + h * .50;
  final r = math.min(w, h) * .31;
  final span = meter.max - meter.min == 0 ? 1.0 : meter.max - meter.min;
  final n = ((meter.value - meter.min) / span).clamp(0.0, 1.0);
  final angle = (90 - 180 * n) * math.pi / 180;
  final nx = cx + math.cos(angle) * r * .78;
  final ny = cy + math.sin(angle) * r * .78;
  b.write(
    '<circle cx="$cx" cy="$cy" r="$r" fill="${p.dialFill}" '
    'stroke="${p.dialStroke}" stroke-width="4"/>',
  );
  for (var i = 0; i <= 10; i++) {
    final a = (90 - 180 * i / 10) * math.pi / 180;
    final long = i % 5 == 0;
    b.write(
      '<line x1="${cx + math.cos(a) * r * (long ? .72 : .82)}" '
      'y1="${cy + math.sin(a) * r * (long ? .72 : .82)}" '
      'x2="${cx + math.cos(a) * r * .95}" '
      'y2="${cy + math.sin(a) * r * .95}" '
      'stroke="${p.tick}" stroke-opacity="${long ? .70 : .36}" '
      'stroke-width="${long ? 2 : 1}"/>',
    );
  }
  b
    ..write(
      '<text x="$cx" y="${cy - r * .48}" text-anchor="middle" '
      'font-size="16" font-weight="900" fill="${p.inkMuted}">+</text>',
    )
    ..write(
      '<text x="${cx + r * .62}" y="${cy + 5}" text-anchor="middle" '
      'font-size="13" font-weight="700" fill="${p.inkMuted}">0</text>',
    )
    ..write(
      '<text x="$cx" y="${cy + r * .68}" text-anchor="middle" '
      'font-size="18" font-weight="900" fill="${p.inkMuted}">-</text>',
    )
    ..write(
      '<line x1="$cx" y1="$cy" x2="$nx" y2="$ny" stroke="${p.needle}" '
      'stroke-width="4" stroke-linecap="round"/>',
    )
    ..write('<circle cx="$cx" cy="$cy" r="8" fill="${p.needle}"/>')
    ..write(
      '<text x="${x + w * .78}" y="${y + h * .56}" text-anchor="middle" '
      'font-size="18" font-weight="800" fill="${p.ink}">'
      '${meter.value > 0 ? '+' : ''}${_esc(_num(meter.value))}${_esc(meter.unit)}</text>',
    );
}

void _horizonSvg(
  StringBuffer b,
  CockpitMeterSpec meter,
  int index,
  double x,
  double y,
  double w,
  double h,
  CockpitColorScheme colors,
  _CockpitSvgPalette p,
) {
  // Centreer op het bezel-middelpunt zodat de wijzerplaat recht in de cirkel valt.
  final cx = x + w * .43;
  final cy = y + h * .50;
  final r = math.min(w, h) * .31;
  final clip = 'cockpit-horizon-$index';
  final pitchOffset = meter.pitch.clamp(-45, 45) * r / 45;
  final bank = meter.bank.clamp(-60, 60);
  b
    ..write(
      '<defs><clipPath id="$clip"><circle cx="$cx" cy="$cy" r="$r"/></clipPath></defs>',
    )
    ..write(
      '<g clip-path="url(#$clip)" transform="rotate($bank $cx $cy)">'
      '<rect x="${cx - r * 1.8}" y="${cy - r * 1.8 + pitchOffset}" '
      'width="${r * 3.6}" height="${r * 1.8}" fill="${colors.sky}"/>'
      '<rect x="${cx - r * 1.8}" y="${cy + pitchOffset}" '
      'width="${r * 3.6}" height="${r * 1.8}" fill="${colors.ground}"/>'
      '<line x1="${cx - r * 1.8}" y1="${cy + pitchOffset}" '
      'x2="${cx + r * 1.8}" y2="${cy + pitchOffset}" '
      'stroke="#F8FAFC" stroke-width="3"/></g>',
    )
    ..write(
      '<circle cx="$cx" cy="$cy" r="$r" fill="none" stroke="${p.glass}" stroke-width="4"/>',
    )
    ..write(
      '<path d="M${cx - 52},$cy h36 M${cx + 16},$cy h36 M$cx,${cy - 7} v14" '
      'stroke="#FACC15" stroke-width="5" stroke-linecap="round"/>',
    )
    // Pitch/bank binnen de wijzerplaat (onder, over de grond) zodat de tekst
    // niet door de kaartbodem zakt. Wit want het staat op de gekleurde grond.
    ..write(
      '<text x="$cx" y="${cy + r * 0.66}" text-anchor="middle" '
      'font-size="13" font-weight="800" fill="#F8FAFC">'
      'P ${_esc(_num(meter.pitch))} / B ${_esc(_num(meter.bank))}</text>',
    );
}

void _headingSvg(
  StringBuffer b,
  CockpitMeterSpec meter,
  double x,
  double y,
  double w,
  double h,
  CockpitColorScheme scheme,
  _CockpitSvgPalette p,
) {
  // Centreer de kompasroos op het bezel-middelpunt zodat hij recht in de cirkel
  // valt en niet rechts uitsteekt.
  final cx = x + w * .43;
  final cy = y + h * .50;
  final r = math.min(w, h) * .31;
  b.write(
    '<circle cx="$cx" cy="$cy" r="$r" fill="${p.dialFill}" '
    'stroke="${p.dialStroke}" stroke-width="4"/>',
  );
  const labels = ['N', 'E', 'S', 'W'];
  for (var i = 0; i < labels.length; i++) {
    final a = (-90 + i * 90) * math.pi / 180;
    b.write(
      '<text x="${cx + math.cos(a) * r * .72}" '
      'y="${cy + math.sin(a) * r * .72 + 6}" text-anchor="middle" '
      'font-size="17" font-weight="900" fill="${p.inkMuted}">${labels[i]}</text>',
    );
  }
  final target = (meter.heading - 90) * math.pi / 180;
  final markerTipX = cx + math.cos(target) * r * 1.02;
  final markerTipY = cy + math.sin(target) * r * 1.02;
  final markerLeftX = cx + math.cos(target + .12) * r * .83;
  final markerLeftY = cy + math.sin(target + .12) * r * .83;
  final markerRightX = cx + math.cos(target - .12) * r * .83;
  final markerRightY = cy + math.sin(target - .12) * r * .83;
  final actual = (meter.value - 90) * math.pi / 180;
  final tipX = cx + math.cos(actual) * r * .78;
  final tipY = cy + math.sin(actual) * r * .78;
  b
    ..write(
      '<path d="M$markerTipX,$markerTipY L$markerLeftX,$markerLeftY '
      'L$markerRightX,$markerRightY Z" fill="${p.accent}" fill-opacity=".95"/>',
    )
    ..write(
      '<path d="M$cx,${cy - 10} L$tipX,$tipY L$cx,${cy + 10} Z" '
      'fill="${p.needle}"/>',
    )
    ..write('<circle cx="$cx" cy="$cy" r="7" fill="${p.ink}"/>')
    ..write(
      '<text x="${x + w * .78}" y="${y + h * .46}" text-anchor="middle" '
      'font-size="15" font-weight="800" fill="${p.ink}">'
      'ACT ${_esc(_headingNum(meter.value))}°</text>',
    )
    ..write(
      '<text x="${x + w * .78}" y="${y + h * .61}" text-anchor="middle" '
      'font-size="12" font-weight="700" fill="${p.inkMuted}">'
      'TGT ${_esc(_headingNum(meter.heading))}°</text>',
    );
  if (meter.markerLabel.isNotEmpty) {
    b.write(
      '<text x="${x + w * .78}" y="${y + h * .73}" text-anchor="middle" '
      'font-size="11" font-weight="600" fill="${p.inkMuted}">'
      '${_esc(meter.markerLabel)}</text>',
    );
  }
}

String _headingNum(double value) => _num(value).padLeft(3, '0');

String _arcPath(
  double cx,
  double cy,
  double r,
  double startDeg,
  double endDeg,
) {
  final start = startDeg * math.pi / 180;
  final end = endDeg * math.pi / 180;
  final x0 = cx + r * math.cos(start);
  final y0 = cy + r * math.sin(start);
  final x1 = cx + r * math.cos(end);
  final y1 = cy + r * math.sin(end);
  final large = (endDeg - startDeg).abs() > 180 ? 1 : 0;
  return 'M$x0,$y0 A$r,$r 0 $large,1 $x1,$y1';
}
