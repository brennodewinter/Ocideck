// Rekenkern van de cockpit-dia: raster, celindeling en tekstbudget.
//
// Eén bron voor twee renderwerelden. De Flutter-painter (app, presenter,
// beamer, PDF/PPTX) en de SVG van de HTML-export tekenden elk hun eigen
// geometrie en liepen daardoor stil uit elkaar; en allebei zetten ze de
// waarde-uitlezing als één ongebonden regel "getal+eenheid" ín de wijzerplaat,
// precies waar de schaalcijfers en de bandeinden zitten. Een eenheid als
// "% van maximale hartslag" liep daardoor dwars door de schaal en tot op de
// bezel (het herontwerp van september 2026, docs/design/COCKPIT_LAYOUT.md).
//
// Het ontwerp: op de wijzerplaat staat geen vrije tekst meer; getal en eenheid
// krijgen een uitleesvenster in de flank die naast een ronde bezel leeg bleef;
// het label krijgt de volle celbreedte eronder. Elke passingsbeslissing volgt
// uit tekenaantal en celmaat — niet uit gemeten pixels — zodat de export, die
// geen tekst kan meten, dezelfde regelval kiest als de app. Daarom staat dit
// bestand onder services/ zonder Flutter-import: het rekent alleen.
import 'dart:math' as math;

import '../models/cockpit.dart';

/// Geschatte breedte per teken, als fractie van de lettergrootte. Bewust ruim
/// voor EB Garamond en Arial: liever een regel te vroeg breken dan tekst die
/// alsnog over een rand loopt.
const double cockpitTextEm = 0.55;

/// Geschatte breedte per cijfer (w800). Cijfers zijn breder dan letters.
const double cockpitDigitEm = 0.62;

/// Regelhoogte als fractie van de lettergrootte.
const double cockpitLineHeight = 1.15;

/// Celverhouding (breedte/hoogte) waarboven het uitleesvenster náást de
/// wijzerplaat komt; smaller dan dit heeft geen bruikbare flank.
const double cockpitWideAspect = 1.35;

/// Onder deze lettergrootte wordt tekst niet meer getekend (de miniatuur in de
/// slidestrook): een eerlijke mini-meter zonder streepjes die tekst voorstellen.
const double cockpitMinTextPx = 7;

/// Kortste eenheid die inline achter het getal mag ("%", "/10", "°C", "km/u"
/// niet: die heeft vier tekens en gaat op een eigen regel).
const int cockpitInlineUnitMaxChars = 3;

/// Een rechthoek in celcoördinaten. Bewust geen `dart:ui`-`Rect`: de
/// SVG-export heeft geen Flutter nodig om te rekenen.
class CockpitRect {
  final double x;
  final double y;
  final double w;
  final double h;

  const CockpitRect(this.x, this.y, this.w, this.h);

  double get right => x + w;
  double get bottom => y + h;
  double get centerX => x + w / 2;
  double get centerY => y + h / 2;
}

/// Kolommen voor [count] meters: drie meters op één rij en vijf als 3 + 2, zodat
/// een dashboard geen leeg vak heeft.
int cockpitColumns(int count) {
  if (count <= 1) return 1;
  if (count == 2) return 2;
  if (count == 3) return 3;
  if (count == 4) return 2;
  return 3;
}

/// Het raster: even grote cellen, een onvolledige laatste rij gecentreerd.
class CockpitGridPlan {
  final int columns;
  final int rows;
  final double cellWidth;
  final double cellHeight;
  final double gap;
  final List<CockpitRect> cells;

  const CockpitGridPlan._({
    required this.columns,
    required this.rows,
    required this.cellWidth,
    required this.cellHeight,
    required this.gap,
    required this.cells,
  });

