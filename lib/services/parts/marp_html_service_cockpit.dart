// Part of the marp_html_service library — see ../marp_html_service.dart.
// Split out for navigability (cockpit instrument SVG rendering); all imports live in the main
// library file. These were private `static` MarpHtmlService helpers; as
// top-level private functions they share the library and are called by
// bare name from the service's public render methods.
part of '../marp_html_service.dart';

String _cockpitSvg(
  CockpitSpec spec,
  ThemeProfile? theme,
  CockpitColorScheme scheme,
) {
  final meters =
      (spec.meters.isEmpty ? CockpitSpec.pentestPreset().meters : spec.meters)
          .take(cockpitMaxMeters)
          .toList();
  final accent = theme?.accentColor ?? '#38BDF8';
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
      'font-family="inherit" width="100%">',
    )
    ..write('<rect width="900" height="500" rx="26" fill="#07111F"/>')
    ..write(
      '<rect x="22" y="22" width="856" height="456" rx="22" '
      'fill="#0F172A" stroke="$accent" stroke-opacity=".35" stroke-width="2"/>',
    )
    ..write(
      '<text x="450" y="58" text-anchor="middle" font-size="24" '
      'font-weight="800" fill="#E5F3FF" letter-spacing="3">COCKPIT VIEW</text>',
    );
  for (var i = 0; i < meters.length; i++) {
    final row = i ~/ cols;
    final col = i % cols;
    final x = 50 + col * cellW;
    final y = 82 + row * cellH;
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
    );
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
) {
  final colors = scheme;
  final cardH = math.max(80.0, h - 24);
  b
    ..write(
      '<rect x="$x" y="$y" width="$w" height="$cardH" rx="18" '
      'fill="#111827" stroke="#334155" stroke-width="1.5"/>',
    )
    ..write(
      '<text x="${x + w / 2}" y="${y + h - 6}" text-anchor="middle" '
      'font-size="13" font-weight="700" fill="#94A3B8">'
      '${_esc(meter.label.isEmpty ? 'Meter ${index + 1}' : meter.label)}</text>',
    );
  switch (meter.type) {
    case CockpitMeterType.thermometer:
      _thermometerSvg(b, meter, x, y, w, cardH, colors);
      break;
    case CockpitMeterType.climbDescent:
      _climbDescentSvg(b, meter, x, y, w, cardH, accent);
      break;
    case CockpitMeterType.horizon:
      _horizonSvg(b, meter, index, x, y, w, cardH, colors);
      break;
    case CockpitMeterType.heading:
      _headingSvg(b, meter, x, y, w, cardH, accent, colors);
      break;
    case CockpitMeterType.speedometer:
    case CockpitMeterType.voltmeter:
    case CockpitMeterType.altimeter:
      _arcGaugeSvg(b, meter, x, y, w, cardH, accent, colors);
      break;
  }
}

