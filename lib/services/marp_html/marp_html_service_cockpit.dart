// Part of the marp_html_service library — see ../marp_html_service.dart.
// Split out for navigability (cockpit instrument SVG rendering); all imports live in the main
// library file. These were private `static` MarpHtmlService helpers; as
// top-level private functions they share the library and are called by
// bare name from the service's public render methods.

// De SVG tekent dezelfde indeling als de app: raster, wijzerplaat,
// uitleesvenster en label komen uit `CockpitGridPlan`/`CockpitCellPlan`
// (services/cockpit_layout.dart), en de regelval van label en eenheid uit
// dezelfde tekencascade. De export kan geen tekst meten; daarom rekent de
// rekenkern op tekenaantal, en staat elke tekstzone als laatste vangnet in
// een clip van haar eigen rechthoek.
part of '../marp_html_service.dart';

/// Instrument- en structuurkleuren voor de cockpit-SVG-export, als één set die
/// op de helderheid van de dia-achtergrond schakelt — zodat de export het
/// dia-thema volgt, net als de app-render (`AppTheme.cockpitPaletteFor`). Alles
/// is hex, want dit is een string-genererende service zonder `Color`.
typedef _CockpitSvgPalette = ({
  String panel,
  String panelStroke,
  String bezel,
  String bezelStroke,
  String face,
  String faceStroke,
  String screwHole,
  String screwMetal,
  String ink,
  String inkMuted,
  String label,
  String needle,
  String accent,
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
/// De waarden spiegelen `AppTheme.cockpitLight`/`cockpitDark`; klassiek tekent
/// in de themakleuren.
_CockpitSvgPalette _cockpitSvgPalette(
  bool light,
  bool authentic,
  String accent,
  String textColor,
  String background,
) {
  if (!authentic) {
    return (
      panel: background,
      panelStroke: accent,
      bezel: background,
      bezelStroke: accent,
      face: background,
      faceStroke: textColor,
      screwHole: textColor,
      screwMetal: textColor,
      ink: textColor,
      inkMuted: textColor,
      label: textColor,
      needle: accent,
      accent: accent,
    );
  }
  return (
    panel: light ? '#CED2D6' : '#202223',
    panelStroke: light ? '#AAB0B5' : '#3A3D3F',
    bezel: light ? '#B9BDC1' : '#343739',
    bezelStroke: light ? '#888D91' : '#08090A',
    face: light ? '#EDE8DA' : '#101314',
    faceStroke: light ? '#23262B' : '#E8E0CA',
    screwHole: light ? '#888D91' : '#090A0B',
    screwMetal: light ? '#C0C4C7' : '#5A5D5E',
    ink: light ? '#23262B' : '#E8E0CA',
    inkMuted: light ? '#585D64' : '#C8BEA5',
    label: light ? '#40454B' : '#D9D1BD',
    needle: light ? '#23262B' : '#E8E0CA',
    accent: accent,
  );
}

/// Het paneel in de export heeft de verhouding van het paneel in de app op een
/// 16:9-dia met titel en logostrook (≈ 2,5 : 1), zodat de rekenkern in beide
/// werelden dezelfde breed/gestapeld-keuze maakt.
const double _cockpitSvgWidth = 1600;
const double _cockpitSvgHeight = 640;

/// Deterministische, platformonafhankelijke hash (FNV-1a, 32 bit) van de
/// cockpit-JSON. Een geëxporteerd document draagt meerdere cockpit-dia's in
/// één id-namespace; met `#cockpit-horizon-0` in twee SVG's wint de eerste en
/// verdwijnen in de tweede de geclipte vensterteksten. Een suffix per SVG
/// houdt de ids uniek en de uitvoer reproduceerbaar.
String _cockpitSvgSuffix(String block) {
  var hash = 0x811C9DC5;
  for (final unit in block.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16);
}

String _cockpitSvg(
  CockpitSpec spec,
  ThemeProfile? theme,
  CockpitColorScheme scheme,
) {
  final suffix = _cockpitSvgSuffix(spec.toBlock());
  final meters =
      (spec.meters.isEmpty ? CockpitSpec.samplePreset().meters : spec.meters)
          .take(cockpitMaxMeters)
          .toList();
  final accent = theme?.accentColor ?? '#38BDF8';
  final textColor = theme?.textColor ?? '#F8FAFC';
  final background = theme?.slideBackgroundColor ?? '#07111F';
  final light = _cockpitLightBg(theme);
  final authentic = scheme.visualStyle == CockpitVisualStyle.authentic;
  final p = _cockpitSvgPalette(light, authentic, accent, textColor, background);
  // Authentiek: paneel met 10 eenheden binnenrand, zoals de app; klassiek:
  // geen paneel, de kaarten staan los op de dia.
  final inset = authentic ? 10.0 : 0.0;
  final grid = CockpitGridPlan.compute(
    count: meters.length,
    width: _cockpitSvgWidth - 2 * inset,
    height: _cockpitSvgHeight - 2 * inset,
  );
  final plan = CockpitCellPlan.compute(
    width: grid.cellWidth,
    height: grid.cellHeight,
    longestDigits: cockpitLongestDigits(meters),
  );
  final readoutScale = cockpitReadoutScale(
    meters,
    plan,
    attitudeTemplate: _cockpitAttitudeTemplate,
    actualTemplate: _cockpitActualTemplate,
    targetTemplate: _cockpitTargetTemplate,
  );
  final b = StringBuffer()
    ..write(
      '<svg viewBox="0 0 ${_num(_cockpitSvgWidth)} ${_num(_cockpitSvgHeight)}" '
      'xmlns="http://www.w3.org/2000/svg" font-family="inherit" width="100%" '
      'class="cockpit-svg ${scheme.visualStyle.name}" '
      'style="font-variant-numeric:tabular-nums lining-nums">',
    );
  if (authentic) {
    b.write(
      '<rect x="0" y="0" width="${_num(_cockpitSvgWidth)}" '
      'height="${_num(_cockpitSvgHeight)}" rx="20" fill="${p.panel}" '
      'stroke="${p.panelStroke}" stroke-width="1.5"/>',
    );
  }
  for (var i = 0; i < meters.length; i++) {
    final cell = grid.cells[i];
    // De verplaatsing op een eigen buitenste <g>: de cockpitPowerOn-animatie
    // zet `transform: scale()` als CSS-eigenschap op `.cockpit-meter`, en die
    // overschrijft een transform-attribuut op hetzelfde element — alle meters
    // belandden op elkaar in cel 0.
    b.write(
      '<g transform="translate(${_num(cell.x + inset)} ${_num(cell.y + inset)})">'
      '<g class="cockpit-meter" style="--meter-index:$i">',
    );
    _cockpitInstrumentSvg(
      b,
      meters[i],
      i,
      plan,
      readoutScale,
      scheme,
      p,
      authentic,
      suffix,
    );
    b.write('</g></g>');
  }
  b.write('</svg>');
  return b.toString();
}

/// De Engelse standaardsjablonen van de export; de app geeft de vertaalde mee.
const _cockpitAttitudeTemplate = 'P {pitch}  B {bank}';
const _cockpitActualTemplate = 'ACT {value}°';
const _cockpitTargetTemplate = 'TGT {heading}°';

void _cockpitInstrumentSvg(
  StringBuffer b,
  CockpitMeterSpec meter,
  int index,
  CockpitCellPlan plan,
  double readoutScale,
  CockpitColorScheme scheme,
  _CockpitSvgPalette p,
  bool authentic,
  String suffix,
) {
  final s = plan.dialSide;
  final cx = plan.dialCenterX;
  final cy = plan.dialCenterY;
  final band = plan.instrumentBand;
  if (authentic) {
    b.write(_instrumentScrews(band, p));
    _bezelSvg(b, cx, cy, s, p, scheme);
  } else {
    final r = math.min(band.w, band.h) * 0.07;
    b.write(
      '<rect x="${_num(band.x)}" y="${_num(band.y)}" width="${_num(band.w)}" '
      'height="${_num(band.h)}" rx="${_num(r)}" fill="${p.panel}" '
      'stroke="${p.panelStroke}" stroke-opacity=".64" stroke-width="1.5"/>',
    );
  }
  switch (meter.type) {
    case CockpitMeterType.thermometer:
      _thermometerSvg(b, meter, '$index-$suffix', cx, cy, s, plan, scheme, p);
      break;
    case CockpitMeterType.climbDescent:
      _climbDescentSvg(b, meter, cx, cy, s, plan, p);
      break;
    case CockpitMeterType.horizon:
      _horizonSvg(b, meter, '$index-$suffix', cx, cy, s, scheme, p);
      break;
    case CockpitMeterType.heading:
      _headingSvg(b, meter, cx, cy, s, plan, p);
      break;
    case CockpitMeterType.speedometer:
      _arcGaugeSvg(b, meter, cx, cy, s, plan, scheme, p, 145, 250);
      break;
    case CockpitMeterType.voltmeter:
      _arcGaugeSvg(b, meter, cx, cy, s, plan, scheme, p, 180, 180);
      break;
    case CockpitMeterType.altimeter:
      _arcGaugeSvg(b, meter, cx, cy, s, plan, scheme, p, 120, 300);
      break;
  }
  _readoutSvg(b, meter, '$index-$suffix', plan, readoutScale, p, authentic);
  _labelSvg(b, meter, index, '$index-$suffix', plan, p);
}

String _instrumentScrews(CockpitRect band, _CockpitSvgPalette p) {
  final short = math.min(band.w, band.h);
  final inset = short * 0.065;
  final sr = math.max(2.2, short * 0.025);
  final points = [
    (band.x + inset, band.y + inset),
    (band.right - inset, band.y + inset),
    (band.x + inset, band.bottom - inset),
    (band.right - inset, band.bottom - inset),
  ];
  return points
      .map(
        (point) =>
            '<circle cx="${_num(point.$1)}" cy="${_num(point.$2)}" '
            'r="${_num(sr)}" fill="${p.screwHole}"/>'
            '<circle cx="${_num(point.$1)}" cy="${_num(point.$2)}" '
            'r="${_num(sr * .72)}" fill="${p.screwMetal}"/>',
      )
      .join();
}

void _bezelSvg(
  StringBuffer b,
  double cx,
  double cy,
  double s,
  _CockpitSvgPalette p,
  CockpitColorScheme scheme,
) {
  final r = s * 0.465;
  b
    ..write(
      '<circle cx="${_num(cx)}" cy="${_num(cy + s * .025)}" r="${_num(r * 1.03)}" '
      'fill="#000" fill-opacity=".6"/>',
    )
    ..write(
      '<circle cx="${_num(cx)}" cy="${_num(cy)}" r="${_num(r)}" fill="${p.bezel}"/>',
    )
    ..write(
      '<circle cx="${_num(cx)}" cy="${_num(cy)}" r="${_num(r * .93)}" fill="none" '
      'stroke="${p.bezelStroke}" stroke-width="${_num(math.max(2, s * .025))}"/>',
    )
    ..write(
      '<circle cx="${_num(cx)}" cy="${_num(cy)}" r="${_num(r * .88)}" fill="${p.face}"/>',
    )
    ..write(
      '<circle cx="${_num(cx)}" cy="${_num(cy)}" r="${_num(r * .86)}" fill="none" '
      'stroke="${p.faceStroke}" stroke-opacity=".22" stroke-width="1"/>',
    );
  // Testlampjes, gedimd: de export kent geen opstartsequentie behalve de
  // CSS-fade.
  final lampY = cy - r * 0.66;
  final lamps = [scheme.critical, scheme.warning, scheme.good];
  for (var i = 0; i < lamps.length; i++) {
    final x = cx + (i - 1) * r * 0.19;
    b
      ..write(
        '<circle cx="${_num(x)}" cy="${_num(lampY)}" r="${_num(r * .027)}" fill="#000"/>',
      )
      ..write(
        '<circle cx="${_num(x)}" cy="${_num(lampY)}" r="${_num(r * .019)}" '
        'fill="${lamps[i]}" fill-opacity=".18"/>',
      );
  }
}

/// Schaalcijfer op de wijzerplaat, gedempt; onder zeven eenheden weggelaten.
String _scaleText(
  double x,
  double y,
  String text,
  CockpitCellPlan plan,
  _CockpitSvgPalette p, {
  String anchor = 'middle',
}) {
  if (plan.scaleSize < cockpitMinTextPx) return '';
  return '<text x="${_num(x)}" y="${_num(y)}" text-anchor="$anchor" '
      'dominant-baseline="central" font-size="${_num(plan.scaleSize)}" '
      'font-weight="600" fill="${p.inkMuted}">${_esc(text)}</text>';
}

String _needleSvg(
  double cx,
  double cy,
  double angleDeg,
  double length,
  double s,
  String color,
) {
  final a = angleDeg * math.pi / 180;
  final dx = math.cos(a), dy = math.sin(a);
  final px = -dy, py = dx;
  final hw = math.max(2.0, s * 0.016);
  final tipX = cx + dx * length, tipY = cy + dy * length;
  final tailX = cx - dx * length * .2, tailY = cy - dy * length * .2;
  return '<path d="M${_num(tipX)},${_num(tipY)} '
      'L${_num(cx + px * hw)},${_num(cy + py * hw)} '
      'L${_num(tailX)},${_num(tailY)} '
      'L${_num(cx - px * hw)},${_num(cy - py * hw)} Z" fill="$color"/>';
}

String _hubSvg(double cx, double cy, double s, _CockpitSvgPalette p) =>
    '<circle cx="${_num(cx)}" cy="${_num(cy)}" r="${_num(s * .052)}" fill="${p.screwHole}"/>'
    '<circle cx="${_num(cx)}" cy="${_num(cy)}" r="${_num(s * .038)}" fill="${p.screwMetal}"/>'
    '<circle cx="${_num(cx)}" cy="${_num(cy)}" r="${_num(s * .022)}" fill="${p.screwHole}"/>'
    '<circle cx="${_num(cx)}" cy="${_num(cy)}" r="${_num(s * .009)}" fill="${p.face}"/>';

void _arcGaugeSvg(
  StringBuffer b,
  CockpitMeterSpec meter,
  double cx,
  double cy,
  double s,
  CockpitCellPlan plan,
  CockpitColorScheme scheme,
  _CockpitSvgPalette p,
  double start,
  double sweep,
) {
  final r = s * 0.335;
  final stroke = math.max(3.0, s * 0.035);
  double angleFor(double value) {
    final span = meter.max - meter.min == 0 ? 1.0 : meter.max - meter.min;
    final n = ((value - meter.min) / span).clamp(0.0, 1.0);
    return start + sweep * n;
  }

  void arc(double from, double to, String color) {
    final a0 = angleFor(from);
    final a1 = angleFor(to);
    if ((a1 - a0).abs() < .5) return;
    b.write(
      '<path d="${_arcPath(cx, cy, r, a0, a1)}" fill="none" '
      'stroke="$color" stroke-opacity=".86" stroke-width="${_num(stroke)}" '
      'stroke-linecap="round"/>',
    );
  }

  b.write(
    '<path d="${_arcPath(cx, cy, r, start, start + sweep)}" fill="none" '
    'stroke="${p.ink}" stroke-opacity=".16" stroke-width="${_num(stroke)}" '
    'stroke-linecap="round"/>',
  );
  final greenStart = math.min(meter.greenFrom, meter.greenTo);
  final greenEnd = math.max(meter.greenFrom, meter.greenTo);
  if (meter.redFrom > greenEnd) {
    arc(meter.min, greenStart, scheme.warning);
    arc(greenStart, greenEnd, scheme.good);
    arc(greenEnd, meter.redFrom, scheme.warning);
    arc(meter.redFrom, meter.max, scheme.critical);
  } else {
    arc(meter.min, meter.redFrom, scheme.critical);
    arc(meter.redFrom, greenStart, scheme.warning);
    arc(greenStart, greenEnd, scheme.good);
    arc(greenEnd, meter.max, scheme.warning);
  }
  for (var i = 0; i <= 10; i++) {
    final major = i % 5 == 0;
    final a = (start + sweep * i / 10) * math.pi / 180;
    final outerR = r + 2, innerR = r - stroke * (major ? 1.45 : .75);
    b.write(
      '<line x1="${_num(cx + math.cos(a) * innerR)}" y1="${_num(cy + math.sin(a) * innerR)}" '
      'x2="${_num(cx + math.cos(a) * outerR)}" y2="${_num(cy + math.sin(a) * outerR)}" '
      'stroke="${p.ink}" stroke-opacity="${major ? .62 : .30}" '
      'stroke-width="${_num(major ? math.max(1.5, s * .009) : math.max(1, s * .005))}"/>',
    );
  }
  // Minimum en maximum in de boogvrije opening, dezelfde plekken als de app.
  final wide = sweep > 220;
  final lx = r * (wide ? .62 : .78), ly = r * (wide ? .40 : .54);
  b
    ..write(
      _scaleText(cx - lx, cy + ly, cockpitFormatNumber(meter.min), plan, p),
    )
    ..write(
      _scaleText(cx + lx, cy + ly, cockpitFormatNumber(meter.max), plan, p),
    )
    ..write(
      _needleSvg(cx, cy, angleFor(meter.value), r - stroke * 1.35, s, p.needle),
    )
    ..write(_hubSvg(cx, cy, s, p));
}

void _thermometerSvg(
  StringBuffer b,
  CockpitMeterSpec meter,
  String id,
  double cx,
  double cy,
  double s,
  CockpitCellPlan plan,
  CockpitColorScheme scheme,
  _CockpitSvgPalette p,
) {
  // Dezelfde buis als de app: capsule op de bezel-as, bol eronder, vloeistof
  // als gradiënt over de zones, markeerstreep op de waarde.
  final tube = s * 0.11;
  final bulbR = tube * 0.82;
  final topY = cy - s * 0.25;
  final bulbY = cy + s * 0.14;
  final chTop = topY + tube * .5;
  final span = bulbY - chTop;
  final n =
      ((meter.value - meter.min) /
              ((meter.max - meter.min) == 0 ? 1.0 : meter.max - meter.min))
          .clamp(0.0, 1.0);
  final levelY = bulbY - span * n;
  final greenStart = math.min(meter.greenFrom, meter.greenTo);
  final greenEnd = math.max(meter.greenFrom, meter.greenTo);
  double norm(double v) =>
      ((v - meter.min) /
              ((meter.max - meter.min) == 0 ? 1.0 : meter.max - meter.min))
          .clamp(0.0, 1.0);
  final List<(double, String)> stops;
  if (meter.redFrom > greenEnd) {
    final gs = norm(greenStart);
    final ge = math.max(gs, norm(greenEnd));
    final rf = math.max(ge, norm(meter.redFrom));
    stops = [
      (0, scheme.cold),
      (gs * .55, scheme.cold),
      (gs, scheme.good),
      (ge, scheme.good),
      ((ge + rf) / 2, scheme.warning),
      (rf, scheme.critical),
      (1, scheme.critical),
    ];
  } else {
    final rr = norm(meter.redFrom);
    final g = math.max(rr, norm(greenStart));
    stops = [
      (0, scheme.critical),
      (rr, scheme.critical),
      ((rr + g) / 2, scheme.warning),
      (g, scheme.good),
      (1, scheme.good),
    ];
  }
  final yJoin = bulbY - math.sqrt(math.max(0, bulbR * bulbR - tube * tube / 4));
  final theta = math.asin((tube / 2) / bulbR) * 180 / math.pi;
  final tubeOpen =
      'M${_num(cx - tube / 2)},${_num(yJoin)} V${_num(topY + tube / 2)} '
      'A${_num(tube / 2)},${_num(tube / 2)} 0 0,1 ${_num(cx + tube / 2)},${_num(topY + tube / 2)} '
      'V${_num(yJoin)}';
  final gradient = 'cockpit-thermo-$id';
  final sw = _num(math.max(1.5, s * .006));
  b
    ..write(
      '<defs><linearGradient id="$gradient" gradientUnits="userSpaceOnUse" x1="0" '
      'y1="${_num(bulbY + bulbR)}" x2="0" y2="${_num(topY)}">'
      '${stops.map((st) => '<stop offset="${_num(st.$1 * 100)}%" stop-color="${st.$2}"/>').join()}'
      '</linearGradient></defs>',
    )
    ..write('<path d="$tubeOpen Z" fill="url(#$gradient)"/>')
    ..write(
      '<circle cx="${_num(cx)}" cy="${_num(bulbY)}" r="${_num(bulbR)}" fill="url(#$gradient)"/>',
    )
    ..write(
      '<path d="$tubeOpen" fill="none" stroke="${p.ink}" stroke-opacity=".42" stroke-width="$sw"/>',
    )
    ..write(
      '<path d="${_arcPath(cx, bulbY, bulbR, -90 + theta, 270 - theta)}" fill="none" '
      'stroke="${p.ink}" stroke-opacity=".42" stroke-width="$sw"/>',
    )
    ..write(
      '<line x1="${_num(cx - tube / 2 - tube * .24)}" y1="${_num(levelY)}" '
      'x2="${_num(cx + tube / 2 + tube * .24)}" y2="${_num(levelY)}" '
      'stroke="${p.ink}" stroke-width="${_num(math.max(2, s * .008))}" stroke-linecap="round"/>',
    )
    ..write(
      '<path d="M${_num(cx + tube / 2 + tube * .24)},${_num(levelY)} '
      'L${_num(cx + tube / 2 + tube * .62)},${_num(levelY - tube * .30)} '
      'L${_num(cx + tube / 2 + tube * .62)},${_num(levelY + tube * .30)} Z" fill="${p.ink}"/>',
    )
    ..write(
      _scaleText(
        cx - s * .10,
        chTop,
        cockpitFormatNumber(meter.max),
        plan,
        p,
        anchor: 'end',
      ),
    )
    ..write(
      _scaleText(
        cx - s * .10,
        bulbY,
        cockpitFormatNumber(meter.min),
        plan,
        p,
        anchor: 'end',
      ),
    );
}

void _climbDescentSvg(
  StringBuffer b,
  CockpitMeterSpec meter,
  double cx,
  double cy,
  double s,
  CockpitCellPlan plan,
  _CockpitSvgPalette p,
) {
  final r = s * 0.33;
  final span = meter.max - meter.min == 0 ? 1.0 : meter.max - meter.min;
  final n = ((meter.value - meter.min) / span).clamp(0.0, 1.0);
  b.write(
    '<circle cx="${_num(cx)}" cy="${_num(cy)}" r="${_num(r)}" fill="none" '
    'stroke="${p.ink}" stroke-opacity=".30" stroke-width="${_num(s * .016)}"/>',
  );
  for (var i = 0; i <= 10; i++) {
    final a = (90 - 180 * i / 10) * math.pi / 180;
    final long = i % 5 == 0;
    b.write(
      '<line x1="${_num(cx + math.cos(a) * r * (long ? .72 : .82))}" '
      'y1="${_num(cy + math.sin(a) * r * (long ? .72 : .82))}" '
      'x2="${_num(cx + math.cos(a) * r * .95)}" '
      'y2="${_num(cy + math.sin(a) * r * .95)}" '
      'stroke="${p.ink}" stroke-opacity=".44" stroke-width="${long ? 2 : 1}"/>',
    );
  }
  b
    ..write(
      _scaleText(
        cx - r * .50,
        cy - r * .52,
        '+${cockpitFormatNumber(meter.max)}',
        plan,
        p,
      ),
    )
    ..write(_scaleText(cx - r * .62, cy, '0', plan, p))
    ..write(
      _scaleText(
        cx - r * .50,
        cy + r * .52,
        cockpitFormatNumber(meter.min),
        plan,
        p,
      ),
    )
    ..write(_needleSvg(cx, cy, 90 - 180 * n, r * .76, s, p.needle))
    ..write(_hubSvg(cx, cy, s, p));
}

void _horizonSvg(
  StringBuffer b,
  CockpitMeterSpec meter,
  String id,
  double cx,
  double cy,
  double s,
  CockpitColorScheme colors,
  _CockpitSvgPalette p,
) {
  final r = s * 0.34;
  final clip = 'cockpit-horizon-$id';
  final pitchOffset = meter.pitch.clamp(-45, 45) * r / 45;
  final bank = meter.bank.clamp(-60, 60);
  b
    ..write(
      '<defs><clipPath id="$clip"><circle cx="${_num(cx)}" cy="${_num(cy)}" r="${_num(r)}"/></clipPath></defs>',
    )
    ..write(
      '<g clip-path="url(#$clip)" transform="rotate(${_num(bank.toDouble())} ${_num(cx)} ${_num(cy)})">'
      '<rect x="${_num(cx - r * 1.6)}" y="${_num(cy - r * 1.6 + pitchOffset)}" '
      'width="${_num(r * 3.2)}" height="${_num(r * 1.6)}" fill="${colors.sky}"/>'
      '<rect x="${_num(cx - r * 1.6)}" y="${_num(cy + pitchOffset)}" '
      'width="${_num(r * 3.2)}" height="${_num(r * 1.6)}" fill="${colors.ground}"/>'
      '<line x1="${_num(cx - r * 1.4)}" y1="${_num(cy + pitchOffset)}" '
      'x2="${_num(cx + r * 1.4)}" y2="${_num(cy + pitchOffset)}" '
      'stroke="#F8FAFC" stroke-width="${_num(r * .035)}"/></g>',
    )
    ..write(
      '<circle cx="${_num(cx)}" cy="${_num(cy)}" r="${_num(r)}" fill="none" '
      'stroke="${p.ink}" stroke-opacity=".55" stroke-width="${_num(s * .018)}"/>',
    )
    ..write(
      '<line x1="${_num(cx - r * .38)}" y1="${_num(cy)}" x2="${_num(cx + r * .38)}" '
      'y2="${_num(cy)}" stroke="#000" stroke-opacity=".55" '
      'stroke-width="${_num(s * .028)}" stroke-linecap="round"/>'
      '<line x1="${_num(cx - r * .38)}" y1="${_num(cy)}" x2="${_num(cx + r * .38)}" '
      'y2="${_num(cy)}" stroke="#FFFFFF" stroke-width="${_num(s * .016)}" '
      'stroke-linecap="round"/>',
    );
  // Pitch en bank staan in het uitleesvenster, niet meer op de grond.
}

void _headingSvg(
  StringBuffer b,
  CockpitMeterSpec meter,
  double cx,
  double cy,
  double s,
  CockpitCellPlan plan,
  _CockpitSvgPalette p,
) {
  final r = s * 0.34;
  b.write(
    '<circle cx="${_num(cx)}" cy="${_num(cy)}" r="${_num(r)}" fill="none" '
    'stroke="${p.ink}" stroke-opacity=".30" stroke-width="${_num(s * .017)}"/>',
  );
  for (var i = 0; i < 36; i++) {
    final a = (i * 10 - 90) * math.pi / 180;
    final long = i % 3 == 0;
    b.write(
      '<line x1="${_num(cx + math.cos(a) * r * (long ? .82 : .90))}" '
      'y1="${_num(cy + math.sin(a) * r * (long ? .82 : .90))}" '
      'x2="${_num(cx + math.cos(a) * r)}" y2="${_num(cy + math.sin(a) * r)}" '
      'stroke="${p.ink}" stroke-opacity="${long ? .62 : .32}" stroke-width="${long ? 2 : 1}"/>',
    );
  }
  const labels = ['N', 'E', 'S', 'W'];
  for (var i = 0; i < labels.length; i++) {
    final a = (-90 + i * 90) * math.pi / 180;
    b.write(
      _scaleText(
        cx + math.cos(a) * r * .66,
        cy + math.sin(a) * r * .66,
        labels[i],
        plan,
        p,
      ),
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
  b
    ..write(
      '<path d="M${_num(markerTipX)},${_num(markerTipY)} L${_num(markerLeftX)},${_num(markerLeftY)} '
      'L${_num(markerRightX)},${_num(markerRightY)} Z" fill="${p.accent}" fill-opacity=".95"/>',
    )
    ..write(
      '<path d="M${_num(cx + math.cos(actual) * r * .72)},${_num(cy + math.sin(actual) * r * .72)} '
      'L${_num(cx + math.cos(actual + 2.6) * r * .18)},${_num(cy + math.sin(actual + 2.6) * r * .18)} '
      'L${_num(cx + math.cos(actual - 2.6) * r * .18)},${_num(cy + math.sin(actual - 2.6) * r * .18)} Z" '
      'fill="${p.needle}"/>',
    )
    ..write(_hubSvg(cx, cy, s, p));
  // ACT/TGT/marker staan in het venster naast de roos (#1110 verhuisd).
}

/// Het uitleesvenster: authentiek een plaat in face-kleur; daarop de regels
/// uit de rekenkern, verticaal gecentreerd, in een clip van het venster.
void _readoutSvg(
  StringBuffer b,
  CockpitMeterSpec meter,
  String id,
  CockpitCellPlan plan,
  double readoutScale,
  _CockpitSvgPalette p,
  bool authentic,
) {
  final win = plan.window;
  final s = plan.dialSide;
  if (authentic) {
    b.write(
      '<rect x="${_num(win.x)}" y="${_num(win.y)}" width="${_num(win.w)}" '
      'height="${_num(win.h)}" rx="${_num(s * .03)}" fill="${p.face}" '
      'stroke="${p.ink}" stroke-opacity=".30" stroke-width="${_num(math.max(1, s * .006))}"/>',
    );
  }
  if (plan.numberSize < cockpitMinTextPx) return;
  final lines = cockpitReadoutLines(
    meter,
    plan,
    attitudeTemplate: _cockpitAttitudeTemplate,
    actualTemplate: _cockpitActualTemplate,
    targetTemplate: _cockpitTargetTemplate,
    scale: readoutScale,
  );
  final clip = 'cockpit-readout-$id';
  b.write(
    '<clipPath id="$clip"><rect x="${_num(win.x)}" y="${_num(win.y)}" '
    'width="${_num(win.w)}" height="${_num(win.h)}"/></clipPath>'
    '<g clip-path="url(#$clip)">',
  );
  var y = win.centerY - cockpitReadoutHeight(lines) / 2;
  for (final line in lines) {
    if (line.size < cockpitMinTextPx) {
      y += line.height + line.gapAfter;
      continue;
    }
    final cy = y + line.height / 2;
    final color = line.strong ? p.ink : p.inkMuted;
    final unit = line.inlineUnitSize >= cockpitMinTextPx
        ? line.inlineUnit
        : null;
    b.write(
      '<text x="${_num(win.centerX)}" y="${_num(cy)}" text-anchor="middle" '
      'dominant-baseline="central" font-size="${_num(line.size)}" '
      'font-weight="${line.strong ? 800 : 600}" fill="$color">${_esc(line.text)}',
    );
    if (unit != null) {
      b.write(
        '<tspan dx="${_num(line.inlineGap)}" font-size="${_num(line.inlineUnitSize)}" '
        'font-weight="600" fill="${p.inkMuted}">${_esc(unit)}</tspan>',
      );
    }
    b.write('</text>');
    y += line.height + line.gapAfter;
  }
  b.write('</g>');
}

/// Het label in de labelstrook, door dezelfde cascade als de app; een lege
/// label krijgt in de export een genummerde plaatshouder.
void _labelSvg(
  StringBuffer b,
  CockpitMeterSpec meter,
  int index,
  String id,
  CockpitCellPlan plan,
  _CockpitSvgPalette p,
) {
  final label = meter.label.isEmpty ? 'Meter ${index + 1}' : meter.label;
  final fit = plan.fitLabel(label);
  if (fit.size < cockpitMinTextPx || fit.lines.isEmpty) return;
  final box = plan.labelBox;
  final lineH = fit.size * cockpitLineHeight;
  var y = box.centerY - fit.lines.length * lineH / 2 + lineH / 2;
  final clip = 'cockpit-label-$id';
  b.write(
    '<clipPath id="$clip"><rect x="${_num(box.x)}" y="${_num(box.y)}" '
    'width="${_num(box.w)}" height="${_num(box.h)}"/></clipPath>'
    '<g clip-path="url(#$clip)">',
  );
  for (final line in fit.lines) {
    b.write(
      '<text x="${_num(box.centerX)}" y="${_num(y)}" text-anchor="middle" '
      'dominant-baseline="central" font-size="${_num(fit.size)}" '
      'font-weight="700" fill="${p.label}">${_esc(line)}</text>',
    );
    y += lineH;
  }
  b.write('</g>');
}

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
  return 'M${_num(x0)},${_num(y0)} A${_num(r)},${_num(r)} 0 $large,1 ${_num(x1)},${_num(y1)}';
}