  factory CockpitGridPlan.compute({
    required int count,
    required double width,
    required double height,
    double gapFraction = 0.018,
  }) {
    final n = count.clamp(1, cockpitMaxMeters);
    final columns = cockpitColumns(n);
    final rows = (n / columns).ceil();
    final gap = width * gapFraction;
    final cellW = (width - gap * (columns - 1)) / columns;
    final cellH = (height - gap * (rows - 1)) / rows;
    final cells = <CockpitRect>[];
    for (var i = 0; i < n; i++) {
      final row = i ~/ columns;
      final col = i % columns;
      final inRow = math.min(columns, n - row * columns);
      final rowShift = (columns - inRow) * (cellW + gap) / 2;
      cells.add(
        CockpitRect(
          col * (cellW + gap) + rowShift,
          row * (cellH + gap),
          cellW,
          cellH,
        ),
      );
    }
    return CockpitGridPlan._(
      columns: columns,
      rows: rows,
      cellWidth: cellW,
      cellHeight: cellH,
      gap: gap,
      cells: cells,
    );
  }
}

/// Getal zonder overbodige decimalen: 70 → "70", 8.4 → "8.4".
String cockpitFormatNumber(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

/// De uitlezing van een scalaire meter; klim/daling krijgt een plusteken.
String cockpitValueText(CockpitMeterSpec meter, {double? shown}) {
  final v = shown ?? meter.value;
  final text = cockpitFormatNumber(v);
  if (meter.type == CockpitMeterType.climbDescent && v > 0) return '+$text';
  return text;
}

bool _isNumeric(CockpitMeterType type) => switch (type) {
  CockpitMeterType.speedometer ||
  CockpitMeterType.voltmeter ||
  CockpitMeterType.altimeter ||
  CockpitMeterType.thermometer ||
  CockpitMeterType.climbDescent => true,
  CockpitMeterType.horizon || CockpitMeterType.heading => false,
};

/// Het langste getal dat op de dia kan verschijnen (minimum, maximum of waarde,
/// met teken). Eén getalmaat per dia volgt hieruit, zodat alle uitlezingen op
/// één lijn staan en de rollende uitlezing tijdens de animatie nooit van maat
/// springt.
int cockpitLongestDigits(List<CockpitMeterSpec> meters) {
  var longest = 1;
  for (final m in meters) {
    if (!_isNumeric(m.type)) continue;
    final candidates = [
      cockpitFormatNumber(m.min),
      cockpitFormatNumber(m.max),
      cockpitValueText(m),
    ];
    if (m.type == CockpitMeterType.climbDescent) {
      candidates.add('+${cockpitFormatNumber(m.max)}');
    }
    for (final c in candidates) {
      longest = math.max(longest, c.length);
    }
  }
  return longest;
}

/// Een korte eenheid zonder spatie staat inline achter het getal.
bool cockpitUnitInline(String unit) =>
    unit.isNotEmpty &&
    unit.runes.length <= cockpitInlineUnitMaxChars &&
    !unit.contains(RegExp(r'\s'));

/// Splitst de (vertaalde) attitude-regel "P {pitch}  B {bank}" op de run van
/// twee of meer spaties in twee vensterregels. Een vertaling zonder dubbele
/// spatie blijft één regel.
List<String> splitCockpitAttitude(String text) {
  final parts = text.split(RegExp(r'\s{2,}'));
  return parts.where((p) => p.isNotEmpty).toList();
}

/// Uitkomst van de pas-cascade: de lettergrootte en de regels.
class CockpitTextFit {
  final double size;
  final List<String> lines;

  const CockpitTextFit(this.size, this.lines);

  bool get ellipsized => lines.isNotEmpty && lines.last.endsWith('…');
}

/// Greedy woordwikkel op een tekenbudget per regel. Eén woord langer dan een
/// regel wordt hard gebroken; wat na [maxLines] overblijft eindigt in een
/// ellipsis.
List<String> wrapCockpitWords(String text, int charsPerLine, int maxLines) {
  final budget = math.max(1, charsPerLine);
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final lines = <String>[];
  var current = '';
  for (final word in words) {
    final candidate = current.isEmpty ? word : '$current $word';
    if (candidate.runes.length <= budget) {
      current = candidate;
      continue;
    }
    if (current.isNotEmpty) lines.add(current);
    var rest = word;
    while (rest.runes.length > budget) {
      lines.add(String.fromCharCodes(rest.runes.take(budget)));
      rest = String.fromCharCodes(rest.runes.skip(budget));
    }
    current = rest;
  }
  if (current.isNotEmpty) lines.add(current);
  if (lines.length <= maxLines) return lines;
  final cut = lines.take(maxLines).toList();
  final last = cut.last.runes.toList();
  final keep = math.max(1, math.min(last.length, budget - 1));
  cut[cut.length - 1] = '${String.fromCharCodes(last.take(keep))}…';
  return cut;
}

/// Wikkelt alleen als élk woord in een regel past en het aantal regels binnen
/// [maxLines] blijft; anders `null`, zodat de aanroeper eerst kan krimpen.
List<String>? _wrapClean(String text, int charsPerLine, int maxLines) {
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.any((w) => w.runes.length > charsPerLine)) return null;
  final lines = wrapCockpitWords(text, charsPerLine, maxLines + 1);
  return lines.length <= maxLines ? lines : null;
}