void _arcGaugeSvg(
  StringBuffer b,
  CockpitMeterSpec meter,
  double x,
  double y,
  double w,
  double h,
  String accent,
  CockpitColorScheme scheme,
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
    'stroke="#1E293B" stroke-width="12" stroke-linecap="round"/>',
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
      '<line x1="$cx" y1="$cy" x2="$nx" y2="$ny" stroke="$accent" '
      'stroke-width="4" stroke-linecap="round"/>',
    )
    ..write('<circle cx="$cx" cy="$cy" r="8" fill="$accent"/>')
    ..write(
      '<text x="${x + w * .78}" y="${y + h * .56}" text-anchor="middle" '
      'font-size="18" font-weight="800" fill="#F8FAFC">'
      '${_esc(_num(meter.value))}${_esc(meter.unit)}</text>',
    )
    ..write(
      '<text x="${cx - r}" y="${cy + 24}" text-anchor="middle" '
      'font-size="11" fill="#64748B">${_esc(_num(meter.min))}</text>',
    )
    ..write(
      '<text x="${cx + r}" y="${cy + 24}" text-anchor="middle" '
      'font-size="11" fill="#64748B">${_esc(_num(meter.max))}</text>',
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
) {
  final tubeX = x + w * .43;
  final top = y + 22;
  final bottom = y + h - 38;
  const tubeWidth = 12.0;
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
      '<rect x="${tubeX - 12}" y="${top - 9}" width="${tubeWidth + 24}" '
      'height="${bottom - top + 54}" rx="15" fill="#FFFFFF" fill-opacity=".055"/>',
    )
    ..write(
      '<rect x="$tubeX" y="$top" width="$tubeWidth" height="${bottom - top}" '
      'rx="8" fill="#1E293B" stroke="#CBD5E1" stroke-opacity=".48" stroke-width="3"/>',
    )
    ..write(
      '<rect x="${tubeX + 3}" y="$fillTop" width="6" '
      'height="${bottom - fillTop + 9}" rx="3" fill="$color"/>',
    )
    ..write(
      '<circle cx="${tubeX + 6}" cy="${bottom + 13}" r="16" fill="#0B1120" '
      'stroke="#CBD5E1" stroke-opacity=".48" stroke-width="3"/>',
    )
    ..write(
      '<circle cx="${tubeX + 6}" cy="${bottom + 13}" r="9" fill="$color"/>',
    );
  for (var i = 0; i <= 4; i++) {
    final yy = bottom - (bottom - top) * i / 4;
    final len = i.isEven ? 30 : 20;
    b.write(
      '<line x1="${tubeX + tubeWidth + 12}" y1="$yy" '
      'x2="${tubeX + tubeWidth + 12 + len}" y2="$yy" '
      'stroke="#CBD5E1" stroke-opacity=".38" stroke-width="2"/>',
    );
  }
  b.write(
    '<text x="${x + w * .70}" y="${y + h * .52}" text-anchor="middle" '
    'font-size="18" font-weight="800" fill="#F8FAFC">'
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
  String accent,
) {
  final cx = x + w * .44;
  final cy = y + h * .52;
  final r = math.min(w, h) * .31;
  final span = meter.max - meter.min == 0 ? 1.0 : meter.max - meter.min;
  final n = ((meter.value - meter.min) / span).clamp(0.0, 1.0);
  final angle = (90 - 180 * n) * math.pi / 180;
  final nx = cx + math.cos(angle) * r * .78;
  final ny = cy + math.sin(angle) * r * .78;
  b.write(
    '<circle cx="$cx" cy="$cy" r="$r" fill="#0B1120" stroke="#475569" stroke-width="4"/>',
  );
  for (var i = 0; i <= 10; i++) {
    final a = (90 - 180 * i / 10) * math.pi / 180;
    final long = i % 5 == 0;
    b.write(
      '<line x1="${cx + math.cos(a) * r * (long ? .72 : .82)}" '
      'y1="${cy + math.sin(a) * r * (long ? .72 : .82)}" '
      'x2="${cx + math.cos(a) * r * .95}" '
      'y2="${cy + math.sin(a) * r * .95}" '
      'stroke="#CBD5E1" stroke-opacity="${long ? .70 : .36}" '
      'stroke-width="${long ? 2 : 1}"/>',
    );
  }
  b
    ..write(
      '<text x="$cx" y="${cy - r * .48}" text-anchor="middle" '
      'font-size="16" font-weight="900" fill="#94A3B8">+</text>',
    )
    ..write(
      '<text x="${cx + r * .62}" y="${cy + 5}" text-anchor="middle" '
      'font-size="13" font-weight="700" fill="#94A3B8">0</text>',
    )
    ..write(
      '<text x="$cx" y="${cy + r * .68}" text-anchor="middle" '
      'font-size="18" font-weight="900" fill="#94A3B8">-</text>',
    )
    ..write(
      '<line x1="$cx" y1="$cy" x2="$nx" y2="$ny" stroke="$accent" '
      'stroke-width="4" stroke-linecap="round"/>',
    )
    ..write('<circle cx="$cx" cy="$cy" r="8" fill="$accent"/>')
    ..write(
      '<text x="${x + w * .78}" y="${y + h * .56}" text-anchor="middle" '
      'font-size="18" font-weight="800" fill="#F8FAFC">'
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
) {
  final cx = x + w * .44;
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
      '<circle cx="$cx" cy="$cy" r="$r" fill="none" stroke="#CBD5E1" stroke-width="4"/>',
    )
    ..write(
      '<path d="M${cx - 52},$cy h36 M${cx + 16},$cy h36 M$cx,${cy - 7} v14" '
      'stroke="#FACC15" stroke-width="5" stroke-linecap="round"/>',
    )
    ..write(
      '<text x="$cx" y="${cy + r + 30}" text-anchor="middle" '
      'font-size="16" font-weight="800" fill="#F8FAFC">'
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
  String accent,
  CockpitColorScheme scheme,
) {
  final cx = x + w / 2;
  final cy = y + h * .50;
  final r = math.min(w, h) * .31;
  b.write(
    '<circle cx="$cx" cy="$cy" r="$r" fill="#0B1120" stroke="#475569" stroke-width="4"/>',
  );
  const labels = ['N', 'E', 'S', 'W'];
  for (var i = 0; i < labels.length; i++) {
    final a = (-90 + i * 90) * math.pi / 180;
    b.write(
      '<text x="${cx + math.cos(a) * r * .72}" '
      'y="${cy + math.sin(a) * r * .72 + 6}" text-anchor="middle" '
      'font-size="17" font-weight="900" fill="#E5E7EB">${labels[i]}</text>',
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
      'L$markerRightX,$markerRightY Z" fill="$accent" fill-opacity=".95"/>',
    )
    ..write(
      '<path d="M$cx,${cy - 10} L$tipX,$tipY L$cx,${cy + 10} Z" '
      'fill="$accent"/>',
    )
    ..write('<circle cx="$cx" cy="$cy" r="7" fill="#F8FAFC"/>')
    ..write(
      '<text x="${x + w * .79}" y="${y + h * .46}" text-anchor="middle" '
      'font-size="15" font-weight="800" fill="#F8FAFC">'
      'ACT ${_esc(_headingNum(meter.value))}°</text>',
    )
    ..write(
      '<text x="${x + w * .79}" y="${y + h * .61}" text-anchor="middle" '
      'font-size="12" font-weight="700" fill="#94A3B8">'
      'TGT ${_esc(_headingNum(meter.heading))}°</text>',
    );
  if (meter.markerLabel.isNotEmpty) {
    b.write(
      '<text x="${x + w * .79}" y="${y + h * .73}" text-anchor="middle" '
      'font-size="11" font-weight="600" fill="#94A3B8">'
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
