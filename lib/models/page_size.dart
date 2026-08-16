// ISO-216 paginamaties voor de documentmodus-export (feature 3).
//
// De A-, B- en C-reeksen volgen ISO 216: A(n) heeft een oppervlak van
// 1 m² × 2^(−n−1), B(n) is het geometrisch gemiddelde van A(n) en A(n−1),
// C(n) is het geometrisch gemiddelde van A(n) en B(n). De langste zijde is
// √2 × de kortste (de Lichtenberg-verhouding), en elke snede halveert de
// kortste zijde — vandaar de tabellen hieronder.
//
// De maten zijn in millimeters, afgerond op hele mm (de ISO-216 tolerantie
// is ±1.5 mm voor ≤150 mm, ±2 mm voor ≤600 mm). Een statische lookup-tabel
// volstaat: er zijn maar 11 maten per reeks (0–10), en de wiskunde bij
// export zou floating-point afrondingsverschillen geven die net fout kunnen
// zijn ten opzichte van wat een printer verwacht.

/// De ISO-216 reeks: A (documenten), B (posters/boeken), C (enveloppen).
enum PaperSeries { a, b, c }

/// Een paginamaat uit ISO-216: reeks + nummer + portret/landschap.
class PageSizeSpec {
  final PaperSeries series;
  final int number;
  final bool landscape;

  const PageSizeSpec({
    required this.series,
    required this.number,
    this.landscape = false,
  });

  /// Standaard A4 portret — de meest voorkomende documentmaat.
  static const a4 = PageSizeSpec(series: PaperSeries.a, number: 4);
  static const a4Landscape = PageSizeSpec(
    series: PaperSeries.a,
    number: 4,
    landscape: true,
  );

  /// (breedteMm, hoogteMm) in portret-oriëntatie — bij landscape geruild.
  (double widthMm, double heightMm) get dimensions {
    final (w, h) = _isoDimensions(series, number);
    return landscape ? (h, w) : (w, h);
  }

  /// CSS `@page size`-waarde, bijv. `"A4"` of `"A4 landscape"`.
  String get cssName {
    final base = '${series.name.toUpperCase()}$number';
    return landscape ? '$base landscape' : base;
  }

  /// LaTeX `documentclass`-papieroptie, bijv. `"a4paper"` of
  /// `"a4paper,landscape"`.
  String get latexName {
    final base = '${series.name.toLowerCase()}${number}paper';
    return landscape ? '$base,landscape' : base;
  }

  /// De maatnaam zonder oriëntatie, bijv. `"A4"`. Taalneutraal met opzet: de
  /// oriëntatie is een wóórd ("liggend"), en dat hoort in de interface door
  /// `l10n.d(…)` te gaan. Een model mag geen BuildContext zien, dus stelt de
  /// aanroeper het label samen uit deze naam plus [landscape].
  String get sizeName => '${series.name.toUpperCase()}$number';

  /// JSON-serialisatie: `"A4"`, `"A4L"`, `"B5"`, etc.
  String get id {
    final base = '${series.name.toUpperCase()}$number';
    return landscape ? '${base}L' : base;
  }