/// De cascade voor label en eenheid, zonder tekstmeting: past de tekst op
/// [size] in [width] → klaar; anders krimpen tot [floor]; past hij dan nog niet
/// op één regel → wikkelen tot [maxLines]; pas daarna een ellipsis.
///
/// Met [wrapFirst] gaat wikkelen op volle grootte vóór krimpen: een eenheid
/// als "% van maximale hartslag" leest beter als twee regels op maat dan als
/// één gekrompen regel; een label houdt liever één regel.
CockpitTextFit fitCockpitText(
  String text, {
  required double width,
  required double size,
  required double floor,
  required int maxLines,
  double em = cockpitTextEm,
  bool wrapFirst = false,
}) {
  final chars = text.runes.length;
  if (chars == 0) return CockpitTextFit(size, const []);
  if (chars * em * size <= width) return CockpitTextFit(size, [text]);
  if (wrapFirst && maxLines > 1) {
    // De grootste maat tussen [size] en [floor] waarop de tekst schoon wikkelt
    // (geen gebroken woord, geen ellipsis), in acht vaste stappen zodat beide
    // renderwerelden dezelfde maat vinden.
    for (var step = 0; step <= 8; step++) {
      final candidate = size - (size - floor) * step / 8;
      final wrapped = _wrapClean(
        text,
        (width / (em * candidate)).floor(),
        maxLines,
      );
      if (wrapped != null) return CockpitTextFit(candidate, wrapped);
    }
  }
  final shrunk = math.max(floor, width / (chars * em));
  if (chars * em * shrunk <= width) return CockpitTextFit(shrunk, [text]);
  final perLine = (width / (em * floor)).floor();
  return CockpitTextFit(floor, wrapCockpitWords(text, perLine, maxLines));
}

enum CockpitCellMode { wide, stacked }

/// De indeling van één cel: waar de wijzerplaat staat, waar het uitleesvenster,
/// waar het label, en welke lettergroottes gelden. Alles fracties van de
/// celmaat; per dia gelijk voor alle cellen.
class CockpitCellPlan {
  final CockpitCellMode mode;
  final double width;
  final double height;

  /// Zijde van het instrumentvierkant; alle instrumentgeometrie (bezel 0,465,
  /// face 0,88·bezel, boog 0,335) is een fractie hiervan.
  final double dialSide;
  final double dialCenterX;
  final double dialCenterY;

  /// Het vlak met bezel én venster: hier staan de schroeven (authentiek) of de
  /// kaart (klassiek).
  final CockpitRect instrumentBand;

  /// Het uitleesvenster: plaat in face-kleur met getal en eenheid.
  final CockpitRect window;

  /// De labelstrook onder de groep.
  final CockpitRect labelBox;

  final double numberSize;
  final double unitSize;
  final double unitFloor;
  final double labelSize;
  final double labelFloor;

  /// Schaalcijfers (min/max) op de wijzerplaat.
  final double scaleSize;

  const CockpitCellPlan._({
    required this.mode,
    required this.width,
    required this.height,
    required this.dialSide,
    required this.dialCenterX,
    required this.dialCenterY,
    required this.instrumentBand,
    required this.window,
    required this.labelBox,
    required this.numberSize,
    required this.unitSize,
    required this.unitFloor,
    required this.labelSize,
    required this.labelFloor,
    required this.scaleSize,
  });

  double get bezelRadius => dialSide * 0.465;

  /// Tekstbreedte binnen het venster (4 % marge per kant).
  double get windowTextWidth => window.w * 0.92;

  factory CockpitCellPlan.compute({
    required double width,
    required double height,
    required int longestDigits,
  }) {
    final w = math.max(1.0, width);
    final h = math.max(1.0, height);
    final digits = math.max(1, longestDigits);
    if (w / h >= cockpitWideAspect) {
      final labelH = 0.15 * h;
      final bandH = h - labelH;
      final d = bandH;
      final x0 = 0.02 * w;
      final rb = 0.465 * d;
      final cx = x0 + d / 2;
      final xL = cx + rb + 0.03 * w;
      final xR = 0.97 * w;
      final cw = math.max(1.0, math.min(xR - xL, 1.4 * d));
      final group = x0 + d + 0.03 * w + cw;
      final shift = math.max(0.0, (w - group - 0.03 * w) / 2);
      final nf = math.min(0.34 * bandH, cw / (cockpitDigitEm * digits));
      final uf = (0.32 * nf).clamp(0.055 * h, 0.085 * h).toDouble();
      return CockpitCellPlan._(
        mode: CockpitCellMode.wide,
        width: w,
        height: h,
        dialSide: d,
        dialCenterX: cx + shift,
        dialCenterY: bandH / 2,
        instrumentBand: CockpitRect(0, 0, w, bandH),
        window: CockpitRect(xL + shift, 0.19 * bandH, cw, 0.62 * bandH),
        labelBox: CockpitRect(0.05 * w, bandH, 0.90 * w, labelH),
        numberSize: nf,
        unitSize: uf,
        unitFloor: 0.055 * h,
        labelSize: 0.085 * h,
        labelFloor: 0.055 * h,
        scaleSize: 0.065 * d,
      );
    }
    final d = 0.62 * h;
    final cw = 0.90 * w;
    final nf = math.min(0.14 * h, cw / (cockpitDigitEm * digits));
    return CockpitCellPlan._(
      mode: CockpitCellMode.stacked,
      width: w,
      height: h,
      dialSide: d,
      dialCenterX: w / 2,
      dialCenterY: d / 2,
      instrumentBand: CockpitRect(0, 0, w, 0.86 * h),
      window: CockpitRect(0.05 * w, 0.62 * h, cw, 0.24 * h),
      labelBox: CockpitRect(0.05 * w, 0.86 * h, 0.90 * w, 0.14 * h),
      numberSize: nf,
      unitSize: 0.06 * h,
      unitFloor: 0.045 * h,
      labelSize: 0.07 * h,
      labelFloor: 0.05 * h,
      scaleSize: 0.065 * d,
    );
  }

  /// Het label, door de cascade: één regel op [labelSize] als het past, anders
  /// krimpen, dan twee regels.
  CockpitTextFit fitLabel(String label) => fitCockpitText(
    label,
    width: labelBox.w,
    size: labelSize,
    floor: labelFloor,
    maxLines: 2,
  );
}

/// Eén regel in het uitleesvenster.
class CockpitReadoutLine {
  final String text;
  final double size;

  /// Vet en in inktkleur (het getal, de ACT-regel); anders gedempt.
  final bool strong;

  /// Korte eenheid inline achter de regel, op [inlineUnitSize].
  final String? inlineUnit;
  final double inlineUnitSize;

  /// Extra ruimte onder deze regel.
  final double gapAfter;

  const CockpitReadoutLine(
    this.text,
    this.size, {
    this.strong = false,
    this.inlineUnit,
    this.inlineUnitSize = 0,
    this.gapAfter = 0,
  });

  /// Regelhoogte: het getal staat strak (1,0), lopende tekst op 1,15.
  double get height => size * (strong ? 1.0 : cockpitLineHeight);