  /// Parse een id terug naar een PageSizeSpec.
  static PageSizeSpec? fromId(String? id) {
    if (id == null || id.isEmpty) return null;
    final match = RegExp(r'^([ABC])(\d+)(L?)$').firstMatch(id);
    if (match == null) return null;
    final series = PaperSeries.values.firstWhere(
      (s) => s.name.toUpperCase() == match.group(1),
      orElse: () => PaperSeries.a,
    );
    final number = int.parse(match.group(2)!);
    if (number < 0 || number > 10) return null;
    return PageSizeSpec(
      series: series,
      number: number,
      landscape: match.group(3) == 'L',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PageSizeSpec &&
      series == other.series &&
      number == other.number &&
      landscape == other.landscape;

  @override
  int get hashCode => Object.hash(series, number, landscape);

  @override
  String toString() => 'PageSizeSpec($id)';
}

/// Paginamarges in millimeters. Standaard 25mm rond — een ruime, leesbare
/// marge die ook bij afdrukken voldoende witruimte laat.
class PageMargins {
  final double topMm;
  final double bottomMm;
  final double leftMm;
  final double rightMm;

  const PageMargins({
    this.topMm = 25,
    this.bottomMm = 25,
    this.leftMm = 20,
    this.rightMm = 20,
  });

  /// Uniforme marge in mm rondom.
  const PageMargins.uniform(double mm)
    : topMm = mm,
      bottomMm = mm,
      leftMm = mm,
      rightMm = mm;

  /// CSS `@page margin`-waarde, bijv. `"25mm 20mm"`.
  String get cssMargin =>
      '${_fmtMm(topMm)}mm ${_fmtMm(rightMm)}mm ${_fmtMm(bottomMm)}mm ${_fmtMm(leftMm)}mm';

  /// LaTeX `geometry`-pakket opties, bijv.
  /// `"top=25mm,bottom=25mm,left=20mm,right=20mm"`.
  String get latexMargin =>
      'top=${_fmtMm(topMm)}mm,bottom=${_fmtMm(bottomMm)}mm,left=${_fmtMm(leftMm)}mm,right=${_fmtMm(rightMm)}mm';

  /// JSON-serialisatie als `"25,25,20,20"` (top,bottom,left,right).
  String get id =>
      '${_fmtMm(topMm)},${_fmtMm(bottomMm)},${_fmtMm(leftMm)},${_fmtMm(rightMm)}';

  PageMargins copyWith({
    double? topMm,
    double? bottomMm,
    double? leftMm,
    double? rightMm,
  }) => PageMargins(
    topMm: topMm ?? this.topMm,
    bottomMm: bottomMm ?? this.bottomMm,
    leftMm: leftMm ?? this.leftMm,
    rightMm: rightMm ?? this.rightMm,
  );

  /// Parse een id terug naar PageMargins.
  static PageMargins? fromId(String? id) {
    if (id == null || id.isEmpty) return null;
    final parts = id.split(',');
    if (parts.length != 4) return null;
    final vals = parts.map((p) => double.tryParse(p)).toList();
    if (vals.any((v) => v == null)) return null;
    return PageMargins(
      topMm: vals[0]!,
      bottomMm: vals[1]!,
      leftMm: vals[2]!,
      rightMm: vals[3]!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PageMargins &&
      topMm == other.topMm &&
      bottomMm == other.bottomMm &&
      leftMm == other.leftMm &&
      rightMm == other.rightMm;

  @override
  int get hashCode => Object.hash(topMm, bottomMm, leftMm, rightMm);

  @override
  String toString() => 'PageMargins($id)';
}

/// ISO-216 afmetingen in mm (portret) voor reeks A, B, C, nummers 0–10.
/// Bron: ISO 216:2007. Afgerond op hele mm.
(double widthMm, double heightMm) _isoDimensions(PaperSeries series, int n) {
  const a = [
    (841.0, 1189.0),
    (594.0, 841.0),
    (420.0, 594.0),
    (297.0, 420.0),
    (210.0, 297.0),
    (148.0, 210.0),
    (105.0, 148.0),
    (74.0, 105.0),
    (52.0, 74.0),
    (37.0, 52.0),
    (26.0, 37.0),
  ];
  const b = [
    (1000.0, 1414.0),
    (707.0, 1000.0),
    (500.0, 707.0),
    (353.0, 500.0),
    (250.0, 353.0),
    (176.0, 250.0),
    (125.0, 176.0),
    (88.0, 125.0),
    (62.0, 88.0),
    (44.0, 62.0),
    (31.0, 44.0),
  ];
  const c = [
    (917.0, 1297.0),
    (648.0, 917.0),
    (458.0, 648.0),
    (324.0, 458.0),
    (229.0, 324.0),
    (162.0, 229.0),
    (114.0, 162.0),
    (81.0, 114.0),
    (57.0, 81.0),
    (40.0, 57.0),
    (28.0, 40.0),
  ];
  final table = switch (series) {
    PaperSeries.a => a,
    PaperSeries.b => b,
    PaperSeries.c => c,
  };
  if (n < 0 || n >= table.length) return a[4]; // val terug op A4
  return table[n];
}

/// Format een mm-waarde zonder onnodige `.0` — `25.0` → `"25"`, `25.5` → `"25.5"`.
String _fmtMm(double mm) =>
    mm == mm.roundToDouble() ? mm.round().toString() : mm.toString();