  /// Geschatte breedte, inclusief inline eenheid.
  double get estimatedWidth {
    final em = strong ? cockpitDigitEm : cockpitTextEm;
    var w = text.runes.length * em * size;
    final unit = inlineUnit;
    if (unit != null) w += inlineGap + unit.runes.length * cockpitTextEm * inlineUnitSize;
    return w;
  }

  double get inlineGap => size * 0.1;
}

/// De vensterregels van een meter: getal (+ inline eenheid) en eenheidregels,
/// of voor horizon en kompas de attitude- en koersregels. De sjablonen komen
/// vertaald van buiten; de export geeft zijn Engelse standaard mee.
List<CockpitReadoutLine> cockpitReadoutLines(
  CockpitMeterSpec meter,
  CockpitCellPlan plan, {
  required String attitudeTemplate,
  required String actualTemplate,
  required String targetTemplate,
  double? shownValue,
  double? shownHeading,
}) {
  final width = plan.windowTextWidth;
  final nf = plan.numberSize;
  switch (meter.type) {
    case CockpitMeterType.horizon:
      final text = attitudeTemplate
          .replaceAll('{pitch}', cockpitFormatNumber(meter.pitch))
          .replaceAll('{bank}', cockpitFormatNumber(meter.bank));
      final lines = splitCockpitAttitude(text);
      var longest = 1;
      for (final l in lines) {
        longest = math.max(longest, l.runes.length);
      }
      final size = math.min(nf, width / (cockpitDigitEm * longest));
      return [
        for (final l in lines) CockpitReadoutLine(l, size, strong: true),
      ];
    case CockpitMeterType.heading:
      final actual = actualTemplate.replaceAll(
        '{value}',
        cockpitFormatNumber((shownHeading ?? meter.value) % 360).padLeft(3, '0'),
      );
      final target = targetTemplate.replaceAll(
        '{heading}',
        cockpitFormatNumber(meter.heading).padLeft(3, '0'),
      );
      final actualSize = math.min(
        nf,
        width / (cockpitDigitEm * actual.runes.length),
      );
      final targetFit = fitCockpitText(
        target,
        width: width,
        size: plan.unitSize,
        floor: plan.unitFloor,
        maxLines: 1,
      );
      final marker = fitCockpitText(
        meter.markerLabel,
        width: width,
        size: plan.unitSize,
        floor: plan.unitFloor,
        maxLines: 2,
        wrapFirst: true,
      );
      return [
        CockpitReadoutLine(
          actual,
          actualSize,
          strong: true,
          gapAfter: nf * 0.05,
        ),
        for (final l in targetFit.lines)
          CockpitReadoutLine(l, targetFit.size, gapAfter: nf * 0.05),
        for (final l in marker.lines) CockpitReadoutLine(l, marker.size),
      ];
    case CockpitMeterType.speedometer:
    case CockpitMeterType.voltmeter:
    case CockpitMeterType.thermometer:
    case CockpitMeterType.altimeter:
    case CockpitMeterType.climbDescent:
      final number = cockpitValueText(meter, shown: shownValue);
      final inline = cockpitUnitInline(meter.unit);
      final unit = fitCockpitText(
        inline ? '' : meter.unit,
        width: width,
        size: plan.unitSize,
        floor: plan.unitFloor,
        maxLines: 2,
        wrapFirst: true,
      );
      return [
        CockpitReadoutLine(
          number,
          nf,
          strong: true,
          inlineUnit: inline ? meter.unit : null,
          inlineUnitSize: nf * 0.45,
          gapAfter: unit.lines.isEmpty ? 0 : plan.unitSize * 0.15,
        ),
        for (final l in unit.lines) CockpitReadoutLine(l, unit.size),
      ];
  }
}

/// Totale hoogte van een regelstapel, voor verticaal centreren in het venster.
double cockpitReadoutHeight(List<CockpitReadoutLine> lines) {
  var total = 0.0;
  for (final l in lines) {
    total += l.height + l.gapAfter;
  }
  return total;
}
